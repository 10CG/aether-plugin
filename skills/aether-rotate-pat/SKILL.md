---
name: aether-rotate-pat
description: |
  Forgejo PAT (Personal Access Token) 凭据轮换工具 (Tier 1 / Aether #45)。
  自动化 list / rotate / resume / cleanup 完整闭环, 含 atomic rollback +
  journal-based interrupt recovery + 24h grace + token fingerprint guard。

  使用场景: "轮换 PAT", "rotate token", "PAT 即将过期", "doctor pat_age 报警",
  "registry-auth", "Forgejo token 过期", "凭据轮换", "renew PAT",
  "credential rotation", "rotation drill", "cleanup _OLD"
argument-hint: "[--list|--rotate|--resume|--cleanup] [--pat-id <id>]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write, AskUserQuestion
dependencies:
  cli:
    required: true
    min_version: "1.16.7"
    role: "Tier 1 rotation tooling lives in aether registry-auth subcommands"
---

# Aether Forgejo PAT 凭换 (aether-rotate-pat)

> **版本**: 0.2.0 (GA) | **Spec**: #45 Phase 2 | **优先级**: P1
> **AB Benchmark**: 3/3 evals WITH_BETTER (2026-05-07; eval-3 deprecated 2026-05-09 per TASK-2.7b GA — re-AB tracked as follow-up)

## 快速决策

```
PAT 即将过期或已过期?
  ├─ 14d/30d alert (aether doctor pat_age) → 走本 Skill 标准 Tier 1 流程
  ├─ 7d critical alert / Tier 1 broken → 走 emergency runbook (web UI)
  └─ 例行预防性轮换 → 走本 Skill
```

**决策核心**: 双 backend 全部 GA (2026-05-08 nomad-variables + 2026-05-09 forgejo-secrets).
- `nomad-variables` (runtime class) — 5-step + atomic rollback + 24h grace, chaos-kill 可 resume
- `forgejo-secrets` (ci-build class) — 2-step + best-effort rollback, chaos-kill 必须走 emergency runbook (单 slot 语义不能 auto-resume)

---

## 前置检查

```bash
# 1. CLI 可用 + 版本
aether version    # 需 >= 1.16.7

# 2. 集群可达
aether status

# 3. 当前 PAT 状态
aether registry-auth list
aether doctor pat_age          # alert tier
aether doctor pat_inventory_drift   # drift detection
```

---

## 5-step 轮换流程 (`nomad-variables` backend)

### Step 1: 生成新 PAT (Forgejo web UI)

```
1. forgejo.10cg.pub → Settings → Applications → Generate New Token
2. Scope **精确匹配** inventory entry `scope` 字段 (不要给多余权限)
3. 保存到本地, chmod 600:
```

```bash
echo "<NEW_PAT_VALUE>" > /tmp/new.pat
chmod 600 /tmp/new.pat
```

### Step 2: 计划核对 (`--dry-run`)

```bash
aether registry-auth rotate --pat-id <id> --dry-run
```

**核对要点**:
- `Consumer count` = inventory 中的 paths 数量
- 每个 path 都是预期 job 名
- 没有未声明的 consumer (drift 应先解决)

### Step 3: 执行 rotation (`--confirm`)

```bash
aether registry-auth rotate --pat-id <id> \
  --new-token-file /tmp/new.pat --confirm
```

每个 consumer 走 5 sub-step: `DELETE_OK` → `PUT_NEW_OK` → `PUT_OLD_OK` →
`RESTART_OK` → `VERIFY_OK`. journal 写入
`.aether/tmp/rotation-state-<pat-id>.json`.

期望输出: `journal_status: complete`.

### Step 4: 验证轮换生效

```bash
aether status <jobname>      # alloc 状态
ssh heavy-1 'docker pull forgejo.10cg.pub/<org>/<image>:latest'
```

### Step 5: 24 小时 grace + cleanup

等 24 小时 (让 mid-restart alloc 用旧 PAT 完成 pull). 然后:

```bash
aether registry-auth cleanup --pat-id <id>
```

最后 Forgejo web UI revoke 旧 PAT.

---

## 失败模式 + 恢复

### Mode 1: Chaos kill mid-rotation

**症状**: `--confirm` 被 SSH 断连或 Ctrl-C 打断

**恢复**:
```bash
# 准备新+旧 token 文件 (同 rotation 时使用的两个 token)
echo "$NEW_PAT_VALUE" > /tmp/new.pat
echo "$OLD_PAT_VALUE" > /tmp/old.pat
chmod 600 /tmp/new.pat /tmp/old.pat

aether registry-auth resume --pat-id <id> \
  --new-token-file /tmp/new.pat --old-token-file /tmp/old.pat
```

Resume 从 journal 续走 forward 或 rollback 路径; sub-step idempotent.

### Mode 2: `TOKEN_FINGERPRINT_MISMATCH`

**根因**: 给的 `--new-token-file` / `--old-token-file` SHA256First16
不匹配 journal 记录 → 用错了 PAT.

**修复**: 必须用 **原始 rotation 时** 的 token 文件 resume.

### Mode 3: `CLEANUP_REFUSED_INCOMPLETE`

**根因**: journal status 不是 `complete` (可能 `in_progress` 或 `rolling_back`)

**修复**: 先 resume 推到 complete 再 cleanup. 或如果 `rolled_back`,
手动确认 cluster 状态正确, 删 journal, 重新 rotate.

### Mode 4: `BOOTSTRAP_NO_AUTOROTATE`

**根因**: PAT class 是 `ops-rotation` (无 consumers; 自身不能 auto-rotate)

**修复**: Forgejo web UI 手动创建新 ops-rotation PAT → 更新 env →
revoke 旧 token. 详见 emergency runbook.

### Mode 5: `ROTATION_FAILED` (rolled_back)

**根因**: 某 sub-step API 调用失败触发 atomic rollback

**修复**: 读 journal `errors[]` 字段定位根因 → 修复 (重启 Nomad / 扩
token scope / 排空节点) → 删 journal → 重新 rotate.

---

## forgejo-secrets backend 流程 (TASK-2.7b GA, 2026-05-09)

ci-build class PAT (例如 `forgejo-actions-ci-2026-Q2`) 走单 slot 2-step 流程, 与 nomad-variables 5-step 显著不同。

### 关键差异

| Aspect | nomad-variables | forgejo-secrets |
|--------|-----------------|-----------------|
| Sub-steps | 5 | **2** (DELETE + PUT_NEW) |
| `*_OLD` sibling | 有 (24h grace) | **无** |
| Atomic rollback | 完整 | **best-effort in-process** |
| OldToken 来源 | cluster 自动读 | **必须 `--old-token-file`** (Forgejo Actions 写-only API) |
| Chaos-kill resume | 支持 | **拒绝** → emergency runbook |
| Bootstrap 凭据 | `cluster.NomadToken` | **`AETHER_FORGEJO_TOKEN` env** (write:user) |

### 用法

```bash
# ENV (按需)
export AETHER_FORGEJO_ADDR="http://192.168.69.200:3000"   # 默认值
export AETHER_FORGEJO_TOKEN="<bootstrap PAT, write:user>"  # 必需

chmod 600 /tmp/new.pat /tmp/old.pat   # 注意: 必须双 token 文件

aether registry-auth rotate --pat-id forgejo-actions-ci-2026-Q2 \
  --new-token-file /tmp/new.pat \
  --old-token-file /tmp/old.pat \
  --dry-run    # 预览: N repos × 2 sub-steps

aether registry-auth rotate --pat-id forgejo-actions-ci-2026-Q2 \
  --new-token-file /tmp/new.pat \
  --old-token-file /tmp/old.pat \
  --confirm    # 真执行

# 完成后立即可 cleanup (无 24h grace, 无 _OLD sibling)
aether registry-auth cleanup --pat-id forgejo-actions-ci-2026-Q2

# Forgejo web UI revoke 旧 PAT, 删本地文件
rm /tmp/new.pat /tmp/old.pat
```

### 中断恢复 (chaos kill / SSH 断)

```bash
aether registry-auth resume --pat-id <id> --new-token-file /tmp/new.pat --old-token-file /tmp/old.pat
# → exit 4 + FORGEJO_MANUAL_RECOVERY_REQUIRED
```

forgejo backend 设计上拒绝 auto-resume (单 slot 无 _OLD 备份, OldToken 不持久化, 无 fingerprint guard). 必须走 emergency runbook 手动逐 repo 确认 secret 状态后修复. 详见 [docs/guides/forgejo-pat-emergency-rotation.md](https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/forgejo-pat-emergency-rotation.md)。

### 失败模式 (forgejo-specific)

- **MISSING_OLD_TOKEN_FILE**: 没传 `--old-token-file` → 必须给 (单 slot 无法 cluster 自读)
- **MISSING_FORGEJO_TOKEN**: `AETHER_FORGEJO_TOKEN` env 未设 → 设为 bootstrap PAT
- **FORGEJO_MANUAL_RECOVERY_REQUIRED**: chaos-kill 后 resume → 走 emergency runbook
- **CLEANUP_REFUSED_INCOMPLETE**: journal status 非 complete → resume 推到 complete (会触发 emergency 路径)

---

## 操作员 checklist

```
□ aether registry-auth list                    — 确认 inventory + drift
□ aether doctor pat_age                        — 确认 alert tier
□ Forgejo web UI 生成新 PAT (匹配 scope)
□ chmod 600 /tmp/new.pat
□ aether registry-auth rotate --pat-id <id> --dry-run
□ 核对 plan
□ aether registry-auth rotate --pat-id <id> --new-token-file /tmp/new.pat --confirm
□ aether status <jobname>                      — 验证 alloc running
□ docker pull 抽样验证                         — 验证新 PAT 可用
□ pat-inventory.yaml last_rotated 更新 + git commit
□ 等 24 小时
□ aether registry-auth cleanup --pat-id <id>
□ Forgejo web UI revoke 旧 PAT
□ rm /tmp/new.pat
```

---

## 参考资源

- **Canonical runbook**: [docs/guides/forgejo-pat-rotation.md](https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/forgejo-pat-rotation.md)
- **Emergency fallback**: [docs/guides/forgejo-pat-emergency-rotation.md](https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/forgejo-pat-emergency-rotation.md)
- **Spec**: openspec/changes/forgejo-pat-rotation-mechanism/
- **Brainstorm decisions**: `.aria/decisions/45-phase2-brainstorm-2026-05-07.md`
- **Issue tracking**: [Aether #45](https://forgejo.10cg.pub/10CG/Aether/issues/45)

---

**Last updated**: 2026-05-09 (GA — both backends shipped; forgejo-secrets eval re-AB tracked as follow-up)
