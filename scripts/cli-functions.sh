#!/bin/bash
#
# Aether CLI 快速检测函数
# 用于在 skills 中 source 引用
#
# 用法:
#   source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
#   require_aether_cli  # 如果 CLI 未安装，打印引导并退出
#

# 检测 CLI 路径
detect_aether_cli() {
    # 1. 环境变量
    [ -n "$AETHER_CLI" ] && [ -x "$AETHER_CLI" ] && echo "$AETHER_CLI" && return 0

    # 2. PATH
    command -v aether 2>/dev/null && return 0

    # 3. ~/.aether/
    local cli="$HOME/.aether/aether"
    [ -f "$cli" ] && [ -x "$cli" ] && echo "$cli" && return 0

    # 4. Windows
    [ -f "$cli.exe" ] && echo "$cli.exe" && return 0

    return 1
}

# 检测并要求 CLI（用于需要 CLI 的 skills）
require_aether_cli() {
    if ! detect_aether_cli > /dev/null 2>&1; then
        cat << 'EOF'
❌ aether CLI 未检测到

请运行以下命令安装:
/aether:doctor

安装完成后重试此命令。
EOF
        return 1
    fi
}

# 获取 CLI 路径（静默模式）
get_aether_cli() {
    detect_aether_cli 2>/dev/null || echo ""
}
