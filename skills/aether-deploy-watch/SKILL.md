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

> **版本**: 2.0.0 | **优先级**: P0

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
- **镜像不存在**: 报告 "CI passed but image not found in registry"，建议检查 CI 构建日志和 registry push 步骤。

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

- 每次 `curl` 使用 `--max-time 10 --connect-timeout 3`。
- 维护 `api_fail_count` 计数器，成功调用重置为 0，连续 3 次失败 → 终止。

```bash
MAX_ITER=18; INTERVAL=10; api_fail_count=0
for i in $(seq 1 $MAX_ITER); do
  # ... 执行 Deployment/Allocation 检查 ...
  if [ $? -ne 0 ]; then
    api_fail_count=$((api_fail_count + 1))
    [ $api_fail_count -ge 3 ] && echo "❌ Nomad API 连续不可达，运行 /aether:doctor" && exit 1
  else
    api_fail_count=0
  fi
  # 终端状态 (successful/failed/all-running) 判定后 break
  echo "[Step 2] Deployment converging... (attempt ${i}/${MAX_ITER})"
  sleep $INTERVAL
done
```

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

deploy-watch 是 CI 推送后监控链的终端环节。完整链路：

```
git push
  → ci-watch-hook 检测推送，写入状态文件
  → CronCreate 创建定时轮询 CI 状态
  → CI 成功
  → CronCreate 触发 deploy-watch
```

### 触发方式

ci-watch-hook 在 CI 成功后，CronCreate 的 prompt 包含命令式指令：

```
IMMEDIATELY invoke /aether:deploy-watch {JOB_NAME} --version {SHA}
Do not summarize. Invoke the skill now.
```

### 状态文件

路径: `.aether/deploy-watch.state`

```yaml
sha: abc1234def567890abc1234def567890abc1234d
repo: 10CG/my-project
job_name: my-project
expected_image: forgejo.10cg.pub/10cg/my-project:abc1234def567890abc1234def567890abc1234d
phase: image | deploy | health | done | failed
started: 2026-03-31T10:00:00Z
```

### 阶段更新

deploy-watch 在每个 Step 转换时更新 `phase` 字段：

```bash
yq -i ".phase = \"deploy\"" .aether/deploy-watch.state
```

状态流转: `image → deploy → health → done` (正常) 或任意阶段 → `failed` (异常)。

用户也可以不依赖 ci-watch-hook，直接调用：
`/aether:deploy-watch my-api --version abc1234def567890abc1234def567890abc1234d`

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

### 依赖工具

| 工具 | 用途 | 缺失时行为 |
|------|------|-----------|
| `curl` | API 调用 | 必须，缺失则终止 |
| `jq` | JSON 解析 | 必须，缺失则终止 |
| `yq` | YAML 读取 | 可选，缺失时回退到 grep 解析 |
| `forgejo` CLI | Registry 查询 (Step 1) | 可选，回退到 docker manifest inspect |

---

**Skill 版本**: 2.0.0
**最后更新**: 2026-03-31
**维护者**: 10CG Infrastructure Team
