---
name: aether-deploy-watch
description: |
  部署全流程监控。从 CI 完成到服务健康的端到端验证。
  四步管道: 镜像验证 → 部署收敛 → 健康检查 → 成功确认。
  直接调用 Nomad/Consul API 进行精确状态判定。

  使用场景："部署后检查"、"deploy watch"、"check if deployed"、
  "push 后监控"、"部署监控"、"服务是否上线"、"watch deploy"
argument-hint: "<job-name> [version] [--timeout=120]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
dependencies:
  cli:
    required: false
    note: "直接通过 Nomad/Consul API 查询，aether-status 仅用于最终展示"
---

# Aether 部署监控 (aether-deploy-watch)

> **版本**: 2.1.0 | **优先级**: P0

## 1. 概述

**核心定位**：部署管道编排器，**不是** aether-status 的包装层。

所有控制流判定通过直接调用 Nomad/Consul HTTP API 完成。
`aether-status` 仅在最终成功/失败时调用一次，用于格式化展示摘要。

```
ci-watch-hook → CronCreate (CI polling) → CI success
  → deploy-watch:
    Step 0: Context → Step 1: Image → Step 2: Deploy → Step 3: Health
                                                            ↓
                                                    aether-status (display)
```

### 两种运行模式

| 模式 | 触发条件 | 执行步骤 |
|------|---------|---------|
| **Mode A** — 管道模式 | 提供 `--version` (40-char SHA) | Step 0 → 1 → 2 → 3 |
| **Mode B** — 即时检查 | 不提供 `--version` | Step 0 → 2 → 3 (使用当前部署版本) |

Mode A 用于 CI 推送后的端到端监控链。Mode B 用于手动检查当前部署是否健康。

---

## 2. Step 0: 上下文解析

### job_name 解析优先级

```
CLI 参数 > .aether/config.yaml watch.job_name > AskUserQuestion
```

**禁止** 从 git remote 猜测 job name。如果无法确定，直接询问用户。

### 读取集群配置

```bash
NOMAD_ADDR=$(yq '.cluster.nomad_addr' .aether/config.yaml 2>/dev/null)
CONSUL_ADDR=$(yq '.cluster.consul_addr' .aether/config.yaml 2>/dev/null)
REGISTRY=$(yq '.cluster.registry' .aether/config.yaml 2>/dev/null)
```

如果配置文件不存在或关键字段缺失，提示用户运行 `/aether:setup` 初始化项目配置。

### 验证 Job 存在

```bash
curl -sf --max-time 5 --connect-timeout 3 "${NOMAD_ADDR}/v1/job/${JOB_NAME}" > /dev/null
```

- **200**: Job 存在，继续。
- **404**: 报告 "Job `${JOB_NAME}` not found in Nomad"，建议 `aether setup` 或手动 `nomad job run`。
- **连接失败**: 报告 Nomad 不可达，建议 `/aether:doctor`。

### target_tag 确定

- **Mode A**: 从 `--version` 参数获取 (期望 40-char commit SHA)。
- **Mode B**: 从 Nomad Job 当前配置提取镜像 tag：

```bash
CURRENT_IMAGE=$(curl -sf --max-time 5 "${NOMAD_ADDR}/v1/job/${JOB_NAME}" | \
  jq -r '.TaskGroups[0].Tasks[0].Config.image // empty')
TARGET_TAG="${CURRENT_IMAGE##*:}"
```

---

## 3. Step 1: 镜像验证

> **仅 Mode A 执行。Mode B 跳过此步。**

单次检查，不做轮询。CI 已经完成，镜像应当已存在。

### 主检查: Forgejo Registry API

```bash
# forgejo CLI wrapper 自动处理 Cloudflare Access 认证
forgejo GET "/repos/${OWNER_REPO}/packages?type=container" 2>/dev/null | \
  jq --arg tag "${TARGET_TAG}" '[.[] | select(.version == $tag)] | length'
```

### 回退: Docker Manifest

```bash
docker manifest inspect "${REGISTRY}/${IMAGE_PATH}:${TARGET_TAG}" > /dev/null 2>&1
```

### 判定

- **镜像存在**: 推进到 Step 2。
- **镜像不存在**: **执行 CI 状态诊断** (见下方)，根据诊断结果报告原因。

### CI 状态诊断 (镜像未找到时)

当 Mode A 镜像不存在时，必须查询 CI 状态后再给出结论。
区分 pending/cancelled/failure/success/unknown 五种状态，针对性报告。

详见 [CI 状态诊断流程](references/ci-diagnosis.md)

---

## 4. Step 2: 部署收敛

同步轮询循环。间隔 10 秒，最多 18 次迭代 (约 3 分钟)。

### 主信号: Deployment 对象

```bash
curl -sf --max-time 10 --connect-timeout 3 \
  "${NOMAD_ADDR}/v1/job/${JOB_NAME}/deployment" | jq '{
  Status,
  StatusDescription,
  JobVersion,
  TaskGroups: (.TaskGroups | to_entries[] | {
    name: .key,
    desired: .value.DesiredTotal,
    placed: .value.PlacedAllocs,
    healthy: .value.HealthyAllocs,
    unhealthy: .value.UnhealthyAllocs,
    canaries: .value.DesiredCanaries
  })
}'
```

### 判定逻辑

| Deployment Status | 行为 |
|-------------------|------|
| `"successful"` | 推进到 Step 3 |
| `"failed"` | **终止**，报告 StatusDescription |
| `"running"` + DesiredCanaries > 0 | 报告 "Canary deployment in progress"，继续轮询 |
| `"running"` | 报告进度 (healthy/desired)，继续轮询 |
| 无 Deployment 对象 | 回退到 Allocation 检查 |

### 回退: Allocation 检查

当 Deployment 端点无数据时 (batch job、旧版本 Nomad 等)：

```bash
curl -sf --max-time 10 --connect-timeout 3 \
  "${NOMAD_ADDR}/v1/job/${JOB_NAME}/allocations" | jq '
  [.[] | select(.ClientStatus != "complete" and .ClientStatus != "lost")] |
  {
    total: length,
    running: [.[] | select(.ClientStatus == "running")] | length,
    pending: [.[] | select(.ClientStatus == "pending")] | length,
    failed: [.[] | select(.ClientStatus == "failed")] | length
  }
'
```

- **全部 failed，0 running** → 终止，获取失败事件进行诊断。
- **部分 running，部分 pending** → 继续轮询，报告进度。
- **全部 running** → 推进到 Step 3。

### 终端失败早退

当检测到 failed allocation 时，立即获取失败原因：

```bash
FAILED_ALLOC=$(curl -sf --max-time 10 --connect-timeout 3 \
  "${NOMAD_ADDR}/v1/job/${JOB_NAME}/allocations" | \
  jq -r '[.[] | select(.ClientStatus == "failed")] | .[0].ID // empty')

if [ -n "$FAILED_ALLOC" ]; then
  curl -sf --max-time 10 --connect-timeout 3 \
    "${NOMAD_ADDR}/v1/allocation/${FAILED_ALLOC}" | \
    jq '.TaskStates | to_entries[] | {
      task: .key,
      state: .value.State,
      failed: .value.Failed,
      last_event: .value.Events[-1].Type,
      message: .value.Events[-1].DisplayMessage
    }'
fi
```

### 容错与轮询结构

每次 API 调用使用 `--max-time 10 --connect-timeout 3`，维护失败计数器，连续 3 次 API 失败终止并报告。

详见 [轮询模式与容错](references/polling-patterns.md)

### Step 2 超时处理 (Mode A)

当 Step 2 轮询耗尽仍未收敛时，**不要凭空猜测原因**。按以下诊断链排查：

```
镜像版本对比 → CI 状态诊断 → Nomad 调度诊断 → 给出结论
```

1. **检查 Nomad 当前运行的镜像 tag 是否与 target_tag 一致**。如果不一致，说明新版本从未被 Nomad 拉取。
2. **执行 CI 状态诊断** (与 Step 1 相同的 API 调用)，区分 cancelled / pending / failure / success。
3. **检查 Nomad evaluations** (`GET /v1/job/${JOB_NAME}/evaluations`)，排查调度问题。
4. 根据诊断结果给出**针对性**建议。

**禁止行为**: 不要在没有证据的情况下建议 `docker network prune`、`docker system prune` 或任何 Docker 清理命令。
这类操作可能破坏正在运行的构建。只有在日志明确显示 Docker 网络/存储问题时才可建议。

---

## 5. Step 3: 健康验证

同步轮询循环。间隔 5 秒，最多 36 次迭代 (约 3 分钟)。

### 检查逻辑

```bash
# Consul 健康实例数
PASSING=$(curl -sf --max-time 10 --connect-timeout 3 \
  "${CONSUL_ADDR}/v1/health/service/${SERVICE_NAME}?passing" | jq 'length')

# Nomad 期望实例数
DESIRED=$(curl -sf --max-time 10 --connect-timeout 3 \
  "${NOMAD_ADDR}/v1/job/${JOB_NAME}" | jq '.TaskGroups[0].Count')
```

### Service Name 解析

```
.aether/config.yaml watch.service_name > job_name (默认)
```

### 成功判定: 连续确认

`PASSING >= DESIRED` 必须在 **连续 2 次检查** (间隔 5 秒) 均为 true 才算通过。

```bash
MAX_ITER=36
INTERVAL=5
consecutive_pass=0

for i in $(seq 1 $MAX_ITER); do
  PASSING=$(curl -sf --max-time 10 --connect-timeout 3 \
    "${CONSUL_ADDR}/v1/health/service/${SERVICE_NAME}?passing" | jq 'length')
  DESIRED=$(curl -sf --max-time 10 --connect-timeout 3 \
    "${NOMAD_ADDR}/v1/job/${JOB_NAME}" | jq '.TaskGroups[0].Count')

  if [ "$PASSING" -ge "$DESIRED" ] 2>/dev/null; then
    consecutive_pass=$((consecutive_pass + 1))
    if [ $consecutive_pass -ge 2 ]; then
      echo "✅ Health check passed (${PASSING}/${DESIRED} passing, confirmed 2x)"
      break
    fi
  else
    consecutive_pass=0
  fi

  echo "[Step 3] Health check: ${PASSING:-0}/${DESIRED:-?} passing (attempt ${i}/${MAX_ITER})"
  sleep $INTERVAL
done
```

### 超时处理

| 情况 | 报告内容 |
|------|---------|
| 超时 + 0 passing | 健康检查完全失败，建议检查服务日志和健康检查端点配置 |
| 超时 + 部分 passing | 部分健康，建议检查特定节点上的 allocation 状态 |

### Phantom Alloc 诊断 (超时时执行)

当 Step 3 超时且 `PASSING < DESIRED` 时，检测 Nomad 报告 running 但 Docker 已退出的 phantom allocation。
仅在超时路径执行，不影响正常部署监控。

详见 [Phantom Alloc 诊断](references/phantom-alloc-diagnosis.md)

---

## 6. 输出规范

### 轮询中进度输出

```
[Step 2] Deployment converging... (3/3 healthy, v42)
[Step 3] Health check: 2/3 passing (attempt 4/36)
```

每次轮询一行，覆盖式输出。保持简洁，不堆叠日志。

### 成功输出

```
✅ Deployment successful — {job_name}
  Nomad: {running}/{desired} running (v{version})
  Consul: {passing}/{desired} passing
  Duration: {elapsed}s

  /aether:rollback {job_name} — if anything looks wrong
```

成功后调用 `/aether:status {job_name}` 展示完整状态摘要。

### 失败输出

```
❌ Deployment failed — {job_name}
  Stage: {which step failed}
  Error: {specific error from API}

  Suggested actions:
  1. {specific fix based on error type}
  2. Run /aether:status {job_name} --failed for details
  3. Run deploy-doctor agent for deep diagnosis
```

**禁止** 在输出中包含自动修复提示（如 "是否需要自动执行修复？"）。
只展示用户可以手动执行的命令。

---

## 7. CronCreate 集成 (ci-watch-hook 触发链)

deploy-watch 是 CI 推送后监控链的终端环节：
`git push → ci-watch-hook → CronCreate → CI success → deploy-watch`

支持状态文件跟踪 (`.aether/deploy-watch.state`) 和直接调用两种模式。

详见 [CronCreate 集成详情](references/croncreate-integration.md)

---

## 参考文档

| 主题 | 文档 |
|------|------|
| CI 状态诊断 | [ci-diagnosis.md](references/ci-diagnosis.md) |
| Phantom Alloc 诊断 | [phantom-alloc-diagnosis.md](references/phantom-alloc-diagnosis.md) |
| 轮询模式与容错 | [polling-patterns.md](references/polling-patterns.md) |
| CronCreate 集成 | [croncreate-integration.md](references/croncreate-integration.md) |

---

## 8. 约束与已知限制

### Bash Tool 超时

Claude Code Bash tool 单次调用约 120 秒超时。Step 2 (18x10s) 和 Step 3 (36x5s) 各自可能超过此限制。
实际实现中，每个 Step 应作为独立的 Bash 调用，轮询次数根据剩余时间动态调整。
对于更长监控场景，推荐 CronCreate 方式 (类似 `aether-ci --watch`)。

### 上游与架构限制

- Forgejo Actions API 无 step 级别日志 (Aether#8，等待上游支持)。
- 健康检查器在 rolling update grace period 期间可能短暂看到错误的 allocation 数量，Step 3 的 consecutive_pass 机制用于缓解。
- Canary 部署: deploy-watch 报告状态但**不会**自动 promote，需用户手动执行或通过 `/aether:deploy` 完成。
- Forgejo commit status API 将 `cancelled` 表现为 `status: "failure"`，必须通过 Actions Tasks API 区分 (Aether#9)。

### 诊断安全原则

- **不要**在无直接证据时建议 destructive Docker 命令 (`docker network prune`, `docker system prune`, `docker rm -f` 等)。
- **不要**将 "镜像未更新" 直接推断为 "Runner 资源泄漏"。正确的诊断链是：检查 CI 状态 → 区分 pending/cancelled/failed → 针对性建议。
- 超时诊断必须遵循 **证据链**: 先收集数据，再给结论。不要从表面现象跳跃到破坏性操作建议。

### 依赖工具

| 工具 | 用途 | 缺失时行为 |
|------|------|-----------|
| `curl` | API 调用 | 必须，缺失则终止 |
| `jq` | JSON 解析 | 必须，缺失则终止 |
| `yq` | YAML 读取 | 可选，缺失时回退到 grep 解析 |
| `forgejo` CLI | Registry 查询 (Step 1) | 可选，回退到 docker manifest inspect |

---

**Skill 版本**: 2.1.0
**最后更新**: 2026-03-31
**维护者**: 10CG Infrastructure Team
