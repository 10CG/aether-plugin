---
name: aether-cli-guard
description: |
  CLI 命令执行前的自动检测 Hook 的说明文档。在执行 aether CLI 命令前检测 CLI 是否已安装，
  未安装时给出安装引导。

  PreToolUse Hook 直接执行 scripts/cli-guard-hook.sh，不会加载本文件；本文件不需要用户调用。
disable-model-invocation: true
user-invocable: false
allowed-tools: Bash
---

# Aether CLI Guard (Hook Skill)

> 本文件只是 hook 的说明：`disable-model-invocation: true` + `user-invocable: false`，任何东西都不会加载它。
> 行为以 `scripts/cli-guard-hook.sh` 为准。

## 触发条件

hooks.json 的 PreToolUse 以 `matcher: "Bash"` 匹配**所有** Bash 调用并执行脚本；脚本自己判断命令里是否含 `aether`：

```bash
# 会进入检测的命令示例
aether volume list
aether init
~/.aether/aether version
```

## 脚本行为

1. 取要检测的命令：优先环境变量 `CLAUDE_TOOL_INPUT`，为空时读 stdin JSON 的 `.tool_input.command`（Claude Code 的 hook 载荷，与 `ci-watch-hook.sh` 同构）；取不到或不含 `aether` 时 `exit 0` 放行。
2. 依次在 PATH、`~/.aether/aether`（且可执行）、`~/.aether/aether.exe` 查找 CLI；找到即 `exit 0`。
3. 找不到时把按平台生成的安装引导（推荐 `/aether:aether-doctor`，或从 GitHub releases 手动下载、Forgejo 源备用）打印到 **stderr**，然后 `exit 2` —— PreToolUse 只有 exit 2（或 JSON deny 决定）才阻断工具调用，exit 2 时 Claude 看到的正是 stderr 上的引导文字。

> stdin JSON 与 exit 2 阻断语义自插件 v1.12.17 起接通（[#489](https://forgejo.10cg.pub/10CG/Aether/issues/489)）；
> 更早版本只读 `CLAUDE_TOOL_INPUT` 且以 `exit 1` 结束，两处任一都让守卫拦不下任何命令。

## Hook 配置

`.claude-plugin/hooks.json` 中的实际配置：

```json
"PreToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      {
        "type": "command",
        "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/cli-guard-hook.sh",
        "timeout": 10
      }
    ]
  }
]
```

## 行为说明

| 检测结果 | 脚本动作 | 输出 |
|---------|------|------|
| CLI 可用 | `exit 0` 放行 | 无 |
| CLI 未安装 / 不可执行 | 安装引导打到 stderr 后 `exit 2`，阻断命令 | 平台检测 + 安装命令 + 验证命令 |
| 非 aether 命令 | `exit 0` 跳过检测 | 无 |
