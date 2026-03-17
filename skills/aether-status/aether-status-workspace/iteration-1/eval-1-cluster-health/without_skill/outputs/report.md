# Aether 集群健康报告

**生成时间**: 2026-03-17 21:55 UTC
**Nomad 地址**: http://192.168.69.80:4646
**Consul 地址**: http://192.168.69.80:8500
**数据中心**: dc1

---

## 总览

| 指标 | 状态 |
|------|------|
| Nomad Server 集群 | **正常** (3/3 alive) |
| Consul 集群 | **正常** (3 Server + 8 Client) |
| Nomad Client 节点 | **正常** (8/8 ready) |
| 运行中 Jobs | 15 |
| 失败的 Allocation | **1 个异常** |
| Consul 健康检查 | **1 个 CRITICAL** |

**整体评估**: 集群基础设施健康，存在 2 个需要关注的应用层问题。

---

## 1. Nomad Server 集群

所有 3 台 Nomad Server 运行正常，版本一致。

| 节点 | IP | 状态 | 版本 |
|------|-----|------|------|
| infra-server-1 | 192.168.69.70 | alive | 1.11.2 |
| infra-server-2 | 192.168.69.71 | alive | 1.11.2 |
| infra-server-3 | 192.168.69.72 | alive | 1.11.2 |

---

## 2. Nomad Client 节点状态

所有 8 个 Client 节点均处于 `ready` 状态，调度资格 `eligible`，无 drain 操作进行中。

### Heavy Nodes (Docker + Exec)

| 节点 | IP | 状态 | 节点类 | Docker | Exec | Host Volumes |
|------|-----|------|--------|--------|------|-------------|
| heavy-1 | 192.168.69.80 | ready | heavy_workload | v29.2.1 | OK | 2 (kairos-data, kairos-prod-data) |
| heavy-2 | 192.168.69.81 | ready | heavy_workload | v29.2.1 | OK | 10 (todo, kairos, nexus) |
| heavy-3 | 192.168.69.82 | ready | heavy_workload | v29.2.1 | OK | 8 (todo, kairos) |

### Light Nodes (Exec only)

| 节点 | IP | 状态 | 节点类 | Exec | Host Volumes |
|------|-----|------|--------|------|-------------|
| light-1 | 192.168.69.90 | ready | light_exec | OK | 0 |
| light-2 | 192.168.69.91 | ready | light_exec | OK | 1 (demo-cache) |
| light-3 | 192.168.69.92 | ready | light_exec | OK | 1 (test-data) |
| light-4 | 192.168.69.93 | ready | light_exec | OK | 1 (test-data) |
| light-5 | 192.168.69.94 | ready | light_exec | OK | 1 (test-data) |

> 备注: 所有 light 节点上的 `raw_exec` 驱动已正确禁用（安全最佳实践）。

---

## 3. 运行中的 Jobs

共 15 个 Job，全部状态为 `running`。

| Job | 类型 | 优先级 | Task Groups | 当前 Running | 历史 Failed | 状态 |
|-----|------|--------|-------------|-------------|-------------|------|
| traefik | service | 50 | traefik | 1 | 4 | OK |
| dev-db | service | 80 | redis, postgres | 2 | 4 (postgres) | OK |
| kairos-dev | service | 50 | kairos | 1 | 3 | OK |
| kairos-prod | service | 50 | kairos | 1 | 2 | OK |
| nexus-api-dev | service | 50 | api | 1 | 1 | OK |
| nexus-db-dev | service | 50 | db | 1 | 0 | OK |
| nexus-redis-dev | service | 50 | redis | 1 | 1 | OK |
| openstock-dev | service | 50 | web | 1 | 1 | OK |
| psych-ai-supervision-dev | service | 50 | api, celery, celery-beat, frontend | 3 | **celery: 2 failed, 0 running** | **ABNORMAL** |
| silknode-gateway | service | 70 | stack | 1 | 0 | OK |
| todo-web-backend-dev | service | 50 | backend | 1 | 0 | OK |
| todo-web-backend-prod | service | 50 | backend | 1 | 0 | OK |
| todo-web-frontend-dev | service | 50 | frontend | 1 | 1 | OK |
| todo-web-frontend-prod | service | 50 | frontend | 1 | 1 | OK |
| wecom-relay | service | 50 | relay | 1 | 0 | OK |

### 当前 Allocation 分布

| 节点 | Running Allocations |
|------|-------------------|
| heavy-1 | 10 (traefik, dev-db x2, todo-web-frontend-dev/prod, openstock-dev, psych-ai-supervision-dev x3, nexus-api-dev) |
| heavy-2 | 7 (todo-web-backend-dev/prod, nexus-db-dev, nexus-redis-dev, kairos-dev, kairos-prod, silknode-gateway) |
| heavy-3 | 1 (wecom-relay) |
| light-1~5 | 0 |

> 备注: Light 节点当前无任何 workload 调度。所有容器化 Job 都分配在 heavy 节点上。

---

## 4. 异常 Allocation 详情

### [CRITICAL] psych-ai-supervision-dev.celery - FAILED

- **Allocation ID**: `47c7970a-4884-c99a-bd9f-cde86a191e75`
- **节点**: heavy-1 (192.168.69.80)
- **Task**: worker
- **状态**: dead (failed)
- **重启次数**: 39 次
- **最终失败时间**: 2026-03-16T09:53:24Z

**失败过程**:
1. Docker 容器反复以 exit code 1 退出（应用层错误）
2. Nomad 按重启策略反复重启（共 39 次）
3. 最终因 Docker 容器清理失败导致不可恢复错误:
   ```
   failed to create container: Failed to purge container e05c48f9...:
   Error response from daemon: cannot remove container: unable to remove
   filesystem: unlinkat /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9...: directory not empty
   ```
4. 标记为 "Error was unrecoverable"，停止重启

**Deployment 状态**: `failed` - "Failed due to progress deadline - not rolling back to stable job version 21 as current job has same specification"

### [WARNING] psych-ai-supervision-dev.api - 运行中但标记为 Unhealthy

- **Allocation ID**: `c130f968-0cc9-14a9-0437-cdfe5fc8ef32`
- **节点**: heavy-1 (192.168.69.80)
- **Task**: api
- **状态**: running (但 DeploymentStatus.Healthy = false)
- **原因**: "Task not running for min_healthy_time of 10s by healthy_deadline of 5m0s"
- **启动时间**: 2026-03-15T01:34:39Z

> 虽然 Task 当前处于 running 状态，但部署健康检查未通过，且 Consul 中该服务的健康检查为 CRITICAL（连接被拒绝）。

---

## 5. Consul 集群状态

### Consul 成员

| 节点 | IP | 角色 | 状态 | 版本 |
|------|-----|------|------|------|
| infra-server-1 | 192.168.69.70 | consul (server) | alive | 1.22.3 |
| infra-server-2 | 192.168.69.71 | consul (server) | alive | 1.22.3 |
| infra-server-3 | 192.168.69.72 | consul (server) | alive | 1.22.3 |
| heavy-1 | 192.168.69.80 | node (client) | alive | 1.22.3 |
| heavy-2 | 192.168.69.81 | node (client) | alive | 1.22.3 |
| heavy-3 | 192.168.69.82 | node (client) | alive | 1.22.3 |
| light-1 | 192.168.69.90 | node (client) | alive | 1.22.3 |
| light-2 | 192.168.69.91 | node (client) | alive | 1.22.3 |
| light-3 | 192.168.69.92 | node (client) | alive | 1.22.3 |
| light-4 | 192.168.69.93 | node (client) | alive | 1.22.3 |
| light-5 | 192.168.69.94 | node (client) | alive | 1.22.3 |

所有 11 个成员状态正常，版本一致 (1.22.3)。

### 注册服务

共 20 个服务注册在 Consul 中:

| 服务 | 节点 | 健康检查 | 状态 |
|------|------|---------|------|
| consul | infra-server-* | serfHealth | passing |
| nomad | infra-server-* | HTTP/RPC/Serf | passing |
| nomad-client | heavy-1/2/3, light-1~5 | HTTP | passing |
| traefik | heavy-1 | HTTP (/ping) | passing |
| dev-db (postgres) | heavy-1 | TCP :5432 | passing |
| dev-redis | heavy-1 | TCP :6379 | passing |
| todo-web-frontend-dev | heavy-1 | HTTP /health | passing |
| todo-web-frontend-prod | heavy-1 | HTTP /health | passing |
| todo-web-backend-dev | heavy-2 | HTTP /health | passing |
| todo-web-backend-prod | heavy-2 | HTTP /health | passing |
| openstock-dev | heavy-1 | HTTP / | passing |
| psych-ai-dev-frontend | heavy-1 | HTTP / | passing |
| **psych-ai-dev-api** | **heavy-1** | **HTTP /health** | **CRITICAL** |
| nexus-api-dev | heavy-1 | HTTP /health | passing |
| nexus-db-dev | heavy-2 | TTL (postgres) | passing |
| nexus-redis-dev | heavy-2 | TCP :6379 | passing |
| kairos-dev | heavy-2 | HTTP /health | passing |
| kairos-prod | heavy-2 | HTTP /health | passing |
| silknode-gateway | heavy-2 | HTTP / | passing |
| silknode-redis | heavy-2 | TCP :16379 | passing |
| wecom-relay | heavy-3 | HTTP /health | passing |

### [CRITICAL] psych-ai-dev-api 健康检查失败

```
GET http://192.168.69.80:31198/health: dial tcp 192.168.69.80:31198: connect: connection refused
```

端口 31198 上的 API 服务无法连接。这与 Nomad 中该 allocation 的 unhealthy 状态一致。

### [WARNING] kairos-prod 组件降级

kairos-prod 健康检查返回 passing，但响应体中有 3 个组件报告 false:

```json
{
  "wecomApi": false,
  "relayClient": false,
  "mediaHandler": false
}
```

这意味着 kairos-prod 的企业微信 API、Relay 客户端和媒体处理功能当前不可用。

### [INFO] wecom-relay Token 过期

wecom-relay 健康检查 passing，但响应显示:
```json
{
  "tokenValid": false,
  "tokenExpiresIn": 0
}
```

微信 Token 已过期，可能影响 kairos-prod 的 wecomApi 组件。

---

## 6. 异常汇总与建议

### CRITICAL - 需要立即处理

#### 1. psych-ai-supervision-dev celery worker 完全停止

**问题**: Celery worker 反复崩溃 (exit code 1)，在 39 次重启后因 Docker 容器清理失败而永久停止。

**建议**:
1. 检查 Celery worker 日志，定位 exit code 1 的根本原因:
   ```bash
   nomad alloc logs 47c7970a worker
   ```
2. 清理 heavy-1 上残留的 Docker 容器文件系统:
   ```bash
   ssh root@heavy-1 "docker system prune -f"
   ssh root@heavy-1 "rm -rf /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9*"
   ```
3. 修复应用错误后，重新部署或强制重新调度:
   ```bash
   nomad job dispatch psych-ai-supervision-dev
   # 或者
   nomad alloc restart -task worker <new-alloc-id>
   ```

#### 2. psych-ai-dev-api 健康检查 CRITICAL

**问题**: API 进程在运行中，但 Consul 健康检查连接被拒绝 (port 31198)。Deployment 标记为 unhealthy。

**建议**:
1. 检查 API 容器日志:
   ```bash
   nomad alloc logs c130f968 api
   ```
2. 确认端口绑定是否正确，容器内进程是否正常监听
3. 可能需要重新部署以获得新的健康 allocation

### WARNING - 需要关注

#### 3. kairos-prod 组件降级 (wecomApi, relayClient, mediaHandler)

**问题**: 三个核心组件不可用，可能影响生产环境中的企业微信集成和媒体处理。

**建议**:
1. 检查 wecom-relay 服务的 Token 刷新机制（当前 Token 已过期）
2. wecom-relay 运行在 heavy-3 上，确认其是否能正常连接到企业微信 API
3. Token 过期可能是 kairos-prod 中 wecomApi 和 relayClient 为 false 的根本原因
4. 检查 mediaHandler 依赖的外部服务是否可达

#### 4. 负载分布不均

**问题**:
- heavy-1 承担 10 个 allocation
- heavy-2 承担 7 个 allocation
- heavy-3 仅承担 1 个 allocation
- 所有 5 个 light 节点完全空闲

**建议**:
1. 考虑将部分无状态服务迁移到 heavy-3
2. 评估 light 节点是否可以运行容器化工作负载（当前仅有 exec 驱动）
3. 如果 light 节点不打算运行 Docker 工作负载，可以考虑安装 Docker 或调整调度约束

### INFO - 供参考

#### 5. 历史 Failed Allocations

多个 Job 有历史 failed 记录，但当前都已恢复正常运行:

| Job | Task Group | 历史 Failed 次数 |
|-----|-----------|----------------|
| dev-db | postgres | 4 |
| traefik | traefik | 4 |
| kairos-dev | kairos | 3 |
| kairos-prod | kairos | 2 |
| psych-ai-supervision-dev | celery | 2 |

这些可能是部署过程中的正常重试，不需要立即处理，但建议定期清理以保持监控清晰度。

---

## 7. 配置备注

当前 `~/.aether/config.yaml` 中的 Nomad/Consul 地址为 `192.168.69.70` (infra-server-1)，与本次查询使用的 `192.168.69.80` (heavy-1) 不同。两个地址都可以工作，因为:
- infra-server-1 (70) 是 Nomad Server 主节点
- heavy-1 (80) 是 Nomad Client，也可通过其转发 API 请求

建议统一使用 `192.168.69.70` (infra-server-1) 作为 API 入口，因为它是专用的基础设施服务器。

---

*报告生成方式: 直接查询 Nomad API (/v1/nodes, /v1/jobs, /v1/allocations, /v1/deployments) 和 Consul API (/v1/agent/members, /v1/health/state/any, /v1/catalog/services)*
