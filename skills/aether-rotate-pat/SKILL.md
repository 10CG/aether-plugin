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

# Aether Forgejo PAT 轮换 (aether-rotate-pat)

> **版本**: 0.4.0 (GA) | **Spec**: #45 Phase 2 | **优先级**: P1
> **AB Benchmark**: 前基线 **4/4 evals WITH_BETTER** (2026-08-26, suite v0.2.2) —— WITHOUT 臂
> 在 eval-4/eval-5 critical FAIL。本版回归门数据见 `references/changelog.md` § AB 基线锚点。

## 快速决策

```
PAT 即将过期或已过期?
  ├─ WARN cadence_33pct / cadence_10pct (aether doctor --check pat_age) → 走本 Skill 标准 Tier 1 流程
  ├─ FAIL critical (已逾期) / Tier 1 broken → 走 emergency runbook (web UI)
  └─ 例行预防性轮换 → 走本 Skill
```

> `pat_age` 告警档自 cli-v1.17.0 (#302) 起**按 class cadence 相对**, 不再是绝对 14d/30d/7d
> (cadence: ci-build 30d / runtime 90d / ops·ops-rotation 180d)。分档公式与
> `non_expiring` 的处理见 [admission-forensics.md](references/admission-forensics.md)。

**决策核心**: 双 backend 全部 GA (2026-05-08 nomad-variables + 2026-05-09 forgejo-secrets).
- `nomad-variables` (runtime class) — 4-step (cli-v1.20.0 起; 此前 5 步, 头一步 `DELETE`) + atomic rollback + 24h grace, chaos-kill 可 resume
- `forgejo-secrets` (ci-build class) — 2-step + best-effort rollback, chaos-kill 必须走 emergency runbook (单 slot 语义不能 auto-resume)

---

## 前置检查

```bash
aether version                              # 1. CLI 可用 + 版本 (需 >= 1.16.7)
aether status                               # 2. 集群可达
aether registry-auth list                   # 3. 当前 PAT 状态 (inventory + drift)
aether doctor --check pat_age               #    alert tier
aether doctor --check pat_inventory_drift   #    drift detection
```

> `doctor` 只接受 `--check <name>`，**不接位置参数** (`Args: cobra.NoArgs`)。写成
> `aether doctor pat_age` 会得 `unknown command` —— 该形态从未存在过 (Aether #275)。
>
> ⚠️ **台账含第四/第五类 backend 的仓 (本仓自 #393 起) 需 cli ≥ 1.20.4**。更早的 binary 内嵌 schema
> 不认 `forgejo-push-mirror` / `github-actions-secrets`，会把**整份**台账拒载 (`INVENTORY_PARSE_FAILED`，
> 列出 N 条「违例」并引导你去核对台账) —— 那是 **CLI 太旧，不是台账写错**。先升级，不要按报错改删条目。

> ⚠️ **`registry-auth list` 的 Consumers 列: 后缀就是它的可信度** (cli-v1.20.3 起)。
> `nomad-variables` 印 `<已核验>/<登记>`；`forgejo-secrets` 印 `N (deferred)`；
> `host-docker-config` / `forgejo-push-mirror` / `github-actions-secrets` 印 `N (declared)` ——
> 后三个 backend **没有在线核验路径**，`(declared)` 明说这数字是**登记**而不是现场。
>
> ⚠️ **但 cli ≤ 1.20.2 的机器上这两列是恒零的假零** ([#340](https://forgejo.10cg.pub/10CG/Aether/issues/340))：
> 老版本算 total 只加 `paths + repos`，登记在 `hosts[]` / `mirrors[]` 的消费者一律印 `0` ——
> 而 `0` 与「这把 token 没有任何消费者」**完全同形**。`heavy-runner-pull-docker-config`
> 真值 **5 台 host**，而它恰恰又是台账自己记录被漏登记过两次的那一行 (heavy-4 / heavy-5)。
> 所以**先 `aether version`**；是老版本就别拿这一列去核防漏清单，改走 JSON：
>
> ```bash
> aether registry-auth list --json | jq '.data.pats[] | select(.id=="heavy-runner-pull-docker-config") | .consumers.hosts | length'
> ```
>
> 边界: 这是**该列在老版本上的**缺陷，别推广成「`list` 不可信」—— 同一条命令对 **forgejo-secrets 行
> 会真的去查 Forgejo**: 设了 `AETHER_FORGEJO_TOKEN` 就逐 repo 实查，没设才回落成 `deferred` 占位。看到
> `deferred` 应**先 export bootstrap PAT 再跑一次**，而不是转去手工翻 `.forgejo/workflows`。五列语义全表见 [admission-forensics.md](references/admission-forensics.md)。

---

## Tier 1 准入边界 (动手前先确认 entry 能自动轮换)

不是每个 inventory entry 都能走 Tier 1。**`--dry-run` / `--confirm` / `resume` 共用同一准入点**
(cli-v1.16.74 起 #281/#287 覆盖前两者，cli-v1.18.0 起 #334 把 `resume` 也接上)，因此 dry-run
拒绝 = confirm 必然也拒绝，不必再试。准入拒绝共 **9 种**错误码 (cli-v1.18.0)，各有确定的手工路径：

> 反过来**不成立**: 最后一道是**问集群**的，集群状态会变 —— dry-run 通过只说明*当时*准入已过，
> 不是一张长期通行证。中间被人改了 Variable 键名，`--confirm` 照样会在同一道墙上被拒。

| 错误码 | 触发条件 | 手工路径 |
|--------|---------|----------|
| `VAR_KEY_UNSUPPORTED` | consumer 用自定义 var key (非 `docker_auth_password`)，如 aria-build 的 `FORGEJO_BOT_PAT` | `aether env set --job <job> <KEY> --from-file <file>` → 手工更新 inventory `last_rotated` |
| `ORG_LEVEL_UNSUPPORTED` | entry 是 **org 级** Actions secret (Tier 1 只做 repo 级) | Forgejo org Settings → Actions → Secrets 手工换 → 手工写 `last_rotated`。见 runbook **Mode 6** |
| `NO_ROTATABLE_CONSUMERS` | entry **有** `consumers` 块但 `paths` / `repos` 为空 → 轮换会"成功"却零次 API 调用 | 修 `.aether/pat-inventory.yaml` 的 `consumers.paths` / `consumers.repos`。见 runbook **Mode 7** |
| `BACKEND_NOT_ROTATABLE` | backend 登记得**没错**，但 Tier 1 不碰它。**三个成员**: `host-docker-config` (凭据住在节点上的某个 docker config)、`forgejo-push-mirror` (GitHub PAT，住在 Forgejo 的 push-mirror 配置里，#384)、`github-actions-secrets` (第三方签发如 npmjs，存在 **GitHub** 仓的 Actions secret 里，#387) | **三支路径互不相通，别串**：`host-docker-config` → 在**报错列出的那些 host** 上 `docker login`（`--password-stdin`）；`forgejo-push-mirror` → 到 **GitHub 上重新生成**，再到**每个 repo 的 Settings → Mirror Settings 重新填入**；`github-actions-secrets` → 到**发行方**重新签发，再到 entry `github_repos[]` 列出的**每个 GitHub 仓** Settings → Secrets and variables → Actions 更新 `secret_name` 同名 secret（只写不回读，换没换成只能靠下一次 CI 实跑验证）。三者事后都要手工写 `last_rotated`。见 runbook **Mode 8** |
| `UNKNOWN_BACKEND` | `consumers.type` 不是五个合法值之一 (typo)：`nomad-variables` / `forgejo-secrets` / `host-docker-config` / `forgejo-push-mirror` / `github-actions-secrets` | 修 `.aether/pat-inventory.yaml`。见 runbook **Mode 8** |
| `FORGEJO_SECRET_NAME_INVALID` | forgejo-secrets entry 的 `consumers.secret_name` 缺失或不匹配 `^[A-Z][A-Z0-9_]*$` | 修 entry 字段后重跑。见 runbook **Mode 9** |
| `FORGEJO_ORG_REQUIRED` | forgejo-secrets entry 缺 `consumers.org` (否则会打到 `/repos//<repo>/...`) | 补 `consumers.org` 后重跑。见 runbook **Mode 9** |
| `PREFLIGHT_FAILED` | 集群预检**跑不起来**（不是跑出了坏结果）。cli-v1.18.0 起 `--dry-run` / `--confirm` / `resume` **三者都可能返回** —— 预检已从 dry-run 专属移到共用准入点；覆盖两个探针：#312 逐 path 父 job 分类（仅 dry-run）与 #334 declared var_key 检查（rotate + resume） | **先读报错分两支**：说 config 解不开 → 本地 `.aether/config.yaml` / `~/.aether/config.yaml` 某字段**类型**不对（标量放在该放块的位置、列表放在该放字符串的位置），**别去查集群**；说探针打不通 → 修 `NOMAD_ADDR` / `cluster.nomad_addr` 可达性（`aether doctor`）。两支都零集群写入 |
| `DECLARED_VAR_KEY_ABSENT` | nomad-variables entry 的某条 declared path 上**没有该 entry 的有效 var key**（`consumers.var_key` 未声明时 = 默认 `docker_auth_password`）。**不声明 `var_key` 也会触发** —— 默认槽位同样被逐 path 预检。一次列出**全部**缺键 path（非 fail-fast），exit 1，零集群写入 | 看报错里每条 path 的括号分两支：`no Variable at this path` = 该 path 上根本没有 Variable（先建，或它已不是 consumer 就从 entry 里删掉）；`Variable exists but holds no such key` = 键名不同（把该 path 拆成自己的 entry 并写显式 `var_key`，之后它会以 `VAR_KEY_UNSUPPORTED` 被拒 → 走手工换）。**改台账，不是加 flag**。交叉核对 `aether doctor --check pat_inventory_drift --json`（`kind=declared_var_key_absent`） |

> **`BACKEND_NOT_ROTATABLE` 与 `UNKNOWN_BACKEND` 意思相反**，别混:
> 前者 = **entry 是对的，Tier 1 是错的工具** (照上表手工路径走)；
> 后者 = **entry 是错的** (`consumers.type` 拼错了，去修台账)。
> 把前者当后者处理，会让操作员去审一个本来就没问题的文件。
>
> ⚠️ 对这个码 **要读 `error.message`，别只读 `suggested_action`**: `classifyBackendRefusal` 对三个成员
> 返回**同一条** `suggested_action`。cli ≤ 1.20.3 那条措辞是 docker-config 那一支的（"`docker login` on
> the hosts named in the message above"）—— push-mirror / Actions-secret 照做等于跑去错误的机器；
> cli-v1.20.4 (#393) 起改为不指向任何 store 的中性文案。逐成员正确的做法**只写在 `error.message` 里**，
> 且它会**指名这条 entry 自己的** host / mirror / repo + secret 名: 同一批节点上 `/root/.docker/config.json`
> 也存在且装着另一枚真凭据，照硬编码路径去 `docker login` 会成功地换错 store 然后 stamp `last_rotated`。
>
> **push-mirror 与 Actions-secret 都注定进不了 Tier 1**: Forgejo 的 `GET push_mirrors` **从不返回凭据**
> (连 `remote_address` 的 userinfo 都被剥掉)；GitHub Actions secret **只写不回读**，且发行方 (npmjs) 与
> 存放处 (GitHub) 两个 API 工具都不说。既没有可指纹的旧值也无处写新值 —— 不是没实现，是 API 面上
> 就没有。字段全表见 [admission-forensics.md](references/admission-forensics.md)。

> 判定顺序固定 (backend 归属 → var_key → 可轮换性 → forgejo 字段 → 集群预检)，前四道只读台账文件、
> 最后一道才问集群。相邻结论（哪个码盖住哪个、`cleanup` 为何**刻意**不跑预检、残留 journal 挡不挡 rotate）见 [admission-forensics.md](references/admission-forensics.md)。

**`--from-file` 不是可选项**: 手工路径一律用 `--from-file`。**绝不**把 token 值写成命令行
参数 —— argv 会进 shell history、`ps aux`、以及 AI 会话 transcript，与 stdout 是否遮蔽
**无关** (#282)。

> ⚠️ **`last_rotated` 只在真的换过之后才写**。工具拒绝执行时不要顺手 stamp —— 那会把一个
> 未轮换的凭据伪装成已轮换，比不轮换更危险。同理，**改 inventory 字段 (例如去掉 `org_level`)
> 把守卫绕过去**，正是这些守卫要防的、更隐蔽的那种谎言。假 stamp 到底骗到了谁，见
> [admission-forensics.md](references/admission-forensics.md)。

---

## 轮换流程 (`nomad-variables` backend)

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
- 若报上节 9 码之一 → 该 entry **不走 Tier 1** (或环境/台账没就绪)，转上节手工路径
  (confirm 也会同样拒绝，别再试)
- cli-v1.17.0 起 plan entry 带 `verify_class`：`job_not_found` / `batch_parent` / `dead` 类 path
  只列 3 步 (跳 RESTART/VERIFY)，信封有 `verify_skipped_count` — 这是预期，不是缺陷；
  skip 清单的处置看 runbook **Mode 8 四分类表**

### Step 3: 执行 rotation (`--confirm`)

```bash
aether registry-auth rotate --pat-id <id> \
  --new-token-file /tmp/new.pat --confirm
```

每个 consumer 走 4 sub-step: `PUT_NEW_OK` → `PUT_OLD_OK` → `RESTART_OK` →
`VERIFY_OK`. journal 写入 `.aether/tmp/rotation-state-<pat-id>.json` (schema 1.2)。

`PUT_NEW` 是**一次 compare-and-swap 写**: 拿 pre-read 的 ModifyIndex 作 cas 条件, 并发
写会被 409 拒掉而不是静默覆盖。cli-v1.20.0 之前是 5 步, 头一步先 `DELETE` 再 `PUT_NEW` ——
那两步之间该 path 上什么都没有, 进程死在那里则兄弟键只剩内存里那一份 (见 Mode 6)。

> **schema 1.2 不向下兼容**: 1.20.0 写的 journal, 老版本 CLI 读不了 (`ErrJournalSchemaMismatch`),
> 反之亦然。**resume 必须用启动那次轮换的同一个 CLI 版本。**

期望输出: `journal_status: complete`.

### Step 4: 验证轮换生效

`aether status <jobname>` 看 alloc 状态 —— **必要但不充分**。

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
**不要重新跑 `--confirm`** —— 那会覆盖 journal、冲掉中断现场，已完成的 consumer 还会被再走一遍。

### Mode 2: `TOKEN_FINGERPRINT_MISMATCH`

**根因**: 给的 `--new-token-file` / `--old-token-file` SHA256First16
不匹配 journal 记录 → 用错了 PAT.

**修复**: 必须用 **原始 rotation 时** 的 token 文件 resume.
旧 token 明文已不可恢复时 resume 无解 —— 走 emergency runbook 手工从 cluster 状态推断修复。

### Mode 3: `CLEANUP_REFUSED_INCOMPLETE`

**根因**: journal status 不是 `complete` (可能 `in_progress` 或 `rolling_back`)

**修复**: 先 resume 推到 complete 再 cleanup. 或如果 `rolled_back`,
手动确认 cluster 状态正确, 删 journal, 重新 rotate.

### Mode 4: `BOOTSTRAP_NO_AUTOROTATE`

**根因**: PAT class 是 `ops-rotation` (entry **根本没有** `consumers` 块; 自身不能 auto-rotate)

**修复**: Forgejo web UI 手动创建新 ops-rotation PAT → 更新 env → revoke 旧 token.
详见 emergency runbook. (与 `NO_ROTATABLE_CONSUMERS` 的「声明了却是空的」不是一回事。)

### Mode 5: `ROTATION_FAILED` (rolled_back)

**根因**: 某 sub-step API 调用失败触发 atomic rollback

**修复**: 读 journal `errors[]` 字段定位根因 → 修复 (重启 Nomad / 扩
token scope / 排空节点) → 删 journal → 重新 rotate.

### Mode 6: `RESUME_PRE_STATE_LOST` (cli-v1.18.0 新增)

**先看 `aether version`**: **>= 1.20.0** 轮换**本身**不会再产生这个状态 (主写改成一次 CAS PUT,
没有「path 上空无一物」的瞬间, #339) —— 仍报这个错 = **别的东西删了那条 Variable**，
照下面走并去查是谁删的。**1.18.0 ~ 1.19.x** 则是轮换断在 `DELETE` 与 `PUT_NEW` 之间。

**根因**: journal 记的是该 consumer 的 Variable 已 `DELETE`，但那条 path 上**现在没有任何
Variable** —— 该 path 原本的其余兄弟键 (`docker_auth_user` 等) 此刻**哪里都不存在**
(`*_OLD` sibling 要到 `PUT_OLD` 才写，中断点还没走到)。完整链条见
[admission-forensics.md](references/admission-forensics.md)。

**修复**: **不要再跑 resume** —— 它会到达同一状态，唯一能做的就是把只含一个键的 Variable
写回去，那正是这道哨兵拦下来的事。手工用 `aether env set --job <job> ... --from-file <file>`
按该 path 应有的键集重建 Variable → 删 journal → 从干净状态重跑 rotate。
(该 path 原本有哪些键，schema 1.2 的 journal 在 `current_consumer.pre_item_keys` 里记着。)

> 这是**止血哨兵，不是修好了**: 在 **cli-v1.18.0 ~ 1.19.x** 上，该窗口只能响亮地停下，
> 不能恢复 —— 撞上了就只有上面那条手工重建的路。根治已随 **cli-v1.20.0** 落地
> ([#339](https://forgejo.10cg.pub/10CG/Aether/issues/339)): 主写变成单次 CAS 写，窗口不再存在。

---

## forgejo-secrets backend 流程 (TASK-2.7b GA, 2026-05-09)

ci-build class PAT (例如 `forgejo-actions-ci-2026-Q2`) 走单 slot 2-step 流程, 与 nomad-variables 的 4-step 显著不同。

### 关键差异

| Aspect | nomad-variables | forgejo-secrets |
|--------|-----------------|-----------------|
| Sub-steps | 4 (cli-v1.20.0 前 5) | **2** (DELETE + PUT_NEW) |
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

# 同一条命令换末尾 flag: --dry-run 先预览 (N repos x 2 sub-steps), 再 --confirm 真执行
aether registry-auth rotate --pat-id forgejo-actions-ci-2026-Q2 \
  --new-token-file /tmp/new.pat \
  --old-token-file /tmp/old.pat \
  --dry-run

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

> ⚠️ **`secret_name` 是 entry 级, 全部 repo 共用一个**（`forgejo_rotate.go` 取一次
> `Consumers.SecretName` 后在 repo 循环里反复用）。所以一个 entry 装不下「不同 repo 用不同
> secret 名」—— 那种情况要拆成多个 entry, 不是在一个 entry 里想办法。
>
> ⚠️ **`rolled_back` ≠ 已验证恢复**。best-effort rollback 的实际动作是: 按
> `CompletedConsumers` **逆序**逐 repo「DELETE 新值 → PUT 回旧值」, 再对失败点那个 in-flight
> repo 补一次 PUT 旧值。但这些调用的错误是**被直接丢弃的**（源码里是 `_ =`），既不中断也不上报。
> 所以 journal 写 `rolled_back` 只说明**回滚流程跑完了**, 不说明每个 repo 的旧值真的回去了 ——
> 必须自己逐 repo 核一遍 secret 的 `created_at`（`list` 那条实查路径, 或 Forgejo UI）。

---

## 操作员 checklist

```
□ aether registry-auth list                    — 确认 inventory + drift
□ aether doctor --check pat_age                — 确认 alert tier
□ Forgejo web UI 生成新 PAT (匹配 scope)
□ chmod 600 /tmp/new.pat
□ aether registry-auth rotate --pat-id <id> --dry-run
□ 核对 plan (若报准入拒绝 9 码之一 → 转手工路径, 不要 --confirm)
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

- **本 skill 深度层** (自包含): [admission-forensics.md](references/admission-forensics.md)
  (判定顺序 · cleanup/journal 语义 · `last_rotated` 被骗的是谁 · `pat_age` 分档 · 四 backend 列语义)
  · [changelog.md](references/changelog.md) (历次追平内容 + AB 基线锚点)
- **Canonical runbook**: [docs/guides/forgejo-pat-rotation.md](https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/forgejo-pat-rotation.md)
- **Emergency fallback**: [docs/guides/forgejo-pat-emergency-rotation.md](https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/forgejo-pat-emergency-rotation.md)
- **Spec**: openspec/changes/forgejo-pat-rotation-mechanism/ · **Issue**: [Aether #45](https://forgejo.10cg.pub/10CG/Aether/issues/45)

---

**Last updated**: 2026-09-09 (Aether #390 追平 cli-v1.20.3 · Aether #357 深度层移入
`references/`)。逐版内容见 [changelog.md](references/changelog.md)。
