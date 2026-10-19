#!/bin/bash
#
# Aether CLI PreToolUse Hook
# 在执行 aether 命令前自动检测 CLI 是否已安装 (#489 修复)
#
# 输入 (两种形态, 与 ci-watch-hook.sh 同构):
#   - stdin JSON: Claude Code 的 hook 载荷, 命令在 .tool_input.command
#   - 环境变量 CLAUDE_TOOL_INPUT (旧形态, 兼容保留)
#
# 拦截语义: PreToolUse 只有 exit 2 (或 JSON deny 决定) 才阻止工具调用;
# exit 1 是非阻断错误, 命令照跑 —— 引导文字必须走 stderr (exit 2 时
# Claude 看到的是 stderr)。
#

set -e

# 获取要执行的命令: env 优先, 空则读 stdin JSON 的 tool_input.command
COMMAND="${CLAUDE_TOOL_INPUT:-}"

if [ -z "$COMMAND" ]; then
    INPUT=$(cat 2>/dev/null || true)
    if [ -n "$INPUT" ]; then
        COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    fi
fi

# 如果不是 Bash 工具调用或没有命令，直接放行
if [ -z "$COMMAND" ]; then
    exit 0
fi

# 检查命令是否包含 aether
if [[ "$COMMAND" != *"aether"* ]]; then
    exit 0  # 不是 aether 命令，放行
fi

# 检测 CLI
detect_cli() {
    # 1. PATH 中
    if command -v aether &> /dev/null; then
        return 0
    fi

    # 2. ~/.aether/
    local cli="$HOME/.aether/aether"
    if [ -f "$cli" ] && [ -x "$cli" ]; then
        return 0
    fi

    # 3. Windows
    if [ -f "$cli.exe" ]; then
        return 0
    fi

    return 1
}

# 如果 CLI 未安装，阻止并显示引导
if ! detect_cli; then
    # Detect platform for install guidance
    _OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    _ARCH=$(uname -m)
    case "$_ARCH" in x86_64|amd64) _ARCH="amd64" ;; aarch64|arm64) _ARCH="arm64" ;; esac
    _BIN="aether-${_OS}-${_ARCH}"

    cat >&2 << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Aether CLI 未检测到
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

您正在尝试执行 aether 命令，但 CLI 未安装。

▸ 推荐: 运行 /aether:aether-doctor 自动安装

▸ 或手动安装 (检测到平台: ${_OS}/${_ARCH}):

  mkdir -p ~/.aether
  curl -sL "https://github.com/10CG/aether-cli/releases/latest/download/${_BIN}" \\
    -o ~/.aether/aether && chmod +x ~/.aether/aether

  如果上述地址不可用，使用 Forgejo 源 (需要 CF Token):
  export CF_ACCESS_TOKEN="your-token"
  curl -s -H "Authorization: Bearer \$CF_ACCESS_TOKEN" \\
    "https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest" | \\
    grep -o '"browser_download_url":"[^"]*${_BIN}[^"]*"' | \\
    head -1 | cut -d'"' -f4 | xargs curl -sL -o ~/.aether/aether
  chmod +x ~/.aether/aether

▸ 安装后验证:
  ~/.aether/aether version

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    exit 2  # PreToolUse 的阻断退出码 (exit 1 不拦截, 命令照跑)
fi

exit 0  # CLI 已安装，放行
