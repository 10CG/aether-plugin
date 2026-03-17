# Aether 状态查询报告: my-api

> **查询时间**: 2026-03-17
> **Nomad 地址**: http://192.168.69.80:4646
> **Consul 地址**: http://192.168.69.80:8500

---

## 连通性检查

```
Nomad API:  OK (http://192.168.69.80:4646)
Consul API: OK (http://192.168.69.80:8500)
```

---

## 查询结果: my-api

**Job `my-api` 在集群中不存在。**

Nomad API 返回 404 — 集群上没有名为 `my-api` 的 Job。这是用户反馈 502 的直接原因：服务未部署或已被删除，反向代理 (Traefik) 无法找到上游，因此返回 502 Bad Gateway。

---

## 集群概览

```
Aether 集群状态
================
Nomad 节点: 3 heavy (ready) + 5 light (ready) = 8 total
运行中 Jobs: 15 (all service type)
失败 Allocs: 1 (psych-ai-supervision-dev @ heavy-1)
Consul 临界: 2 (psych-ai-dev-api @ heavy-1, kairos-dev @ heavy-2)
```

### 节点状态

| 节点 | 状态 | 类别 |
|------|------|------|
| heavy-1 | ready | heavy_workload |
| heavy-2 | ready | heavy_workload |
| heavy-3 | ready | heavy_workload |
| light-1 | ready | light_exec |
| light-2 | ready | light_exec |
| light-3 | ready | light_exec |
| light-4 | ready | light_exec |
| light-5 | ready | light_exec |

### 所有 Jobs

| Job | 状态 | Running | Failed (历史) |
|-----|------|---------|---------------|
| dev-db | running | 2 | 4 |
| kairos-dev | running | 1 | 3 |
| kairos-prod | running | 1 | 2 |
| nexus-api-dev | running | 1 | 1 |
| nexus-db-dev | running | 1 | 0 |
| nexus-redis-dev | running | 1 | 1 |
| openstock-dev | running | 1 | 1 |
| psych-ai-supervision-dev | running | 3 | 5 |
| silknode-gateway | running | 1 | 0 |
| todo-web-backend-dev | running | 1 | 0 |
| todo-web-backend-prod | running | 1 | 0 |
| todo-web-frontend-dev | running | 1 | 1 |
| todo-web-frontend-prod | running | 1 | 1 |
| traefik | running | 1 | 4 |
| wecom-relay | running | 1 | 0 |

---

## 诊断结论

### 502 根本原因

`my-api` 这个 Job **不存在于 Nomad 集群**。反向代理 (Traefik) 无法将请求路由到不存在的后端服务，因此返回 **502 Bad Gateway**。

### Allocation 健康

- 无法检查 — Job 不存在，没有任何 allocation。

### 最近重启

- 无法检查 — Job 不存在，没有 allocation 历史。

### 日志

- 无法检查 — Job 不存在，没有可查询的日志。

---

## 修复建议

1. **确认 Job 名称是否正确**
   - 集群上没有 `my-api`，请确认实际的 Job 名称
   - 可能的相似名称: `nexus-api-dev`（集群上唯一包含 "api" 的 Job）

2. **如果服务之前存在但被删除**
   ```bash
   # 检查是否有 stopped 的 job（Nomad 默认不显示已停止的 job）
   curl -s "http://192.168.69.80:4646/v1/jobs?prefix=my" | jq '.[] | {name: .Name, status: .Status}'
   ```

3. **如果需要部署该服务**
   ```bash
   # 使用 aether deploy 部署
   /aether:deploy my-api
   ```

4. **检查 Traefik 路由配置**
   - 确认 Traefik 的路由规则是否指向了正确的 Nomad 服务名
   - 如果域名仍指向 `my-api`，但该 Job 已更名或删除，需要更新路由

5. **临时缓解**
   - 更新 DNS 或 Traefik 路由，移除对 `my-api` 的引用，避免用户持续看到 502

---

## 其他需要关注的问题

集群整体运行正常，但以下服务存在问题:

1. **psych-ai-supervision-dev**: 1 个失败的 allocation (heavy-1)，Consul 健康检查 critical
2. **kairos-dev**: Consul 健康检查 critical (heavy-2)

---

*报告由 aether-status skill (v1.1.0) 生成*
