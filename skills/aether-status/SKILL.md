---
name: aether-status
description: |
  聚合查询 Aether 集群和服务状态。
  整合 Nomad 节点、Job、Allocation 和 Consul 服务健康信息。

  使用场景："查看集群状态"、"检查服务是否正常"、"查看部署情况"
argument-hint: "[service-name]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash
---

# Aether 状态查询 (aether-status)

> **版本**: 0.1.0 | **优先级**: P1

## 快速开始

### 使用场景

- 查看集群整体健康状态
- 检查特定服务的部署情况
- 排查服务不可用问题

## 执行逻辑

### 无参数 — 集群概览

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

输出格式：

```
Aether 集群状态
===============
Nomad 节点: 3 heavy (ready) + 5 light (ready)
运行中 Jobs: 5 (4 service, 1 batch)
失败 Allocs: 1 (my-project @ heavy-1)
Consul 服务: 8 passing, 1 critical
```

### 指定服务 — 服务详情

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

输出格式：

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
