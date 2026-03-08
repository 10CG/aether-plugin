---
name: aether-deploy-watch
description: |
  部署监控与诊断工具。在 CI/CD 完成后自动检查 Nomad 部署状态，收集错误信息并提供修复建议。

  使用场景："部署后检查"、"CI 成功但服务不可用"、"查看 allocation 状态"、"部署失败排查"
argument-hint: "[job-name] [--follow] [--timeout=60]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Aether 部署监控 (aether-deploy-watch)

> **版本**: 1.0.0 | **优先级**: P0

## 概述

解决的核心问题：**CI 显示成功，不等于服务真正可用**

典型场景：
1. CI 构建并推送镜像成功
2. Nomad 拉取镜像失败（auth 配置错误、网络问题等）
3. Allocation 进入 failed 状态
4. 用户没有及时发现和处理问题

**本 Skill 的作用**：
- 自动检查部署后的实际状态
- 收集失败 allocation 的日志
- 分析错误模式并给出修复建议
- 减少人工信息搬运

---

## 快速开始

### 基本用法

```
/aether:deploy-watch my-api
```

自动检查 `my-api` 的部署状态，### 持续监控

```
/aether:deploy-watch my-api --follow
```

持续监控 60 秒，直到部署成功或明确失败。

### 自定义超时

```
/aether:deploy-watch my-api --follow --timeout=120
```

---

## 执行流程

### Phase 1: 获取最近部署状态

```bash
# 读取 Nomad 配置
NOMAD_ADDR="${NOMAD_ADDR:-http://192.168.69.70:4646}"
JOB_NAME="my-api"

# 获取 Job 的所有 allocation
ALLOCATIONS=$(curl -s "${NOMAD_ADDR}/v1/job/${JOB_NAME}/allocations")

# 分析状态分布
echo "$ALLOCATIONS" | jq -r '
  group_by(.ClientStatus) |
  to_entries |
  map({status: .key, count: (.value | length)})
'
```

**状态含义**：

| 状态 | 含义 | 是否正常 |
|------|------|---------|
| `running` | 正在运行 | ✓ |
| `pending` | 等待调度 | ⚠ 可能资源不足 |
| `failed` | 已失败 | ✗ 需要排查 |
| `lost` | 失联 | ✗ 严重问题 |
| `complete` | 已完成（batch） | ✓ |
| `unknown` | 未知 | ⚠ 需要检查 |

### Phase 2: 失败诊断

当发现 failed allocation 时，自动收集诊断信息：

```bash
# 获取失败的 allocation ID
FAILED_ALLOC_ID=$(echo "$ALLOCATIONS" | jq -r '[.[] | select(.ClientStatus == "failed") | .ID][0]')

if [ -n "$FAILED_ALLOC_ID" ]; then
  echo "发现失败的 allocation: $FAILED_ALLOC_ID"

  # 获取 allocation 详情
  curl -s "${NOMAD_ADDR}/v1/allocation/${FAILED_ALLOC_ID}" | jq '{
    id: .ID,
    task_group: .TaskGroup,
    client_status: .ClientStatus,
    task_states: .TaskStates
  }'

  # 获取失败原因
  curl -s "${NOMAD_ADDR}/v1/allocation/${FAILED_ALLOC_ID}" | jq '.TaskStates'
fi
```

### Phase 3: 日志收集

自动拉取失败 allocation 的日志：

```bash
# 获取 stderr 日志（错误信息）
curl -s "${NOMAD_ADDR}/v1/client/${CLIENT_ID}/allocation/${ALLOC_ID}/fs" \
  -X POST \
  -d '{"path": "/alloc/logs/.stderr", "offset": 0, "limit": 10000}'

# 或者使用 nomad logs 命令
nomad alloc-logs -stderr -n 100 $ALLOC_ID
```

### Phase 4: 错误模式匹配

分析日志，匹配常见错误模式：

| 错误模式 | 正则表达式 | 可能原因 | 修复建议 |
|---------|-----------|---------|---------|
| 镜像拉取失败 | `image.*pull.*failed|failed to pull|unauthorized` | Registry auth 配置错误 | 检查 nomad job 中的 auth 配置 |
| 网络不可达 | `network.*unreachable|connection refused|timeout` | 网络策略/防火墙 | 检查 network mode 和防火墙规则 |
| 权限拒绝 | `permission denied|access denied` | 文件/目录权限 | 检查 volume 权限和用户配置 |
| 内存不足 | `OOMKilled|out of memory` | 内存限制太低 | 增加 memory 资源配置 |
| 健康检查失败 | `health check failed| unhealthy` | 服务启动失败 | 检查服务日志和健康检查配置 |
| 配置错误 | `config.*error|invalid.*config` | 配置文件问题 | 检查环境变量和配置文件 |

### Phase 5: 修复建议

根据错误类型给出具体修复建议：

```markdown
## 诊断结果

### 问题: 镜像拉取失败

**错误信息**:
```
failed to pull image forgejo.10cg.pub/my-api:abc123: unauthorized
```

**分析**:
Registry 认证失败，Nomad 无法拉取镜像。

**可能原因**:
1. Job 文件中 auth 配置使用了错误的 secrets 名称
2. Registry token 已过期或无效
3. Cloudflare Access 保护导致认证失败

**修复建议**:

1. 检查 Nomad Job 文件中的 auth 配置:
   ```hcl
   auth {
     username = "${FORGEJO_USER}"   # 确保使用正确的变量名
     password = "${FORGEJO_TOKEN}"
     # 不要添加 server_address，让 Docker 自动检测
   }
   ```

2. 验证 Secrets 配置:
   ```bash
   # 检查 secrets 是否正确设置
   nomad var get nomad/jobs/my-api
   ```

3. 如果 Registry 被 Cloudflare Access 保护:
   - 在 Cloudflare Zero Trust 中为 Docker 添加 bypass 规则
   - 或使用 Service Token 进行认证

**快速修复命令**:
```bash
# 重新部署（触发新的 allocation）
nomad job run deploy/nomad-prod.hcl
```
```

---

## 完整输出示例

### 成功部署

```
Aether 部署监控
================
Job: my-api
监控时间: 2026-03-08 18:30:00

[✓] 部署状态检查
    Job 状态: running
    Allocations:
      - 6c8f2a1d (running) - heavy-1 ✓
      - 7d9e3b2e (running) - heavy-2 ✓
    健康检查: 通过
    服务地址: http://192.168.69.100:8080

状态: ✓ 部署成功
```

### 部署失败

```
Aether 部署监控
================
Job: my-api
监控时间: 2026-03-08 18:30:00

[!] 部署状态检查
    Job 状态: running (有失败 allocation)
    Allocations:
      - 6c8f2a1d (running) - heavy-1 ✓
      - 8e0f4c3f (failed)  - heavy-2 ✗

[✗] 失败诊断
    Allocation: 8e0f4c3f-abc1-def2-3ghi4
    节点: heavy-2
    Task: api
    状态: failed (exit code: 1)

    错误日志 (最后 20 行):
    ┌────────────────────────────────────────────────────────┐
    │ time="2026-03-08T18:29:55Z" level=error msg="pulling image failed" │
    │ time="2026-03-08T18:29:55Z" level=error msg="unauthorized: authentication required" │
    │ time="2026-03-08T18:29:55Z" level=fatal msg="failed to pull image" │
    └────────────────────────────────────────────────────────┘

[!] 错误分析
    匹配模式: 镜像拉取失败 (unauthorized)

    可能原因:
    1. Job 文件中 auth 配置错误
    2. Registry token 无效
    3. Cloudflare Access 保护

[→] 修复建议

    1. 检查 deploy/nomad-prod.hcl 中的 auth 配置:
       确保: username = "${FORGEJO_USER}"
           password = "${FORGEJO_TOKEN}"
       不要添加 server_address

    2. 运行以下命令检查:
       grep -A5 "auth {" deploy/nomad-prod.hcl

    3. 修复后重新部署:
       nomad job run deploy/nomad-prod.hcl

状态: ✗ 部署失败 - 需要修复

是否需要自动执行修复？ [Y/n]
```

### 持续监控模式

```
/aether:deploy-watch my-api --follow --timeout=120

Aether 部署监控 (持续模式)
============================
Job: my-api
超时: 120 秒

[18:30:00] 检查 #1
    Allocations: 1 pending, 0 running
    状态: 等待调度...

[18:30:05] 检查 #2
    Allocations: 1 pending, 0 running
    状态: 等待调度...

[18:30:10] 检查 #3
    Allocations: 0 pending, 1 running (starting)
    状态: 服务启动中...

[18:30:15] 检查 #4
    Allocations: 0 pending, 1 running (healthy)
    健康检查: ✓ 通过

状态: ✓ 部署成功 (耗时: 15 秒)
```

---

## 与其他 Skills 的集成

### 在 aether-deploy 后自动调用

```markdown
## aether-deploy 中的集成

部署完成后，建议自动运行:

```bash
nomad job run deploy/nomad-prod.hcl
/aether:deploy-watch my-api --follow --timeout=60
```

这样可以立即验证部署是否真正成功。
```

### 作为 CI/CD 的最后一步

```yaml
# .forgejo/workflows/deploy.yml

- name: 部署后验证
  run: |
    # 等待 allocation 创建
    sleep 5

    # 调用 aether 验证
    # (这里需要 aether CLI 支持此功能)
    aether deploy-watch my-api --timeout=30 || exit 1
```

---

## 命令行等价操作

```bash
# 查看Job 状态
nomad job status my-api

# 查看 allocations
nomad job allocs my-api

# 查看特定 allocation 详情
nomad alloc status $ALLOC_ID

# 查看日志
nomad alloc logs -stderr $ALLOC_ID

# 实时跟踪日志
nomad alloc logs -f $ALLOC_ID
```

---

## 参考文档

- [aether-deploy Skill](../aether-deploy/SKILL.md) - 触发部署
- [aether-status Skill](../aether-status/SKILL.md) - 查看状态
- [Nomad Allocation API](https://developer.hashicorp.com/nomad/api-docs/allocations)

---

**Skill 版本**: 1.0.0
**最后更新**: 2026-03-08
**维护者**: 10CG Infrastructure Team
