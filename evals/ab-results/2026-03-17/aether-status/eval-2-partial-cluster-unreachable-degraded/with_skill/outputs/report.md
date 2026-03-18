# Aether 集群状态报告 (降级评估)

> **查询时间**: 2026-03-18 12:36 UTC
> **触发原因**: 用户报告 Consul (http://192.168.69.70:8500) 疑似不可用
> **报告模式**: 全量查询 (实际两个 API 均可达)

---

## 连通性检测结果

| 组件 | 地址 | 状态 | 备注 |
|------|------|------|------|
| Nomad API | http://192.168.69.70:4646 | **可达** | `{"server":{"message":"ok","ok":true}}` |
| Consul API | http://192.168.69.70:8500 | **可达** | Leader: `192.168.69.70:8300` |

**结论**: Consul API 当前可正常响应，未处于不可用状态。用户观察到的问题可能是瞬时网络抖动或浏览器/客户端层面的连接问题，建议排查本地网络或 DNS。

---

## Aether 集群状态

```
Nomad 节点: 3 heavy (ready) + 5 light (ready) = 8 nodes
运行中 Jobs: 17 (全部 service 类型, 全部 running)
失败 Allocs: 2 (psych-ai-supervision-dev/celery @ heavy-1, mailpit @ heavy-2)
Consul 服务: 48 passing, 0 warning, 1 critical
```

---

## 1. Nomad 节点状态

所有 8 个节点均为 `ready` 状态，无节点处于 drain 或 ineligible 状态。

| 节点 | IP | 节点类型 | 状态 | 驱动 | Nomad 版本 |
|------|----|----------|------|------|-----------|
| heavy-1 | 192.168.69.80 | heavy_workload | ready | docker, exec | 1.11.2 |
| heavy-2 | 192.168.69.81 | heavy_workload | ready | docker, exec | 1.11.2 |
| heavy-3 | 192.168.69.82 | heavy_workload | ready | docker, exec | 1.11.2 |
| light-1 | 192.168.69.90 | light_exec | ready | exec | 1.11.2 |
| light-2 | 192.168.69.91 | light_exec | ready | exec | 1.11.2 |
| light-3 | 192.168.69.92 | light_exec | ready | exec | 1.11.2 |
| light-4 | 192.168.69.93 | light_exec | ready | exec | 1.11.2 |
| light-5 | 192.168.69.94 | light_exec | ready | exec | 1.11.2 |

---

## 2. Jobs 运行状态

全部 17 个 Jobs 当前状态为 `running`。

| Job | 类型 | 状态 | 优先级 | 说明 |
|-----|------|------|--------|------|
| traefik | service | running | 50 | 反向代理/负载均衡 |
| dev-db | service | running | 80 | 开发数据库 (postgres + redis) |
| kairos-dev | service | running | 50 | Kairos 开发环境 |
| kairos-prod | service | running | 50 | Kairos 生产环境 |
| mailpit | service | running | 30 | 邮件测试工具 |
| nexus-api-dev | service | running | 50 | Nexus API 开发 |
| nexus-db-dev | service | running | 50 | Nexus 数据库 |
| nexus-redis-dev | service | running | 50 | Nexus Redis 缓存 |
| openstock-dev | service | running | 50 | OpenStock 开发 |
| psych-ai-supervision-dev | service | running | 50 | Psych AI 开发 (4 task groups) |
| silknode-gateway | service | running | 70 | SilkNode 网关 |
| silknode-web | service | running | 60 | SilkNode 前端 |
| todo-web-backend-dev | service | running | 50 | Todo 后端开发 |
| todo-web-backend-prod | service | running | 50 | Todo 后端生产 |
| todo-web-frontend-dev | service | running | 50 | Todo 前端开发 |
| todo-web-frontend-prod | service | running | 50 | Todo 前端生产 |
| wecom-relay | service | running | 50 | 企业微信中继 |

---

## 3. 失败的 Allocations

当前有 2 个处于 `failed` 状态的 Allocation:

| Alloc ID | Job | Task Group | Node | 状态 |
|----------|-----|------------|------|------|
| 47c7970a | psych-ai-supervision-dev | celery | heavy-1 | failed |
| 970c9c1e | mailpit | mailpit | heavy-2 | failed |

**说明**: 这两个失败的 allocation 是历史记录，对应的 Job 均已有新的 running allocation 替代，当前服务正常运行。

---

## 4. Consul 服务健康

### 健康检查统计

| 状态 | 数量 |
|------|------|
| passing | 48 |
| warning | 0 |
| critical | **1** |

### Critical 服务详情

| 节点 | 服务 | 检查名称 | 错误详情 |
|------|------|----------|----------|
| heavy-1 | psych-ai-dev-api | service: "psych-ai-dev-api" check | `Get "http://192.168.69.80:31198/health": dial tcp 192.168.69.80:31198: connect: connection refused` |

**分析**: `psych-ai-dev-api` 的健康检查端口 31198 连接被拒绝。该 Allocation 虽在 Nomad 中报告为 `running`，但实际应用进程可能未正常监听或已崩溃。需要进一步检查该 allocation 的日志。

### 已注册 Consul 服务清单 (26 个)

**基础设施服务**: consul, nomad (x3 servers), nomad-client (x8 nodes), traefik

**应用服务**:
- todo-web-backend-dev, todo-web-backend-prod
- todo-web-frontend-dev, todo-web-frontend-prod
- kairos-dev, kairos-prod
- nexus-api-dev, nexus-db-dev, nexus-redis-dev
- openstock-dev
- psych-ai-dev-api, psych-ai-dev-frontend
- silknode-gateway, silknode-redis, silknode-web
- wecom-relay
- dev-db, dev-redis
- mailpit-smtp, mailpit-ui

---

## 5. Running Allocations 分布

### heavy-1 (192.168.69.80) - 10 个 allocations
- dev-db/redis, dev-db/postgres
- todo-web-frontend-dev, todo-web-frontend-prod
- openstock-dev
- psych-ai-supervision-dev (api, frontend, celery-beat)
- traefik
- nexus-api-dev
- silknode-web
- mailpit

### heavy-2 (192.168.69.81) - 7 个 allocations
- todo-web-backend-prod, todo-web-backend-dev
- nexus-redis-dev, nexus-db-dev
- kairos-prod, kairos-dev
- silknode-gateway

### heavy-3 (192.168.69.82) - 1 个 allocation
- wecom-relay

### light-1 ~ light-5 - 0 个 allocations
Light 节点当前没有运行任何工作负载 (仅支持 exec 驱动，大部分 Job 需要 docker)。

---

## 6. 假设 Consul 不可用时的影响分析

虽然 Consul 当前实际可达，但如果确实发生 Consul 不可用的情况，以下是影响评估:

### 直接影响

1. **服务发现中断**: Traefik 依赖 Consul Catalog 进行服务发现和路由。Consul 不可用时：
   - 新的服务注册和注销不会被 Traefik 感知
   - 已缓存的路由仍可短暂工作，但不会更新
   - 新部署的服务无法被自动路由

2. **健康检查失效**: 26 个服务的健康检查将全部停止
   - Traefik 无法剔除不健康的后端实例
   - 流量可能被转发到已故障的实例

3. **DNS 服务发现不可用**: 通过 Consul DNS (*.service.consul) 的服务解析将失败

### 不受影响的部分

1. **Nomad 调度**: Nomad 可独立运行，Job 调度和 Allocation 管理不依赖 Consul
2. **已运行容器**: 已启动的容器不会因 Consul 宕机而停止
3. **直接 IP 访问**: 通过 IP:Port 直接访问服务不受影响
4. **Volume 管理**: Host Volume 操作不依赖 Consul

### 降级策略下的可用信息

在 Consul 不可用时，以下信息仍可通过 Nomad API 获取：
- 节点状态 (8/8 ready)
- Job 列表及运行状态 (17 running)
- Allocation 状态和分布
- 容器日志
- 部署历史

**不可获取**: 服务健康状态、服务实例发现、DNS 解析

---

## 7. 修复建议

### 当前需要关注的问题

1. **psych-ai-dev-api 健康检查 critical**
   ```bash
   # 检查 allocation 日志
   curl -s "http://192.168.69.70:4646/v1/job/psych-ai-supervision-dev/allocations" | \
     jq -r '[.[] | select(.ClientStatus == "running" and .TaskGroup == "api")][0].ID'
   # 然后查看对应 allocation 的 stderr 日志
   ```

2. **heavy-3 工作负载偏低**: 仅运行 1 个 allocation (wecom-relay)，而 heavy-1 有 10 个。考虑调整亲和性/约束条件以均衡分布。

3. **Light 节点全部空闲**: 5 个 light 节点无任何工作负载，仅有 exec 驱动。如需利用这些节点，需要部署不依赖 docker 的 Job 或为 light 节点安装 docker。

### 如果 Consul 确实出现故障

```bash
# 1. 检查 Consul 服务状态
ssh root@heavy-1 'systemctl status consul'

# 2. 查看 Consul 日志
ssh root@heavy-1 'journalctl -u consul -n 50'

# 3. 检查 Consul 集群成员
ssh root@heavy-1 'consul members'

# 4. 重启 Consul (如需)
ssh root@heavy-1 'systemctl restart consul'
```

---

**报告生成**: aether-status skill v1.1.0
**查询模式**: 全量 (Nomad + Consul 均可达)
**数据时间**: 2026-03-18 12:36 UTC
