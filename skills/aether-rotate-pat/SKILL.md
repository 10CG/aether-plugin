---
name: aether-rotate-pat
description: |
  Forgejo PAT 自动化轮换 (Tier 1 / nomad-variables backend, #45 Phase 2)。
  按 5 步流程 (DELETE→PUT_NEW→PUT_OLD→restart→verify) 安全轮换 cluster-wide
  registry pull credentials；进度持久化到 journal，process kill 后可 resume；
  24h grace 窗口后清理 *_OLD 兜底数据。

  使用场景："轮换 PAT"、"rotate registry token"、"PAT 到期了"、
  "registry-auth rotate"、"Forgejo token 该换了"、"凭据轮换"
argument-hint: "<pat-id>"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, AskUserQuestion, Read
dependencies:
  cli:
    required: true
    min_version: "1.12.0"
---

# Aether PAT 轮换 (aether-rotate-pat)

> **版本**: 0.1.0 | **优先级**: P2 (security-sensitive ops, low frequency)

按需的安全凭据轮换工作流。本 Skill 是 `aether registry-auth rotate/resume/cleanup` 三命令的引导式封装：列出库存 → 选择 PAT → 执行计划 → 等待 grace → 清理。**只处理 nomad-variables backend**；forgejo-secrets backend (ci-build PATs) 仍需 Web UI 手动操作 (Path C 待定)。

## 前置检查

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
require_aether_cli || exit 1

# 必须在含 .aether/pat-inventory.yaml 的目录运行
if [ ! -f .aether/pat-inventory.yaml ]; then
    echo "❌ .aether/pat-inventory.yaml not found"
    echo "   Run from a repo containing the PAT inventory file"
    exit 1
fi

# Cluster 必须可达
aether status &>/dev/null || {
    echo "❌ Nomad cluster not reachable — run /aether:doctor"
    exit 1
}
```

## 工作流

### Step 1: 列出库存 + 识别需要轮换的 PAT

```bash
LIST=$(aether registry-auth list --json)
echo "$LIST" | jq -r '.data[] | "\(.id) | class=\(.class) | age=\(.age_days)d | due in \(.days_to_rotation_due)d"'
```

**判定**:
- `days_to_rotation_due <= 14` → 红色，应该轮换
- `days_to_rotation_due in (14, 30]` → 黄色，下次维护窗口轮换
- `> 30` → 绿色，无需操作

如果 `class == ops-rotation`：**跳过自动化** — 这类 PAT 必须 Web UI 手动操作。提示用户："这是 bootstrap 类 PAT (rotation 工具自身依赖)，请走 docs/guides/forgejo-pat-rotation.md §Step 7 手动流程。"

如果 `class == ci-build`：**跳过自动化** — Path C 还没 ship。提示用户："ci-build 类 PAT (Forgejo Actions secrets) 暂未自动化，请按 #45 Path C follow-up 手动操作或 Web UI。"

### Step 2: 用户确认 + 准备新 PAT

询问用户用 `AskUserQuestion`:
- "已经在 Forgejo Web UI 创建了新 PAT 并保存到文件了吗？"
- 选项: ✅ 已保存到 /tmp/new.pat / 还没创建 / 取消

如果还没：引导用户走 docs/guides/forgejo-pat-rotation.md §Step 2 流程，**等用户确认后再继续**。**绝对不要替用户执行 Forgejo Web UI 操作或代写 PAT 值** (security-sensitive)。

### Step 3: dry-run 显示计划

```bash
PAT_ID="<from user selection>"
aether registry-auth rotate --pat-id "$PAT_ID" --dry-run --json | \
    jq '{consumer_count, total_operations, plan: [.plan[] | {consumer, backend}]}'
```

向用户展示：将操作的 consumer 数量、总 step 数、每个 consumer 的路径。等待用户确认 "继续 / 取消 / 改用其他 PAT"。

### Step 4: 执行 --confirm

```bash
TOKEN_FILE="${TOKEN_FILE:-/tmp/new.pat}"
chmod 600 "$TOKEN_FILE"  # 安全检查

OUT=$(aether registry-auth rotate \
    --pat-id "$PAT_ID" \
    --new-token-file "$TOKEN_FILE" \
    --confirm --json 2>&1)

STATUS=$(echo "$OUT" | jq -r '.status // "error"')
FINAL=$(echo "$OUT" | jq -r '.data.final_status // empty')

if [ "$STATUS" != "ok" ] || [ "$FINAL" != "complete" ]; then
    CODE=$(echo "$OUT" | jq -r '.error.code // empty')
    JOURNAL=$(echo "$OUT" | jq -r '.data.journal_path // empty')
    echo "❌ rotate failed: code=$CODE journal=$JOURNAL"
    # 走故障排查分支 (Step 5)
fi
```

### Step 5: 故障 → 自动诊断 + 引导 resume

按 `error.code` 路由到 docs/guides/forgejo-pat-rotation.md §Troubleshooting：

| code | 行动 |
|------|------|
| `MISSING_TOKEN_FILE` | 提示 --new-token-file 写错或文件不存在 |
| `OLD_TOKEN_KEY_MISSING` | 提示先 `aether env set <path> docker_auth_password <current>` |
| `ROTATE_BOOTSTRAP` | bootstrap 类，走 Web UI |
| `BACKEND_UNSUPPORTED` | forgejo-secrets 类，等 Path C |
| `ROTATE_FAILED` | 检查 journal，准备 resume |
| `nomadAllocVerify... no running alloc` | consumer Job 缺 `template { change_mode = "restart" }` — 修 Job spec → resume |

如果是 ROTATE_FAILED，引导 resume：
```bash
aether registry-auth resume \
    --pat-id "$PAT_ID" \
    --new-token-file /tmp/new.pat \
    --old-token-file /tmp/old.pat
```

注意：resume 需要 BOTH new + old token files (fingerprint guard)。

### Step 6: 24h grace + cleanup 提醒

成功后明确告诉用户：
- "rotate 成功 (final_status=complete)"
- "请等待 ≥24h grace window 让所有 consumer 切换"
- "24h 后运行 `aether registry-auth cleanup --pat-id $PAT_ID` 清理 *_OLD"
- "最后到 Forgejo Web UI 删除旧 PAT (revoke)"
- "更新 .aether/pat-inventory.yaml 的 last_rotated 字段"

**不要自动 cleanup** — 24h 窗口必须人工等待。

## 安全规约

- ❌ 不读取 `/tmp/new.pat` 内容向用户展示 (即使是脱敏后)
- ❌ 不向 chat 历史 echo PAT 明文
- ❌ 不在 commit message / log / journal 之外的地方记录 PAT 任何形式
- ❌ 不替用户在 Forgejo Web UI 操作 (创建/删除 PAT 必须人工)
- ✅ chmod 600 token 文件
- ✅ 错误信息已被 nomadVarSet 边界 scrub (F-MAJOR-4 fix)
- ✅ 所有 cluster-mutating 操作前要求用户明确确认

## 引用

- 完整 runbook: [docs/guides/forgejo-pat-rotation.md](../../../docs/guides/forgejo-pat-rotation.md)
- CLI commands: `aether registry-auth {list,rotate,resume,cleanup} --help`
- 凭据原则: CLAUDE.md §凭据管理原则
- Spec: openspec/changes/forgejo-pat-rotation-mechanism/

## 已知限制

- forgejo-secrets backend (ci-build PATs) 不支持 (Path C deferred)
- `--verify-deadline` flag 未在 cmd 层暴露 (R2-C-07 follow-up) — 大集群慢启动需改 RotateOpts 程序化调用
- AB benchmark 未跑 (per CLAUDE.md §Skill 强制流程 — 待 follow-up，不阻塞代码使用)
