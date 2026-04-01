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

> **版本**: 2.0.0 | **优先级**: P0

## 核心原则

**调查优先，不是清单。** 异常信号是入口，不是终点。发现一个问题时，追踪到根因再停。

- 不要停在计数层面（"3 个 critical"）—— 查看每个 critical 的 Output 内容
- 不要停在 Consul API 层面 —— 验证 Raft 共识、Serf 成员、DNS 解析
- 不要停在 Allocation 状态 —— 检查 TaskStates 事件链、退出码、资源使用
- 发现负载不均时 —— 计算每个节点的精确分配率百分比，不只说"不均衡"

---

## 集群拓扑（查询前必须理解）

```
Infra 层 (192.168.69.70-72): Nomad Server + Consul Server + dnsmasq
  → .service.consul DNS 解析依赖这 3 台 dnsmasq
  → Consul Raft 共识在这 3 台之间

Heavy 节点 (heavy-1/2/3, 192.168.69.80-82): Docker workload
  → 所有容器服务运行在此
  → node_class = heavy_workload

Light 节点 (light-1~5, 192.168.69.90-94): exec only
  → 仅运行 exec driver 任务，无 Docker
  → node_class = light_exec，空闲是正常状态
```

---

## 调查信号映射

发现以下信号时，按箭头方向深入：

| 信号 | 调查方向 |
|------|---------|
| Allocation failed | → TaskStates 事件链 → 退出码 → 区分 OOM / image pull / crash loop / port conflict |
| Consul health critical | → 查看 Check Output 具体内容 → 区分 connection refused / timeout / 500 |
| 节点负载 >80% | → 列出该节点所有 alloc 的资源分配 → 标注 Warning；>95% 标注 Critical |
| 同一 Job 反复失败 | → 检查是否每次在同一节点 → 节点级 driver/disk/OOM 问题 |
| 同一节点集中失败 | → 检查 Docker driver 状态、磁盘空间、dmesg OOM 记录 |
| Nomad running + Consul 0 passing | → **Phantom alloc** (Issue #12): 检查 TaskStates.State 是否 dead |
| 部署后服务降级 | → 对比前后 Job spec 版本差异（镜像、资源、count） |
| Consul 不可达 | → 不只报错，主动验证 Raft leader / Serf members / DNS 8600 / KV store |

---

## 输出要求

### 严重度分级（必须使用）

| 级别 | 定义 | 示例 |
|------|------|------|
| **Critical** | 用户可感知的服务中断 | alloc 全部 failed、Consul 0 passing、端口不可达 |
| **Warning** | 降级但可用 | 部分 alloc pending、节点负载 >80%、单点故障风险 |
| **Info** | 潜在风险 | 资源分布不均、历史失败记录、配置非最优 |

### 可行动建议（必须具体）

不要只说"建议增加资源"。给出具体内容：
- HCL stanza 示例（constraint/spread/affinity/resources 的具体值）
- 迁移计划：before/after allocation 分布表
- 操作命令：`nomad alloc stop`、`nomad node drain`、具体 job run 命令

---

## 查询入口

- **无参数**: 集群全局健康 — 节点、Job、Allocation、Consul、资源
- **`<job>`**: 单服务深入 — 元信息、镜像、alloc 分布、Consul 实例、部署历史
- **`--failed`**: 失败 alloc 根因分析 — 事件链、模式识别、资源相关、镜像问题
- **`--recent`**: 近期部署时间线 — 版本变更、失败/回滚标注、spec diff
- **`--logs`**: 日志获取 — running + failed alloc 的 stdout/stderr，错误模式识别
- **`--watch`**: 持续监控 — 每 5 秒刷新，连续 5 次失败自动退出

---

## Consul 深度检查（不要跳过）

对 Consul 不要只看 `/v1/health/state/critical` 的计数。始终覆盖：

- **Raft 共识**: `GET /v1/status/leader` + `GET /v1/status/peers` → leader 是否稳定，3 voter 是否一致
- **Serf 成员**: `GET /v1/agent/members` → 所有节点是否 alive，有无 failed/left
- **DNS 解析**: `dig @192.168.69.70 <service>.service.consul` → 验证 dnsmasq 转发链路
- **健康检查详情**: `GET /v1/health/service/{name}` → 读 Check Output，不只看 Status

---

## 降级策略

- **Nomad 可达 + Consul 不可达**: 展示 Nomad 数据，同时主动诊断 Consul 为何不可达（Raft? Serf? 网络?）
- **双不可达**: 报错 + 建议 `/aether:setup --show` 确认配置

---

## 前置条件

执行前需要 Aether 集群配置。读取 `.aether/config.yaml` 或 `~/.aether/config.yaml` 中的 `cluster.nomad_addr` 和 `cluster.consul_addr`。未配置时提示运行 `/aether:setup`。
