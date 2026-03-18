# Aether Rollback Report: web-frontend

> **Skill**: aether-rollback v0.3.0
> **Date**: 2026-03-18
> **Nomad Addr**: http://192.168.69.70:4646

---

## Step 1: 获取版本历史

**Command executed**:
```bash
curl -s "http://192.168.69.70:4646/v1/job/web-frontend/versions" | \
  jq '[.Versions[] | {version: .Version, stable: .Stable, submitTime: .SubmitTime}]'
```

**API Result**: Job `web-frontend` not found on the cluster (API returned `job versions not found`).

The Nomad API at `http://192.168.69.70:4646` was reachable but the job `web-frontend` does not exist in the cluster. Additional attempts to query `/v1/job/web-frontend` and `/v1/job/web-frontend/allocations` confirmed the job is not registered.

---

## Step 2: 版本列表 (Simulated)

Since the API call did not return version data, the following is what WOULD be displayed if the job existed with the described scenario (v3.2.0 deployed, causing white screen):

```
回滚: web-frontend
================
版本历史:
  v2 (当前) - image: web-frontend:v3.2.0 - 约 30min ago - 2/2 unhealthy ⚠️
  v1         - image: web-frontend:v3.1.0 - 约 2d ago    - 已替换 (上次稳定)
  v0         - image: web-frontend:v3.0.0 - 约 7d ago    - 已替换

推荐回滚到: v1 (最近的稳定版本, image: web-frontend:v3.1.0)

选择回滚目标版本？ [v1 (推荐) / v0 / 输入版本号]
```

**WOULD ask user**: 使用 `AskUserQuestion` 让用户确认回滚目标版本。根据场景描述 ("回滚到上一个稳定版本")，用户大概率选择 v1 (web-frontend:v3.1.0)。

---

## Step 3: 执行回滚 (Simulated)

**WOULD execute**:
```bash
# Nomad revert 到 version 1
curl -s -X POST "http://192.168.69.70:4646/v1/job/web-frontend/revert" \
  -d '{"JobID": "web-frontend", "JobVersion": 1}'
```

Expected response: `{"EvalID": "abc123-...", "EvalCreateIndex": ..., "JobModifyIndex": ...}`

---

## Step 4: 等待回滚完成 (Simulated)

**WOULD execute**:
```bash
# 轮询等待新 allocation 变为 running
for i in $(seq 1 20); do
  RUNNING=$(curl -s "http://192.168.69.70:4646/v1/job/web-frontend/allocations" | \
    jq '[.[] | select(.ClientStatus == "running" and .JobVersion == 1)] | length')
  if [ "$RUNNING" -ge 2 ]; then
    echo "All instances running"
    break
  fi
  echo "Waiting... ($RUNNING/2 running)"
  sleep 3
done
```

Expected: 在 30-60 秒内，2 个 allocation 进入 `running` 状态。

---

## Step 5: 验证健康状态 (Simulated)

**WOULD execute**:
```bash
# Consul 健康检查
curl -s "http://192.168.69.70:8500/v1/health/service/web-frontend?passing" | jq 'length'
```

Expected: 返回 `2`，表示 2 个健康实例。

---

## Step 6: 结果

```
回滚结果
========
状态: ❌ 无法执行 (Job 未找到)
服务: web-frontend
Nomad: http://192.168.69.70:4646
原因: Nomad API 返回 "job not found"，该 Job 未在集群中注册。

可能原因:
  1. Job 名称不正确 (区分大小写)
  2. Job 在不同的 namespace 下 (尝试添加 ?namespace=xxx)
  3. Job 已被删除
  4. Nomad 地址指向错误的集群

建议操作:
  1. 确认 Job 名称: curl -s http://192.168.69.70:4646/v1/jobs | jq '.[].Name'
  2. 检查所有 namespace: curl -s http://192.168.69.70:4646/v1/jobs?namespace=* | jq '.[].Name'
  3. 确认 Nomad 集群地址是否正确
  4. 使用 /aether:status 查看集群中所有 Job
```

---

## 如果 Job 存在，预期成功输出

```
回滚成功
========
服务: web-frontend
回滚: v2 (v3.2.0) -> v1 (v3.1.0)
当前版本: v1 (web-frontend:v3.1.0)
实例: 2/2 running
健康检查: all passing

回滚完成，服务已恢复。
白屏问题已通过回滚到 v3.1.0 解决。
```

---

## 后续建议

1. **确认服务恢复**: 请用户在浏览器中验证页面不再白屏
2. **调查 v3.2.0 问题**: 检查 v3.2.0 的变更，找出白屏根因
3. **修复后重新部署**: 修复后通过正常 CI/CD 流程重新部署
4. **回滚失败时**: 使用 `/aether:status web-frontend` 查看详细状态，或使用 `deploy-doctor` agent 诊断

---

## 执行摘要

| 项目 | 值 |
|------|-----|
| Skill | aether-rollback |
| 目标服务 | web-frontend |
| Nomad 地址 | http://192.168.69.70:4646 |
| API 可达 | Yes |
| Job 存在 | No |
| 版本历史 | N/A (job not found) |
| 回滚执行 | Not executed |
| 回滚结果 | Blocked - job not found |
| 用户确认步骤 | Planned (AskUserQuestion) but not reached |
