---
name: aether-status
description: |
  聚合查询 Aether 集群和服务状态。整合 Nomad 节点、Job、Allocation 和 Consul 服务健康信息。
  支持查看失败 allocation、最近部署、日志等详细信息。

  使用场景："查看集群状态"、"检查服务是否正常"、"查看失败的 allocation"、"查看最近部署"、"查看服务日志"
argument-hint: "[service-name] [--failed] [--recent] [--logs] [--watch]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash
dependencies:
  cli:
    required: false
    note: "可直接通过 Nomad/Consul API 查询，无需 CLI"
---

# Aether 状态查询 (aether-status)

> **版本**: 1.1.0 | **优先级**: P0

## 快速开始

### 使用场景

- 查看集群整体健康状态
- 检查特定服务的部署情况
- 查看失败的 allocation 详情
- 查看最近的部署状态
- 排查服务不可用问题

### 命令参数

| 参数 | 说明 | 示例 |
|------|------|------|
| 无参数 | 集群概览 | `/aether:status` |
| `<job-name>` | 服务详情 | `/aether:status my-api` |
| `--failed` | 查看失败的 allocation | `/aether:status --failed` |
| `--recent` | 查看最近的部署 | `/aether:status --recent` |
| `--logs` | 查看日志 | `/aether:status my-api --logs` |
| `--watch` | 持续监控 | `/aether:status my-api --watch` |

---

## 执行模式

### 模式 1: 集群概览（无参数）

```bash
/aether:status
```

执行以下查询并汇总：

```bash
# 1. Nomad 节点状态
curl -s "${NOMAD_ADDR}/v1/nodes" | jq '[.[] | {name: .Name, status: .Status, class: .NodeClass}]'

# 2. 运行中的 Jobs
curl -s "${NOMAD_ADDR}/v1/jobs" | jq '[.[] | select(.Status == "running") | {name: .Name, type: .Type, status: .Status}]'

# 3. 失败的 Allocations
curl -s "${NOMAD_ADDR}/v1/allocations" | jq '[.[] | select(.ClientStatus == "failed") | {job: .JobID, node: .NodeName, status: .ClientStatus}]'

# 4. Consul 服务健康
curl -s "${CONSUL_HTTP_ADDR}/v1/health/state/critical" | jq 'length'
```

**输出格式**：

```
Aether 集群状态
================
Nomad 节点: 3 heavy (ready) + 5 light (ready)
运行中 Jobs: 5 (4 service, 1 batch)
失败 Allocs: 1 (my-project @ heavy-1)
Consul 服务: 8 passing, 1 critical
```

---

### 模式 2: 服务详情（指定 job-name）

```bash
/aether:status my-project
```

执行以下查询：

```bash
# 1. Job 详情
curl -s "${NOMAD_ADDR}/v1/job/my-project" | jq '{name: .Name, type: .Type, status: .Status, version: .Version}'

# 2. Allocations
curl -s "${NOMAD_ADDR}/v1/job/my-project/allocations" | jq '[.[] | {id: .ID[:8], node: .NodeName, status: .ClientStatus, version: .JobVersion}]'

# 3. Consul 服务实例
curl -s "${CONSUL_HTTP_ADDR}/v1/health/service/my-project?passing" | jq '[.[] | {node: .Node.Node, address: .Service.Address, port: .Service.Port}]'
```

**输出格式**：

```
服务: my-project
================
Job: my-project (service, running, v3)
镜像: forgejo.10cg.pub/org/my-project:abc123

Allocations:
  abc12345 @ heavy-1 - running (v3)
  def67890 @ heavy-2 - running (v3)

Consul 实例:
  heavy-1:28456 - healthy
  heavy-2:31022 - healthy

最近部署: 2h ago
```

---

### 模式 3: 查看失败的 Allocations（--failed）

```bash
/aether:status --failed
```

查询所有失败的 allocation 并显示详细信息：

```bash
# 获取所有失败的 allocations
FAILED_ALLOCS=$(curl -s "${NOMAD_ADDR}/v1/allocations?filter=ClientStatus==failed")

# 对每个失败的 allocation 获取详情
for alloc_id in $(echo "$FAILED_ALLOCS" | jq -r '.[].ID'); do
  # 获取 allocation 详情
  curl -s "${NOMAD_ADDR}/v1/allocation/${alloc_id}" | jq '{
    id: .ID,
    job: .JobID,
    task_group: .TaskGroup,
    node: .NodeName,
    status: .ClientStatus,
    task_states: .TaskStates
  }'
done
```

**输出格式**：

```
失败的 Allocations
==================

Allocation: abc12345-def67890-ghi12345
Job: my-project
Task Group: api
Node: heavy-1
Status: failed

Task 状态:
  api: failed (exit code: 1)

失败时间: 2026-03-08 18:30:00
```

---

### 模式 4: 查看最近部署（--recent）

```bash
/aether:status --recent
```

显示最近 10 个 deployment 的状态：

```bash
# 获取所有 jobs 并按 ModifyIndex 排序
curl -s "${NOMAD_ADDR}/v1/jobs" | jq '[.[] | {
  name: .Name,
  status: .Status,
  version: .Version,
  modify_index: .ModifyIndex
}] | sort_by(-.modify_index) | .[0:10]'
```

**输出格式**：

```
最近部署
========
时间范围: 最近 24 小时

┌─────────────────┬─────────┬─────────┬─────────────────────┐
│ Job             │ 状态    │ 版本    │ 更新时间             │
├─────────────────┼─────────┼─────────┼─────────────────────┤
│ my-api          │ running │ v5      │ 10 分钟前           │
│ web-frontend    │ running │ v3      │ 2 小时前            │
│ data-worker     │ failed  │ v2      │ 5 小时前            │
└─────────────────┴─────────┴─────────┴─────────────────────┘

⚠ 1 个部署失败
```

---

### 模式 5: 查看日志（--logs）

```bash
/aether:status my-project --logs
```

获取指定服务的日志：

```bash
# 获取 running 的 allocation ID
ALLOC_ID=$(curl -s "${NOMAD_ADDR}/v1/job/my-project/allocations" | jq -r '[.[] | select(.ClientStatus == "running") | .ID][0]')

# 获取 stdout 日志（最近 100 行）
curl -s "${NOMAD_ADDR}/v1/client/fs/logs/${ALLOC_ID}?task=api&type=stdout&plain=true" | tail -100

# 获取 stderr 日志（最近 100 行）
curl -s "${NOMAD_ADDR}/v1/client/fs/logs/${ALLOC_ID}?task=api&type=stderr&plain=true" | tail -100
```

**输出格式**：

```
服务日志: my-project
===================
Allocation: abc12345
Task: api

--- stdout (最近 100 行) ---
2026-03-08 18:30:00 INFO Server started on port 8080
2026-03-08 18:30:01 INFO Connected to database
...

--- stderr (最近 100 行) ---
2026-03-08 18:30:05 WARN Connection pool running low
...
```

---

### 模式 6: 持续监控（--watch）

```bash
/aether:status my-project --watch
```

持续监控服务状态，每 5 秒刷新一次，连续失败 5 次自动退出：

```bash
FAIL_COUNT=0
MAX_FAILURES=5

while [ $FAIL_COUNT -lt $MAX_FAILURES ]; do
  clear
  echo "Aether 状态监控 - $(date)"
  echo "================================"

  # 检查 API 可达性
  if ! curl -sf --max-time 5 "${NOMAD_ADDR}/v1/agent/health" > /dev/null 2>&1; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "⚠ Nomad API 无响应 (${FAIL_COUNT}/${MAX_FAILURES})"
    echo "  连续失败 ${MAX_FAILURES} 次后将自动退出"
    sleep 5
    continue
  fi

  FAIL_COUNT=0  # 重置计数
  # 显示状态
  /aether:status my-project
  sleep 5
done

echo "错误: Nomad API 连续 ${MAX_FAILURES} 次无响应，监控已停止"
echo "修复建议: 检查 NOMAD_ADDR (${NOMAD_ADDR}) 是否可达"
```

---

## 被 aether-deploy-watch 调用

`aether-deploy-watch` Skill 会调用本 Skill 获取状态：

```markdown
## aether-deploy-watch 中的调用示例

### 获取最近部署状态
```
/aether:status my-api --recent
```

### 检查失败
```
/aether:status my-api --failed
```

### 获取日志
```
/aether:status my-api --logs
```
```

---

## API 参考

### Nomad API

```bash
# 节点列表
GET ${NOMAD_ADDR}/v1/nodes

# Job 列表
GET ${NOMAD_ADDR}/v1/jobs

# Job 详情
GET ${NOMAD_ADDR}/v1/job/{job_id}

# Job Allocations
GET ${NOMAD_ADDR}/v1/job/{job_id}/allocations

# Allocation 详情
GET ${NOMAD_ADDR}/v1/allocation/{alloc_id}

# Allocation 日志
GET ${NOMAD_ADDR}/v1/client/fs/logs/{alloc_id}?task={task}&type={stdout|stderr}
```

### Consul API

```bash
# 服务健康状态
GET ${CONSUL_HTTP_ADDR}/v1/health/service/{service_name}

# 临界服务
GET ${CONSUL_HTTP_ADDR}/v1/health/state/critical
```

---

## 前置条件：集群配置

执行前需要配置 Aether 集群入口，参考 `/aether:setup`。

### 配置读取

```bash
# 1. 检查项目 .env
if [ -f ".env" ]; then source .env; fi

# 2. 检查全局配置
if [ -z "$NOMAD_ADDR" ] && [ -f "$HOME/.aether/config.yaml" ]; then
  NOMAD_ADDR=$(yq '.endpoints.nomad' ~/.aether/config.yaml)
  CONSUL_HTTP_ADDR=$(yq '.endpoints.consul' ~/.aether/config.yaml)
fi

# 3. 未配置则提示
if [ -z "$NOMAD_ADDR" ]; then
  echo "请先运行 /aether:setup 配置集群"
  exit 1
fi
```

---

## 故障处理

### 集群不可达

所有 API 调用前先检查连通性，设置超时防止长时间阻塞：

```bash
# 检查 Nomad 可达性（5 秒超时）
if ! curl -sf --max-time 5 "${NOMAD_ADDR}/v1/agent/health" > /dev/null 2>&1; then
  echo "错误: 无法连接 Nomad API (${NOMAD_ADDR})"
  echo ""
  echo "修复建议:"
  echo "  1. 确认地址正确: echo \$NOMAD_ADDR"
  echo "  2. 测试网络连通: curl -v ${NOMAD_ADDR}/v1/agent/health"
  echo "  3. 检查 Nomad 服务: ssh root@heavy-1 'systemctl status nomad'"
  echo "  4. 重新配置: /aether:setup"
  exit 1
fi

# 检查 Consul 可达性（5 秒超时）
if ! curl -sf --max-time 5 "${CONSUL_HTTP_ADDR}/v1/status/leader" > /dev/null 2>&1; then
  echo "错误: 无法连接 Consul API (${CONSUL_HTTP_ADDR})"
  echo ""
  echo "修复建议:"
  echo "  1. 确认地址正确: echo \$CONSUL_HTTP_ADDR"
  echo "  2. 测试网络连通: curl -v ${CONSUL_HTTP_ADDR}/v1/status/leader"
  echo "  3. 检查 Consul 服务: ssh root@heavy-1 'systemctl status consul'"
  echo "  4. 重新配置: /aether:setup"
  exit 1
fi
```

### 部分可达（降级策略）

当 Nomad 可达但 Consul 不可达（或反之），采用降级模式：

```bash
NOMAD_OK=false
CONSUL_OK=false

curl -sf --max-time 5 "${NOMAD_ADDR}/v1/agent/health" > /dev/null 2>&1 && NOMAD_OK=true
curl -sf --max-time 5 "${CONSUL_HTTP_ADDR}/v1/status/leader" > /dev/null 2>&1 && CONSUL_OK=true

if [ "$NOMAD_OK" = true ] && [ "$CONSUL_OK" = false ]; then
  echo "⚠ Consul 不可达，仅显示 Nomad 数据（服务健康信息不可用）"
  # 仅查询 Nomad 节点、Jobs、Allocations
  # 跳过 Consul 服务健康查询

elif [ "$NOMAD_OK" = false ] && [ "$CONSUL_OK" = true ]; then
  echo "⚠ Nomad 不可达，仅显示 Consul 数据（节点和 Job 信息不可用）"
  # 仅查询 Consul 服务状态

elif [ "$NOMAD_OK" = false ] && [ "$CONSUL_OK" = false ]; then
  echo "错误: Nomad 和 Consul 均不可达，无法查询状态"
  echo "修复建议: 运行 /aether:setup 检查集群配置"
  exit 1
fi
```

### API 超时处理

所有 API 请求添加 `--max-time` 防止阻塞：

```bash
# 标准查询（10 秒超时）
RESPONSE=$(curl -sf --max-time 10 "${NOMAD_ADDR}/v1/nodes" 2>&1)
if [ $? -ne 0 ]; then
  echo "⚠ 查询节点状态超时，请检查网络或稍后重试"
fi

# 日志获取（30 秒超时，数据量较大）
LOGS=$(curl -sf --max-time 30 "${NOMAD_ADDR}/v1/client/fs/logs/${ALLOC_ID}?task=api&type=stdout&plain=true" 2>&1)
if [ $? -ne 0 ]; then
  echo "⚠ 获取日志超时"
  echo "  尝试直接获取: ssh root@<node> 'nomad alloc logs ${ALLOC_ID}'"
fi
```

### 常见错误速查

| 错误 | 原因 | 修复 |
|------|------|------|
| `无法连接 Nomad API` | 地址错误或服务未启动 | 检查 `NOMAD_ADDR`，重启 Nomad 服务 |
| `无法连接 Consul API` | 地址错误或服务未启动 | 检查 `CONSUL_HTTP_ADDR`，重启 Consul 服务 |
| `查询超时` | 网络不稳定或集群负载高 | 稍后重试，检查集群资源占用 |
| `请先运行 /aether:setup` | 未配置集群地址 | 运行 `/aether:setup` 完成配置 |
| `jq: parse error` | API 返回非 JSON（HTML 错误页等） | 确认地址和端口正确 |
| `watch 模式自动退出` | Nomad API 连续 5 次无响应 | 检查集群状态后重新启动 watch |

---

## 与其他 Skills 的关系

```
aether-status (基础层)
    ↑
    │ 被调用
    │
aether-deploy-watch (组合层) - 部署监控
aether-doctor (诊断层) - 环境诊断
```

---

**Skill 版本**: 1.1.0
**最后更新**: 2026-03-17
**维护者**: 10CG Infrastructure Team
