# Aether 集群健康检查报告

> **检查时间**: 2026-03-18 ~19:30 UTC
> **Nomad**: http://192.168.69.70:4646
> **Consul**: http://192.168.69.70:8500

---

## 总体评估

| 维度 | 状态 | 说明 |
|------|------|------|
| API 可达性 | PASS | Nomad 和 Consul 均正常响应 |
| 节点健康 | PASS | 8/8 节点状态 ready，无 drain |
| Jobs 运行 | WARN | 17 个 Job 全部 running，但 psych-ai-supervision-dev 有组件异常 |
| 失败 Allocations | FAIL | 2 个 failed（psych-ai-supervision-dev 的 celery 和 celery-beat） |
| Consul 服务健康 | FAIL | 1 个 critical（psych-ai-dev-api 健康检查连接被拒绝） |
| 负载分布 | WARN | heavy 节点负载严重不均：heavy-1 承载 12 个，heavy-3 仅 1 个 |

---

## 1. 节点状态

### 全部节点一览

| 节点 | IP | 状态 | NodeClass | 调度资格 | Drain | 驱动 |
|------|----|------|-----------|----------|-------|------|
| heavy-1 | 192.168.69.80 | ready | heavy_workload | eligible | false | docker, exec, java, qemu, raw_exec |
| heavy-2 | 192.168.69.81 | ready | heavy_workload | eligible | false | docker, exec, java, qemu, raw_exec |
| heavy-3 | 192.168.69.82 | ready | heavy_workload | eligible | false | docker, exec, java, qemu, raw_exec |
| light-1 | 192.168.69.90 | ready | light_exec | eligible | false | exec, raw_exec |
| light-2 | 192.168.69.91 | ready | light_exec | eligible | false | exec, raw_exec |
| light-3 | 192.168.69.92 | ready | light_exec | eligible | false | exec, raw_exec |
| light-4 | 192.168.69.93 | ready | light_exec | eligible | false | exec, raw_exec |
| light-5 | 192.168.69.94 | ready | light_exec | eligible | false | exec, raw_exec |

**分布**: 3 个 heavy_workload 节点 + 5 个 light_exec 节点，共 8 个节点。所有节点均处于 ready 状态且调度资格为 eligible。

### Heavy 节点硬件规格

| 节点 | CPU Shares | CPU 核心 | 内存 (MB) | 磁盘 (MB) |
|------|-----------|---------|----------|----------|
| heavy-1 | 4606 | 2 | 3915 | 96550 |
| heavy-2 | 4606 | 2 | 3915 | 96550 |
| heavy-3 | 4608 | 2 | 3915 | 96550 |

三台 heavy 节点硬件配置完全一致（2 核、~4GB 内存、~96GB 磁盘）。

---

## 2. 运行中的 Jobs

共 **17 个 Job**，全部为 `service` 类型，全部状态 `running`，均部署在 `dc1` 数据中心。

| Job | 类型 | 状态 | 优先级 | 节点 |
|-----|------|------|--------|------|
| traefik | service | running | 50 | heavy-1 |
| dev-db | service | running | 80 | heavy-1 (postgres + redis) |
| silknode-gateway | service | running | 70 | heavy-2 |
| silknode-web | service | running | 60 | heavy-1 |
| kairos-dev | service | running | 50 | heavy-1 |
| kairos-prod | service | running | 50 | heavy-2 |
| nexus-api-dev | service | running | 50 | heavy-1 |
| nexus-db-dev | service | running | 50 | heavy-2 |
| nexus-redis-dev | service | running | 50 | heavy-2 |
| openstock-dev | service | running | 50 | heavy-1 |
| psych-ai-supervision-dev | service | running | 50 | heavy-1 (api + frontend; celery/celery-beat failed) |
| todo-web-backend-dev | service | running | 50 | heavy-2 |
| todo-web-backend-prod | service | running | 50 | heavy-2 |
| todo-web-frontend-dev | service | running | 50 | heavy-1 |
| todo-web-frontend-prod | service | running | 50 | heavy-1 |
| mailpit | service | running | 30 | heavy-1 |
| wecom-relay | service | running | 50 | heavy-3 |

### 最近部署活动（按时间倒序）

| Job | 最后更新时间 | 状态 |
|-----|-------------|------|
| kairos-dev | 2026-03-18 19:11 | running |
| silknode-web | 2026-03-18 18:45 | running |
| todo-web-backend-dev | 2026-03-18 17:34 | running |
| mailpit | 2026-03-18 12:26 | running |
| nexus-api-dev | 2026-03-17 23:10 | running |
| silknode-gateway | 2026-03-17 08:45 | running |
| wecom-relay | 2026-03-16 07:37 | running |

今天有 4 个 Job 进行了部署/更新操作，均显示为 running。

---

## 3. 失败的 Allocations [CRITICAL]

### 3.1 psych-ai-supervision-dev / celery (47c7970a)

- **Task Group**: celery
- **节点**: heavy-1
- **状态**: failed (dead)
- **重启次数**: 39 次
- **创建时间**: 2026-03-15 01:34:35 UTC
- **最终失败时间**: 2026-03-16 09:53:24 UTC

**失败时间线**:
1. 容器反复以 Exit Code 1 退出（至少 39 次重启）
2. 每次存活约 50 分钟后崩溃
3. 最终因 **Docker 驱动故障**标记为不可恢复：
   ```
   Driver Failure: failed to create container: Failed to purge container e05c48f9e8dc...:
   Error response from daemon: cannot remove container: unable to remove filesystem:
   unlinkat /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9e8dc...: directory not empty
   ```

### 3.2 psych-ai-supervision-dev / celery-beat (a47723fa)

- **Task Group**: celery-beat
- **节点**: heavy-1
- **状态**: failed (dead)
- **重启次数**: 83 次
- **创建时间**: 2026-03-15 01:34:35 UTC
- **最终失败时间**: 2026-03-18 12:49:41 UTC

**失败时间线**:
1. 容器反复以 Exit Code 1 退出（83 次重启 -- 比 celery 更多，存活更久）
2. 每次存活约 1 小时后崩溃
3. 最终同样因 **Docker 驱动故障**标记为不可恢复：
   ```
   Driver Failure: failed to create container: Failed to purge container 9a9e2b9bd22c...:
   unable to remove filesystem: unlinkat /opt/aether-volumes/runners/heavy-1/docker/containers/9a9e2b9bd22c...: directory not empty
   ```

### 3.3 psych-ai-supervision-dev / api (c130f968) -- 运行中但不健康

- **状态**: running，但 Consul 健康检查为 **critical**
- **事件**: 最后一个事件是 `Alloc Unhealthy`
- **Consul 输出**:
  ```
  Get "http://192.168.69.80:31198/health": dial tcp 192.168.69.80:31198: connect: connection refused
  ```

**根因分析 (API stderr 日志)**:
```
asyncpg.exceptions.InvalidCatalogNameError: database "psych_supervision" does not exist
ERROR: Application startup failed. Exiting.
```

API 容器在启动但因找不到数据库 `psych_supervision` 而反复崩溃重启。这是所有 psych-ai 组件失败的根本原因。

---

## 4. Consul 服务健康

### 统计概览

| 指标 | 数量 |
|------|------|
| 通过的健康检查 (passing) | 48 |
| 临界的健康检查 (critical) | 1 |

### Critical 检查详情

| 服务 | 节点 | 状态 | 详情 |
|------|------|------|------|
| psych-ai-dev-api | heavy-1 | critical | `connection refused` on http://192.168.69.80:31198/health |

### 所有已注册服务健康状态

| 服务 | 节点 | 状态 |
|------|------|------|
| consul (Serf) | 11 nodes | passing |
| nomad | infra-server-1/2/3 | passing |
| nomad-client | 8 nodes | passing |
| dev-db | heavy-1 | passing |
| dev-redis | heavy-1 | passing |
| kairos-dev | heavy-1 | passing |
| kairos-prod | heavy-2 | passing |
| mailpit-smtp | heavy-1 | passing |
| mailpit-ui | heavy-1 | passing |
| nexus-api-dev | heavy-1 | passing |
| nexus-db-dev | heavy-2 | passing |
| nexus-redis-dev | heavy-2 | passing |
| openstock-dev | heavy-1 | passing |
| psych-ai-dev-api | heavy-1 | **CRITICAL** |
| psych-ai-dev-frontend | heavy-1 | passing |
| silknode-gateway | heavy-2 | passing |
| silknode-redis | heavy-2 | passing |
| silknode-web | heavy-1 | passing |
| todo-web-backend-dev | heavy-2 | passing |
| todo-web-backend-prod | heavy-2 | passing |
| todo-web-frontend-dev | heavy-1 | passing |
| todo-web-frontend-prod | heavy-1 | passing |
| traefik | heavy-1 | passing |
| wecom-relay | heavy-3 | passing |

**注意**: light 节点 (light-1 到 light-5) 当前没有运行任何应用服务，仅运行 Consul agent 和 nomad-client。

---

## 5. Heavy 节点负载分布分析 [WARNING]

### Allocation 分布

| 节点 | 运行中 Allocations | 百分比 | 状态 |
|------|-------------------|--------|------|
| heavy-1 | 12 | 63% | **过载** |
| heavy-2 | 6 | 32% | 正常 |
| heavy-3 | 1 | 5% | **严重空闲** |

### 资源分配详情

#### heavy-1 (12 allocations) -- 资源紧张

| Job | Task Group | CPU (MHz) | 内存 (MB) |
|-----|-----------|-----------|----------|
| dev-db | postgres | 500 | 512 |
| dev-db | redis | 200 | 256 |
| silknode-web | web (nextjs) | 500 | 512 |
| kairos-dev | kairos | 500 | 512 |
| nexus-api-dev | api | 300 | 512 |
| nexus-api-dev | migrate | 100 | 128 |
| nexus-api-dev | worker | 200 | 256 |
| psych-ai-supervision-dev | api | 500 | 512 |
| psych-ai-supervision-dev | frontend (nginx) | 200 | 128 |
| openstock-dev | web | 300 | 256 |
| traefik | traefik | 200 | 128 |
| mailpit | mailpit | 100 | 128 |
| todo-web-frontend-dev | frontend | 100 | 32 |
| todo-web-frontend-prod | frontend | 100 | 64 |
| **合计** | | **3800 MHz** | **3936 MB** |

**heavy-1 资源使用率**:
- CPU: 3800 / 4606 = **82.5%** (已分配)
- 内存: 3936 / 3915 = **100.5%** (已超分配!)

#### heavy-2 (6 allocations) -- 中等负载

| Job | Task Group | CPU (MHz) | 内存 (MB) |
|-----|-----------|-----------|----------|
| kairos-prod | kairos | 1000 | 1024 |
| todo-web-backend-prod | backend | 500 | 512 |
| silknode-gateway | gateway | 500 | 512 |
| silknode-gateway | redis | 200 | 300 |
| nexus-db-dev | postgres | 300 | 512 |
| nexus-redis-dev | redis | 100 | 128 |
| todo-web-backend-dev | backend | 300 | 256 |
| **合计** | | **2900 MHz** | **3244 MB** |

**heavy-2 资源使用率**:
- CPU: 2900 / 4606 = **63.0%**
- 内存: 3244 / 3915 = **82.9%**

#### heavy-3 (1 allocation) -- 严重空闲

| Job | Task Group | CPU (MHz) | 内存 (MB) |
|-----|-----------|-----------|----------|
| wecom-relay | relay | 200 | 256 |
| **合计** | | **200 MHz** | **256 MB** |

**heavy-3 资源使用率**:
- CPU: 200 / 4608 = **4.3%**
- 内存: 256 / 3915 = **6.5%**

### 负载不均分析

```
heavy-1:  ████████████████████████████████████████░░░░░░░░  82.5% CPU / 100.5% MEM  [12 allocs]
heavy-2:  ██████████████████████████████░░░░░░░░░░░░░░░░░░  63.0% CPU /  82.9% MEM  [6 allocs]
heavy-3:  ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   4.3% CPU /   6.5% MEM  [1 alloc]
```

**heavy-1 的内存已经超分配 (100.5%)**，这很可能是集群"不稳定"的主要原因之一。当实际内存使用接近或超过物理限制时，会导致 OOM kill、容器崩溃、Docker 文件系统异常等连锁问题。

---

## 6. 根因分析与关联

### 问题 1: psych-ai-supervision-dev 全面异常

**故障链**:
```
数据库 "psych_supervision" 不存在
    --> API 启动失败 (asyncpg.InvalidCatalogNameError)
    --> Consul 健康检查 critical (connection refused on :31198/health)
    --> celery/celery-beat 无法连接后端，反复崩溃 (exit code 1)
    --> Docker 文件系统残留导致 Driver Failure (unlinkat: directory not empty)
    --> Allocation 标记为 unrecoverable，停止重启
```

**根本原因**: `psych_supervision` 数据库不存在。API 依赖这个数据库，而 dev-db（PostgreSQL）虽然在 heavy-1 上运行且 Consul 显示 passing，但其中没有创建该数据库。

### 问题 2: heavy-1 内存超分配

heavy-1 分配了 3936 MB 内存，而节点总共只有 3915 MB。这说明 Nomad 的资源配额管理可能未正确设置，或者 Job spec 中的内存请求合计超过了节点容量。这会导致：
- 容器被 OOM Kill
- Docker 无法正常清理容器（产生 "directory not empty" 错误）
- 连锁服务不稳定

### 问题 3: heavy-3 严重空闲

heavy-3 仅运行 1 个 wecom-relay（200MHz CPU, 256MB RAM），利用率不到 7%。可能原因：
- Job spec 中使用了 `constraint` 将服务绑定到特定节点
- 大部分 Job 使用了 `affinity` 或 volume 绑定到 heavy-1

---

## 7. 处理建议

### P0 -- 立即处理

#### 7.1 修复 psych-ai-supervision-dev 数据库

```bash
# 1. 确认 dev-db PostgreSQL 连接
ssh root@heavy-1 "docker exec $(docker ps -q -f name=postgres) psql -U postgres -l"

# 2. 创建缺失的数据库
ssh root@heavy-1 "docker exec $(docker ps -q -f name=postgres) psql -U postgres -c 'CREATE DATABASE psych_supervision;'"

# 3. 重新部署 psych-ai-supervision-dev（重置失败的 allocations）
nomad job restart -address=http://192.168.69.70:4646 psych-ai-supervision-dev

# 或者停止再启动
nomad job stop -address=http://192.168.69.70:4646 psych-ai-supervision-dev
nomad job run -address=http://192.168.69.70:4646 <job-file>.hcl
```

#### 7.2 清理 heavy-1 Docker 文件系统残留

```bash
# 清理已停止的容器和悬挂镜像
ssh root@heavy-1 "docker system prune -f"

# 清理残留的容器目录（如果 docker prune 不够）
ssh root@heavy-1 "docker container prune -f && docker volume prune -f"
```

### P1 -- 尽快处理

#### 7.3 重新均衡 heavy 节点负载

建议将部分 Job 从 heavy-1 迁移到 heavy-3。推荐迁移的候选 Job（无 volume 绑定依赖的）：

| 迁移候选 Job | 当前节点 | CPU | 内存 | 说明 |
|-------------|---------|-----|------|------|
| openstock-dev | heavy-1 | 300 | 256 | 无状态应用，可安全迁移 |
| kairos-dev | heavy-1 | 500 | 512 | 与 kairos-prod 分离到不同节点更安全 |
| silknode-web | heavy-1 | 500 | 512 | NextJS 应用，无状态 |

迁移后的预估分布：
```
heavy-1:  2500 MHz / 2656 MB  (54% CPU / 68% MEM)  [9 allocs]
heavy-2:  2900 MHz / 3244 MB  (63% CPU / 83% MEM)  [6 allocs]
heavy-3:  1500 MHz / 1536 MB  (33% CPU / 39% MEM)  [4 allocs]
```

**操作方式**:
- 在 Job spec 中添加 `spread` stanza 或调整 `constraint` 以实现更均匀分布
- 或使用 `affinity` 引导调度器将部分 Job 调度到 heavy-3

```hcl
# 示例: 在 Job spec 中添加 spread
spread {
  attribute = "${node.unique.name}"
  weight    = 100
}
```

#### 7.4 审查 Job 内存配置

heavy-1 的内存已超分配 (3936MB allocated vs 3915MB available)。需要：
1. 审查每个 Job 的实际内存使用（`nomad alloc status`）
2. 对于实际使用远低于分配的 Job，减少 `resources.memory` 值
3. 考虑设置 `memory_max` (可突发内存) 和更低的基础 `memory` 值

### P2 -- 持续改进

#### 7.5 利用 light 节点

当前 5 个 light 节点完全空闲（无应用 allocation）。light 节点只有 `exec` 和 `raw_exec` 驱动（无 docker），但可以考虑：
- 安装 Docker 驱动扩展 light 节点能力
- 将非 Docker 类型的任务（如静态文件服务、定时任务）调度到 light 节点

#### 7.6 添加安全告警

psych-ai API 日志中出现 `使用默认的SECRET_KEY，生产环境请修改！` 警告。即使是 dev 环境，也建议通过环境变量设置独立的 SECRET_KEY。

#### 7.7 定期健康检查

建议设置自动化监控：
- Nomad failed allocation 告警
- Consul critical check 告警
- 节点内存使用率超过 80% 告警

---

## 8. 检查总结

| 检查项 | 结果 | 严重程度 |
|--------|------|----------|
| Nomad/Consul API 可达 | PASS | -- |
| 所有节点 ready | PASS | -- |
| 所有 Job running | PASS | -- |
| psych-ai-supervision-dev celery/celery-beat failed | FAIL | P0 |
| psych-ai-dev-api Consul 健康检查 critical | FAIL | P0 |
| psych-ai-supervision-dev 数据库缺失 | FAIL | P0 (根因) |
| heavy-1 Docker 文件系统残留 | WARN | P0 |
| heavy-1 内存超分配 (100.5%) | WARN | P1 |
| heavy 节点负载不均 (63% vs 5%) | WARN | P1 |
| light 节点完全空闲 | INFO | P2 |
| psych-ai SECRET_KEY 使用默认值 | INFO | P2 |

**最优先处理**: 在 dev-db PostgreSQL 中创建 `psych_supervision` 数据库，然后重启 psych-ai-supervision-dev Job。同时清理 heavy-1 上的 Docker 文件系统残留，并规划 Job 迁移以均衡负载。
