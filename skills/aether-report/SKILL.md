---
name: aether-report
description: |
  向 Aether 维护团队报告 Bug 或提交功能建议。自动收集环境信息，
  自动路由到 Forgejo（内部用户）或 GitHub（外部用户）。

  使用场景："报告 bug"、"report an issue"、"提交功能建议"、
  "aether 有个问题想反馈"、"feature request"、"提 issue"、
  "反馈问题"、"report bug to aether"
argument-hint: "[bug|feature|question]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
dependencies:
  cli:
    required: false
    note: "CLI version is auto-detected for context, not required"
---

# Aether Issue 报告 (aether-report)

**版本**: 1.1.0 | **优先级**: P1

帮助用户向 Aether 维护团队报告 Bug、提交功能建议或提问。自动收集环境信息并路由到正确的仓库。

**自动路由逻辑（核心差异点）：**

```
forgejo CLI 可用 + FORGEJO_TOKEN? → Forgejo (内部用户优先)
GITHUB_TOKEN?                    → GitHub API
无 token                         → GitHub Pre-filled URL
```

**目标仓库：**

- Forgejo: `https://forgejo.10cg.pub/10CG/Aether`（内部，通过 `forgejo` CLI wrapper）
- GitHub: `https://github.com/10CG/aether-plugin`（外部，公开）

---

## 执行流程

### Step 1: 分类 Issue 类型

解析用户调用参数：

```
/aether:report bug      → Bug Report
/aether:report feature  → Feature Request
/aether:report question → Question
/aether:report          → 从用户的自然语言推断，或用 AskUserQuestion 询问
```

标签映射：bug → `bug` | feature → `enhancement` | question → `question`

### Step 2: 自动收集环境信息

```bash
CLI_VERSION=$(aether version 2>/dev/null || echo "未安装")
PLUGIN_VERSION=$(cat "${CLAUDE_PLUGIN_ROOT}/VERSION" 2>/dev/null || echo "unknown")
OS_INFO=$(uname -s -m 2>/dev/null || echo "unknown")
HAS_CONFIG=$( [ -f ".aether/config.yaml" ] && echo "yes" || echo "no" )
```

**安全边界 — 绝不自动收集：** config 文件内容、环境变量、SSH 配置、git 历史、源代码。

### Step 3: 交互收集用户输入

用 AskUserQuestion 收集。如果用户在初始消息中已提供足够信息，不要重复询问已知部分。

**Bug Report:** 标题 / 复现步骤 + 预期 vs 实际 / 错误输出（可选）
**Feature Request:** 标题 / 使用场景 / 建议方案（可选）
**Question:** 标题 / 详细描述

### Step 4: 组合 Issue Body

**Bug Report 模板：**

```markdown
## Bug Report

**描述**: {user_description}

**复现步骤**:
{steps}

**预期行为**: {expected}
**实际行为**: {actual}

**错误输出**:
```
{error_output}
```

## 环境信息
- Aether CLI: {cli_version}
- Aether Plugin: {plugin_version}
- OS: {os_info}
- 项目配置: {has_config}

---
*由 aether-report 自动生成*
```

**Feature Request 模板：**

```markdown
## Feature Request

**描述**: {user_description}

**使用场景**: {use_case}

**建议方案**: {proposed_solution}

## 环境信息
- Aether CLI: {cli_version}
- Aether Plugin: {plugin_version}

---
*由 aether-report 自动生成*
```

### Step 4.5: 空 body 拦截（必须）

**触发原因**: Aether issue #23 (2026-04-09 创建, 2026-05-14 因 body 空无法 triage 而关闭) 暴露的根因 — 早期第三方项目集成或自动化流程可能调用 issue submission 接口但未提供有意义内容。本步骤是硬拦截，防止此类 placeholder issue 进入 backlog。

**检查项** — 提交前必须满足全部：

1. **用户内容字段非空**:
   - Bug Report: `description` + `steps` 至少一个 ≥ 20 字符（非空白）
   - Feature Request: `description` + `use_case` 至少一个 ≥ 20 字符
   - Question: `description` ≥ 20 字符
2. **不是纯模板**: body 包含至少一处 `{user_*}` 渲染后的实际内容，不能全是模板骨架 + 环境信息
3. **Title 非空且不只是问号/省略号**: title 不为空且至少 10 字符（"a" / "?" / "..." 这种拒绝）

**拦截行为**:

```
⚠️ Issue 内容不足以让维护者 triage。

具体缺失:
  - [ ] description 字段为空（建议 ≥ 20 字符描述问题）
  - [ ] steps 字段为空（建议给至少 1 个复现步骤）

参考已 ship 的 doctor checks (heavy_node_dns_clean_upstream 等), 每个
都有: 触发现象 → 诊断路径 → 修复方法 三层信息。请补充后再提交。

[1] 重新填写  [2] 取消提交
```

用 AskUserQuestion 给用户选择。选 [1] 回 Step 3 重新收集；选 [2] 直接退出 skill。

**绝不允许的回退路径**: 即使用户三次重填仍空，也不能强行提交 — 直接退出，提示用户"明确想清楚再来"。本 skill 不创建 placeholder issue 是 #23 教训的核心约束。

### Step 5: 隐私审查（必须）

提交前，**必须**展示完整 Issue 内容给用户确认：

```
即将提交以下 Issue 到 {target_repo}:

---
标题: {title}
{full_body}
---
标签: {label} | 目标: {Forgejo 或 GitHub}

此内容将公开可见。请确认：
  1. 提交  2. 编辑后提交  3. 取消
```

使用 AskUserQuestion 获取确认。用户选择编辑时，允许修改任何内容。

### Step 6: 提交路由

```bash
ROUTE=""
# Priority 1: Forgejo (内部用户)
if command -v forgejo &>/dev/null && [ -n "${FORGEJO_TOKEN:-}" ]; then
  ROUTE="forgejo"
fi
# Priority 2: GitHub API
if [ -z "$ROUTE" ] && [ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]; then
  ROUTE="github_api"
fi
# Priority 3: GitHub Pre-filled URL
if [ -z "$ROUTE" ]; then
  ROUTE="github_url"
fi
```

**Forgejo 提交：**

```bash
forgejo POST /repos/10CG/Aether/issues -d "{
  \"title\": \"${TITLE}\",
  \"body\": \"${BODY}\"
}"
```

> ⚠️ **不要给 Forgejo 加 `labels` 字段**。Forgejo API `CreateIssueOption.labels` 是 `[]int64`（label ID 数组），跟 GitHub 的 `[]string` 不同 — 直接传 `["bug"]` 会返 HTTP 422 `json: cannot unmarshal string into Go struct field CreateIssueOption.labels of type int64`。如确需 label，先 `GET /repos/{owner}/{repo}/labels` 拿 ID 数组再传整数；否则交给维护者人工 triage 加标签（issue #138）。

**GitHub API 提交：**

```bash
TOKEN="${GITHUB_TOKEN:-$GH_TOKEN}"
curl -s -X POST \
  "https://api.github.com/repos/10CG/aether-plugin/issues" \
  -H "Authorization: token ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -d "{\"title\":\"${TITLE}\",\"body\":\"${BODY}\",\"labels\":[\"${LABEL}\"]}"
```

**GitHub Pre-filled URL（无 token 时）：**

```bash
ENCODED_TITLE=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read()))" <<< "$TITLE")
ENCODED_BODY=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read()))" <<< "$BODY")
URL="https://github.com/10CG/aether-plugin/issues/new?title=${ENCODED_TITLE}&body=${ENCODED_BODY}&labels=${LABEL}"

if [ ${#URL} -gt 7800 ]; then
  echo "Issue body too long for URL. Please paste manually:"
  echo "$BODY"
  echo "Open: https://github.com/10CG/aether-plugin/issues/new"
else
  echo "Open this URL to submit the issue:"
  echo "$URL"
fi
```

### Step 7: 输出结果

**API 提交成功：**

```
Issue 已提交
  URL:   {issue_url}
  类型:  {Bug Report / Feature Request / Question}
  目标:  {Forgejo / GitHub}
  标题:  {title}
Aether 维护团队会尽快查看。
```

**Pre-filled URL（无 token）：**

```
Issue 已准备好
请在浏览器中打开以下链接提交:
  {pre_filled_url}
提示: 设置 GITHUB_TOKEN 可直接从终端提交。
```

**提交失败：**

```
提交失败: {error}
Issue 内容已保存，请手动提交:
  https://github.com/10CG/aether-plugin/issues/new
{issue_body_for_paste}
```

---

## 与其他 Skill 的集成

- `aether-doctor` 诊断出 Aether 自身的 Bug 时，建议用户执行 `/aether:report bug`
- `aether-deploy` / `aether-rollback` 遇到非预期错误时，建议用户执行 `/aether:report`
- 用户说 "aether 有问题" 时，先判断意图：
  - 需要本地诊断 → 引导到 `/aether:doctor`
  - 需要向维护者反馈 → 使用 `/aether:report`
- Issue 提交后返回的 URL 可供用户在后续对话中引用

---

## 限制和注意事项

- Forgejo 提交需要 `forgejo` CLI + `FORGEJO_TOKEN` + Cloudflare Access 凭据
- GitHub Pre-filled URL 在无头环境（SSH、Docker）中无法自动打开浏览器，会打印 URL
- URL 长度超过 ~7800 字符时降级为打印 markdown 供手动粘贴
- 不支持附件/截图上传（GitHub API 限制）
- 所有收集的信息仅用于 Issue 内容，不会发送到第三方服务

---

**Skill 版本**: 1.1.0
**最后更新**: 2026-05-14
**维护者**: 10CG Infrastructure Team

## Changelog

- **1.1.0** (2026-05-14): 加 Step 4.5 空-body 拦截（Aether #23 教训）
- **1.0.0** (2026-03-31): 初版
