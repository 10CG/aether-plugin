# my-api 服务诊断报告

**时间**: 2026-03-17
**Nomad 地址**: http://192.168.69.80:4646
**Consul 地址**: http://192.168.69.70:8500

---

## 诊断结论

**my-api 服务在 Nomad 集群中不存在。** 这是用户收到 502 错误的根本原因 -- 反向代理 (Traefik) 无法将请求转发到后端服务，因为该服务根本没有在集群上运行。

---

## 详细排查过程

### 1. Nomad Job 查询

通过 Nomad API (`/v1/job/my-api`) 查询，返回结果为 `job not found`。

通过前缀搜索 (`/v1/jobs?prefix=my`) 查询，返回空数组 `[]`，确认没有任何以 `my` 开头的 Job。

集群仅有 `default` 命名空间，无需跨命名空间搜索。

### 2. Allocation 状态

由于 Job 不存在，`/v1/job/my-api/allocations` 返回空数组，无 allocation 可检查。

### 3. 部署历史

`/v1/job/my-api/deployments` 返回空数组，无部署记录。

### 4. Consul 服务注册

在 Consul 服务目录中搜索包含 `api` 或 `my` 的服务，未找到 `my-api`。

找到的 API 相关服务：
- `nexus-api-dev`
- `psych-ai-dev-api`

### 5. 集群健康状况

集群本身运行正常，所有 8 个节点状态为 `ready` 且调度状态为 `eligible`：

| 节点 | IP | 状态 | 调度 |
|------|----|------|------|
| heavy-1 | 192.168.69.80 | ready | eligible |
| heavy-2 | 192.168.69.81 | ready | eligible |
| heavy-3 | 192.168.69.82 | ready | eligible |
| light-1 | 192.168.69.90 | ready | eligible |
| light-2 | 192.168.69.91 | ready | eligible |
| light-3 | 192.168.69.92 | ready | eligible |
| light-4 | 192.168.69.93 | ready | eligible |
| light-5 | 192.168.69.94 | ready | eligible |

### 6. 集群现有 Job 列表

当前运行的 15 个 Job 中没有 `my-api`：

| Job | 状态 |
|-----|------|
| dev-db | running |
| kairos-dev | running |
| kairos-prod | running |
| nexus-api-dev | running |
| nexus-db-dev | running |
| nexus-redis-dev | running |
| openstock-dev | running |
| psych-ai-supervision-dev | running |
| silknode-gateway | running |
| todo-web-backend-dev | running |
| todo-web-backend-prod | running |
| todo-web-frontend-dev | running |
| todo-web-frontend-prod | running |
| traefik | running |
| wecom-relay | running |

---

## 502 错误原因分析

用户反馈的 502 Bad Gateway 错误，原因是：

1. **服务未部署**: `my-api` 这个 Job 从未在 Nomad 集群中注册过（或已被删除/停止）
2. **反向代理无后端**: Traefik 作为集群的反向代理正在运行，但找不到 `my-api` 的后端实例，因此返回 502

---

## 建议操作

1. **确认服务名称**: 检查服务是否以其他名称部署（如 `nexus-api-dev`、`psych-ai-dev-api` 等）
2. **检查部署配置**: 确认 `my-api` 的 Nomad Job 规范文件 (HCL) 是否存在，路径通常为 `deploy/nomad-dev.hcl` 或 `deploy/nomad-prod.hcl`
3. **重新部署**: 如果 Job 文件存在，使用以下命令提交：
   ```bash
   nomad job run deploy/nomad-dev.hcl
   ```
   或通过 CI/CD (Forgejo Actions) 触发部署
4. **检查 Traefik 路由**: 查看 Traefik 的路由配置，确认 `my-api` 对应的域名/路径指向哪个后端服务
5. **检查 CI/CD 历史**: 查看 Forgejo 上的 Actions 记录，确认最近是否有部署失败的记录

---

## 总结

| 检查项 | 结果 |
|--------|------|
| Job 是否存在 | 不存在 |
| Allocation 健康 | N/A (无 allocation) |
| 最近重启 | N/A (无 allocation) |
| 日志错误 | N/A (无 allocation) |
| 集群节点健康 | 全部正常 (8/8 ready) |
| 502 根因 | 服务未部署到集群 |
