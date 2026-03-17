# Aether 集群健康报告

> **生成时间**: 2026-03-17 21:58 UTC
> **Nomad 地址**: http://192.168.69.80:4646
> **Consul 地址**: http://192.168.69.70:8500
> **Skill**: aether-status v1.1.0 (模式 1: 集群概览 + 模式 3: 失败 Allocation 详情)

---

## 集群概览

```
Aether 集群状态
================
Nomad 集群: 3 Server peers (Leader: 192.168.69.71:4647)
Nomad 节点: 3 heavy (ready) + 5 light (ready) = 8/8 节点正常
运行中 Jobs: 15 (15 service, 0 batch)
Allocations: 17 running, 1 failed, 5 complete
失败 Allocs: 1 (psych-ai-supervision-dev/celery @ heavy-1)
Consul 服务: 19 服务 passing (44 checks), 2 critical
```

---

## 1. Nomad 节点状态

### Server 集群

| 角色 | 地址 | 状态 |
|------|------|------|
| Server Peer | 192.168.69.70:4647 | OK |
| Server Peer (Leader) | 192.168.69.71:4647 | OK |
| Server Peer | 192.168.69.72:4647 | OK |

Server 集群 3 节点运行正常，Leader 为 192.168.69.71。

### Client 节点

| 节点 | 地址 | 类型 | 状态 | Drain | 调度资格 | 运行中 Allocs |
|------|------|------|------|-------|----------|--------------|
| heavy-1 | 192.168.69.80 | heavy_workload | ready | No | eligible | 10 |
| heavy-2 | 192.168.69.81 | heavy_workload | ready | No | eligible | 7 |
| heavy-3 | 192.168.69.82 | heavy_workload | ready | No | eligible | 1 |
| light-1 | 192.168.69.90 | light_exec | ready | No | eligible | 0 |
| light-2 | 192.168.69.91 | light_exec | ready | No | eligible | 0 |
| light-3 | 192.168.69.92 | light_exec | ready | No | eligible | 0 |
| light-4 | 192.168.69.93 | light_exec | ready | No | eligible | 0 |
| light-5 | 192.168.69.94 | light_exec | ready | No | eligible | 0 |

所有 8 个节点状态均为 `ready`，无 Drain，调度资格均为 `eligible`。Nomad 版本: 1.11.2。

---

## 2. 运行中的 Jobs

共 **15** 个 Jobs，全部为 `service` 类型，状态均为 `running`。

| Job | 类型 | 状态 | 节点分布 |
|-----|------|------|----------|
| traefik | service | running | heavy-1 |
| dev-db | service | running | heavy-1 (x2) |
| kairos-prod | service | running | heavy-2 |
| kairos-dev | service | running | heavy-2 |
| nexus-api-dev | service | running | heavy-1 |
| nexus-db-dev | service | running | heavy-2 |
| nexus-redis-dev | service | running | heavy-2 |
| openstock-dev | service | running | heavy-1 |
| psych-ai-supervision-dev | service | running | heavy-1 (x3) |
| silknode-gateway | service | running | heavy-2 |
| todo-web-backend-dev | service | running | heavy-2 |
| todo-web-backend-prod | service | running | heavy-2 |
| todo-web-frontend-dev | service | running | heavy-1 |
| todo-web-frontend-prod | service | running | heavy-1 |
| wecom-relay | service | running | heavy-3 |

### 最近部署 (按 ModifyIndex 排序)

| Job | 状态 | ModifyIndex |
|-----|------|-------------|
| kairos-dev | running | 50034 |
| nexus-api-dev | running | 50010 |
| silknode-gateway | running | 48983 |
| wecom-relay | running | 47158 |
| kairos-prod | running | 45007 |

---

## 3. 失败的 Allocations

### [CRITICAL] psych-ai-supervision-dev / celery @ heavy-1

```
Allocation: 47c7970a-4884-c99a-bd9f-cde86a191e75
Job:        psych-ai-supervision-dev
Task Group: celery
Task:       worker
Node:       heavy-1 (192.168.69.80)
Status:     failed (dead)
Restarts:   39 次
创建时间:   2026-03-15 01:34:35 UTC
最后重启:   2026-03-16 09:53:08 UTC
终止时间:   2026-03-16 09:53:24 UTC
```

**失败事件链**:

1. **多次 Exit Code 1 退出** -- Docker 容器多次以 exit code 1 非零退出，累计重启 39 次
2. **Docker 驱动失败** -- 最终因 Docker 容器清理失败导致不可恢复错误:
   ```
   failed to create container: Failed to purge container e05c48f9e8dc...
   Error response from daemon: cannot remove container: unable to remove filesystem:
   unlinkat /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9e8dc...: directory not empty
   ```
3. **最终状态**: `Not Restarting` -- "Error was unrecoverable"

**根因分析**: 该 celery worker 容器反复崩溃 (exit code 1)，在第 39 次重启时，Docker 尝试清理旧容器失败（文件系统目录非空），导致无法创建新容器，allocation 标记为不可恢复。

---

## 4. Consul 服务健康状况

### 概览

- **Passing**: 19 个服务 (44 个 health checks 通过)
- **Warning**: 0
- **Critical**: 2 个服务检查失败

### Passing 服务列表

| 服务 | 状态 |
|------|------|
| dev-db | passing |
| dev-redis | passing |
| kairos-prod | passing |
| nexus-api-dev | passing |
| nexus-db-dev | passing |
| nexus-redis-dev | passing |
| nomad | passing |
| nomad-client | passing |
| openstock-dev | passing |
| psych-ai-dev-frontend | passing |
| silknode-gateway | passing |
| silknode-redis | passing |
| todo-web-backend-dev | passing |
| todo-web-backend-prod | passing |
| todo-web-frontend-dev | passing |
| todo-web-frontend-prod | passing |
| traefik | passing |
| wecom-relay | passing |

### [CRITICAL] 失败的服务检查

#### 1. psych-ai-dev-api @ heavy-1

```
服务:    psych-ai-dev-api
节点:    heavy-1
检查类型: HTTP
错误信息: Get "http://192.168.69.80:31198/health": dial tcp 192.168.69.80:31198: connect: connection refused
```

**关联**: 此问题与上述 `psych-ai-supervision-dev` Job 的 celery worker 失败直接相关。API 服务虽然在运行，但其健康检查端口 31198 连接被拒绝。

#### 2. kairos-dev @ heavy-2

```
服务:    kairos-dev
节点:    heavy-2
检查类型: HTTP
错误信息: (空 -- 刚注册，健康检查尚未通过)
```

**关联**: kairos-dev 的 allocation (993c1c2e) 刚于 2026-03-17 21:58:09 UTC 创建并启动，容器正在下载镜像并初始化中，Consul 健康检查尚未通过。这是**正常的启动过程**，预计数秒后将转为 passing。

---

## 5. 异常汇总与修复建议

### 异常 1: psych-ai-supervision-dev celery worker 持续失败

**严重程度**: HIGH

**现象**:
- celery task group 的 worker 任务已死亡，重启 39 次后因 Docker 驱动错误停止
- Consul 中 psych-ai-dev-api 健康检查 critical

**修复建议**:

1. **清理 Docker 残留容器** (优先):
   ```bash
   ssh root@heavy-1 "docker rm -f e05c48f9e8dc"
   ssh root@heavy-1 "docker system prune -f"
   ```

2. **检查 celery worker 应用日志** (排查 exit code 1 根因):
   ```bash
   # 获取 running allocation 的日志
   ALLOC_ID=$(curl -s http://192.168.69.80:4646/v1/job/psych-ai-supervision-dev/allocations | \
     jq -r '[.[] | select(.ClientStatus == "running")][0].ID')
   curl -s "http://192.168.69.80:4646/v1/client/fs/logs/${ALLOC_ID}?task=worker&type=stderr&plain=true"
   ```

3. **重新部署 celery task group**:
   ```bash
   # 先停止再启动，让 Nomad 重新调度
   nomad job restart -task celery psych-ai-supervision-dev
   # 或者重新提交 job
   nomad job run psych-ai-supervision-dev.hcl
   ```

4. **检查 psych-ai-dev-api 健康检查端口**:
   ```bash
   ssh root@heavy-1 "curl -sf http://localhost:31198/health"
   ssh root@heavy-1 "netstat -tlnp | grep 31198"
   ```

### 异常 2: kairos-dev Consul 检查 critical (低风险)

**严重程度**: LOW -- 可能是瞬态状态

**现象**: kairos-dev 刚完成新部署 (allocation 993c1c2e 于 21:58:09 创建)，容器正在启动中。

**建议**: 等待 30-60 秒后再次检查:
```bash
curl -s http://192.168.69.70:8500/v1/health/service/kairos-dev | \
  jq '[.[] | {node: .Node.Node, status: .Checks[].Status}]'
```

如果持续 critical 超过 5 分钟，查看容器日志:
```bash
ALLOC_ID=$(curl -s http://192.168.69.80:4646/v1/job/kairos-dev/allocations | \
  jq -r '[.[] | select(.ClientStatus == "running")][0].ID')
curl -s "http://192.168.69.80:4646/v1/client/fs/logs/${ALLOC_ID}?task=kairos&type=stderr&plain=true"
```

### 观察项: 负载分布不均

**严重程度**: INFO

**现象**: 所有工作负载集中在 heavy 节点 (heavy-1: 10 allocs, heavy-2: 7 allocs, heavy-3: 1 alloc)，5 个 light 节点完全空闲。

**说明**: light 节点类型为 `light_exec`，仅支持 exec 驱动，不支持 Docker。这是架构设计决定的分配方式，无需修复。但可以考虑:
- heavy-3 仅运行 1 个 allocation (wecom-relay)，可考虑将部分 heavy-1/heavy-2 的负载迁移过去以均衡资源使用
- 如果 light 节点有 exec 类型的 job 需求，可以利用这些空闲资源

---

## 6. 总结

| 维度 | 状态 | 说明 |
|------|------|------|
| Nomad Server 集群 | OK | 3 peers, Leader 正常 |
| Nomad Client 节点 | OK | 8/8 ready, 无 drain |
| Jobs | WARN | 15/15 running, 但 1 个 job 有 failed allocation |
| Allocations | WARN | 17 running / 1 failed / 5 complete |
| Consul 服务 | WARN | 19 passing / 2 critical |
| **总体健康度** | **WARN** | **需关注 psych-ai-supervision-dev 失败问题** |

**需要立即处理**:
1. psych-ai-supervision-dev 的 celery worker 已停止运行，需要清理 Docker 残留并重新部署

**需要观察**:
2. kairos-dev 刚部署，等待健康检查通过

---

*报告由 aether-status skill v1.1.0 生成 | 数据源: Nomad API + Consul API*
