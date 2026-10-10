# aether-rotate-pat — 变更记录

> SKILL.md 正文只留一行 "Last updated"。历次追平的**内容**记在这里，
> 便于回答「这条规则是什么时候、因为什么进来的」。

---

## 2026-10-10 (Aether #481 — token 值不经过 AI 会话)

Step 1 与 Mode 1 写 token 文件的示例原为 `echo "<NEW_PAT_VALUE>" > /tmp/new.pat` /
`echo "$NEW_PAT_VALUE" > ...`，forgejo-secrets 用法里是 `export AETHER_FORGEJO_TOKEN="<bootstrap PAT, ...>"`。
照做就要把真实值打进命令，值会进 AI 会话 transcript 和 shell history —— 与正文「`--from-file`
不是可选项」同一个理由 (#282)。改为由操作员在自己的终端里
`(umask 077; read -rs T && printf '%s' "$T" > /tmp/new.pat)` 写文件，`AETHER_FORGEJO_TOKEN`
从文件读。`chmod 600` 保留: umask 只管新建的文件，管不到已经存在的那份。CLI 读 token 文件时
`strings.TrimSpace`，所以 `printf '%s'` 不带换行与原先 `echo` 带换行等价。runbook
`docs/guides/forgejo-pat-rotation.md` 的 Step 1 / Mode 1 / forgejo-secrets 用法同步改。

---

## 2026-09-12 (Aether #390 追加 — 第五类 backend `github-actions-secrets`, cli-v1.20.4 / #387 / PR #393)

09-09 那版写于 PR #393 合并之前，与 cli-v1.20.4 有 4 处不符 (PR #393 pre_merge 审计 C4 →
#390 评论)，本次补齐 (依据 `internal/registryauth/admission.go` "Three members as of #387"、
`cmd/registry_auth_list.go`、`cmd/registry_auth_rotate.go` `ce63ef9`、runbook Mode 8 第五行):

- `BACKEND_NOT_ROTATABLE` 成员 **两个 → 三个** (+`github-actions-secrets`: 第三方签发、存在
  GitHub 仓 Actions secret 里)。第三条手工路径: 发行方重新签发 → entry `github_repos[]` 每个
  GitHub 仓 Settings → Secrets and variables → Actions 更新 `secret_name` 同名 secret →
  手工写 `last_rotated`。Actions secret 只写不回读，换没换成只能靠下一次 CI 实跑验证。
- `UNKNOWN_BACKEND` 合法值 **四个 → 五个**。
- Consumers 列 `N (declared)` 覆盖三个 backend (`github_repos[]` 计入)。
- 下面 09-09 段的「`suggested_action` 是两成员共用、措辞是 docker-config 那一支」**限定为
  cli ≤ 1.20.3**: cli-v1.20.4 (#393 `ce63ef9`) 起共用文案改为不指向任何 store 的中性措辞
  ("Follow the manual path named in the message above — it names this entry's own store")。
  「要读 `error.message`」这个结论不变。
- 新增版本地板告诫: 台账含第四/第五类 backend 的仓需 cli ≥ 1.20.4，更早版本整份拒载
  (`INVENTORY_PARSE_FAILED`)，是 CLI 太旧不是台账写错。frontmatter `min_version` 仍是
  `registry-auth` 子命令的 1.16.7 —— 版本地板是**台账**的属性，在正文标注而非上抬 `min_version`。

---

## 2026-09-09 (Aether #390 + #357 — cli-v1.20.3 追平 + references 拆分)

**#390 内容追平** (依据 `internal/registryauth/admission.go`、
`cmd/registry_auth_list.go`、`internal/pat/inventory_schema.json`、
runbook `docs/guides/forgejo-pat-rotation.md` Mode 8，均为 cli-v1.20.3 / PR #389 后的状态):

- `registry-auth list` 的 Consumers 列**已修** ([#340](https://forgejo.10cg.pub/10CG/Aether/issues/340))
  —— `host-docker-config` 与 `forgejo-push-mirror` 现在印 `N (declared)`
  (`heavy-runner-pull-docker-config` 显示 `5 (declared)`)。原先「恒显示 0」的表述改为
  **版本条件式**: cli ≤ 1.20.2 的机器上仍是假零，那些机器必须走 `--json`。
- `BACKEND_NOT_ROTATABLE` 从**一个**成因变成**两个**:
  新增 `forgejo-push-mirror` ([#384](https://forgejo.10cg.pub/10CG/Aether/issues/384))。
  两者**手工路径不同** —— 前者 `docker login`，后者「GitHub 重新生成 → 各仓
  Settings → Mirror Settings 重填」。
- `UNKNOWN_BACKEND` 的合法值由三个补到**四个** (+`forgejo-push-mirror`)，与
  `inventory_schema.json` 的 `consumers.type` enum 对齐。
- 新增一条实测告诫 (**限 cli ≤ 1.20.3**，见上方 09-12 段): 该码的 JSON `suggested_action`
  是**两成员共用的单一字符串** (`classifyBackendRefusal` 不按成员分派)，措辞是 docker-config
  那一支的 ("`docker login` on the hosts named in the message above")。
  push-mirror 的正确路径**只在 `error.message` 里**。

**#357 结构** ([#357](https://forgejo.10cg.pub/10CG/Aether/issues/357)): SKILL.md 越过
守门层 400 行警戒线 (430 行)。把「判定顺序 / 相邻语义 / `pat_age` 档位细则 / 变更记录」
这些**不在动手路径上**的深度层移入 `references/`，动手要用的 9 码表、手工路径、
5 步流程、失败模式全部留在正文。

---

## 2026-08-26 (Aether #338 — 追平 cli-v1.18.0)

准入 8 码表 → **9 码** (+`DECLARED_VAR_KEY_ABSENT`) · `PREFLIGHT_FAILED` 作用域由
「仅 `--dry-run`」更正为 `--dry-run`/`--confirm`/`resume` 三入口 + 两支 suggested_action
分流 · 明示 `cleanup` **刻意不跑**集群预检 · 新增 Mode 6 `RESUME_PRE_STATE_LOST` ·
`registry-auth list` 的 Consumers 列对 host-docker-config 恒显示 0 (#340，**已于
2026-09-08 cli-v1.20.3 修复**，见上)。

## 2026-08-23 (Aether #326)

`pat_age` 告警档追平 #302 cadence 相对标签 · 准入错误码三码表扩为 8 码表
(+`BACKEND_NOT_ROTATABLE` / `UNKNOWN_BACKEND` / `FORGEJO_SECRET_NAME_INVALID` /
`FORGEJO_ORG_REQUIRED` / `PREFLIGHT_FAILED`) · dry-run `verify_class` 说明 ·
Step 4 验证改为真消费新 token 的 registry 探针 —— 原 `ssh heavy-N docker pull` 验的是节点
`/root/.docker/config.json` 另一套凭据，#234 prong b 后恒绿 = 假绿，本轮 AB 盲评抓到。

## 2026-08-09 (Aether #275)

doctor `--check` 形态修正 · 新增 Tier 1 准入边界三码 · bootstrap scope 更正为
`write:repository` · resume 退出码更正为 1 · AB 基线刷新 4/4。

---

## AB 基线锚点

| 日期 | suite | 结果 | 说明 |
|---|---|---|---|
| 2026-05-07 | v0.1.0 | WITH_BETTER 3/3 | 首个基线 |
| 2026-08-09 | v1.2.0 | WITH_BETTER 4/4 | #275 |
| 2026-08-26 | v0.2.2 | WITH_BETTER 4/4 | #338，首次去标识化盲评 + 工具门禁实跑 |
| 2026-09-09 | v0.2.2 | 回归门 base vs post | #390+#357，见 `ab-results/2026-09-09-390-357-refs-split-regression/` |
