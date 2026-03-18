# Aether 集群健康检查报告

**检查时间**: 2026-03-18 20:21 UTC
**Nomad 地址**: http://192.168.69.70:4646
**Consul 地址**: http://192.168.69.70:8500

---

## 一、总体评估

| 指标 | 状态 |
|------|------|
| 集群整体 | **需要关注** |
| Nomad Server | 正常 (3/3) |
| Nomad Client | 正常 (8/8) |
| Consul 节点 | 正常 (11/11) |
| 运行中 Jobs | 17/17 |
| 失败 Allocation | **2 个 (需处理)** |
| 健康检查 Critical | **1 个 (需处理)** |
| 负载分布 | **严重不均衡** |

---

## 二、Nomad 节点状态

### 所有节点均为 `ready` 状态，无 drain 节点

| 节点 | IP | 类型 | 状态 | CPU 核心 | 内存 | 磁盘 | Nomad 版本 | Docker |
|------|-----|------|------|----------|------|------|------------|--------|
| heavy-1 | 192.168.69.80 | heavy_workload | ready | 2 (4606 MHz) | 3915 MB | 96 GB | 1.11.2 | 29.2.1 |
| heavy-2 | 192.168.69.81 | heavy_workload | ready | 2 (4606 MHz) | 3915 MB | 96 GB | 1.11.2 | 29.2.1 |
| heavy-3 | 192.168.69.82 | heavy_workload | ready | 2 (4608 MHz) | 3915 MB | 96 GB | 1.11.2 | 29.2.1 |
| light-1 | 192.168.69.90 | light_exec | ready | - | - | - | 1.11.2 | N/A |
| light-2 | 192.168.69.91 | light_exec | ready | - | - | - | 1.11.2 | N/A |
| light-3 | 192.168.69.92 | light_exec | ready | - | - | - | 1.11.2 | N/A |
| light-4 | 192.168.69.93 | light_exec | ready | - | - | - | 1.11.2 | N/A |
| light-5 | 192.168.69.94 | light_exec | ready | - | - | - | 1.11.2 | N/A |

**Consul 额外节点** (非 Nomad):
- infra-server-1 (192.168.69.70) - Consul/Nomad Server
- infra-server-2 (192.168.69.71) - Consul/Nomad Server
- infra-server-3 (192.168.69.72) - Consul/Nomad Server

所有 Consul Serf Health、Nomad Server HTTP/RPC/Serf 检查均为 **passing**。

---

## 三、运行中的 Jobs (17 个)

| Job 名称 | 类型 | 优先级 | 状态 | 历史失败 | 当前 Running |
|-----------|------|--------|------|----------|-------------|
| traefik | service | 50 | running | 4 | 1 |
| dev-db | service | 80 | running | 4 (postgres) | 2 (redis+postgres) |
| kairos-dev | service | 50 | running | 3 | 1 |
| kairos-prod | service | 50 | running | 2 | 1 |
| silknode-gateway | service | 70 | running | 0 | 1 |
| silknode-web | service | 60 | running | 0 | 1 |
| nexus-api-dev | service | 50 | running | 7 | 1 |
| nexus-db-dev | service | 50 | running | 0 | 1 |
| nexus-redis-dev | service | 50 | running | 1 | 1 |
| todo-web-backend-dev | service | 50 | running | 0 | 1 |
| todo-web-backend-prod | service | 50 | running | 0 | 1 |
| todo-web-frontend-dev | service | 50 | running | 1 | 1 |
| todo-web-frontend-prod | service | 50 | running | 1 | 1 |
| openstock-dev | service | 50 | running | 1 | 1 |
| psych-ai-supervision-dev | service | 50 | running | **celery: 2, celery-beat: 2, api: 1, frontend: 1** | **2** (缺 celery, celery-beat) |
| mailpit | service | 30 | running | 1 | 1 |
| wecom-relay | service | 50 | running | 0 | 1 |

---

## 四、失败的 Allocation (严重问题)

### 4.1 psych-ai-supervision-dev.celery[0]

- **状态**: dead (failed)
- **节点**: heavy-1
- **错误类型**: Driver Failure (不可恢复)
- **错误详情**:
  ```
  failed to create container: Failed to purge container e05c48f9...:
  Error response from daemon: cannot remove container: unable to remove filesystem:
  unlinkat /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9...: directory not empty
  ```
- **最后重试时间**: 2026-03-16 07:33 UTC
- **结论**: Docker 容器清理失败，残留文件系统导致无法创建新容器

### 4.2 psych-ai-supervision-dev.celery-beat[0]

- **状态**: dead (failed)
- **错误类型**: Driver Failure (不可恢复)
- **错误详情**:
  ```
  failed to create container: Failed to purge container 9a9e2b9b...:
  Error response from daemon: cannot remove container: unable to remove filesystem:
  unlinkat /opt/aether-volumes/runners/heavy-1/docker/containers/9a9e2b9b...: directory not empty
  ```
- **最后重试时间**: 2026-03-18 12:29 UTC
- **结论**: 同上，Docker 容器文件系统残留问题

### 4.3 失败的部署

- **psych-ai-supervision-dev**: 部署状态为 `failed`
  - 原因: "Failed due to progress deadline - not rolling back to stable job version 21 as current job has same specification"

---

## 五、Consul 服务健康检查

### Critical (1 个)

| 节点 | 服务 | 检查类型 | 错误信息 |
|------|------|----------|----------|
| heavy-1 | psych-ai-dev-api | HTTP | `dial tcp 192.168.69.80:31198: connect: connection refused` |

> 注: psych-ai-dev-api 的 Nomad allocation 状态显示为 running，但 Consul 健康检查显示 connection refused。这说明容器虽然在运行，但应用进程可能未正常监听端口或已崩溃。其 DeploymentStatus.Healthy 也标记为 `false`。

### Warning (0 个)

无 warning 状态的检查。

### 需关注的服务状态

| 服务 | 状态 | 备注 |
|------|------|------|
| kairos-prod | passing (但部分组件异常) | `wecomApi: false`, `relayClient: false`, `mediaHandler: false` |
| wecom-relay | passing (但 token 异常) | `tokenValid: false`, `tokenExpiresIn: 0` |

> **kairos-prod** 的 wecomApi 和 relayClient 组件为 false，与 wecom-relay 的 token 失效直接相关。wecom-relay 的 token 未刷新可能导致企业微信集成功能不可用。

### Passing (所有其他服务)

以下服务健康检查全部通过:
- traefik, dev-db, dev-redis, todo-web-frontend-dev/prod, todo-web-backend-dev/prod
- openstock-dev, nexus-api-dev, nexus-db-dev, nexus-redis-dev
- kairos-dev, silknode-gateway, silknode-web, silknode-redis
- mailpit-ui, mailpit-smtp, psych-ai-dev-frontend
- 所有 Nomad Client/Server 检查

---

## 六、Heavy 节点负载分布分析

### 当前 Allocation 分布

| 节点 | Running Allocations | 占比 | 服务列表 |
|------|---------------------|------|----------|
| **heavy-1** | **12** | **63%** | traefik, dev-db(redis+postgres), kairos-dev, nexus-api-dev, openstock-dev, todo-web-frontend-dev, todo-web-frontend-prod, psych-ai(frontend+api), mailpit, silknode-web |
| **heavy-2** | **6** | **32%** | todo-web-backend-dev, todo-web-backend-prod, nexus-redis-dev, nexus-db-dev, silknode-gateway, kairos-prod |
| **heavy-3** | **1** | **5%** | wecom-relay |

### 负载分布评估: 严重不均衡

```
heavy-1: ████████████████████████████████████████████████████  12 allocs (63%)
heavy-2: ██████████████████████████                            6 allocs (32%)
heavy-3: ████                                                  1 alloc  (5%)
```

**问题分析**:
1. **heavy-1 过载**: 承载了 63% 的工作负载（12 个 allocation），包括关键基础设施（traefik）、数据库（dev-db）和多个应用服务
2. **heavy-3 严重闲置**: 仅运行 1 个轻量级服务（wecom-relay），资源大量浪费
3. **单点故障风险**: 如果 heavy-1 宕机，将影响 traefik（反向代理入口）、所有 frontend 服务、数据库、以及多个核心应用

### Light 节点使用情况

所有 5 个 light 节点（light-1 到 light-5）当前 **没有运行任何 allocation**，处于完全空闲状态。这些节点仅支持 `exec` 驱动，不支持 Docker，因此无法承载当前的 Docker 容器工作负载。

---

## 七、问题汇总与处理建议

### 严重 (需立即处理)

#### 1. psych-ai-supervision-dev celery/celery-beat 容器失败

**根因**: heavy-1 上 Docker 容器文件系统残留，导致无法清理旧容器和创建新容器。

**处理步骤**:
```bash
# 1. SSH 到 heavy-1 清理残留容器目录
ssh root@heavy-1

# 2. 停止相关容器（如果还有残留进程）
docker ps -a | grep psych-ai
docker rm -f <container_id>

# 3. 手动清理残留的容器文件系统
# 检查目录
ls /opt/aether-volumes/runners/heavy-1/docker/containers/

# 如果确认是残留文件，手动删除
rm -rf /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9e8dc*
rm -rf /opt/aether-volumes/runners/heavy-1/docker/containers/9a9e2b9bd22c*

# 4. Docker 系统清理
docker system prune -f

# 5. 重新部署 psych-ai-supervision-dev
# 在 Nomad 中重新评估 job
nomad job eval psych-ai-supervision-dev
# 或者重新提交 job spec
nomad job run psych-ai-supervision-dev.hcl
```

#### 2. psych-ai-dev-api 健康检查失败

**根因**: 虽然 allocation 状态为 running，但应用进程未正常监听 31198 端口。DeploymentStatus.Healthy 为 false。

**处理步骤**:
```bash
# 1. 检查容器内进程状态
ssh root@heavy-1
docker ps | grep psych-ai.*api
docker logs <container_id> --tail 50

# 2. 如果应用崩溃，重启 allocation
nomad alloc restart c130f968-0cc9-14a9-0437-cdfe5fc8ef32

# 3. 如果问题持续，检查应用配置和依赖
# celery 和 celery-beat 的失败可能是 API 不健康的原因之一
```

### 重要 (建议尽快处理)

#### 3. wecom-relay Token 失效

**问题**: wecom-relay 健康检查通过，但 `tokenValid: false`，token 过期（`tokenExpiresIn: 0`），上次刷新时间为 2026-03-17 23:07 UTC。

**影响**: kairos-prod 的 wecomApi 和 relayClient 组件也显示为 false，企业微信相关功能不可用。

**处理步骤**:
```bash
# 1. 检查 wecom-relay 日志
ssh root@heavy-3
docker logs <wecom-relay-container> --tail 100

# 2. 检查企业微信 API 凭据是否过期或被吊销
# 3. 可能需要手动触发 token 刷新或更新凭据配置
# 4. 重启 allocation 尝试重新获取 token
nomad alloc restart bd2de368-f2c6-17d0-741b-f55bd66c68a1
```

#### 4. Heavy 节点负载严重不均衡

**问题**: heavy-1 承载 12 个 allocation (63%), heavy-3 仅 1 个 (5%)

**处理建议**:

**短期** - 迁移部分服务到 heavy-3:
```bash
# 以下服务可以考虑迁移到 heavy-3（需要确保 host volumes 已创建）:
# - openstock-dev (无 volume 依赖，易迁移)
# - mailpit (轻量服务)
# - psych-ai-supervision-dev (修复后)

# 1. 在 heavy-3 创建必要的 host volumes
aether volume create --node heavy-3 --project <project> --volumes <volumes>

# 2. 修改 Job spec 添加 affinity 或 constraint 引导调度
# 在 job spec 的 group 级别添加:
#   affinity {
#     attribute = "${node.unique.name}"
#     value     = "heavy-3"
#     weight    = 50
#   }

# 3. 也可以使用 spread stanza 实现自动均衡:
#   spread {
#     attribute = "${node.unique.name}"
#     weight    = 100
#   }
```

**长期** - 优化调度策略:
- 为 heavy_workload 类型的 job 添加 `spread` 策略，确保 Nomad 调度器在 heavy 节点之间均匀分配
- 评估是否可以将部分无状态服务改为 exec 驱动，利用闲置的 light 节点
- 考虑为 traefik 配置高可用（多实例），消除单点故障风险

### 一般建议

#### 5. nexus-api-dev 历史失败次数较多 (7 次)

虽然当前正常运行，但 7 次历史失败表明该服务稳定性不佳。建议:
- 检查应用日志中的错误模式
- 检查是否有内存泄漏或资源不足的问题
- 考虑增加健康检查宽限期

#### 6. dev-db postgres 历史失败 (4 次)

数据库服务的历史失败值得关注:
- 检查是否有 OOM Kill 记录
- 检查磁盘空间使用情况（heavy-1 总磁盘 96 GB）
- 确认 PostgreSQL 的内存配置是否合理

#### 7. Light 节点利用率为零

5 个 light 节点完全空闲。建议:
- 如果有可以用 exec 驱动运行的工作负载，分配到 light 节点
- 如果不需要这些节点，考虑缩减集群规模以节省资源
- 或为 light 节点安装 Docker，使其可以承载容器工作负载

---

## 八、Consul 注册服务总览 (21 个)

| 服务名 | 标签 |
|--------|------|
| consul | (内部) |
| nomad | serf, http, rpc |
| nomad-client | http |
| traefik | traefik.enable=true |
| dev-db | database, postgresql, development |
| dev-redis | development, cache, redis |
| kairos-dev | traefik -> kairos-dev.10cg.pub |
| kairos-prod | traefik -> kairos.10cg.pub |
| nexus-api-dev | traefik -> nexus-dev.10cg.pub |
| nexus-db-dev | (internal) |
| nexus-redis-dev | (internal) |
| openstock-dev | traefik -> openstock-dev.10cg.pub |
| psych-ai-dev-api | traefik -> psych-dev.10cg.pub/api |
| psych-ai-dev-frontend | traefik -> psych-dev.10cg.pub |
| silknode-gateway | api, gateway, silknode |
| silknode-redis | cache, redis, silknode |
| silknode-web | web, nextjs, silknode |
| todo-web-backend-dev | traefik -> todo-dev.10cg.pub/api |
| todo-web-backend-prod | traefik -> todo.10cg.pub/api |
| todo-web-frontend-dev | traefik -> todo-dev.10cg.pub |
| todo-web-frontend-prod | traefik -> todo.10cg.pub |
| mailpit-smtp | smtp, dev-tool |
| mailpit-ui | mail, dev-tool |
| wecom-relay | wecom, relay |

---

## 九、处理优先级

| 优先级 | 问题 | 行动 |
|--------|------|------|
| P0 | psych-ai celery/celery-beat 容器失败 | 清理 Docker 残留文件系统，重新部署 |
| P0 | psych-ai-dev-api 健康检查 critical | 检查应用进程，可能需要重启 |
| P1 | wecom-relay token 失效 | 检查凭据，重启服务重新获取 token |
| P1 | kairos-prod 部分组件异常 | 依赖 wecom-relay 修复 |
| P2 | heavy 节点负载不均衡 | 调整 Job 调度策略，迁移服务到 heavy-3 |
| P3 | light 节点完全空闲 | 评估是否安装 Docker 或调整集群规模 |

---

*报告生成工具: Claude AI*
*数据源: Nomad API + Consul API 实时查询*
