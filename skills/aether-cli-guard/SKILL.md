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

1. 从环境变量 `CLAUDE_TOOL_INPUT` 取命令；为空或不含 `aether` 时 `exit 0` 放行。
2. 依次在 PATH、`~/.aether/aether`（且可执行）、`~/.aether/aether.exe` 查找 CLI；找到即 `exit 0`。
3. 找不到时按平台打印安装引导（推荐 `/aether:aether-doctor`，或从 GitHub releases 手动下载、Forgejo 源备用），然后 `exit 1`。

> **已知问题（[#489](https://forgejo.10cg.pub/10CG/Aether/issues/489)，待修）**：Claude Code 通过 stdin 的 JSON 传入 hook 载荷，
> 脚本只读 `CLAUDE_TOOL_INPUT`、没有像同插件 `ci-watch-hook.sh` 那样回退到 stdin；且 PreToolUse 只有 exit 2 才会拦截，
> exit 1 是非阻断错误。两处任一成立，这道守卫都拦不下任何命令。

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

## 行为说明（脚本的设计意图；实际是否拦截见上方已知问题）

| 检测结果 | 脚本动作 | 输出 |
|---------|------|------|
| CLI 可用 | `exit 0` 放行 | 无 |
| CLI 未安装 / 不可执行 | 打印安装引导后 `exit 1`，意图是阻止命令 | 平台检测 + 安装命令 + 验证命令 |
| 非 aether 命令 | `exit 0` 跳过检测 | 无 |
