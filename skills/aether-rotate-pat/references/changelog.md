# aether-rotate-pat — 变更记录

> SKILL.md 正文只留一行 "Last updated"。历次追平的**内容**记在这里，
> 便于回答「这条规则是什么时候、因为什么进来的」。

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
- 新增一条实测告诫: 该码的 JSON `suggested_action` 是**两成员共用的单一字符串**
  (`classifyBackendRefusal` 不按成员分派)，措辞是 docker-config 那一支的
  ("`docker login` on the hosts named in the message above")。
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
