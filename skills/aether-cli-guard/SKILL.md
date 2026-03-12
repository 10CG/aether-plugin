---
name: aether-cli-guard
description: |
  CLI 命令执行前的自动检测 Hook。在执行 aether CLI 命令前检测 CLI 是否已安装。
  如果未安装，阻止命令执行并引导用户安装。

  此 Skill 由 PreToolUse Hook 自动触发，不需要用户直接调用。
disable-model-invocation: true
user-invocable: false
allowed-tools: Bash
---

# Aether CLI Guard (Hook Skill)

> **版本**: 1.0.0 | **类型**: Hook Skill

## 触发条件

当用户执行的 Bash 命令包含 `aether` 关键字时自动触发：

```bash
# 会触发检测的命令示例
aether volume list
aether init
~/.aether/aether version
```

## 检测逻辑

```bash
#!/bin/bash
# 检测 CLI 是否可用

# 1. 检查命令是否包含 aether
if [[ "$COMMAND" != *"aether"* ]]; then
    exit 0  # 不是 aether 命令，放行
fi

# 2. 检查 CLI 是否存在
CLI_FOUND=false

if command -v aether &> /dev/null; then
    CLI_FOUND=true
elif [ -f "$HOME/.aether/aether" ] && [ -x "$HOME/.aether/aether" ]; then
    CLI_FOUND=true
elif [ -f "$HOME/.aether/aether.exe" ]; then
    CLI_FOUND=true
fi

# 3. 如果未找到，输出引导信息并阻止
if [ "$CLI_FOUND" = false ]; then
    echo ""
    echo "❌ 检测到 aether 命令，但 CLI 未安装"
    echo ""
    echo "请运行以下命令安装:"
    echo "  /aether:doctor"
    echo ""
    echo "或手动安装:"
    echo "  curl -sL https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest | \\"
    echo "    jq -r '.assets[] | select(.name | test(\"aether-linux\")) | .browser_download_url' | \\"
    echo "    head -1 | xargs curl -sL -o ~/.aether/aether && chmod +x ~/.aether/aether"
    echo ""
    exit 1  # 阻止命令执行
fi

exit 0  # CLI 已安装，放行
```

## Hook 配置

在 `hooks.json` 中配置：

```json
{
  "hooks": {
    "PreToolUse": {
      "skill": "aether:aether-cli-guard",
      "enabled": true,
      "filter": {
        "tools": ["Bash"],
        "patterns": ["aether"]
      },
      "description": "执行 aether 命令前检测 CLI"
    }
  }
}
```

## 行为说明

| 检测结果 | 行为 |
|---------|------|
| CLI 已安装 | 放行，命令正常执行 |
| CLI 未安装 | 阻止，显示安装引导 |
| 非 aether 命令 | 跳过检测，放行 |

---

**Skill 版本**: 1.0.0
**最后更新**: 2026-03-12
