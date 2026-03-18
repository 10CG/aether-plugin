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

## 查询模式

以下描述各场景建议覆盖的信息维度。具体查询顺序和输出组织方式可根据实际情况灵活调整。

### 集群概览（无参数）

建议覆盖的信息：
- **Nomad 节点**: 各节点状态、NodeClass 分布
- **运行中的 Jobs**: 数量、类型分布（service/batch/system）
- **失败的 Allocations**: 数量及关联的 Job 和节点
- **Consul 服务健康**: passing/critical 数量

常用查询：

```bash
curl -s "${NOMAD_ADDR}/v1/nodes" | jq '[.[] | {name: .Name, status: .Status, class: .NodeClass}]'
curl -s "${NOMAD_ADDR}/v1/jobs" | jq '[.[] | select(.Status == "running") | {name: .Name, type: .Type, status: .Status}]'
curl -s "${NOMAD_ADDR}/v1/allocations" | jq '[.[] | select(.ClientStatus == "failed") | {job: .JobID, node: .NodeName, status: .ClientStatus}]'
curl -s "${CONSUL_HTTP_ADDR}/v1/health/state/critical" | jq 'length'
```

---

### 服务详情（指定 job-name）

建议覆盖的信息：
- **Job 状态**: 类型、运行状态、当前版本、使用的镜像
- **Allocations**: 各 allocation 的节点分布、状态、版本
- **Consul 健康**: 服务实例地址、端口、健康状态
- **部署历史**: 最近部署时间

常用查询：

```bash
curl -s "${NOMAD_ADDR}/v1/job/{job_id}" | jq '{name: .Name, type: .Type, status: .Status, version: .Version}'
curl -s "${NOMAD_ADDR}/v1/job/{job_id}/allocations" | jq '[.[] | {id: .ID[:8], node: .NodeName, status: .ClientStatus, version: .JobVersion}]'
curl -s "${CONSUL_HTTP_ADDR}/v1/health/service/{job_id}?passing" | jq '[.[] | {node: .Node.Node, address: .Service.Address, port: .Service.Port}]'
```

---

### 失败的 Allocations（--failed）

建议覆盖的信息：
- 每个失败 allocation 的 **Job、TaskGroup、节点、失败时间**
- **TaskStates** 中的退出码和事件详情
- 如有重复失败模式（同一 Job 或同一节点反复失败），**指出模式**

常用查询：

```bash
# 获取失败的 allocations 列表
curl -s "${NOMAD_ADDR}/v1/allocations?filter=ClientStatus==failed"

# 获取单个 allocation 详情
curl -s "${NOMAD_ADDR}/v1/allocation/${alloc_id}"
```

---

### 最近部署（--recent）

建议覆盖的信息：
- 最近部署的 **Job 名称、状态、版本、更新时间**
- 标注任何 **失败的部署**

常用查询：

```bash
curl -s "${NOMAD_ADDR}/v1/jobs" | jq '[.[] | {name: .Name, status: .Status, version: .Version, modify_index: .ModifyIndex}] | sort_by(-.modify_index) | .[0:10]'
```

---

### 日志查看（--logs）

建议覆盖的信息：
- 目标服务 running allocation 的 **stdout 和 stderr**
- 如果服务已失败，获取 **最近失败 allocation 的日志**

常用查询：

```bash
ALLOC_ID=$(curl -s "${NOMAD_ADDR}/v1/job/{job_id}/allocations" | jq -r '[.[] | select(.ClientStatus == "running") | .ID][0]')
curl -s "${NOMAD_ADDR}/v1/client/fs/logs/${ALLOC_ID}?task={task}&type=stdout&plain=true" | tail -100
curl -s "${NOMAD_ADDR}/v1/client/fs/logs/${ALLOC_ID}?task={task}&type=stderr&plain=true" | tail -100
```

---

### 持续监控（--watch）

持续监控服务状态。建议：
- 每 5 秒刷新，连续失败 5 次自动退出
- 检查 API 可达性后再查询状态
- 失败时提示用户检查 `NOMAD_ADDR`

---

## 深入调查指引

在完成基本查询后，深入调查任何发现的异常。不要局限于上述查询模式 -- 以下是值得探索的方向：

- **依赖链**: 如果某服务异常，检查它依赖的其他服务是否也有问题
- **节点级别**: 如果多个服务在同一节点失败，调查节点本身的资源状况（CPU、内存、磁盘）
- **历史模式**: 对比当前状态与近期部署历史，判断是新引入的问题还是长期存在
- **日志关联**: 结合 stdout/stderr 日志和 allocation 事件，还原故障时间线
- **Consul 健康检查详情**: 不仅看 passing/critical 数量，还看具体的检查输出内容

**核心原则**: 覆盖所有用户请求的维度，但不止步于此。发现异常信号时主动追踪根因。

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
