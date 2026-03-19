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

> **版本**: 1.2.0 | **优先级**: P0

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

以下描述各场景建议覆盖的信息维度。具体查询方式、顺序和输出组织可根据实际情况灵活调整，鼓励超越列表范围主动探索。

### 集群概览（无参数）

查询集群全局健康状况，覆盖以下维度：

- **Nomad 节点健康**: 各节点 Status、Eligibility、NodeClass 分布、Drain 状态
- **Job 运行状态**: 数量、类型分布（service/batch/system）、Dead/Pending 异常
- **Allocation 健康**: Running vs Failed vs Pending 分布，关联 Job 和节点
- **Consul 服务健康**: passing/warning/critical 数量及具体服务名
- **资源利用率**: 各节点 CPU/Memory/Disk 已分配与可用比率
- **调度约束**: 是否有 Job 因约束 (constraint/affinity) 无法调度

发现异常信号时，不要停在数字层面 -- 追踪具体原因。

---

### 服务详情（指定 job-name）

深入查看单个服务的完整状态，覆盖以下维度：

- **Job 元信息**: 类型、Status、当前版本号、TaskGroup 配置
- **容器镜像**: 正在使用的镜像及 tag，是否与预期一致
- **Allocation 分布**: 各 allocation 的节点位置、状态、版本号、健康检查结果
- **Consul 服务实例**: 地址、端口、健康检查输出内容（不仅是 passing/critical）
- **部署历史**: 最近版本变更时间线，是否有回滚记录
- **网络与端口**: 动态端口分配、服务发现 DNS 记录
- **资源实际使用**: allocation 的 CPU/Memory 实际使用 vs 分配值

---

### 失败的 Allocations（--failed）

分析失败 allocation 的根因，覆盖以下维度：

- **失败清单**: 每个失败 allocation 的 Job、TaskGroup、节点、失败时间
- **退出详情**: TaskStates 中的退出码、事件链、重启次数
- **模式识别**: 同一 Job 反复失败？同一节点集中失败？特定时间段集中？
- **资源相关**: 是否因 OOM 被 kill、磁盘空间不足、端口冲突
- **镜像问题**: 是否因镜像拉取失败（registry 不可达、tag 不存在）
- **依赖失败**: 是否因前置服务未就绪导致健康检查超时

---

### 最近部署（--recent）

回顾近期部署活动，覆盖以下维度：

- **部署时间线**: 最近部署的 Job 名称、版本、时间、状态
- **失败部署**: 标注失败或回滚的部署，分析失败原因
- **版本变更**: 对比部署前后的 Job spec 差异（镜像、资源、count）
- **部署策略**: canary/rolling 部署的进度和健康判定

---

### 日志查看（--logs）

获取服务日志用于诊断，覆盖以下维度：

- **运行中实例**: 获取 running allocation 的 stdout 和 stderr
- **失败实例**: 如服务已失败，获取最近失败 allocation 的日志
- **错误模式**: 识别日志中的异常模式（panic、connection refused、timeout）
- **时间关联**: 将日志事件与 allocation 状态变更时间对应

---

### 持续监控（--watch）

持续监控服务状态。建议：
- 每 5 秒刷新，连续失败 5 次自动退出
- 检查 API 可达性后再查询状态
- 失败时提示用户检查 `NOMAD_ADDR`

---

## 深入调查指引

**核心原则**: 基础查询只是起点。发现任何异常信号时，主动深入追踪根因，覆盖用户请求的所有维度，并超越这些维度提供洞察。

### Consul 内部健康

- **Raft 共识**: leader 是否稳定、commit index 是否一致、是否有 leadership 切换
- **Serf 成员**: 所有成员是否 alive、是否有 failed/left 节点、网络分区迹象
- **DNS 解析**: 服务 DNS 记录 (`<service>.service.consul`) 是否正确解析
- **KV 依赖**: 服务是否依赖 Consul KV 中的配置，KV 中的值是否正确
- **健康检查详情**: 不仅看 passing/critical 计数，查看具体检查的 Output 内容

### 资源分析

- **节点级资源**: 每个节点的 CPU/Memory/Disk 总量、已分配量、可用量
- **过度分配**: 是否有节点分配率 >90%，存在资源争抢风险
- **调度约束**: constraint/affinity/spread 策略是否导致资源不均衡
- **资源趋势**: 对比当前资源使用与历史水平，预判容量瓶颈

### 服务拓扑

- **域名路由**: 从域名到 Traefik/反向代理到 Nomad Job 的完整路径
- **服务间依赖**: 服务 A 依赖服务 B 时，B 的健康状况如何
- **端口映射**: 动态端口分配、静态端口冲突检测
- **跨节点通信**: 服务实例分布在不同节点时的网络连通性

### 影响评估

- **严重度分级**: Critical（用户可感知的服务中断）、Warning（降级但可用）、Info（潜在风险）
- **影响范围**: 受影响的 Job 数量、用户面服务 vs 内部服务
- **级联风险**: 当前问题是否可能导致其他服务连锁失败

### 可行动建议

- **HCL 优化**: 建议 constraint/spread/affinity 调整以改善调度
- **扩缩容**: 基于资源分析建议 count 调整或节点扩容
- **配置修复**: 具体的配置修改建议（镜像 tag、资源限制、健康检查参数）
- **运维操作**: 需要执行的 drain/restart/redeploy 操作及其风险

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

# Raft 状态
GET ${CONSUL_HTTP_ADDR}/v1/status/leader
GET ${CONSUL_HTTP_ADDR}/v1/status/peers

# Serf 成员
GET ${CONSUL_HTTP_ADDR}/v1/agent/members

# KV 读取
GET ${CONSUL_HTTP_ADDR}/v1/kv/{key}

# DNS 查询
dig @<consul-ip> <service>.service.consul
```

---

## 前置条件：集群配置

执行前需要配置 Aether 集群入口，参考 `/aether:setup`。

### 配置读取

```bash
# 1. 检查项目配置
if [ -f ".aether/config.yaml" ]; then
  NOMAD_ADDR=$(yq '.cluster.nomad_addr' .aether/config.yaml)
  CONSUL_HTTP_ADDR=$(yq '.cluster.consul_addr' .aether/config.yaml)
fi

# 2. 检查全局配置
if [ -z "$NOMAD_ADDR" ] && [ -f "$HOME/.aether/config.yaml" ]; then
  NOMAD_ADDR=$(yq '.cluster.nomad_addr' ~/.aether/config.yaml)
  CONSUL_HTTP_ADDR=$(yq '.cluster.consul_addr' ~/.aether/config.yaml)
fi

# 3. 未配置则提示
if [ -z "$NOMAD_ADDR" ]; then
  echo "请先运行 /aether:setup 配置集群"
  exit 1
fi
```

---

## 故障处理

### 连通性检查原则

- 所有 API 调用前先检查连通性，使用 `--max-time 5` 防止阻塞
- 检查端点：Nomad `/v1/agent/health`，Consul `/v1/status/leader`
- 连接失败时：确认地址、测试网络、检查服务状态、尝试 `/aether:setup`

### 降级策略

- **Nomad 可达 + Consul 不可达**：仅显示 Nomad 数据，标注服务健康信息不可用
- **Consul 可达 + Nomad 不可达**：仅显示 Consul 数据，标注节点和 Job 信息不可用
- **双不可达**：报错并建议检查集群配置

### 超时建议

- 标准查询：10 秒超时
- 日志获取：30 秒超时（数据量较大）
- 超时后可尝试 SSH 直连节点获取日志

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

**Skill 版本**: 1.2.0
**最后更新**: 2026-03-19
**维护者**: 10CG Infrastructure Team
