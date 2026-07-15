# integration-policy marker 注入 fixture 集 (Aether #245 TASK-005)

> **权威来源声明**: 本目录是 C1 (`aether-init` 成对栅栏日期戳 marker 注入/回填, TASK-005)
> 产出的**权威 fixture 输入**，供 C2 (`aether doctor claude_md_integration_policy_present`,
> TASK-009) 的 Go 测试**直接消费**——TASK-009 不得脱离本目录自行手造复刻同一 marker
> 契约（openspec/245-aether-conventions/detailed-tasks.yaml TASK-005/TASK-009
> post_planning R2 Critical 修正: C1↔C2 契约往返验证）。
>
> 每个场景给出 `.before.md`（注入前的消费方 CLAUDE.md，若适用）与 `.after.md`
> （`aether-init` 执行注入/回填流程后的结果）。文件名前缀数字对应
> `aether-plugin/skills/aether-init/references/file-generation.md`
> § "CLAUDE.md 集成规范 Policy 注入" 小节里的分支编号 (1a/1b/2/3)。

## 场景清单

| 文件 | 对应分支 | `aether-init` 行为 | 预期 `aether doctor claude_md_integration_policy_present` 结果 |
|------|---------|---------------------|------------------------------------------------------------|
| `01a-create-new.after.md` | 1a：无 CLAUDE.md | 直接创建（无覆盖风险，无需确认） | PASS |
| `01b-append-existing.before.md` → `01b-append-existing.after.md` | 1b：有 CLAUDE.md 但无 marker | `AskUserQuestion` 确认 → `cp .bak` → diff 回显 → 用户同意后 EOF append | PASS |
| `02-update-stale.before.md` → `02-update-stale.after.md` | 2：有 marker 但日期戳陈旧 (`2026-06-01` < 模板 `2026-07-15`) | `AskUserQuestion` 确认更新 → `cp .bak` → diff 回显 → 用户同意后**成对栅栏块替换**（栅栏外用户内容逐字不动） | PASS |
| `03-noop-current.md` | 3：有 marker 且日期戳与模板一致 | 跳过，不产生任何写操作（幂等回填的核心断言：重跑不产生重复段） | PASS |
| `04-coexist-ci-then-integration.before.md` → `04-coexist-ci-then-integration.after.md` | 2（CI-policy 块在前，integration-policy 块在后共存） | 只更新 integration-policy 块 | PASS，且 CI-policy 块（`<!-- aether-ci-policy -->` 起始那一段）与 before 相比 **0-diff** |
| `05-coexist-integration-then-ci.before.md` → `05-coexist-integration-then-ci.after.md` | 2（顺序颠倒：integration-policy 块在前，CI-policy 块在后） | 同上，验证"任意顺序共存"不依赖块出现顺序 | PASS，CI-policy 块 0-diff |
| `06-degrade-ambiguous-start.before.md` → `06-degrade-ambiguous-start.after.md` | 强制注入失败降级路径（成对栅栏定位歧义：文件中出现 2 组 `start` marker，只有 1 组 `end` marker，无法安全判定哪个 start 与该 end 配对） | **不**做 in-place 替换；退化为"追加 + 告警"：`cp .bak` 后在 EOF 追加一段完整合法的新 marker 块 + 一行 HTML 注释警告，原有内容（含有歧义的孤立 start marker）**不被截断/覆盖** | **PASS**——文件末尾存在一组完整合法的新 marker（start+end 精确配对），探测逻辑必须定位到这组，不被前面孤立的 `start` marker 误导判定为"不完整" |
| `07-incomplete-start-only.md` | marker 边界 fixture (a)：半成品（`start` marker 存在，无配对 `end`，且**不存在**任何其他完整合法的 marker 对） | 若重跑 `aether-init`：命中"有 CLAUDE.md 但无*完整*marker"态，等同分支 1b 处理（视为需要重新注入；旧的孤立 start 行保留在原位，不做删除，仅追加新完整块 + 告警） | **WARN**（"标记不完整需人工核对"）——全文档不存在任何完整配对的新 marker，不可判 PASS |
| `08-legacy-ci-policy-only.md` | marker 边界 fixture (b)：只有旧版单起始 `<!-- aether-ci-policy -->` marker，**完全不含**新 `aether:integration-policy` marker | 命中分支 1b（"有 CLAUDE.md 但无 integration-policy marker"——旧 CI-policy marker 与新 marker 是两个独立 sentinel，互不影响判定） | **WARN**——探测逻辑必须用**精确字符串匹配** `aether:integration-policy` 前缀，不得用宽松包含判断把 `aether-ci-policy` 误判为新 marker 已存在 |

## 不变式（每个 `.after.md` 都必须满足）

1. **栅栏外用户内容逐字不变**——除 `01a`（无 before）外，`.before.md` 中不属于
   `<!-- aether:integration-policy ... start -->` … `<!-- aether:integration-policy end -->`
   区间的所有行，在对应 `.after.md` 中必须逐字节相同（`04`/`05` 额外要求 CI-policy
   块本身也逐字节相同）。
2. **绝不破坏性截断**——即便走降级路径（`06`），原文件的既有内容也只会被"追加"，不会被
   "先 truncate 再写入"这种模式破坏。
3. **精确 marker 匹配**——判定逻辑必须锚定完整字符串
   `<!-- aether:integration-policy YYYY-MM-DD start -->` 与
   `<!-- aether:integration-policy end -->`（首尾锚定，日期戳用
   `[0-9]{4}-[0-9]{2}-[0-9]{2}` 捕获），不得用形如 `grep -q 'integration-policy'`
   的宽松包含判断（`08` 场景是该不变式的直接反例测试）。
4. **不 retrofit 旧 marker**——本目录任何 `.after.md` 都不会修改/删除既有的
   `<!-- aether-ci-policy -->` 单起始 marker 本身（`04`/`05`/`08` 均验证这点）。

## 与 openspec 的对应关系

- 生成规则见 `aether-plugin/skills/aether-init/references/file-generation.md`
  § "CLAUDE.md 集成规范 Policy 注入 (C1)"。
- 权威规格：`openspec/245-aether-conventions/proposal.md` §item C1 +
  `openspec/245-aether-conventions/detailed-tasks.yaml` TASK-005（本目录）/
  TASK-009（消费方）。
