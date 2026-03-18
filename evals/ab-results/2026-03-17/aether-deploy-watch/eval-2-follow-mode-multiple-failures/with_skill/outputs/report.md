# Aether 部署监控 - 全面巡检报告

> **时间**: 2026-03-18 12:45 UTC
> **Nomad**: http://192.168.69.70:4646
> **Consul**: http://192.168.69.70:8500

---

## 集群概览

| Job | 类型 | 状态 | 健康状况 |
|-----|------|------|----------|
| dev-db | service | running | 正常 |
| kairos-dev | service | running | 正常 |
| kairos-prod | service | running | **配置缺失** |
| mailpit | service | running | 正常（历史故障已恢复） |
| nexus-api-dev | service | running | 正常 |
| nexus-db-dev | service | running | 正常 |
| nexus-redis-dev | service | running | 正常 |
| openstock-dev | service | running | 正常 |
| psych-ai-supervision-dev | service | running | **严重故障** |
| silknode-gateway | service | running | 正常 |
| silknode-web | service | running | 正常（用户触发过重启） |
| todo-web-backend-dev | service | running | 正常 |
| todo-web-backend-prod | service | running | 正常 |
| todo-web-frontend-dev | service | running | 正常 |
| todo-web-frontend-prod | service | running | 正常 |
| traefik | service | running | 正常 |
| wecom-relay | service | running | 正常 |

**集群节点**: 8 节点全部 `ready`（heavy-1/2/3, light-1/2/3/4/5）

---

## 问题汇总

| 严重级别 | Job | 问题 | 影响 |
|---------|-----|------|------|
| **P0 严重** | psych-ai-supervision-dev | worker 已死、beat 持续报错、api 无法连接数据库 | 服务完全不可用 |
| **P1 重要** | kairos-prod | 企微（WeCom）集成缺少配置 | Webhook 和媒体处理不可用 |
| **P2 一般** | mailpit | 历史故障 allocation（已恢复） | 当前无影响 |

---

## 问题 1: psych-ai-supervision-dev（P0 严重）

### 状态检查

```
Job: psych-ai-supervision-dev (service, running, v21)
最新部署: v21 - FAILED
  失败原因: Failed due to progress deadline

Allocations:
  47c7970a (celery/worker)     - FAILED   (desired=run)  restarts=39
  a47723fa (celery-beat/beat)   - running  (desired=run)  restarts=82
  c130f968 (api/api)            - running  (desired=run)  restarts=0   Alloc Unhealthy
  9747d4e1 (frontend/nginx)     - running  (desired=run)  restarts=0

Consul 健康检查:
  psych-ai-dev-api:      CRITICAL
  psych-ai-dev-frontend: passing
```

### 失败诊断

本服务存在 **三个独立但关联的故障**：

---

#### 故障 A: Celery Worker 已死（不可恢复）

**错误信息**:
```
Driver Failure: failed to create container: Failed to purge container
e05c48f9e8dc...: Error response from daemon: cannot remove container:
unable to remove filesystem: unlinkat /opt/aether-volumes/runners/heavy-1/
docker/containers/e05c48f9e8dc...: directory not empty
```

**错误分析**:

匹配模式: **Docker 驱动故障** + **网络不可达**

Worker 经历了双重故障：
1. 首先因无法连接 Redis（`192.168.69.82:6379` - heavy-3）反复崩溃退出（exit code 1），重启 39 次
2. 最终在尝试清理旧容器时遭遇 Docker 文件系统锁定，触发 `Driver Failure`
3. Nomad 判定为不可恢复错误（`Not Restarting: Error was unrecoverable`），彻底停止

**根因**: Redis 服务配置指向 `192.168.69.82:6379`（heavy-3），但 heavy-3 上 **没有运行 Redis**。仅有 `wecom-relay` 一个 allocation 在运行。Consul 中也未注册任何 Redis 服务在 heavy-3 上。

---

#### 故障 B: Celery Beat 持续报错（82 次重启）

**错误信息**:
```
[ERROR/MainProcess] beat: Connection error: Error 111 connecting to
192.168.69.82:6379. Connection refused. Trying again in 32.0 seconds...
```

**错误分析**:

匹配模式: **网络不可达**（`connection refused`）

与 Worker 相同的根因：Redis broker 地址 `redis://192.168.69.82:6379/1` 不可达。Beat 进程每 32 秒重试一次，无限循环。虽然 Nomad 显示 `running`，但实际上 **无法执行任何定时任务**。

---

#### 故障 C: API 服务启动失败

**错误信息**:
```
asyncpg.exceptions.InvalidCatalogNameError: database "psych_supervision" does not exist

ERROR:    Application startup failed. Exiting.
```

**错误分析**:

匹配模式: **配置错误**（`config.*error`）

API 服务配置的数据库连接串为 `postgresql://postgres:dev123456@192.168.69.80:5432/psych_supervision`，但目标 PostgreSQL 上 **不存在 `psych_supervision` 数据库**。API 服务反复启动失败，Consul 健康检查报告 `connection refused`（服务进程已退出）。

Nomad 部署因此超时：`Task not running for min_healthy_time of 10s by healthy_deadline of 5m0s`

---

#### 修复建议

**第一优先级 - 恢复 Redis 连接**:

```bash
# 方案 A: 在 heavy-3 上启动 Redis 服务
# 如果之前有 Redis Job，重新提交
nomad job run <redis-job-for-psych>.hcl

# 方案 B: 修改 Job 配置，指向已有的 Redis
# 集群中 dev-redis 运行在 heavy-1 (192.168.69.80)
# 修改 psych-ai-supervision-dev 的环境变量:
#   REDIS_URL=redis://192.168.69.80:6379/0
#   CELERY_BROKER_URL=redis://192.168.69.80:6379/1
# 注意: 确认 dev-redis 的端口映射和 DB 编号不冲突
```

**第二优先级 - 创建数据库**:

```bash
# 连接到 heavy-1 上的 PostgreSQL (dev-db allocation)
# 创建缺失的数据库
ssh root@heavy-1 "docker exec <postgres-container> \
  psql -U postgres -c 'CREATE DATABASE psych_supervision;'"

# 或通过 Nomad exec
# 找到 dev-db 的 postgres allocation
nomad alloc exec <dev-db-postgres-alloc-id> \
  psql -U postgres -c 'CREATE DATABASE psych_supervision;'
```

**第三优先级 - 清理 Docker 并重启 Worker**:

```bash
# 清理 heavy-1 上残留的 Docker 容器文件
ssh root@heavy-1 "docker system prune -f"

# 清理后，停止并重新提交 Job
nomad job stop psych-ai-supervision-dev
nomad job run <psych-ai-supervision-dev>.hcl

# 监控恢复情况
# /aether:deploy-watch psych-ai-supervision-dev --follow --timeout=120
```

**完整恢复流程**:
1. 确认/启动 Redis 服务（指向正确地址）
2. 创建 `psych_supervision` 数据库
3. 清理 heavy-1 Docker 残留文件
4. 重新提交 psych-ai-supervision-dev Job
5. 使用 `/aether:deploy-watch psych-ai-supervision-dev --follow` 验证

---

## 问题 2: kairos-prod（P1 重要）

### 状态检查

```
Job: kairos-prod (service, running, v0)
最新部署: v0 - successful (但有 2 个 unhealthy alloc 历史)

Allocations:
  f501bca3 (kairos/kairos) - running (desired=run) restarts=0
  DeploymentStatus: Healthy=True

Consul 健康检查:
  kairos-prod: passing
```

### 失败诊断

**错误信息**（stderr 日志）:
```
[Bootstrap] 企微配置加载失败，Webhook 将不可用: Error: 缺少必需的环境变量:
  WECOM_CORP_ID, WECOM_AGENT_ID, WECOM_SECRET, WECOM_ENCODING_AES_KEY
[Bootstrap] WeCom API 未初始化，媒体处理器将不可用
[Skills] 跳过 sendVoiceMessage skill: 缺少 ttsGateway 或 wecomClient
```

**错误分析**:

匹配模式: **配置错误**（`config.*error`）

服务本身正常启动（端口 3000 监听中，健康检查通过），但 **企微（WeCom）集成功能完全不可用**：
- 缺少 4 个必需环境变量: `WECOM_CORP_ID`, `WECOM_AGENT_ID`, `WECOM_SECRET`, `WECOM_ENCODING_AES_KEY`
- Webhook 回调无法工作
- 语音消息功能被跳过
- 媒体处理器无法初始化

当前 Job 环境变量中只配置了基础服务参数（`NODE_ENV`, `PORT`, `DATABASE_PATH` 等），未包含企微相关 secrets。

**部署历史注意**: 部署 v0 成功，但经历了 3 次 placement（1 healthy + 2 unhealthy），说明部署过程不太顺利。

### 修复建议

```bash
# 1. 在 Nomad Job 文件中添加企微环境变量
#    可以通过 Nomad Vault 集成或直接在 Job spec 中配置:
#
#    env {
#      WECOM_CORP_ID          = "{{ ... }}"
#      WECOM_AGENT_ID         = "{{ ... }}"
#      WECOM_SECRET           = "{{ ... }}"
#      WECOM_ENCODING_AES_KEY = "{{ ... }}"
#    }
#
#    建议使用 Nomad template + Vault/Consul KV 存储 secrets

# 2. 重新部署
nomad job run <kairos-prod>.hcl

# 3. 验证
# /aether:deploy-watch kairos-prod --follow
```

---

## 问题 3: mailpit（P2 一般 - 已自愈）

### 状态检查

```
Job: mailpit (service, running, v2)
最新部署: v2 - successful

Allocations:
  756da541 (mailpit/mailpit) - running  (desired=run)  restarts=0   [当前]
  970c9c1e (mailpit/mailpit) - failed   (desired=stop) restarts=2   [历史]

Consul 健康检查:
  mailpit-smtp: passing
  mailpit-ui:   passing
```

### 失败诊断

**历史故障记录**（allocation 970c9c1e）:

```
Exceeded allowed attempts 2 in interval 30m0s and mode is "fail"
Alloc Unhealthy: Unhealthy because of failed task
Exit Code: 1 (Docker container exited with non-zero exit code)
```

**错误分析**:

匹配模式: **配置错误 / 启动失败**

旧 allocation 在 heavy-2 上连续崩溃 2 次后被标记为 failed。Nomad 随后在 heavy-1 上成功调度了新的 allocation（756da541），当前运行正常。

**结论**: 问题已自动恢复，可能是 heavy-2 节点上的临时问题（资源竞争或 Docker 状态异常）。当前无需干预。

---

## 其他观察

### silknode-web（信息级别）

```
Allocation: 7d3e7f1c (nextjs) - running, restarts=1
重启原因: "User requested task to restart" (用户手动触发)
```

这是用户主动重启，非故障。Exit Code 0，正常。

### 集群资源分布

| 节点 | 运行 Jobs | 状态 |
|------|----------|------|
| heavy-1 (192.168.69.80) | dev-db, nexus-api-dev, psych-ai-supervision-dev, silknode-web, traefik, mailpit, openstock-dev, todo-web-frontend-dev/prod | ready |
| heavy-2 (192.168.69.81) | kairos-dev, kairos-prod, nexus-db-dev, nexus-redis-dev, silknode-gateway, todo-web-backend-dev/prod | ready |
| heavy-3 (192.168.69.82) | wecom-relay | ready |
| light-1~5 | (无 allocation) | ready |

**注意**: heavy-1 负载明显偏重（9+ jobs），heavy-3 几乎空闲，light 节点完全空闲。可考虑通过 constraint/affinity 配置优化分布。

---

## 行动优先级

| 优先级 | 行动 | 预计影响 |
|--------|------|----------|
| **P0** | 恢复 psych-ai-supervision-dev 的 Redis 连接 | 解决 worker/beat 全部故障 |
| **P0** | 为 psych-ai-supervision-dev 创建 PostgreSQL 数据库 | 解决 API 启动失败 |
| **P0** | 清理 heavy-1 Docker 残留文件，重新部署 psych | 恢复完整服务 |
| **P1** | 为 kairos-prod 配置企微环境变量 | 恢复 WeCom 集成功能 |
| **P2** | 监控 mailpit 在 heavy-2 上的稳定性 | 预防性观察 |
| **P3** | 考虑优化 Job 跨节点分布 | 提升集群弹性 |

---

## Consul 健康检查摘要

| 状态 | 服务 | 数量 |
|------|------|------|
| passing | 全部服务（除下列外） | 27 |
| **critical** | psych-ai-dev-api | 1 |

---

*报告生成: aether-deploy-watch*
*巡检范围: 全集群 17 个 Jobs, 8 个节点*
