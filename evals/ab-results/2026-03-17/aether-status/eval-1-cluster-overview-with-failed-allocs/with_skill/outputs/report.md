# Aether 集群健康检查报告

> **检查时间**: 2026-03-18 20:30 UTC
> **Nomad**: http://192.168.69.70:4646
> **Consul**: http://192.168.69.70:8500

---

## 集群概览

```
Aether 集群状态
================
Nomad 节点: 3 heavy (ready) + 5 light (ready) = 8/8 在线
运行中 Jobs: 17 (全部 service 类型)
当前活跃 Allocs: 20 running
失败 Allocs: 2 (psych-ai-supervision-dev/celery @ heavy-1, mailpit @ heavy-2)
Consul 服务: 21 个应用服务, 48 passing, 1 critical
Nomad 版本: 1.11.2 (全集群统一)
```

---

## 1. Nomad 节点状态

所有 8 个节点均为 `ready` 状态，无 drain 或 ineligible 节点。

| 节点 | IP | 状态 | 类型 | 驱动 | 调度资格 |
|------|-----|------|------|------|---------|
| heavy-1 | 192.168.69.80 | ready | heavy_workload | docker, exec | eligible |
| heavy-2 | 192.168.69.81 | ready | heavy_workload | docker, exec | eligible |
| heavy-3 | 192.168.69.82 | ready | heavy_workload | docker, exec | eligible |
| light-1 | 192.168.69.90 | ready | light_exec | exec | eligible |
| light-2 | 192.168.69.91 | ready | light_exec | exec | eligible |
| light-3 | 192.168.69.92 | ready | light_exec | exec | eligible |
| light-4 | 192.168.69.93 | ready | light_exec | exec | eligible |
| light-5 | 192.168.69.94 | ready | light_exec | exec | eligible |

**结论**: 节点层面健康，无异常。

---

## 2. 运行中的 Jobs

共 17 个 Job，全部为 service 类型，状态均为 `running`。

| Job | 状态 | Running | 历史 Failed | 最近提交时间 |
|-----|------|---------|------------|-------------|
| mailpit | running | 1 | 1 | 2026-03-18 12:26 |
| silknode-web | running | 1 | 0 | 2026-03-18 10:55 |
| nexus-api-dev | running | 1 | **7** | 2026-03-17 23:10 |
| kairos-dev | running | 1 | 3 | 2026-03-17 23:00 |
| silknode-gateway | running | 1 | 0 | 2026-03-17 08:45 |
| wecom-relay | running | 1 | 0 | 2026-03-16 07:37 |
| kairos-prod | running | 1 | 2 | 2026-03-15 01:39 |
| dev-db | running | 2 | 4 | 2026-03-10 08:30 |
| psych-ai-supervision-dev | running | 3 | **5** | 2026-03-10 07:14 |
| traefik | running | 1 | 4 | 2026-03-09 14:10 |
| nexus-db-dev | running | 1 | 0 | 2026-03-10 08:28 |
| nexus-redis-dev | running | 1 | 1 | 2026-03-08 13:56 |
| todo-web-backend-dev | running | 1 | 0 | 2026-03-10 21:03 |
| todo-web-backend-prod | running | 1 | 0 | 2026-03-10 21:03 |
| todo-web-frontend-dev | running | 1 | 1 | 2026-03-08 |
| todo-web-frontend-prod | running | 1 | 1 | 2026-03-08 |
| openstock-dev | running | 1 | 1 | 2026-03-08 |

**需关注**: `nexus-api-dev` 累计 7 次失败，`psych-ai-supervision-dev` 累计 5 次失败，`traefik` 和 `dev-db` 各 4 次。虽然当前都有 running 实例，但高失败次数说明部署过程中存在反复问题。

---

## 3. 失败的 Allocations 详情

### 3.1 psych-ai-supervision-dev / celery (当前活跃失败)

```
Allocation: 47c7970a-4884-c99a-bd9f-cde86a191e75
Job:        psych-ai-supervision-dev
Task Group: celery
Node:       heavy-1
Status:     failed (desired: run)
Restarts:   39 次

Task 状态:
  worker: dead (failed)

最近事件:
  [2026-03-16 09:53:08] Restarting - Task restarting in 16s
  [2026-03-16 09:53:24] Driver Failure - failed to create container:
    Failed to purge container e05c48f9...: unable to remove filesystem:
    unlinkat /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9...:
    directory not empty
  [2026-03-16 09:53:24] Not Restarting - Error was unrecoverable
```

**根因**: Docker 容器清理失败。heavy-1 上残留的容器文件系统目录无法删除 (`directory not empty`)，导致新容器无法创建。经过 39 次重启后被标记为不可恢复。

**当前影响**: celery worker 未运行 (desired=run 但 status=failed)，异步任务队列无法处理。psych-ai-supervision-dev 的 API 和 frontend 正常，但后台任务不工作。

### 3.2 mailpit (历史失败，已恢复)

```
Allocation: 970c9c1e-5098-b5cc-67e3-aab40ad909bb
Job:        mailpit
Task Group: mailpit
Node:       heavy-2
Status:     failed (desired: stop)
Restarts:   2 次

Task 状态:
  mailpit: dead (failed)

最近事件:
  [2026-03-18 12:26:04] Terminated - Exit Code: 1
  [2026-03-18 12:26:04] Not Restarting - Exceeded allowed attempts 2 in 30m, mode "fail"
  [2026-03-18 12:26:04] Alloc Unhealthy
```

**状态**: desired=stop，表明该 allocation 是旧版本的残留。mailpit 当前有 1 个 running 实例（新版本已部署成功），此失败记录为部署更新过程中的历史记录，**无需处理**。

---

## 4. Consul 服务健康

### 4.1 健康概览

- **Passing**: 48 个健康检查通过（含 nomad/nomad-client 系统检查）
- **Critical**: 1 个
- **Warning**: 0 个

### 4.2 Critical 服务

```
服务:    psych-ai-dev-api
节点:    heavy-1
检查类型: HTTP
检查 URL: http://192.168.69.80:31198/health
错误:    connection refused
```

**原因**: 端口 31198 上的 psych-ai-dev-api 健康检查端点无法连接。可能与 celery worker 失败后的级联影响有关，或者 API 容器的动态端口已变更但 Consul 注册未更新。

### 4.3 注册的服务列表 (21 个应用服务)

| 服务 | 健康检查 | 状态 |
|------|---------|------|
| traefik | passing | OK |
| dev-db (PostgreSQL) | passing | OK |
| dev-redis | passing | OK |
| kairos-dev | passing | OK |
| kairos-prod | passing | OK |
| mailpit-smtp | passing | OK |
| mailpit-ui | passing | OK |
| nexus-api-dev | passing | OK |
| nexus-db-dev | passing | OK |
| nexus-redis-dev | passing | OK |
| openstock-dev | passing | OK |
| psych-ai-dev-api | **critical** | FAIL |
| psych-ai-dev-frontend | passing | OK |
| silknode-gateway | passing | OK |
| silknode-redis | passing | OK |
| silknode-web | passing | OK |
| todo-web-backend-dev | passing | OK |
| todo-web-backend-prod | passing | OK |
| todo-web-frontend-dev | passing | OK |
| todo-web-frontend-prod | passing | OK |
| wecom-relay | passing | OK |

---

## 5. Heavy 节点负载分布分析

### 5.1 Allocation 分布

| 节点 | Running Allocs | 占比 | 部署的 Jobs |
|------|---------------|------|------------|
| **heavy-1** | **12** | **60%** | dev-db (redis+postgres), mailpit, nexus-api-dev, openstock-dev, psych-ai-supervision-dev (frontend+api+celery-beat), silknode-web, todo-web-frontend-dev, todo-web-frontend-prod, traefik |
| **heavy-2** | **7** | **35%** | kairos-dev, kairos-prod, nexus-db-dev, nexus-redis-dev, silknode-gateway, todo-web-backend-dev, todo-web-backend-prod |
| **heavy-3** | **1** | **5%** | wecom-relay |

### 5.2 分布评估

```
负载分布严重不均衡
====================
heavy-1: ████████████████████████ 60% (12 allocs)
heavy-2: ██████████████           35% (7 allocs)
heavy-3: ██                        5% (1 alloc)
```

**问题**: heavy-3 严重闲置，仅运行 1 个 wecom-relay 服务。heavy-1 承载了集群 60% 的工作负载，包括关键基础设施（traefik 反向代理、dev-db 数据库）和多个应用服务。

**风险**:
- heavy-1 故障将导致 9 个服务同时不可用（包括 traefik 入口网关）
- heavy-3 的计算资源大量浪费
- heavy-1 上的 Docker 文件系统问题（见 celery 失败）可能与负载过高有关

### 5.3 Light 节点使用情况

5 个 light 节点全部在线但 **无运行 allocation**。这些节点仅支持 exec 驱动（无 docker），所以当前所有需要 Docker 的 Job 无法调度到 light 节点。

---

## 6. 问题汇总与处理建议

### P0 - 需要立即处理

#### 6.1 psych-ai-supervision-dev celery worker 失败

**问题**: Docker 容器文件系统残留导致 celery worker 无法启动，已重试 39 次后放弃。

**修复步骤**:
```bash
# 1. SSH 到 heavy-1 清理残留容器文件
ssh root@heavy-1 "docker system prune -f"

# 2. 如果上述不够，手动清理问题目录
ssh root@heavy-1 "rm -rf /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9e8dc*"

# 3. 重启失败的 allocation
# 方法一: 停止并重启 job
curl -X POST "http://192.168.69.70:4646/v1/job/psych-ai-supervision-dev/periodic/force"
# 方法二: 通过 CLI
ssh root@heavy-1 "nomad alloc restart 47c7970a"
# 方法三: 重新提交 job spec
nomad job run psych-ai-supervision-dev.hcl
```

#### 6.2 psych-ai-dev-api Consul 健康检查失败

**问题**: API 健康端点 connection refused。

**修复步骤**:
```bash
# 1. 确认 API 容器是否真的在运行
curl -sf "http://192.168.69.70:4646/v1/job/psych-ai-supervision-dev/allocations" | \
  jq '.[] | select(.TaskGroup == "api" and .ClientStatus == "running") | {id: .ID[:8], node: .NodeName}'

# 2. 检查实际监听端口
ssh root@heavy-1 "docker ps | grep psych"

# 3. 如果端口不匹配，可能需要重新注册服务或重启 allocation
nomad alloc restart <api-alloc-id>
```

### P1 - 建议尽快处理

#### 6.3 Heavy 节点负载不均衡

**问题**: heavy-1 承载 60% 负载，heavy-3 仅 5%。

**建议**:
```bash
# 1. 将部分 Job 的 constraint 调整为允许更多节点
# 检查哪些 job 有节点约束
for job in dev-db openstock-dev traefik; do
  echo "=== $job ==="
  curl -sf "http://192.168.69.70:4646/v1/job/$job" | jq '.Constraints, .TaskGroups[].Constraints'
done

# 2. 对无状态服务，考虑增加 count 并分散到 heavy-2/heavy-3
# 3. 对有状态服务 (dev-db)，确保 volume 在目标节点也已创建:
#    aether volume create --node heavy-3 --project dev-db --volumes data

# 4. 考虑将 traefik 部署为 system 类型 job，在所有 heavy 节点运行
```

#### 6.4 nexus-api-dev 高失败率

**问题**: 累计 7 次历史失败（当前运行正常）。

**建议**:
```bash
# 查看历史失败原因
curl -sf "http://192.168.69.70:4646/v1/job/nexus-api-dev/allocations" | \
  jq '[.[] | select(.ClientStatus == "failed") | {id: .ID[:8], events: [.TaskStates[].Events[] | select(.Type == "Terminated" or .Type == "Driver Failure") | .DisplayMessage]}]'

# 如果是频繁 OOM 或配置错误，调整资源限制或修复应用配置
```

### P2 - 优化建议

#### 6.5 Light 节点利用率

5 个 light 节点完全闲置。如果有不需要 Docker 的工作负载（如纯 exec 任务、批处理），可以调度到 light 节点以分散压力。

#### 6.6 Docker 文件系统清理

heavy-1 上出现的 Docker 容器清理问题建议设置定期维护：
```bash
# 在所有 heavy 节点设置 cron 定期清理
ssh root@heavy-1 "echo '0 3 * * * docker system prune -f --volumes 2>&1 | logger -t docker-prune' | crontab -"
ssh root@heavy-2 "echo '0 3 * * * docker system prune -f --volumes 2>&1 | logger -t docker-prune' | crontab -"
ssh root@heavy-3 "echo '0 3 * * * docker system prune -f --volumes 2>&1 | logger -t docker-prune' | crontab -"
```

---

## 7. 总结

| 类别 | 状态 | 说明 |
|------|------|------|
| 节点可用性 | **正常** | 8/8 节点 ready |
| Job 运行 | **基本正常** | 17/17 job running，但 celery worker 缺失 |
| Allocation 健康 | **需关注** | 2 个 failed alloc（1 个活跃，1 个历史） |
| Consul 服务 | **需关注** | 1 个 critical（psych-ai-dev-api） |
| 负载分布 | **不均衡** | heavy-1 过载 (60%)，heavy-3 闲置 (5%) |
| 整体评级 | **亚健康** | 可用但存在隐患，建议按优先级处理上述问题 |

---

*报告由 aether-status skill 生成 | 2026-03-18*
