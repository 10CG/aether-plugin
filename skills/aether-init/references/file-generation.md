# 文件生成

## Phase 2 概述

用户确认部署方案后，按**此顺序**生成部署文件（**US-030 约束**: CLAUDE.md 必须在 nomad HCL 之后生成，
以便 `__JOB_NAME__` 占位符能从已生成的 nomad-dev.hcl parse 出来）：

1. Dockerfile
2. .dockerignore
3. deploy/nomad-dev.hcl
4. deploy/nomad-prod.hcl
5. .forgejo/workflows/deploy.yaml
6. CLAUDE.md — 两段独立注入，互不依赖顺序：
   - CI Monitoring Policy：如不存在则创建；如存在则按 Step 1.1c 流程判断是否 append（见
     [§ CLAUDE.md CI Monitoring Policy 注入](#claudemd-ci-monitoring-policy-注入-us-030)）
   - 集群集成规范 Policy（C1, Aether #245）：如不存在则创建；如存在则按四分支判断
     创建 / append / 原地更新 / 跳过（见
     [§ CLAUDE.md 集成规范 Policy 注入](#claudemd-集成规范-policy-注入-成对栅栏日期戳-marker-aether-245-c1)），
     两套 marker 独立，**不 retrofit** 对方

## Dockerfile 生成

根据语言/框架选择模板，详见 [Dockerfile 模板](dockerfile-templates.md)

## Nomad HCL 生成

### 变量占位符

| 占位符 | 说明 | 示例值 |
|--------|------|-------|
| `__PROJECT_NAME__` | 项目名称 | my-api |
| `__DOCKER_IMAGE__` | 镜像地址 | forgejo.10cg.pub/org/my-api |
| `__PORT__` | 服务端口 | 8080 |
| `__NODE_CLASS__` | 节点类型 | heavy_workload |
| `__REPLICAS__` | 副本数 | 2 |
| `__DATA_DIR__` | 数据目录 | /data/my-api |

### dev vs prod 差异

| 配置项 | dev | prod |
|--------|-----|-----|
| 副本数 | 1 | 2+ |
| 镜像 tag | latest | semver |
| 健康检查 | 宽松 | 严格 |
| 滚动更新 | 无 | 有 |

详见 [Nomad 模板](nomad-templates.md)

> 📌 涉及 Consul service 依赖的 `template {}` 写法（三件套: `wait` + `change_mode=noop` + `if` 守卫），
> 见 [nomad-templates.md § Consul Template 渲染抖动缓解](./nomad-templates.md#consul-template-渲染抖动缓解-render-flap-mitigation)。

## Workflow 生成

### 变量

| 变量 | 说明 |
|------|------|
| `PROJECT_NAME` | 项目名称 |
| `REGISTRY` | 镜像仓库地址 |
| `NOMAD_ADDR` | Nomad API 地址 |

### Secrets 配置

| Secret | 说明 | 是否必需 |
|--------|------|---------|
| `NOMAD_ADDR` | Nomad API 地址 | ✓ |
| `NOMAD_TOKEN` | Nomad 访问令牌 | ✓ |
| `FORGEJO_TOKEN` | 镜像推送令牌 | 自动注入 |

详见 [Workflow 模板](workflow-templates.md)

## 生成流程

```bash
# 1. 创建目录
mkdir -p deploy .forgejo/workflows

# 2. 生成 Dockerfile
# 根据 project-analysis.md 的决策选择模板

# 3. 生成 Nomad HCL
# 替换占位符
sed "s/__PROJECT_NAME__/my-api/g" deploy/nomad-dev.hcl

# 4. 生成 Workflow
# 检查 secrets 配置

# 5. 验证生成文件
ls -la deploy/ .forgejo/
```

## 生成后验证

1. 检查 Dockerfile 语法: `docker build --check .`
2. 检查 Nomad HCL 语法: `nomad job validate deploy/nomad-dev.hcl`
3. 检查 Workflow 语法: `actionlint .forgejo/workflows/deploy.yaml`

---

## CLAUDE.md CI Monitoring Policy 注入 (US-030)

> **Source**: [US-030](../../../../docs/requirements/user-stories/US-030.md) |
> [proposal.md](../../../../openspec/changes/2026-04-10-init-inject-ci-policy/proposal.md)

### 插入行为

新项目（无 CLAUDE.md）或已有项目（有 CLAUDE.md 但无 Policy 章节）都会注入 CI Monitoring Policy。
注入内容来自 [`deploy-monitoring-rules.md`](deploy-monitoring-rules.md)，该文件首行为
HTML marker `<!-- aether-ci-policy -->`（语言无关 sentinel）。

### 检测逻辑 (triple-fallback grep，仅针对目标 CLAUDE.md)

```bash
# R2-I: grep 必须仅针对目标 CLAUDE.md，不要把 deploy-monitoring-rules.md 模板本身读入
if [ -f CLAUDE.md ] && grep -qE "(<!-- aether-ci-policy -->|部署监控规则|CI/CD Monitoring Policy)" CLAUDE.md; then
  # 3 种历史/当前 sentinel 命中任一即跳过：
  #   <!-- aether-ci-policy -->  (v1.7.2+ HTML marker — 推荐)
  #   部署监控规则               (v1.7.1 之前的 Chinese 注入)
  #   CI/CD Monitoring Policy    (v1.7.1 手动添加到 4 项目的英文段)
  echo "Already has policy, skipping"
else
  # 注入流程继续
fi
```

### 占位符替换

| 占位符 | 解析顺序 |
|--------|---------|
| `__JOB_NAME__` | (1) 从已生成的 `deploy/nomad-dev.hcl` parse `job "<name>" {`（用 `grep -m1` 取首个匹配 — multi-job 时取第一个）<br>(2) 失败时 fallback 到 `${PROJECT_NAME}-dev` |

**关键 (R2-B)**: 文件生成顺序必须保证 `deploy/nomad-dev.hcl` 在 `CLAUDE.md` 之前生成
（见 Phase 2 顺序表），否则 parse 失败将退回 fallback 命名。

### 注入位置（确定性 EOF append）

不使用"插入到部署节后"启发式（在 Round 1 audit 中被认定为模型层不确定）。注入位置**始终为**:

```
<CLAUDE.md 原有内容>
<blank line>
---
<blank line>
<deploy-monitoring-rules.md 内容，__JOB_NAME__ 已替换>
```

### 已存在 CLAUDE.md 的处理 (AskUserQuestion 保守策略)

如果目标项目有 CLAUDE.md 且未命中 triple-fallback grep：
1. 通过 `AskUserQuestion` 询问用户是否 append Policy 章节
2. 用户同意 → append 到 EOF
3. 用户拒绝 → 跳过，记录到 generation report
4. **绝不静默覆盖或修改用户已有内容**

### HTML marker durability (R2-H)

HTML marker `<!-- aether-ci-policy -->` **MUST NOT** be stripped by future markdown
processing tools. If a markdown linter (prettier, markdownlint, remark) is added to CI
in the future, configure it to preserve HTML comments.

**[订正 2026-07-15, 见 Aether [#245](https://forgejo.10cg.pub/10CG/Aether/issues/245)]** 本节此前声称 "The drift check function in
`static-benchmark.sh` (`check_template_drift`) relies on this marker being the first
line" —— 该函数从未实现: `static-benchmark.sh` 实测唯一函数是 `check_cost`
（112 行）。**待办**: 目前没有任何自动化守护强制这条约定，marker 保持首行纯靠人工
约定 + code review 兜底。若未来要补机械检测，必须先证明脚本真的被某 CI job 调用、
且能在刻意破坏 marker 顺序时报错，不能重演本次"写了没接线"的失效模式。

### Monorepo 暂不支持

当前 `__JOB_NAME__` 是单一占位符，只支持 single-image 项目。monorepo 多镜像场景：
`# TODO(US-031): support monorepo via __JOB_NAMES_LIST__`

---

## CLAUDE.md 集成规范 Policy 注入 (成对栅栏日期戳 marker, Aether #245 C1)

> **Source**: openspec `245-aether-conventions/proposal.md` §item C1（TASK-005，maintainer-only /
> 需主仓权限，请勿对 Forgejo URL 发 WebFetch，人读参考） |
> 注入内容来自 [`integration-policy-rules.md`](integration-policy-rules.md)（TASK-003 产出）。
>
> 本节是**新增的独立注入机制**，服务两个目的：(1) 新项目 Phase 2 生成 CLAUDE.md 时的
> 常规注入；(2) **老项目回填 (C1)** —— 已接入 Aether 但 CLAUDE.md 里没有这段 policy
> 的项目（如 #241 触发源 TurfSync），重跑 `/aether:init` 即可幂等补上或刷新。

### 与 CI Monitoring Policy 注入的关系（两套独立机制，互不改造）

| | 旧：CI-policy | 新：integration-policy (本节) |
|---|---|---|
| marker | 单起始 `<!-- aether-ci-policy -->`（presence-only） | 成对栅栏日期戳 `<!-- aether:integration-policy YYYY-MM-DD start -->` … `<!-- aether:integration-policy end -->` |
| 能力 | 命中即跳过，**无 update-in-place** | 支持原地更新（date 陈旧时替换栅栏内内容） |
| 内容源 | [`deploy-monitoring-rules.md`](deploy-monitoring-rules.md) | [`integration-policy-rules.md`](integration-policy-rules.md) |
| 检测方式 | triple-fallback grep（含历史中文/英文 sentinel） | 精确锚定正则，仅认 `aether:integration-policy` 字面 marker |

**[决策] 不 retrofit 现有 `<!-- aether-ci-policy -->` 单 marker。** 本节新增逻辑
**绝不**修改、删除、或"升级"旧 CI-policy marker 本身；旧 marker 保持 presence-only
不动，成对栅栏日期戳只是 **go-forward 标准**（用于所有*新*注入的 policy 段，当前仅
integration-policy 一种）。两种格式并存是已知且记录在案的不一致（blast radius 远大于
收益 —— retrofit 意味着触碰每个已接入项目的 CLAUDE.md）。

两个 marker 可在同一 CLAUDE.md 内以**任意顺序**共存。本节的检测/替换逻辑必须
**只操作 `aether:integration-policy` 边界内的内容**，CI-policy 块必须保持逐字节不变
（fixture `04`/`05` 校验此不变式，见下方 § Fixture）。

### marker 格式

```
<!-- aether:integration-policy 2026-07-15 start -->
...policy 段内容（来自 integration-policy-rules.md，含标题/铁律列表/invoke 指引）...
<!-- aether:integration-policy end -->
```

- 成对栅栏（start/end 各一行独立 HTML 注释）精确定界，使 in-place 块替换可行（旧单
  marker 因为没有 end 锚点做不到这点）。
- 日期戳（`YYYY-MM-DD`）取自 `integration-policy-rules.md` 首行 start marker 里嵌入的
  日期 —— 该文件本身就是"当前期望版本"的唯一来源，**不**在 CLAUDE.md 生成逻辑或
  CLI 里另外硬编码一份日期常量（避免重演 `check_template_drift`"写了没接线"式的
  虚假新鲜度承诺）。
- ISO 日期字符串天然按字典序等价于按时间序（避开 `vN` 形态下 `v10 < v2` 这类 bash
  字符串比较错乱）。
- **精确锚定匹配，不用宽松包含判断**：判定用
  `^<!-- aether:integration-policy [0-9]{4}-[0-9]{2}-[0-9]{2} start -->$` 与
  `^<!-- aether:integration-policy end -->$`（首尾锚定 + 日期戳用
  `[0-9]{4}-[0-9]{2}-[0-9]{2}` 捕获）。**绝不**用形如 `grep -q 'integration-policy'`
  或 `grep -q 'policy'` 这类宽松包含判断 —— 那会把旧 `aether-ci-policy` 误判成新
  marker 已存在（见 fixture `08-legacy-ci-policy-only.md`，这是本条的直接反例测试）。

### 检测与决策树（四分支：1 拆 1a/1b，见 detailed-tasks.yaml TASK-005 post_planning R1）

```bash
# 0. 读取当前期望日期戳（唯一来源：模板文件自身的 start marker）
TEMPLATE_DATE=$(grep -m1 -oE '<!-- aether:integration-policy [0-9]{4}-[0-9]{2}-[0-9]{2} start -->' \
  "${CLAUDE_PLUGIN_ROOT}/skills/aether-init/references/integration-policy-rules.md" \
  | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')

if [ ! -f CLAUDE.md ]; then
  # ── 分支 1a：无 CLAUDE.md，无覆盖风险，直接创建 ──────────────────
  # 无需 AskUserQuestion（没有可覆盖的用户内容）
  cat "${CLAUDE_PLUGIN_ROOT}/skills/aether-init/references/integration-policy-rules.md" > CLAUDE.md
  exit 0
fi

# 精确扫描（不与旧 aether-ci-policy 混淆）
START_COUNT=$(grep -cE '^<!-- aether:integration-policy [0-9]{4}-[0-9]{2}-[0-9]{2} start -->$' CLAUDE.md)
END_COUNT=$(grep -cE '^<!-- aether:integration-policy end -->$' CLAUDE.md)

if [ "$START_COUNT" -eq 0 ] && [ "$END_COUNT" -eq 0 ]; then
  # ── 分支 1b：有 CLAUDE.md 但无 marker（不论是否已有旧 aether-ci-policy） ──
  # 复用现有 CI-policy 注入逻辑的 consent gate，不得静默追加
  cp CLAUDE.md CLAUDE.md.bak
  # AskUserQuestion: "是否将「集群集成规范」policy 段追加到 CLAUDE.md 末尾？"
  #   同意 → { echo; echo "---"; echo; cat integration-policy-rules.md; } >> CLAUDE.md
  #          diff -u CLAUDE.md.bak CLAUDE.md   # 回显给用户确认已写入内容
  #   拒绝 → 不写；rm CLAUDE.md.bak；记录到 generation report

elif [ "$START_COUNT" -eq 1 ] && [ "$END_COUNT" -eq 1 ]; then
  EXISTING_DATE=$(grep -oE '<!-- aether:integration-policy [0-9]{4}-[0-9]{2}-[0-9]{2} start -->' CLAUDE.md \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')

  if [[ "$EXISTING_DATE" < "$TEMPLATE_DATE" ]]; then
    # ── 分支 2：陈旧 marker → 原地更新（成对栅栏块替换） ──────────
    cp CLAUDE.md CLAUDE.md.bak
    # AskUserQuestion: "检测到集成规范 policy 已过时 (${EXISTING_DATE} → ${TEMPLATE_DATE})，是否更新？"
    #   同意 → 只替换 [start marker 行 .. end marker 行] 闭区间为新内容，栅栏外文本逐字保留
    #          diff -u CLAUDE.md.bak CLAUDE.md   # 回显，只应看到 marker 块内的 diff
    #   拒绝 → 不写，还原（保留 .bak 或删除，取决于是否已写；不得已写后再回滚破坏内容）
  else
    # ── 分支 3：已是当前版本 → 跳过，零写操作（幂等回填的核心断言） ──
    : # no-op
  fi

else
  # ── 强制注入失败 → 降级为「追加 + 告警」，绝不做 in-place 替换 ──
  # 触发条件：START_COUNT/END_COUNT 不是 (0,0) 也不是 (1,1)（如 2 组 start 只配 1 组 end，
  # 或 start/end 数量不对等）——无法安全判定该替换哪一段
  cp CLAUDE.md CLAUDE.md.bak
  {
    echo
    echo "<!-- aether-init: 检测到 marker 定位歧义 (start=${START_COUNT}, end=${END_COUNT})，"
    echo "     无法安全判定应替换哪一段，已降级为追加 + 告警，原内容未被修改，"
    echo "     请人工核对并清理重复/孤立的 marker 后重跑 aether-init 完成收敛。 -->"
    echo
    cat "${CLAUDE_PLUGIN_ROOT}/skills/aether-init/references/integration-policy-rules.md"
  } >> CLAUDE.md
  # 明确提示用户：这是降级路径，不是正常流程
fi
```

> 以上为判定逻辑的示意脚本，Claude 执行 `aether-init` 时应通过 Read/Edit/Write/
> AskUserQuestion 工具完成等价语义，而非真的调用一个外部 bash 脚本。

### 强制注入失败 → 降级规则（绝不静默覆盖 / 绝不破坏性截断）

任何"无法安全判定应该替换哪一段"的情形（典型如：文件中出现 2 组 start marker 却只有
1 组 end marker；start/end 数量不相等；正则捕获到的日期戳格式异常），**必须**：

1. 先 `cp CLAUDE.md CLAUDE.md.bak`（即使最终走追加路径，也要留痕）。
2. **不**尝试 in-place 替换（歧义状态下没有安全的替换目标）。
3. 降级为**追加**：在 EOF 加一行说明性 HTML 注释（解释降级原因）+ 一组完整合法的新
   marker 块（当前日期戳）。
4. 原文件已有内容（包括造成歧义的那些孤立/重复 marker 片段）**一律保留，不做任何
   删除或截断** —— 尤其禁止"先 truncate 整个文件再重写"这类实现方式，那在写入过程
   中途失败时会产生比原问题更糟的数据丢失。
5. 向用户输出明确的降级告警（这是异常路径，不是正常成功路径），提示人工核对清理。

fixture `06-degrade-ambiguous-start.{before,after}.md` 是该降级路径的具体样例。

### 幂等性保证（支撑 C1 老项目回填）

C1 老项目回填的核心要求是**可重跑**：同一项目对同一版本的 `integration-policy-rules.md`
重复执行 `aether-init` 的注入检测，不应产生重复 marker 段、不应改写非 marker 区域的
用户内容。三条分支已合起来保证这点：

- 分支 3（当前版本已存在）→ 零写操作，重跑与不重跑等价（幂等）。
- 分支 2（陈旧版本已存在）→ 只替换栅栏内内容，且替换后日期戳与模板一致，下次重跑
  会自然落入分支 3。
- 分支 1a/1b（无 marker）→ 写入一组完整合法 marker 后，下次重跑同样落入分支 3。

唯一不满足"零副作用重跑"的路径是强制失败降级（歧义态），这是**预期行为**——歧义
本身就代表文件处于需要人工介入的状态，降级追加是让状态朝"存在至少一组合法 marker"
收敛，而不是在原地反复报错卡死流程。

### Fixture（C1↔C2 契约往返验证的权威输入）

四分支 + 三类边界/复合场景的完整样例落盘于
[`fixtures/integration-policy/`](fixtures/integration-policy/README.md)，供本流程自检，
也是 `aether doctor claude_md_integration_policy_present`（TASK-009, Aether #245 C2）
Go 测试的**权威 fixture 输入**（而非该 check 自行手造复刻同一 marker 契约 ——
detailed-tasks.yaml TASK-005/TASK-009 post_planning R2 Critical 修正 "C1↔C2 契约往返验证"）：

| Fixture | 场景 |
|---|---|
| `01a-create-new.after.md` | 分支 1a：无 CLAUDE.md → 创建 |
| `01b-append-existing.{before,after}.md` | 分支 1b：有 CLAUDE.md 无 marker → consent gate + append |
| `02-update-stale.{before,after}.md` | 分支 2：陈旧 marker → 原地替换，栅栏外内容不动 |
| `03-noop-current.md` | 分支 3：已是当前版本 → 零写操作（幂等） |
| `04-coexist-ci-then-integration.{before,after}.md` | CI-policy 块在前 + integration-policy 块在后共存 → 只更新后者，前者 0-diff |
| `05-coexist-integration-then-ci.{before,after}.md` | 顺序颠倒（验证"任意顺序共存"） |
| `06-degrade-ambiguous-start.{before,after}.md` | 强制注入失败 → 降级为追加 + 告警 |
| `07-incomplete-start-only.md` | marker 边界：只有 start 无 end，且全文无任何完整配对 |
| `08-legacy-ci-policy-only.md` | marker 边界：只有旧 `aether-ci-policy`，精确匹配须判定"无新 marker" |

**CI-policy 0-diff 校验**：`04`/`05` 两组 fixture 的 before/after 中，CI-policy 块
（`<!-- aether-ci-policy -->` 起始的整段）逐字节相同，用于证明本节新增逻辑没有触碰
旧机制（回应"不 retrofit"决策）。
