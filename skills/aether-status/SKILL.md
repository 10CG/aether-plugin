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

持续监控服务状态，每 5 秒刷新一次：

```bash
while true; do
  clear
  echo "Aether 状态监控 - $(date)"
  echo "================================"
  # 显示状态
  /aether:status my-project
  sleep 5
done
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

**Skill 版本**: 1.0.0
**最后更新**: 2026-03-08
**维护者**: 10CG Infrastructure Team
