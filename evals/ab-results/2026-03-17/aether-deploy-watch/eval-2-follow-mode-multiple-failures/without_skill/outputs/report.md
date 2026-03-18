# Nomad 集群全面巡检报告

**巡检时间**: 2026-03-18 12:47 UTC
**集群地址**: Nomad http://192.168.69.70:4646 | Consul http://192.168.69.70:8500
**巡检范围**: 全部 17 个 Job, 8 个节点

---

## 一、集群基础设施状态

### 节点状态

| 节点 | IP | 状态 | Drain |
|------|-----|------|-------|
| heavy-1 | 192.168.69.80 | ready | No |
| heavy-2 | 192.168.69.81 | ready | No |
| heavy-3 | 192.168.69.82 | ready | No |
| light-1 | 192.168.69.90 | ready | No |
| light-2 | 192.168.69.91 | ready | No |
| light-3 | 192.168.69.92 | ready | No |
| light-4 | 192.168.69.93 | ready | No |
| light-5 | 192.168.69.94 | ready | No |

**结论**: 所有 8 个节点状态正常，无 drain 或 down 节点。

### 磁盘空间 (heavy-1)

- `/opt` 分区: 95G 总量, 15G 已用 (16%), 76G 可用
- `/opt/aether-volumes/`: 12G 已用
- 11 个已退出的 Docker 容器待清理

---

## 二、Job 部署状态总览

### 全部 Job 清单 (17个)

| Job | 状态 | 健康度 | 说明 |
|-----|------|--------|------|
| psych-ai-supervision-dev | **CRITICAL** | celery 0/1 运行 | celery worker 完全宕机 |
| psych-ai-supervision-dev | **CRITICAL** | celery-beat 异常 | Redis 连接失败, 82次重启 |
| psych-ai-supervision-dev | **CRITICAL** | API 健康检查失败 | 数据库不存在导致启动失败 |
| nexus-api-dev | WARNING | worker unhealthy | arq worker 超时错误 |
| openstock-dev | WARNING | unhealthy | Nodemailer 连接失败 |
| kairos-prod | OK | 1/1 运行 | 部署时有2个 unhealthy, 当前已恢复 |
| kairos-dev | OK | 1/1 运行 | 历史3个失败, 当前正常 |
| dev-db | OK | 2/2 运行 | postgres + redis 正常 |
| nexus-db-dev | OK | 1/1 运行 | 正常 |
| nexus-redis-dev | OK | 1/1 运行 | 正常 |
| traefik | OK | 1/1 运行 | 正常 |
| silknode-gateway | OK | 1/1 运行 | 正常 |
| silknode-web | OK | 1/1 运行 | 正常 |
| mailpit | OK | 1/1 运行 | 正常 |
| todo-web-backend-dev | OK | 1/1 运行 | 正常 |
| todo-web-backend-prod | OK | 1/1 运行 | 正常 |
| todo-web-frontend-dev | OK | 1/1 运行 | 正常 |
| todo-web-frontend-prod | OK | 1/1 运行 | 正常 |
| wecom-relay | OK | 1/1 运行 | 正常 |

### Consul 健康检查

- **Critical**: 1 个 — `psych-ai-dev-api` (http://192.168.69.80:31198/health 连接被拒绝)
- **Warning**: 0 个
- **Passing**: 23 个服务全部通过（不含 psych-ai-dev-api）

---

## 三、严重问题详细分析

### 问题 1: psych-ai-supervision-dev — API 服务启动失败

**严重程度**: CRITICAL
**影响范围**: API 无法提供服务, Consul 健康检查 critical
**当前状态**: 容器在运行但应用已崩溃 (状态: running/unhealthy)

**根因分析**:
```
asyncpg.exceptions.InvalidCatalogNameError: database "psych_supervision" does not exist
ERROR: Application startup failed. Exiting.
```

API 配置连接 `postgresql://postgres:dev123456@192.168.69.80:5432/psych_supervision`，但 dev-db (heavy-1) 上的 PostgreSQL 实例中不存在 `psych_supervision` 数据库。当前数据库列表仅包含: `postgres`, `silknode_dev`, `template0`, `template1`。

uvicorn 进程启动时无法连接数据库，直接退出，导致:
- Consul 健康检查持续返回 connection refused
- 最近一次部署标记为 failed: "Failed due to progress deadline"
- API allocation 标记为 "Alloc Unhealthy"

**修复建议**:
```bash
# 1. 在 dev-db 的 PostgreSQL 中创建缺失的数据库
ssh root@192.168.69.80 'docker exec -it f8af7d6c3ad6 psql -U postgres -c "CREATE DATABASE psych_supervision;"'

# 2. 如果需要特定用户权限
ssh root@192.168.69.80 'docker exec -it f8af7d6c3ad6 psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE psych_supervision TO postgres;"'

# 3. 重新部署 psych-ai-supervision-dev 以触发数据库迁移
# 或者重启当前 allocation
curl -X PUT http://192.168.69.70:4646/v1/job/psych-ai-supervision-dev -d @psych-ai-supervision-dev.hcl
```

---

### 问题 2: psych-ai-supervision-dev — Celery Worker 完全宕机

**严重程度**: CRITICAL
**影响范围**: 所有异步任务无法执行
**当前状态**: allocation failed, desired=run, 39次重启后 Docker Driver Failure

**根因分析**:
Worker 最初因应用错误 (exit code 1) 反复崩溃重启 39 次。最终在尝试清理旧容器时遭遇 Docker 底层文件系统错误:

```
Driver Failure: failed to create container: Failed to purge container e05c48f9e8dc...:
Error response from daemon: cannot remove container: unable to remove filesystem:
unlinkat /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9e8dc...: directory not empty
```

此错误被标记为 "unrecoverable"，Nomad 不再尝试重启。

**双重根因**:
1. **应用层**: Celery worker 无法启动，很可能与 Redis 不可达 (见问题3) 和数据库不存在 (见问题1) 有关
2. **基础设施层**: Docker 文件系统清理失败，残留容器文件锁定了路径

**修复建议**:
```bash
# 1. 清理 heavy-1 上的残留容器文件
ssh root@192.168.69.80 'docker system prune -f'

# 2. 如果上述不够，手动清理残留目录
ssh root@192.168.69.80 'rm -rf /opt/aether-volumes/runners/heavy-1/docker/containers/e05c48f9e8dcdc3553d8a9524f42fb70a75c1d2b40a6b4673c506c46c48feee2'

# 3. 先解决 Redis 和数据库问题 (问题1和3)，然后重新部署
# 重新提交 job 以创建新的 celery allocation
nomad job run psych-ai-supervision-dev.hcl
```

---

### 问题 3: psych-ai-supervision-dev — Celery Beat Redis 连接失败

**严重程度**: CRITICAL
**影响范围**: 定时任务调度完全瘫痪
**当前状态**: 容器 running 但持续报错, 82次重启

**根因分析**:
Celery Beat 配置连接 `redis://192.168.69.82:6379/1` (heavy-3)，但 heavy-3 上没有运行任何 Redis 实例。

heavy-3 当前仅运行:
- wecom-relay 容器
- buildkit 构建器
- forgejo runner

错误日志持续输出:
```
beat: Connection error: Error 111 connecting to 192.168.69.82:6379. Connection refused.
Trying again in 32.0 seconds...
```

所有三个 psych-ai 组件 (api, celery, celery-beat) 都配置了相同的 Redis 地址 `192.168.69.82:6379`，这个 Redis 实例不存在。

**修复建议**:
```bash
# 方案 A: 在 heavy-3 上部署一个 Redis 实例给 psych-ai 使用
# 创建一个新的 Nomad job 或添加到现有 dev-db job

# 方案 B: 修改 psych-ai-supervision-dev 的配置，使用已存在的 Redis
# dev-db 的 Redis 运行在 192.168.69.80:6379
# 更新 CELERY_BROKER_URL 和 REDIS_URL 环境变量:
#   CELERY_BROKER_URL=redis://192.168.69.80:6379/1
#   REDIS_URL=redis://192.168.69.80:6379/0
# 注意: 需确认不与 nexus-redis-dev 冲突（nexus 用的是 192.168.69.80:6379）
```

---

### 问题 4: nexus-api-dev — Worker 超时错误

**严重程度**: WARNING
**影响范围**: arq 后台任务执行超时
**当前状态**: 容器 running 但标记 unhealthy

**根因分析**:
nexus-api-dev 的 arq worker 出现 asyncio 超时:
```
asyncio.exceptions.CancelledError
TimeoutError
12:47:16: 40807.04s -> cron:flush_telemetry_batch() delayed=40806.23s
```

`flush_telemetry_batch` 任务延迟了约 11 小时 (40807秒)，说明 worker 长时间未能正常处理任务队列。

API 服务本身 (healthy) 和数据库连接正常，问题仅出现在后台 worker。

**修复建议**:
```bash
# 1. 重启 nexus-api-dev 的 worker 容器
ssh root@192.168.69.80 'docker restart 276129f53ef6'

# 2. 如果持续出现，检查 telemetry batch 任务的逻辑
# 可能需要增加超时时间或优化批处理大小

# 3. 考虑将 worker 分离为独立的 task group 以便独立重启
```

---

### 问题 5: openstock-dev — Nodemailer 连接失败

**严重程度**: LOW
**影响范围**: 邮件发送功能不可用
**当前状态**: 容器 running, 应用可用但邮件功能异常

**根因分析**:
```
NODEMAILER_EMAIL or NODEMAILER_PASSWORD is not set. Email functionality will not work.
Nodemailer transporter verification failed: [Error: Client network socket disconnected
before secure TLS connection was established] { code: 'ESOCKET', host: '142.251.169.108', port: 465 }
```

两个问题叠加:
1. 环境变量 `NODEMAILER_EMAIL` 和 `NODEMAILER_PASSWORD` 未设置
2. 即使尝试连接 Gmail SMTP (142.251.169.108:465)，TLS 连接也失败（可能是网络策略限制）

**修复建议**:
```bash
# 1. 在 Nomad job 定义中添加邮件环境变量
# 或使用 Vault 管理 secrets

# 2. 如果已部署 mailpit，考虑将 openstock 的 SMTP 指向 mailpit
# SMTP_HOST=192.168.69.80:1025 (mailpit 的 SMTP 端口)
```

---

## 四、kairos-prod 状态确认

用户特别关注的 kairos-prod:

- **当前状态**: 1/1 running, healthy
- **部署历史**: 最近一次部署 (c1ea28cb) 标记为 successful，但过程中有 2 个 allocation 标记为 unhealthy（尝试了 3 次 placement 才成功 1 个）
- **容器状态**: heavy-2 上运行两个 kairos 容器，均为 healthy
  - `kairos-a8001703` (kairos-dev): Up 14 hours, healthy
  - `kairos-f501bca3` (kairos-prod): Up 3 days, healthy
- **结论**: kairos-prod 当前运行正常。部署时的 unhealthy allocation 已经过去，可能是由镜像拉取超时或启动慢导致。

---

## 五、错误模式总结

| 错误模式 | 涉及 Job | 频率 | 风险 |
|----------|----------|------|------|
| 数据库不存在 | psych-ai-supervision-dev | 持续 | CRITICAL |
| Redis 实例缺失 | psych-ai-supervision-dev | 持续 (每32秒) | CRITICAL |
| Docker 文件系统残留 | psych-ai-supervision-dev | 不可恢复 | CRITICAL |
| Worker 任务超时 | nexus-api-dev | 间歇 | WARNING |
| 邮件服务配置缺失 | openstock-dev | 持续 | LOW |
| 部署时多次重试 | kairos-prod | 历史 | INFO |

---

## 六、优先修复顺序

### P0 — 立即修复 (psych-ai-supervision-dev 完全不可用)

1. **创建 PostgreSQL 数据库** `psych_supervision`
   ```bash
   ssh root@192.168.69.80 'docker exec f8af7d6c3ad6 psql -U postgres -c "CREATE DATABASE psych_supervision;"'
   ```

2. **部署 Redis 或修正 Redis 地址**
   - 将 `CELERY_BROKER_URL` 和 `REDIS_URL` 从 `192.168.69.82:6379` 改为一个实际存在的 Redis 实例
   - 最简方案: 使用 dev-db 的 Redis `192.168.69.80:6379`（使用不同 db 编号避免冲突）

3. **清理 Docker 残留并重新部署**
   ```bash
   ssh root@192.168.69.80 'docker system prune -f'
   # 然后重新提交 psych-ai-supervision-dev job
   ```

### P1 — 尽快修复

4. **重启 nexus-api-dev worker** 解决任务积压
   ```bash
   ssh root@192.168.69.80 'docker restart 276129f53ef6'
   ```

### P2 — 计划修复

5. **配置 openstock-dev 邮件服务** — 设置环境变量或指向 mailpit

### P3 — 运维优化

6. **清理 heavy-1 上的 11 个已退出容器** 释放空间
   ```bash
   ssh root@192.168.69.80 'docker container prune -f'
   ```

7. **审查 kairos-prod 部署配置** — 增加 `healthy_deadline` 或优化镜像大小以减少部署时的 unhealthy 重试

---

## 七、当前未失败的 Allocation 中的历史失败计数

| Job | Task Group | 历史失败数 | 说明 |
|-----|-----------|-----------|------|
| dev-db | postgres | 4 | 历史失败, 当前正常 |
| traefik | traefik | 4 | 历史失败, 当前正常 |
| kairos-dev | kairos | 3 | 历史失败, 当前正常 |
| kairos-prod | kairos | 2 | 历史失败, 当前正常 |
| psych-ai-supervision-dev | celery | 2 | **当前失败** |
| nexus-redis-dev | redis | 1 | 历史失败, 当前正常 |
| openstock-dev | web | 1 | 历史失败, 当前正常 |
| mailpit | mailpit | 1 | 历史失败, 当前正常 |
| todo-web-frontend-dev | frontend | 1 | 历史失败, 当前正常 |
| todo-web-frontend-prod | frontend | 1 | 历史失败, 当前正常 |

---

**报告生成时间**: 2026-03-18T12:47:00Z
**巡检工具**: Nomad HTTP API + Consul HTTP API + SSH Docker 诊断
