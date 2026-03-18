# Aether 集群降级状态报告

**生成时间**: 2026-03-18
**报告类型**: 部分组件不可达 — 降级状态评估
**用户报告**: Consul (http://192.168.69.70:8500) 疑似不可用，Nomad (http://192.168.69.70:4646) 正常

---

## 1. 连通性诊断结果

| 组件 | 地址 | 状态 | 备注 |
|------|------|------|------|
| **Consul API** | http://192.168.69.70:8500 | **可达** | Leader: 192.168.69.70:8300 |
| **Consul DNS** | 192.168.69.70:8600 | **可达** | 正常解析 consul.service.consul |
| **Consul KV** | http://192.168.69.70:8500/v1/kv | **可达** | KV 数据可读 |
| **Nomad API** | http://192.168.69.70:4646 | **可达** | Leader: 192.168.69.71:4647 |

> **结论**: 经实际测试，Consul API 当前是**可达的**。用户观察到的不可用可能是临时性网络波动、客户端侧问题、或已自行恢复。以下报告基于实际查询到的数据。

---

## 2. Consul 集群状态

### 2.1 Raft 共识

| 节点 | 地址 | 角色 | 状态 |
|------|------|------|------|
| infra-server-1 | 192.168.69.70:8300 | Voter | **LEADER** |
| infra-server-2 | 192.168.69.71:8300 | Voter | Follower |
| infra-server-3 | 192.168.69.72:8300 | Voter | Follower |

Consul 集群 3 节点 Raft 共识正常，Leader 选举稳定。

### 2.2 集群成员 (Serf)

| 成员 | IP | Status | 角色 |
|------|-----|--------|------|
| infra-server-1 | 192.168.69.70 | alive (1) | consul (server) |
| infra-server-2 | 192.168.69.71 | alive (1) | consul (server) |
| infra-server-3 | 192.168.69.72 | alive (1) | consul (server) |
| heavy-1 | 192.168.69.80 | alive (1) | node (client) |
| heavy-2 | 192.168.69.81 | alive (1) | node (client) |
| heavy-3 | 192.168.69.82 | alive (1) | node (client) |
| light-1 | 192.168.69.90 | alive (1) | node (client) |
| light-2 | 192.168.69.91 | alive (1) | node (client) |
| light-3 | 192.168.69.92 | alive (1) | node (client) |
| light-4 | 192.168.69.93 | alive (1) | node (client) |
| light-5 | 192.168.69.94 | alive (1) | node (client) |

全部 11 个成员在线，无节点离线。

### 2.3 Consul 注册节点

共 11 个节点在 Consul catalog 中注册:
- 3 个 infra-server 节点 (192.168.69.70-72)
- 3 个 heavy 节点 (192.168.69.80-82)
- 5 个 light 节点 (192.168.69.90-94)

Consul 版本: **1.22.3** (全部节点一致)

---

## 3. Nomad 集群状态

### 3.1 Nomad Server Peers

| Server | 地址 |
|--------|------|
| infra-server-1 | 192.168.69.70:4647 |
| infra-server-2 | 192.168.69.71:4647 |
| infra-server-3 | 192.168.69.72:4647 |

Leader: **192.168.69.71:4647** (infra-server-2)

### 3.2 Nomad 节点状态

| 节点 | IP | Status | Class | Docker | Exec | 版本 |
|------|-----|--------|-------|--------|------|------|
| heavy-1 | 192.168.69.80 | **ready** | heavy_workload | Yes | Yes | 1.11.2 |
| heavy-2 | 192.168.69.81 | **ready** | heavy_workload | Yes | Yes | 1.11.2 |
| heavy-3 | 192.168.69.82 | **ready** | heavy_workload | Yes | Yes | 1.11.2 |
| light-1 | 192.168.69.90 | **ready** | light_exec | No | Yes | 1.11.2 |
| light-2 | 192.168.69.91 | **ready** | light_exec | No | Yes | 1.11.2 |
| light-3 | 192.168.69.92 | **ready** | light_exec | No | Yes | 1.11.2 |
| light-4 | 192.168.69.93 | **ready** | light_exec | No | Yes | 1.11.2 |
| light-5 | 192.168.69.94 | **ready** | light_exec | No | Yes | 1.11.2 |

全部 8 个 Client 节点状态 **ready**，调度资格 **eligible**，无节点处于 drain 状态。

---

## 4. Jobs 运行状态

### 4.1 Jobs 总览

共 **17 个 Jobs**，全部状态为 **running**。

| Job | 类型 | 优先级 | 状态 | Task Groups |
|-----|------|--------|------|-------------|
| traefik | service | 50 | running | traefik |
| dev-db | service | 80 | running | redis, postgres |
| kairos-dev | service | 50 | running | kairos |
| kairos-prod | service | 50 | running | kairos |
| mailpit | service | 30 | running | mailpit |
| nexus-api-dev | service | 50 | running | api |
| nexus-db-dev | service | 50 | running | db |
| nexus-redis-dev | service | 50 | running | redis |
| openstock-dev | service | 50 | running | web |
| psych-ai-supervision-dev | service | 50 | running | api, frontend, celery-beat, celery |
| silknode-gateway | service | 70 | running | stack |
| silknode-web | service | 60 | running | web |
| todo-web-backend-dev | service | 50 | running | backend |
| todo-web-backend-prod | service | 50 | running | backend |
| todo-web-frontend-dev | service | 50 | running | frontend |
| todo-web-frontend-prod | service | 50 | running | frontend |
| wecom-relay | service | 50 | running | relay |

### 4.2 运行中的 Allocations (20 个)

| Job | Task Group | 节点 | 状态 |
|-----|-----------|------|------|
| dev-db | redis | heavy-1 | running |
| dev-db | postgres | heavy-1 | running |
| kairos-dev | kairos | heavy-2 | running |
| kairos-prod | kairos | heavy-2 | running |
| mailpit | mailpit | heavy-1 | running |
| nexus-api-dev | api | heavy-1 | running |
| nexus-db-dev | db | heavy-2 | running |
| nexus-redis-dev | redis | heavy-2 | running |
| openstock-dev | web | heavy-1 | running |
| psych-ai-supervision-dev | api | heavy-1 | running |
| psych-ai-supervision-dev | frontend | heavy-1 | running |
| psych-ai-supervision-dev | celery-beat | heavy-1 | running |
| silknode-gateway | stack | heavy-2 | running |
| silknode-web | web | heavy-1 | running |
| todo-web-backend-dev | backend | heavy-2 | running |
| todo-web-backend-prod | backend | heavy-2 | running |
| todo-web-frontend-dev | frontend | heavy-1 | running |
| todo-web-frontend-prod | frontend | heavy-1 | running |
| traefik | traefik | heavy-1 | running |
| wecom-relay | relay | heavy-3 | running |

**工作负载分布**:
- **heavy-1**: 12 个 allocations (高负载)
- **heavy-2**: 7 个 allocations
- **heavy-3**: 1 个 allocation (wecom-relay)
- **light-1~5**: 0 个 allocations (仅支持 exec driver，无 Docker)

### 4.3 失败的 Allocations

| Job | Task Group | 节点 | 状态 |
|-----|-----------|------|------|
| psych-ai-supervision-dev | celery | heavy-1 | **failed** |
| mailpit | mailpit | heavy-2 | **failed** (历史，已在 heavy-1 重新调度成功) |

**psych-ai-supervision-dev/celery** 是唯一当前未运行的 task group，celery worker 已失败且未被重新调度成功。

---

## 5. 服务发现状态 (Consul 视角)

### 5.1 注册的服务 (25 个)

| 服务 | 标签/路由 |
|------|----------|
| consul | (内部) |
| nomad | serf, http, rpc |
| nomad-client | http |
| dev-db | database, postgresql, development |
| dev-redis | redis, development, cache |
| kairos-dev | Host(`kairos-dev.10cg.pub`) |
| kairos-prod | Host(`kairos.10cg.pub`) |
| mailpit-smtp | smtp, dev-tool |
| mailpit-ui | dev-tool, mail |
| nexus-api-dev | Host(`nexus-dev.10cg.pub`) |
| nexus-db-dev | (internal) |
| nexus-redis-dev | (internal) |
| openstock-dev | Host(`openstock-dev.10cg.pub`) |
| psych-ai-dev-api | Host(`psych-dev.10cg.pub`) && PathPrefix(`/api`) |
| psych-ai-dev-frontend | Host(`psych-dev.10cg.pub`) |
| silknode-gateway | api, gateway |
| silknode-redis | cache, redis |
| silknode-web | web, nextjs |
| todo-web-backend-dev | Host(`todo-dev.10cg.pub`) && PathPrefix(`/api`) |
| todo-web-backend-prod | Host(`todo.10cg.pub`) && PathPrefix(`/api`) |
| todo-web-frontend-dev | Host(`todo-dev.10cg.pub`) |
| todo-web-frontend-prod | Host(`todo.10cg.pub`) |
| traefik | traefik.enable=true |
| wecom-relay | wecom, relay |

### 5.2 健康检查状态

**Critical (1)**:
| 服务 | 节点 | 状态 | 原因 |
|------|------|------|------|
| psych-ai-dev-api | heavy-1 | **CRITICAL** | `connection refused` on :31198/health |

**Warning (0)**: 无

**Passing (37)**: 其余所有服务健康检查通过

---

## 6. 假设性分析: 若 Consul 真的不可用，影响范围

尽管当前 Consul 实际可达，以下分析假设 Consul 完全不可用时的影响：

### 6.1 直接影响

| 影响面 | 说明 | 严重程度 |
|--------|------|----------|
| **Traefik 路由** | Traefik 通过 Consul Catalog 进行服务发现，无法发现新服务或更新路由 | **高** |
| **服务发现** | 服务间通过 Consul DNS/API 发现彼此的能力丧失 | **高** |
| **健康检查** | Consul 健康检查停止更新，无法区分健康/不健康实例 | **中** |
| **KV 配置** | kairos 等服务依赖 Consul KV 存储配置（API keys、secrets） | **高** |

### 6.2 不受影响的功能

| 功能 | 说明 |
|------|------|
| **Nomad 调度** | Nomad 可独立运行，Job 调度不依赖 Consul |
| **已运行容器** | 已启动的容器继续运行 |
| **已建立连接** | 通过 IP 直连的服务不受影响 |
| **Traefik 已缓存路由** | 已加载的路由规则在 Traefik 重启前保持有效 |

### 6.3 受影响的服务清单 (Traefik 路由)

以下服务通过 Traefik + Consul 进行流量路由，Consul 不可用会导致**新部署无法被路由发现**：

| 域名 | 服务 | 当前状态 |
|------|------|----------|
| todo-dev.10cg.pub | todo-web-frontend-dev / backend-dev | 正常 |
| todo.10cg.pub | todo-web-frontend-prod / backend-prod | 正常 |
| kairos-dev.10cg.pub | kairos-dev | 正常 |
| kairos.10cg.pub | kairos-prod | 正常 |
| openstock-dev.10cg.pub | openstock-dev | 正常 |
| nexus-dev.10cg.pub | nexus-api-dev | 正常 |
| psych-dev.10cg.pub | psych-ai-dev-api / frontend | **API 端 Critical** |

---

## 7. 问题汇总与建议

### 7.1 当前实际问题

| # | 问题 | 严重程度 | 建议操作 |
|---|------|----------|----------|
| 1 | **psych-ai-dev-api 健康检查 Critical** | 中 | 检查 API 进程是否正常监听端口 31198，可能需要重启 allocation |
| 2 | **psych-ai-supervision-dev/celery worker 失败** | 中 | Celery worker 未运行，异步任务无法处理，检查日志排查失败原因 |
| 3 | **heavy-1 负载集中** | 低 | 12/20 个 allocation 集中在 heavy-1，考虑分散调度 |
| 4 | **light 节点闲置** | 低 | 5 个 light 节点无工作负载（仅支持 exec driver，无 Docker） |

### 7.2 Consul 连通性

Consul 当前实际**可达**。如果之前确实观察到不可用：
1. 检查客户端侧网络（防火墙、DNS 解析）
2. 查看 Consul server 日志: `journalctl -u consul -n 100 --since "1 hour ago"`
3. 检查是否有临时性 Leader 选举事件: `curl http://192.168.69.70:8500/v1/operator/raft/configuration`
4. 监控 Consul 集群健康: `consul monitor -log-level=warn`

---

## 8. 总结

| 指标 | 值 |
|------|-----|
| Consul 状态 | **可达** (3/3 servers alive, Leader stable) |
| Nomad 状态 | **可达** (3/3 servers, Leader on infra-server-2) |
| 节点健康 | **8/8 ready** (全部 Client 节点正常) |
| Jobs 运行 | **17/17 running** |
| Allocations | **20 running** / 2 failed (历史) |
| 健康检查 | **1 critical** (psych-ai-dev-api) / 0 warning |
| 服务发现 | **正常** (25 服务注册, DNS 可用) |

**整体评估**: 集群运行基本正常。Consul 和 Nomad 均可达，无降级状态。唯一需要关注的是 psych-ai-supervision-dev 项目的 API 健康检查失败和 celery worker 未运行。
