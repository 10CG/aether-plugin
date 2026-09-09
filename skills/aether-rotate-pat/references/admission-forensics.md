# Tier 1 准入边界 — 判定顺序与相邻语义

> 本文是 `SKILL.md` §「Tier 1 准入边界」的深度层。SKILL.md 里留的是**动手要用的**
> 9 码表与手工路径；这里放的是「为什么是这个顺序」「哪些相邻结论**不成立**」——
> 都是踩过的坑，引用时按需读，不必通读。

---

## 判定顺序 (固定)

```
backend 归属 (Mode 8 两码) → var_key → 可轮换性 (Mode 6/7)
  → forgejo 字段 (Mode 9) → 集群预检 (PREFLIGHT_FAILED / DECLARED_VAR_KEY_ABSENT, cli-v1.18.0)
```

前四道**只读台账文件**，最后一道才问集群。由此推出两条容易被问到的结论：

- **声明了自定义 `var_key` 的 entry 永远先撞 `VAR_KEY_UNSUPPORTED`**，经 CLI 看不到
  `DECLARED_VAR_KEY_ABSENT` —— 后者只在有效键 = `docker_auth_password` 时可见。
- org 级 entry 同时字段畸形时只会看到 `ORG_LEVEL_UNSUPPORTED` —— 终局判定优先，
  先修字段再跑只是撞第二堵墙。

另有 `BACKEND_MISMATCH` 只在 `resume` 出现 (journal 的 backend 与 entry `consumers.type`
不符)，正常 CLI 路径到不了，见到即 journal 被手改过。

---

## `cleanup` 不跑那两道集群预检 —— 刻意设计，不是遗漏

`cleanup` 只查 backend 归属。它依 journal 的 `CompletedConsumers` 推导 `*_OLD` path，
不读 `paths` / `var_key`。给它加同样的守卫，会让「轮换成功之后才改了台账」的 entry
再也 cleanup 不了 —— 于是 `*_OLD` 里那份**旧 token 永远留在集群上**，而按期清掉旧凭据
正是 24h grace + cleanup 存在的理由。

所以「rotate 被硬拒」**不蕴含**「cleanup 也被硬拒」，别据此推断上一次轮换的收尾也卡住了。

---

## 残留 journal 不会挡住下一次 `rotate`

`RotateNomadVariables` 是 `NewJournal` 后直接 `WriteAtomic`，无存在性检查，旧 journal
被直接覆盖。它挡住的只有 `cleanup` (`CLEANUP_REFUSED_INCOMPLETE`)。

所以删 journal **不是重跑 rotate 的前置条件**；真正的代价在别处 —— 覆盖会**冲掉上一次
中断的现场记录**。这正是 SKILL.md 的 Mode 5 / Mode 6 让你「先删 journal 再重跑」的理由:
那是要你**先取证再显式清场**，而不是靠一次盲目重跑把证据顺手抹掉。

---

## `NO_ROTATABLE_CONSUMERS` 与 `BOOTSTRAP_NO_AUTOROTATE` 不是一回事

- `BOOTSTRAP_NO_AUTOROTATE` (SKILL.md Mode 4): entry **根本没有** `consumers` 块
  (ops-rotation class 引导凭据，本就不该自动轮换)。
- `NO_ROTATABLE_CONSUMERS`: **声明了却是空的**，属 inventory 写错 —— 要**修数据**
  而非换路径。

---

## `last_rotated` 被骗的是谁 (别搞反)

SKILL.md 的红线是「工具拒绝执行时不要顺手 stamp」。这里补的是**后果的真实分布**：

- `pat_age` **不读** `last_rotated` (它只看 `rotation_due` / `issued_at`)，假 stamp
  **不会**让告警闭嘴，逾期照报。
- 绝大多数 entry 上，`last_rotated` **没有任何机器读者** —— 被骗的纯粹是**读台账的人和审计**。
- 唯一的例外要精确记: `doctor --check forgejo_actions_secret_drift` 只读
  **`org_level: true` 的 forgejo-secrets entry** 的 `last_rotated`（源码里只有 `OrgLevel`
  分支往锚点表里写值），拿它判各 repo 的 secret 是否陈旧 (#299)。所以**只有对 org 级 entry
  假 stamp** 才会让它把新鲜 repo secret 打成 STALE；对 repo 级或 nomad-variables entry
  假 stamp，该检查根本读不到。
  (自带台账条目的 repo 级覆盖另有 `declaredRepoOverride` 豁免，不会被报 shadowing。)

**这不削弱那条红线** —— 审计证据被污染本身就是代价，只是别把「告警会闭嘴」当成理由去讲。

---

## `registry-auth list` 对 forgejo-secrets 行是**实查**，不是恒 deferred

同一条 `list` 命令对 forgejo-secrets 行会真的去查 Forgejo（`registry_auth_list.go`
#122 finding 2）: 设了 `AETHER_FORGEJO_TOKEN` 就逐 repo 实查, 给出 `ok` / `drifted` /
`unreachable`; **没设**该 env 才回落成 `deferred` 占位。

所以看到 `deferred` 的正确反应是**先 export bootstrap PAT 再跑一次**, 而不是转去手工翻
`.forgejo/workflows`。

四个 backend 的 Consumers 列语义:

| backend | 列形态 | 含义 |
|---|---|---|
| `nomad-variables` | `<已核验>/<登记>` | 真去 Nomad 数过 |
| `forgejo-secrets` | `N (deferred)` | 没给 bootstrap PAT，这一趟没核验 |
| `host-docker-config` | `N (declared)` | 无在线核验路径，数字 = 登记 |
| `forgejo-push-mirror` | `N (declared)` | 同上 |

后两个的 `--json` `system_state.reachable/missing` 恒 `0/0` —— 那是诚实的「一个都没核验过」，
不是坏了。

---

## 为什么 `forgejo-push-mirror` 注定进不了 Tier 1

`GET /repos/{owner}/{repo}/push_mirrors` 只回 created / interval / last_error /
last_update / public_key / remote_address / remote_name / repo_name / sync_on_commit，
且 `remote_address` 的 userinfo **已被剥掉**。

于是凭据**既读不回也写不进**: 没有可指纹的旧值 (fingerprint guard 无从建立)，
没有 `*_OLD` sibling，也没有 CAS 可言。**这不是没实现，是 API 面上就没有。**

两条对账口径上的硬限制（`.aether/pat-inventory.yaml` 里也记着）:

1. 「哪条 mirror 用哪把 token」API 不回，是**纯人工登记值**，没有任何 check 能验证，
   写错了不会有人报。
2. `remote_name` 是 Forgejo 生成的不透明串 (实测 `remote_mirror_bgzm5atZGb`)，
   删掉重建就会换 —— **台账在任何一次 mirror 重建之后都会失效**。

---

## Mode 6 `RESUME_PRE_STATE_LOST` 的完整根因

SKILL.md 给的是症状与修复。完整链条:

轮换恰好断在 `DELETE` 与 `PUT_NEW` 之间 (只有 cli-v1.18.0 ~ 1.19.x 的 5 步流程有这个窗口)。
该 path 轮换前的其余键 —— `docker_auth_user` 以及这条 path 原本携带的**任何**兄弟键 ——
此刻**哪里都不存在**: `*_OLD` sibling 要到 `PUT_OLD` (5 步里的第 3 步, 在 `PUT_NEW` 之后)
才写，中断点还没走到那里。

所以 resume 无解: 它能做的只是把**只含一个键**的 Variable 写回去，而那正是这道哨兵拦下来的事。

**该 path 原本有哪些键**: schema 1.2 (cli-v1.20.0+) 的 journal 在
`current_consumer.pre_item_keys` 里记着轮换前的**键名**(不含值)，重建时直接读它，不用靠猜。
1.2 之前的 journal 没有这一栏。

---

## cli < 1.16.74 存在假绿

旧版 `--dry-run` 不校验 var_key，对 `VAR_KEY_UNSUPPORTED` 那类 entry 会打印完整绿色
plan 并 exit 0，直到 `--confirm` 才报晦涩的 `missing docker_auth_password key`。
撞到这个组合先 `aether version`。

---

## `pat_age` 告警档 (cli-v1.17.0 / #302 起按 class cadence 相对)

不再是绝对 14d/30d/7d:

| `days_to_due` 区间 | 结果 |
|---|---|
| (cadence/10, cadence/3] | WARN `cadence_33pct` |
| [1, cadence/10] | WARN `cadence_10pct` |
| ≤ 0 | FAIL `critical` (绝对边界) |

cadence: ci-build 30d / runtime 90d / ops·ops-rotation 180d。

`rotation_policy: non_expiring` 的 entry 零 finding (`days_to_due: null` = 未知，
不是逾期)。旧标签 `"14d"` / `"7d"` 不再出现在 doctor 输出 —— 仍沿用它们的是
`cf_token_age`，别混。
