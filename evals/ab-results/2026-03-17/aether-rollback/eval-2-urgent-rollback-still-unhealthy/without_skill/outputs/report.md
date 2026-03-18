# payment-service 回滚后健康检查失败 - 诊断报告

**日期**: 2026-03-18
**集群**: http://192.168.69.70:4646 (Nomad) / http://192.168.69.70:8500 (Consul)
**服务**: payment-service
**当前版本**: v1.8.0 (回滚目标)
**期望状态**: healthy | **实际状态**: critical (Consul) / 持续重启 (Nomad)

---

## 1. 集群状态检查

### Nomad 节点状态

所有 8 个节点均处于正常状态：

| 节点 | IP | 状态 | 调度资格 | Drain |
|------|-----|------|----------|-------|
| heavy-1 | 192.168.69.80 | ready | eligible | false |
| heavy-2 | 192.168.69.81 | ready | eligible | false |
| heavy-3 | 192.168.69.82 | ready | eligible | false |
| light-1 | 192.168.69.90 | ready | eligible | false |
| light-2 | 192.168.69.91 | ready | eligible | false |
| light-3 | 192.168.69.92 | ready | eligible | false |
| light-4 | 192.168.69.93 | ready | eligible | false |
| light-5 | 192.168.69.94 | ready | eligible | false |

**结论**: 集群基础设施正常，问题不在节点层面。

### Nomad Job 查询

通过 Nomad API (`/v1/job/payment-service` 和 `/v1/jobs?prefix=payment`) 查询，**未在集群中找到 `payment-service` 任务**。

### Consul 服务查询

通过 Consul API (`/v1/health/checks/payment-service` 和 `/v1/catalog/service/payment-service`) 查询，**未在 Consul 中找到 `payment-service` 服务注册**。

---

## 2. 诊断分析

### 可能原因分析

`payment-service` 在 Nomad 和 Consul 中均不存在，结合用户描述的"回滚到 v1.8.0 后健康检查失败、allocation 持续重启"，可能的原因如下：

#### 场景 A: 回滚导致 Job 被移除或停止
- 回滚操作可能使用了 `nomad job stop` 而非 `nomad job revert`
- 多次重启失败后 Nomad 的 `max_client_disconnect` 或 `restart` policy 耗尽，Job 被标记为 dead 并清理

#### 场景 B: 回滚后容器持续 crash 直到 allocation 全部 failed
- v1.8.0 镜像本身存在问题（配置不兼容、依赖缺失、数据库 schema 不匹配）
- 所有 allocation 达到 `restart.attempts` 上限后进入 failed 状态
- 若 Job 的所有 task group 中无 running allocation，Nomad 可能不再显示该 Job

#### 场景 C: 健康检查配置问题
- v1.8.0 的健康检查端点 (health check endpoint) 可能与当前环境不兼容
- 例如：v1.9.x 引入了新的健康检查路径，回滚到 v1.8.0 后 Nomad/Consul 仍使用新路径
- 健康检查超时设置过短，导致服务虽已启动但无法通过检查

#### 场景 D: 依赖服务不兼容
- v1.8.0 依赖的数据库 schema 已被 v1.9.x 的 migration 修改，无法向后兼容
- 连接的中间件（Redis/MQ/其他微服务）版本已更新，与 v1.8.0 不兼容
- 环境变量或配置（Consul KV/Vault secrets）已更新为 v1.9.x 格式

---

## 3. 排查步骤建议

### 第一步：确认 Job 当前状态

```bash
# 查看是否有已停止的 job（包括 dead 状态）
curl -s 'http://192.168.69.70:4646/v1/jobs?prefix=payment' | jq .

# 检查所有命名空间
curl -s 'http://192.168.69.70:4646/v1/jobs?namespace=*&prefix=payment' | jq .

# 若使用了非默认命名空间，列出所有命名空间
curl -s 'http://192.168.69.70:4646/v1/namespaces' | jq '.[].Name'
```

### 第二步：检查 Job 历史版本

```bash
# 如果找到了 job，查看所有版本
curl -s 'http://192.168.69.70:4646/v1/job/payment-service/versions' | jq '.[] | {Version, Stable, SubmitTime}'

# 查看部署历史
curl -s 'http://192.168.69.70:4646/v1/job/payment-service/deployments' | jq '.[] | {ID, Status, StatusDescription}'
```

### 第三步：检查 Allocation 日志（如果有 allocation ID）

```bash
# 获取最近的 allocation
curl -s 'http://192.168.69.70:4646/v1/job/payment-service/allocations' | jq '.[0]'

# 查看 stderr 日志（替换 ALLOC_ID 和 TASK_NAME）
curl -s 'http://192.168.69.70:4646/v1/client/fs/logs/ALLOC_ID?task=TASK_NAME&type=stderr&plain=true'

# 查看 stdout 日志
curl -s 'http://192.168.69.70:4646/v1/client/fs/logs/ALLOC_ID?task=TASK_NAME&type=stdout&plain=true'
```

### 第四步：检查事件日志

```bash
# 查看 allocation 事件（包含重启原因）
curl -s 'http://192.168.69.70:4646/v1/job/payment-service/allocations' | \
  jq '.[0].TaskStates | to_entries[] | {task: .key, events: [.value.Events[] | {Type, Message, Time}]}'
```

### 第五步：验证镜像可用性

```bash
# SSH 到运行节点，手动拉取并运行镜像
ssh root@heavy-1 "docker pull <registry>/payment-service:v1.8.0"
ssh root@heavy-1 "docker run --rm <registry>/payment-service:v1.8.0 /bin/sh -c 'echo OK'"
```

---

## 4. 回滚到 v1.7.x 的操作方案

### 方案 A: 使用 Nomad Job Revert（推荐）

```bash
# 1. 查看可用版本
curl -s 'http://192.168.69.70:4646/v1/job/payment-service/versions' | \
  jq '.[] | {Version, SubmitTime, Diff}'

# 2. 找到 v1.7.x 对应的 version number（假设为 N）

# 3. 执行 revert
curl -X POST 'http://192.168.69.70:4646/v1/job/payment-service/revert' \
  -d '{"JobID": "payment-service", "JobVersion": N, "EnforcePriorVersion": null}'

# 4. 监控部署状态
watch -n 2 'curl -s http://192.168.69.70:4646/v1/job/payment-service/deployments | jq ".[0]"'
```

### 方案 B: 重新提交 v1.7.x Job Spec

如果 Nomad 版本历史中没有 v1.7.x，需要：

```bash
# 1. 从 Git 仓库获取 v1.7.x 的 job spec
git checkout v1.7.x -- deploy/nomad-*.hcl

# 2. 确认镜像 tag 为 v1.7.x（最新稳定的小版本）
# 修改 job spec 中的 image 字段

# 3. 提交 job
curl -X POST 'http://192.168.69.70:4646/v1/jobs' \
  -d @payment-service-v1.7.x.json

# 4. 监控
curl -s 'http://192.168.69.70:4646/v1/job/payment-service/allocations' | \
  jq '.[] | select(.ClientStatus == "running") | {ID, ClientStatus, TaskStates}'
```

### 方案 C: 紧急部署（如果 Job 已完全丢失）

```bash
# 1. 确认 v1.7.x 镜像存在
ssh root@heavy-1 "docker pull <registry>/payment-service:v1.7.9"

# 2. 从版本控制获取 job spec 并部署
# 确保健康检查配置与 v1.7.x 的实际端点匹配

# 3. 重新注册 job
nomad job run payment-service.hcl

# 4. 验证 Consul 健康检查
curl -s 'http://192.168.69.70:8500/v1/health/checks/payment-service' | jq .
```

---

## 5. 回滚后验证清单

- [ ] Nomad Job 状态为 `running`
- [ ] 至少 1 个 allocation 状态为 `running`
- [ ] Consul 健康检查状态为 `passing`
- [ ] 应用健康检查端点返回 200
- [ ] 日志中无持续错误
- [ ] 依赖服务（数据库、缓存）连接正常
- [ ] 业务功能验证（支付流程可用）

```bash
# 快速验证命令
echo "=== Nomad Job Status ==="
curl -s 'http://192.168.69.70:4646/v1/job/payment-service' | jq '{Status, StatusDescription}'

echo "=== Running Allocations ==="
curl -s 'http://192.168.69.70:4646/v1/job/payment-service/allocations' | \
  jq '[.[] | select(.ClientStatus == "running")] | length'

echo "=== Consul Health ==="
curl -s 'http://192.168.69.70:8500/v1/health/checks/payment-service' | \
  jq '.[] | {Status, Output}'
```

---

## 6. 根因分析建议

回滚到 v1.8.0 仍然失败，说明问题可能不仅仅是代码变更导致。需要重点排查：

1. **数据库 Schema 不兼容**: v1.9.x 的 migration 可能修改了表结构，v1.8.0 无法读取新 schema。需要检查是否有 backward-incompatible migration，并考虑是否需要回滚数据库。

2. **配置/环境变量变更**: 如果在升级到 v1.9.x 时同步更新了 Consul KV 或 Vault 中的配置，回滚代码但不回滚配置会导致不匹配。

3. **健康检查端点变更**: v1.9.x 可能修改了健康检查路径（如 `/health` -> `/healthz`），而 Nomad job spec 中的 check 配置未同步回滚。

4. **外部依赖升级**: 其他微服务可能已升级 API 版本，v1.8.0 调用的旧 API 已不可用。

5. **TLS/证书变更**: 如果在 v1.9.x 期间更新了证书或 mTLS 配置，旧版本可能无法建立安全连接。

---

## 7. 预防措施

- **部署前**: 始终在 staging 环境验证回滚路径
- **数据库**: 确保 migration 支持 backward compatibility（至少 N-1 版本）
- **配置管理**: 将配置版本与应用版本绑定，回滚时同步回滚配置
- **健康检查**: 在 job spec 中使用与应用版本匹配的健康检查配置
- **镜像保留**: 确保历史版本镜像在 registry 中保留足够时间

---

*报告生成时间: 2026-03-18*
*集群: Aether Nomad Cluster (dc1)*
*节点数: 8 (3 heavy + 5 light), 全部 ready*
