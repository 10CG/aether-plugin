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

> **版本**: 0.3.1 (GA) | **Spec**: #45 Phase 2 | **优先级**: P1
> **AB Benchmark**: **4/4 evals WITH_BETTER (2026-08-09, suite v1.2.0, Aether #275)** —— WITHOUT 臂在
> eval-4/eval-5 critical FAIL。前基线 3/3 (2026-05-07);已 retire 的 eval-3 由 eval-4 取代。

## 快速决策

```
PAT 即将过期或已过期?
  ├─ WARN cadence_33pct / cadence_10pct (aether doctor --check pat_age) → 走本 Skill 标准 Tier 1 流程
  ├─ FAIL critical (已逾期) / Tier 1 broken → 走 emergency runbook (web UI)
  └─ 例行预防性轮换 → 走本 Skill
```

> `pat_age` 告警档自 cli-v1.17.0 (#302) 起**按 class cadence 相对**, 不再是绝对 14d/30d/7d:
> `days_to_due` 在 (cadence/10, cadence/3] → WARN `cadence_33pct`; [1, cadence/10] → WARN
> `cadence_10pct`; ≤ 0 → FAIL `critical` (绝对边界)。cadence: ci-build 30d / runtime 90d /
> ops·ops-rotation 180d。`rotation_policy: non_expiring` 的 entry 零 finding (`days_to_due: null`
> = 未知, 不是逾期)。旧标签 `"14d"`/`"7d"` 不再出现在 doctor 输出 — 仍沿用的是 `cf_token_age`,
> 别混。

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
aether doctor --check pat_age               # alert tier
aether doctor --check pat_inventory_drift   # drift detection
```

> `doctor` 只接受 `--check <name>`，**不接位置参数** (`Args: cobra.NoArgs`)。写成
> `aether doctor pat_age` 会得 `unknown command` —— 该形态从未存在过 (Aether #275)。

---

## Tier 1 准入边界 (动手前先确认 entry 能自动轮换)

不是每个 inventory entry 都能走 Tier 1。**`--dry-run` 与 `--confirm` 共用同一准入点**
(cli-v1.16.74 起, #281/#287)，因此 dry-run 拒绝 = confirm 必然也拒绝，dry-run 通过 =
准入已过。准入拒绝共 **8 种**错误码 (cli-v1.17.0)，各有确定的手工路径：

| 错误码 | 触发条件 | 手工路径 |
|--------|---------|----------|
| `VAR_KEY_UNSUPPORTED` | consumer 用自定义 var key (非 `docker_auth_password`)，如 aria-build 的 `FORGEJO_BOT_PAT` | `aether env set --job <job> <KEY> --from-file <file>` → 手工更新 inventory `last_rotated` |
| `ORG_LEVEL_UNSUPPORTED` | entry 是 **org 级** Actions secret (Tier 1 只做 repo 级) | Forgejo org Settings → Actions → Secrets 手工换 → 手工写 `last_rotated`。见 runbook **Mode 6** |
| `NO_ROTATABLE_CONSUMERS` | entry **有** `consumers` 块但 `paths` / `repos` 为空 → 轮换会"成功"却零次 API 调用 | 修 `.aether/pat-inventory.yaml` 的 `consumers.paths` / `consumers.repos`。见 runbook **Mode 7** |
| `BACKEND_NOT_ROTATABLE` | `consumers.type: host-docker-config` — 凭据住在节点 `/root/.docker/config.json`，不归 Tier 1 | 在报错列出的 host 上 `docker login`（`--password-stdin`）→ 手工写 `last_rotated`。见 runbook **Mode 8** |
| `UNKNOWN_BACKEND` | `consumers.type` 不是 `nomad-variables` / `forgejo-secrets` / `host-docker-config` 之一 (typo) | 修 `.aether/pat-inventory.yaml`。见 runbook **Mode 8** |
| `FORGEJO_SECRET_NAME_INVALID` | forgejo-secrets entry 的 `consumers.secret_name` 缺失或不匹配 `^[A-Z][A-Z0-9_]*$` | 修 entry 字段后重跑。见 runbook **Mode 9** |
| `FORGEJO_ORG_REQUIRED` | forgejo-secrets entry 缺 `consumers.org` (否则会打到 `/repos//<repo>/...`) | 补 `consumers.org` 后重跑。见 runbook **Mode 9** |
| `PREFLIGHT_FAILED` | **仅 `--dry-run`** (nomad-variables, cli-v1.17.0 #312)：dry-run 现在逐 path 对 Nomad 预检父 job，Nomad 不可达 → 拒绝打印无法验证的绿 plan | 修 `NOMAD_ADDR` / `cluster.nomad_addr` 可达性 (`aether doctor`) 后重跑；**离线 dry-run 不再可能** |

> 判定顺序固定: backend 归属 (Mode 8 两码) → var_key → 可轮换性 (Mode 6/7) → forgejo 字段 (Mode 9)。
> org 级 entry 同时字段畸形时只会看到 `ORG_LEVEL_UNSUPPORTED` —— 终局判定优先，先修字段再跑只是撞第二堵墙。
> 另有 `BACKEND_MISMATCH` 只在 `resume` 出现 (journal 的 backend 与 entry `consumers.type` 不符)，
> 正常 CLI 路径到不了，见到即 journal 被手改过。

> 与 **Mode 4 `BOOTSTRAP_NO_AUTOROTATE` 不同**: 那是 entry **根本没有** `consumers` 块
> (ops-rotation class 引导凭据，本就不该自动轮换)；上表第三行是**声明了却是空的**，属
> inventory 写错，要修数据而非换路径。

**`--from-file` 不是可选项**: 手工路径一律用 `--from-file`。**绝不**把 token 值写成命令行
参数 —— argv 会进 shell history、`ps aux`、以及 AI 会话 transcript，与 stdout 是否遮蔽
**无关** (#282)。

> ⚠️ **`last_rotated` 只在真的换过之后才写**。工具拒绝执行时不要顺手 stamp ——
> 那会把一个未轮换的凭据伪装成已轮换，比不轮换更危险。

> ⚠️ **cli < 1.16.74 存在假绿**: 旧版 `--dry-run` 不校验 var_key，对上表第一种 entry 会
> 打印完整绿色 5-step plan 并 exit 0，直到 `--confirm` 才报晦涩的
> `missing docker_auth_password key`。撞到这个组合先 `aether version`。

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
- 若报上节 8 码之一 → 该 entry **不走 Tier 1** (或环境没就绪)，转上节手工路径
  (confirm 也会同样拒绝，别再试)
- cli-v1.17.0 起 plan entry 带 `verify_class`：`job_not_found` / `batch_parent` / `dead` 类 path
  只列 3 步 (跳 RESTART/VERIFY)，信封有 `verify_skipped_count` — 这是预期，不是缺陷；
  skip 清单的处置看 runbook **Mode 8 四分类表**

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
aether status <jobname>      # alloc 状态 — 必要但**不充分**
```

> ⚠️ Tier 1 的 `VERIFY_OK` 只轮询 alloc 是否 `running`，**从不回读 token** (#301)。
> alloc 绿 = 调度成功，不等于新凭据可用。必须另外做一次真正消费新 token 的探测。

**阳性对照 (真的用新 token 打 registry)** — 内网端点，token 走配置文件不进 argv (#282):

```bash
umask 077
printf 'user = "%s:%s"\n' "<registry-user>" "$(cat /tmp/new.pat)" > /tmp/curlrc.$$
curl -sS -K /tmp/curlrc.$$ -o /dev/null -w '%{http_code}\n' \
  "http://192.168.69.200:3000/v2/<org>/<image>/tags/list"   # 期望 200
rm -f /tmp/curlrc.$$
```

200 = 新 token 真能读 registry；401 = 值没写对或 scope 不足。
(外网 `forgejo.10cg.pub` 前有 CF Access，裸 curl 得 302 而非 401，判不了凭据。)

> ❌ **不要用 `ssh heavy-N 'docker pull ...'` 当验证** —— 它走节点
> `/root/.docker/config.json`，与本次轮换的 job 级 `docker_auth_password` 是
> **两套独立凭据**；#234 prong b 之后节点那份已不是任何 Nomad job 的可用性依赖，
> 所以它无论轮换成没成都会绿 (典型假绿)。同理，靠 alloc 重启触发重拉也不可靠：
> 镜像本地已存在时 docker driver 可能根本不发 pull，auth 一次都没行使。

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
| Bootstrap 凭据 | `cluster.NomadToken` | **`AETHER_FORGEJO_TOKEN` env** (**`write:repository`**) |

> ⚠️ **两个 backend 的 bootstrap scope 不同**: `nomad-variables` 走 `/users/<n>/tokens`
> 需 **`write:user`**；`forgejo-secrets` 走 `/repos/<o>/<r>/actions/secrets` 需
> **`write:repository`**。实战推荐 bootstrap PAT **两个都勾**，一次创建覆盖两个 backend。
> 权威 access matrix 见 runbook §Pre-requisites。

### 用法

```bash
# ENV (按需)
export AETHER_FORGEJO_ADDR="http://192.168.69.200:3000"   # 默认值
export AETHER_FORGEJO_TOKEN="<bootstrap PAT, write:repository>"  # 必需 (勿用 write:user-only)

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
# → exit 1, error.code = FORGEJO_MANUAL_RECOVERY_REQUIRED
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
□ aether doctor --check pat_age                — 确认 alert tier
□ Forgejo web UI 生成新 PAT (匹配 scope)
□ chmod 600 /tmp/new.pat
□ aether registry-auth rotate --pat-id <id> --dry-run
□ 核对 plan (若报准入拒绝 8 码之一 → 转手工路径, 不要 --confirm)
□ aether registry-auth rotate --pat-id <id> --new-token-file /tmp/new.pat --confirm
□ aether status <jobname>                      — 验证 alloc running
□ registry /v2 tags 探针 (新 token, -K 配置文件)  — 期望 200; **不要**用 ssh docker pull (另一套凭据, 恒绿)
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

**Last updated**: 2026-08-23 (Aether #326 — pat_age 告警档追平 #302 cadence 相对标签 · 准入错误码
三码表扩为 8 码表 (+BACKEND_NOT_ROTATABLE/UNKNOWN_BACKEND/FORGEJO_SECRET_NAME_INVALID/
FORGEJO_ORG_REQUIRED/PREFLIGHT_FAILED) · dry-run verify_class 说明 ·
Step 4 验证改为真消费新 token 的 registry 探针 — 原 `ssh heavy-N docker pull` 验的是节点
`/root/.docker/config.json` 另一套凭据, #234 prong b 后恒绿 = 假绿, 本轮 AB 盲评抓到)
2026-08-09 (Aether #275 — doctor `--check` 形态修正 · 新增 Tier 1 准入边界三码 ·
bootstrap scope 更正为 `write:repository` · resume 退出码更正为 1 · AB 基线刷新 4/4)
