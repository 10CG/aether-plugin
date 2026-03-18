# Aether 集群健康检查报告

**检查时间**: 2026-03-18
**Nomad**: http://192.168.69.70:4646
**Consul**: http://192.168.69.70:8500

---

## 1. 集群概览

| 指标 | 值 |
|------|-----|
| 总节点数 | 8 |
| Heavy 节点 | 3 (全部 ready) |
| Light 节点 | 5 (全部 ready) |
| 运行中 Jobs | 17 |
| 运行中 Allocations | 20 |
| 失败 Allocations | 1 (活跃) |
| Consul 成员 | 11 (含 3 infra-server) |
| Consul Critical 检查 | 1 |

**整体状态**: **需要关注** - 存在活跃失败和健康检查告警

---

## 2. 节点状态

### 所有节点均为 ready 状态

| 节点 | IP | 类型 | 状态 | Drain | 调度资格 | Docker | Nomad 版本 |
|------|-----|------|------|-------|---------|--------|-----------|
| heavy-1 | 192.168.69.80 | heavy_workload | ready | No | eligible | v29.2.1 | 1.11.2 |
| heavy-2 | 192.168.69.81 | heavy_workload | ready | No | eligible | v29.2.1 | 1.11.2 |
| heavy-3 | 192.168.69.82 | heavy_workload | ready | No | eligible | v29.2.1 | 1.11.2 |
| light-1 | 192.168.69.90 | light_exec | ready | No | eligible | N/A | 1.11.2 |
| light-2 | 192.168.69.91 | light_exec | ready | No | eligible | N/A | 1.11.2 |
| light-3 | 192.168.69.92 | light_exec | ready | No | eligible | N/A | 1.11.2 |
| light-4 | 192.168.69.93 | light_exec | ready | No | eligible | N/A | 1.11.2 |
| light-5 | 192.168.69.94 | light_exec | ready | No | eligible | N/A | 1.11.2 |

### Heavy 节点资源

| 节点 | CPU | 内存 | 磁盘 |
|------|-----|------|------|
| heavy-1 | 4606 MHz | 3915 MB | 96550 MB |
| heavy-2 | 4606 MHz | 3915 MB | 96550 MB |
| heavy-3 | 4608 MHz | 3915 MB | 96550 MB |

---

## 3. 运行中的 Jobs (17个)

| Job | 类型 | 优先级 | 状态 | 历史失败数 |
|-----|------|--------|------|-----------|
| traefik | service | 50 | running | 4 |
| dev-db | service | 80 | running | 4 |
| todo-web-backend-dev | service | 50 | running | 0 |
| todo-web-backend-prod | service | 50 | running | 0 |
| todo-web-frontend-dev | service | 50 | running | 1 |
| todo-web-frontend-prod | service | 50 | running | 1 |
| openstock-dev | service | 50 | running | 1 |
| kairos-dev | service | 50 | running | 3 |
| kairos-prod | service | 50 | running | 2 |
| nexus-api-dev | service | 50 | running | 7 |
| nexus-db-dev | service | 50 | running | 0 |
| nexus-redis-dev | service | 50 | running | 1 |
| psych-ai-supervision-dev | service | 50 | running | 5 |
| silknode-gateway | service | 70 | running | 0 |
| silknode-web | service | 60 | running | 0 |
| wecom-relay | service | 50 | running | 0 |
| mailpit | service | 30 | running | 1 |

---

## 4. 失败和异常 Allocations

### 4.1 活跃失败: psych-ai-supervision-dev.celery

| 属性 | 值 |
|------|-----|
| Alloc ID | 47c7970a-4884... |
| 节点 | heavy-1 |
| 状态 | **failed** (desired: run) |
| 重启次数 | **39 次** |
| 最终错误 | **不可恢复错误** |

**错误详情**:
```
Driver Failure: failed to create container: Failed to purge container ...
Error response from daemon: cannot remove container: unable to remove filesystem:
unlinkat /opt/aether-volumes/runners/heavy-1/docker/containers/...: directory not empty
```

**分析**: Docker 容器清理失败，无法删除旧容器的文件系统。这是一个 Docker daemon 层面的问题，可能由于文件锁或挂载点残留导致。重启 39 次后被标记为不可恢复。

### 4.2 健康检查失败: psych-ai-supervision-dev.api

| 属性 | 值 |
|------|-----|
| Alloc ID | c130f968-0cc9... |
| 节点 | heavy-1 |
| 状态 | running (但标记为 **unhealthy**) |
| DeploymentStatus.Healthy | **false** |

**错误详情**:
```
Alloc Unhealthy: Task not running for min_healthy_time of 10s by healthy_deadline of 5m0s
```

**分析**: API 任务虽然在运行，但在部署健康检查截止时间(5分钟)内未能通过健康检查。任务可能启动缓慢或健康端点响应异常。

### 4.3 已恢复的失败: mailpit

| 属性 | 值 |
|------|-----|
| 旧 Alloc | 970c9c1e... (heavy-2, failed, stopped) |
| 新 Alloc | 756da541... (heavy-1, running, healthy) |

**分析**: mailpit 在 heavy-2 上失败后已自动重新调度到 heavy-1 并恢复正常运行。

### 4.4 历史失败汇总

| Job | 失败 Task Groups | 总失败次数 |
|-----|-----------------|-----------|
| nexus-api-dev | api(7) | 7 |
| psych-ai-supervision-dev | celery(2), celery-beat(1), frontend(1), api(1) | 5 |
| dev-db | postgres(4) | 4 |
| traefik | traefik(4) | 4 |
| kairos-dev | kairos(3) | 3 |
| kairos-prod | kairos(2) | 2 |

**重点关注**: nexus-api-dev 累计 7 次失败是最高的，表明该服务存在持续的稳定性问题。

---

## 5. Heavy 节点负载分布分析

### 当前 Allocation 分布

| 节点 | 运行中 Allocations | 占比 | 运行的服务 |
|------|-------------------|------|-----------|
| **heavy-1** | **12** | **60%** | dev-db(redis, postgres), mailpit, nexus-api-dev, openstock-dev, psych-ai-supervision-dev(api, celery-beat, frontend), silknode-web, todo-web-frontend-dev, todo-web-frontend-prod, traefik |
| heavy-2 | 7 | 35% | kairos-dev, kairos-prod, nexus-db-dev, nexus-redis-dev, silknode-gateway, todo-web-backend-dev, todo-web-backend-prod |
| **heavy-3** | **1** | **5%** | wecom-relay |

### 负载分布评估: **严重不均衡**

```
heavy-1: ████████████████████████████████████████████████████████████  12 (60%)
heavy-2: ███████████████████████████████████                           7 (35%)
heavy-3: █████                                                         1 ( 5%)
```

**问题**:
1. **heavy-1 负载过重** - 承载了 12 个 allocation (60%)，包括关键基础设施 (traefik, dev-db) 和多个应用
2. **heavy-3 严重闲置** - 仅运行 1 个 wecom-relay 服务，资源严重浪费
3. **单点故障风险** - heavy-1 宕机将影响 traefik (反向代理)、数据库、及多数前端服务

---

## 6. Consul 服务健康状况

### Critical 健康检查 (1个)

| 服务 | 节点 | 检查类型 | 错误 |
|------|------|---------|------|
| **psych-ai-dev-api** | heavy-1 | HTTP | `Get "http://192.168.69.80:31198/health": dial tcp 192.168.69.80:31198: connect: connection refused` |

**分析**: psych-ai-dev-api 的 HTTP 健康检查返回连接被拒绝。这与上面 Nomad 中 psych-ai-supervision-dev.api 标记为 unhealthy 的情况一致。该 API 服务虽然容器在运行，但实际并未正常监听端口。

### Warning 健康检查

无 warning 状态的检查。

### 正常服务 (23个)

所有其他注册服务的健康检查均为 passing 状态，包括:
- 基础设施: consul, nomad(9实例), nomad-client(8实例), traefik
- 数据库: dev-db, dev-redis, nexus-db-dev, nexus-redis-dev, silknode-redis
- 应用: kairos-dev, kairos-prod, nexus-api-dev, openstock-dev, silknode-gateway, silknode-web, todo-web-*(4个), wecom-relay, mailpit-*

### Consul 集群成员 (11个)

所有 11 个 Consul 成员状态正常 (Status: 1 = alive):
- 3 个 infra-server (70, 71, 72) - Consul Server
- 3 个 heavy 节点 (80, 81, 82)
- 5 个 light 节点 (90-94)

---

## 7. Light 节点使用情况

所有 5 个 Light 节点 (light-1 到 light-5) 当前 **没有任何运行中的 Nomad allocation**。这些节点的 NodeClass 为 `light_exec`，仅支持 `exec` 驱动，不支持 Docker。

**说明**: Light 节点未被利用可能是设计如此(仅用于特定 exec 类型任务)，但如果集群不稳定，可以考虑扩展其能力。

---

## 8. 处理建议

### 紧急 (P0) - 立即处理

#### 8.1 修复 psych-ai-supervision-dev.celery 的 Docker 文件系统问题

```bash
# 1. SSH 到 heavy-1 清理残留容器
ssh root@heavy-1

# 2. 查看问题容器
docker ps -a | grep psych

# 3. 强制清理
docker system prune -f

# 4. 如果仍然失败，手动清理残留目录
ls -la /opt/aether-volumes/runners/heavy-1/docker/containers/
# 删除有问题的容器目录

# 5. 在 Nomad 中重新调度
# 可以通过 force-reschedule 或重新提交 job
nomad job restart psych-ai-supervision-dev
```

#### 8.2 修复 psych-ai-supervision-dev.api 健康检查

```bash
# 1. 检查 API 容器日志
nomad alloc logs c130f968-0cc9-14a9-0437-cdfe5fc8ef32

# 2. 确认端口绑定
ssh root@heavy-1 "netstat -tlnp | grep 31198"

# 3. 如果 API 依赖 celery，先修复 celery 再观察
# 4. 如果需要，调整 healthy_deadline 或 min_healthy_time
```

### 重要 (P1) - 本周处理

#### 8.3 重新均衡 Heavy 节点负载

当前 heavy-1 承载 60% 的负载，建议将部分服务迁移到 heavy-3:

**建议迁移方案**:

| 迁移服务 | 从 | 到 | 原因 |
|----------|-----|-----|------|
| openstock-dev | heavy-1 | heavy-3 | 无 volume 依赖，易迁移 |
| todo-web-frontend-dev | heavy-1 | heavy-3 | 低优先级 dev 服务 |
| todo-web-frontend-prod | heavy-1 | heavy-3 | 分散前端风险 |

**迁移后预期分布**:
```
heavy-1: 9 allocations (45%) - 核心服务 + psych-ai
heavy-2: 7 allocations (35%) - 后端 + 数据库
heavy-3: 4 allocations (20%) - 前端 + wecom-relay
```

**实施方法**: 在 Job 的 HCL 文件中添加 `constraint` 或使用 `affinity` 引导调度:
```hcl
constraint {
  attribute = "${node.unique.name}"
  value     = "heavy-3"
}
```

或使用 spread stanza 让 Nomad 自动均衡:
```hcl
spread {
  attribute = "${node.unique.name}"
  weight    = 100
}
```

#### 8.4 为 heavy-3 配置 Host Volumes

heavy-3 当前配置的 Host Volumes 与 heavy-2 类似(todo-web, kairos)，如果要迁移更多服务过去，需要确保目标 volumes 已创建:

```bash
aether volume create --node heavy-3 --project openstock --volumes data
```

### 改进 (P2) - 持续优化

#### 8.5 解决 nexus-api-dev 高失败率

累计 7 次失败是所有 Job 中最高的:
- 检查应用日志确定失败根因
- 考虑增加 `restart` 策略的 `attempts` 和 `delay`
- 审查资源限制是否充足(CPU/Memory)

#### 8.6 监控 traefik 稳定性

traefik 作为反向代理是关键基础设施，累计 4 次失败需要关注:
- 确认当前运行版本无已知 bug
- 考虑增加 `priority` 确保优先调度
- 建议配置 Traefik 访问日志监控

#### 8.7 考虑 Light 节点利用

5 个 Light 节点完全空闲。如果支持，可以考虑:
- 在 light 节点上启用 Docker 驱动，分担轻量级容器服务
- 或部署 exec 类型的监控/辅助任务到 light 节点

#### 8.8 增加服务冗余

当前所有应用服务都是单实例运行 (count=1)。对于生产服务 (todo-web-*-prod, kairos-prod)，建议:
- 增加 `count = 2` 实现高可用
- 配合 `spread` stanza 分散到不同 heavy 节点

---

## 9. 总结

| 类别 | 状态 | 说明 |
|------|------|------|
| 节点健康 | **正常** | 全部 8 节点 ready |
| Consul 集群 | **正常** | 11 成员全部 alive |
| Job 运行 | **需关注** | 17 个 Job 运行中，但 2 个有活跃问题 |
| 失败 Allocations | **告警** | psych-ai celery 不可恢复失败 + API unhealthy |
| Consul 健康检查 | **告警** | psych-ai-dev-api 连接被拒 |
| 负载均衡 | **严重不均** | heavy-1(60%) vs heavy-3(5%) |
| Light 节点 | **空闲** | 5 个节点 0 allocations |

**优先级排序**:
1. 修复 psych-ai-supervision-dev 的 celery 和 API 问题
2. 重新均衡 heavy 节点负载
3. 调查 nexus-api-dev 高失败率
4. 规划服务冗余和 light 节点利用
