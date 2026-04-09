# CI 状态诊断 (镜像未找到时)

当 Mode A 镜像不存在时，**必须**查询 CI 状态后再给出结论：

```bash
# 1. 聚合状态
CI_STATUS=$(forgejo GET "/repos/${OWNER_REPO}/commits/${TARGET_TAG}/status" 2>/dev/null)
AGG_STATE=$(echo "$CI_STATUS" | jq -r '.state // "unknown"')

# 2. 如果聚合状态为 failure，进一步区分 cancelled vs 真正失败
if [ "$AGG_STATE" = "failure" ]; then
  TASKS=$(forgejo GET "/repos/${OWNER_REPO}/actions/tasks?limit=10&page=1" 2>/dev/null)
  # 筛选匹配 SHA 的任务
  MATCH=$(echo "$TASKS" | jq --arg sha "${TARGET_TAG}" '
    [.workflow_runs // [] | .[] | select(.head_sha == $sha)]')
  CANCELLED=$(echo "$MATCH" | jq '[.[] | select(.status == "cancelled")] | length')
  FAILED=$(echo "$MATCH" | jq '[.[] | select(.status == "failure")] | length')
fi
```

**根据诊断结果报告**:

| CI 状态 | 含义 | 报告与建议 |
|---------|------|-----------|
| `pending` | CI 仍在排队或运行中 | "CI 尚未完成，镜像尚未构建。等待 CI 完成后重试，或使用 `/aether:aether-ci` 查看进度" |
| `failure` + 全部 cancelled | 被新 push 取代 (正常行为) | "此 commit 的 CI 已被取消（可能被更新的 push 取代）。这是正常行为，请对最新 commit 运行 deploy-watch" |
| `failure` + 有真正 failure | 构建/测试真正失败 | "CI 构建失败，镜像未推送。使用 `/aether:aether-ci` 诊断失败原因" |
| `success` | CI 通过但镜像不在 registry | "CI 通过但镜像未在 registry 中找到。检查 CI workflow 是否包含 docker push 步骤" |
| `unknown` / API 失败 | 无法获取 CI 状态 | "无法查询 CI 状态，请手动检查 Forgejo Web UI" |

**关键**: `cancelled` 状态在 Forgejo commit status API 中表现为 `status: "failure", description: "Has been cancelled"`，
必须通过 Actions Tasks API 的 `status` 字段区分。**不要**将 cancelled 误判为构建失败。
