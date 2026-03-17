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

# 2. 查找 CLI 二进制文件
CLI_PATH=""
if command -v aether &> /dev/null; then
    CLI_PATH="$(command -v aether)"
elif [ -f "$HOME/.aether/aether" ]; then
    CLI_PATH="$HOME/.aether/aether"
elif [ -f "$HOME/.aether/aether.exe" ]; then
    CLI_PATH="$HOME/.aether/aether.exe"
fi

# 3. 检测结果处理
if [ -z "$CLI_PATH" ]; then
    echo "❌ 检测到 aether 命令，但 CLI 未安装"
    echo "请运行 /aether:doctor 安装，或手动安装:"
    echo "  curl -sL https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest | \\"
    echo "    jq -r '.assets[] | select(.name | test(\"aether-linux\")) | .browser_download_url' | \\"
    echo "    head -1 | xargs curl -sL -o ~/.aether/aether && chmod +x ~/.aether/aether"
    echo "⚠️  安装提示: 如网络不通，请检查 DNS 或使用代理; 下载后请用 file 命令验证为 ELF 二进制"
    exit 1
elif [ ! -x "$CLI_PATH" ]; then
    echo "❌ CLI 存在但不可执行: $CLI_PATH"
    echo "请运行: chmod +x $CLI_PATH"
    exit 1
elif ! "$CLI_PATH" version &> /dev/null; then
    echo "❌ CLI 二进制可能损坏: $CLI_PATH"
    echo "请删除后重新安装: rm $CLI_PATH && /aether:doctor"
    exit 1
fi

exit 0  # CLI 可用，放行
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

| 检测结果 | 行为 | 输出 |
|---------|------|------|
| CLI 可用 | `exit 0` 放行，命令正常执行 | 无（透传至原命令） |
| CLI 未安装 | `exit 1` 阻止，显示安装引导 | 安装命令 + 网络/验证提示 |
| 存在但不可执行 | `exit 1` 阻止，提示 chmod | `chmod +x` 修复命令 |
| 二进制损坏 | `exit 1` 阻止，提示重装 | 删除 + 重装命令 |
| 非 aether 命令 | `exit 0` 跳过检测，放行 | 无 |

---

**Skill 版本**: 1.0.0
**最后更新**: 2026-03-12
