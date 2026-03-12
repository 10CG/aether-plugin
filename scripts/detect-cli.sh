#!/bin/bash
#
# Aether CLI Detection Script
# 用于检测 aether CLI 是否已安装并返回其路径
#
# 用法:
#   source scripts/detect-cli.sh
#   CLI_PATH=$(detect_aether_cli)
#
#   # 或直接执行检测
#   ./scripts/detect-cli.sh
#
# 返回值:
#   0 - CLI 已找到
#   1 - CLI 未找到
#
# 环境变量:
#   AETHER_CLI - 手动指定 CLI 路径（可选）
#

set -e

# CLI 最低版本要求
CLI_MIN_VERSION="${CLI_MIN_VERSION:-0.7.0}"
CLI_INSTALL_DIR="$HOME/.aether"

# Forgejo Release API
RELEASE_API="https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest"

# ============================================
# detect_cf_access_token - 检测 Cloudflare Access Token
# ============================================
detect_cf_access_token() {
    local token=""

    # 1. 检查环境变量 (优先级从高到低)
    for var in CF_ACCESS_TOKEN CLOUDFLARE_ACCESS_TOKEN CF_AUTHORIZATION; do
        if [ -n "${!var}" ]; then
            echo "${!var}"
            return 0
        fi
    done

    # 2. 检查配置文件
    for file in ~/.cloudflare/access-token ~/.cfaccess ~/.config/cloudflare/access-token; do
        if [ -f "$file" ] && [ -r "$file" ]; then
            token=$(cat "$file" 2>/dev/null | tr -d '[:space:]')
            if [ -n "$token" ]; then
                echo "$token"
                return 0
            fi
        fi
    done

    return 1
}

# ============================================
# fetch_release_with_cf_auth - 使用 CF Token 获取 Release 信息
# ============================================
fetch_release_with_cf_auth() {
    local binary_name="$1"
    local cf_token

    cf_token=$(detect_cf_access_token) || {
        echo "NO_CF_TOKEN"
        return 1
    }

    # 使用 CF Token 认证请求
    local response
    response=$(curl -s -H "Authorization: Bearer $cf_token" \
        -H "Cookie: CF_Authorization=$cf_token" \
        "$RELEASE_API" 2>/dev/null)

    # 检查是否成功获取 (不是 302 重定向)
    if echo "$response" | grep -q '"browser_download_url"'; then
        # 提取下载 URL
        local download_url
        download_url=$(echo "$response" | grep -o "\"browser_download_url\":\"[^\"]*${binary_name}[^\"]*\"" | \
            head -1 | sed 's/.*"browser_download_url":"\([^"]*\)".*/\1/')
        echo "$download_url"
        return 0
    fi

    echo "CF_AUTH_FAILED"
    return 1
}

# ============================================
# check_cf_access_required - 检查是否需要 CF Access 认证
# ============================================
check_cf_access_required() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" "$RELEASE_API" 2>/dev/null)

    # 302 表示需要重定向到认证页
    if [ "$response" = "302" ] || [ "$response" = "401" ]; then
        return 0  # 需要 CF 认证
    fi
    return 1  # 不需要认证
}

# ============================================
# print_cf_token_guidance - 打印 CF Token 配置引导
# ============================================
print_cf_token_guidance() {
    cat << 'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  Forgejo API 需要 Cloudflare Access 认证
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

检测到 Forgejo 部署在 Cloudflare Access 保护后面。
请配置 CF Access Token 后重试：

▸ 方法 1: 环境变量（推荐）
  export CF_ACCESS_TOKEN="your-token-here"

▸ 方法 2: 配置文件
  echo "your-token-here" > ~/.cfaccess
  chmod 600 ~/.cfaccess

▸ 如何获取 Token:
  1. 在浏览器中访问 https://forgejo.10cg.pub 并完成 CF 认证
  2. 打开开发者工具 (F12) → Application → Cookies
  3. 找到并复制 CF_Authorization cookie 值

▸ 配置后重试:
  /aether:doctor

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

或者使用备选安装方案:
  - 从 GitHub releases 下载（如果已同步）
  - 从源码构建（需要 Go 环境）

EOF
}

# ============================================
# detect_aether_cli - 检测 aether CLI 路径
# ============================================
detect_aether_cli() {
    local cli=""

    # 1. 环境变量优先
    if [ -n "$AETHER_CLI" ] && [ -x "$AETHER_CLI" ]; then
        echo "$AETHER_CLI"
        return 0
    fi

    # 2. PATH 中查找
    if command -v aether &> /dev/null; then
        command -v aether
        return 0
    fi

    # 3. ~/.aether/ 目录 (Linux/macOS)
    cli="$CLI_INSTALL_DIR/aether"
    if [ -f "$cli" ] && [ -x "$cli" ]; then
        echo "$cli"
        return 0
    fi

    # 4. Windows (Git Bash / MSYS / Cygwin)
    cli="$CLI_INSTALL_DIR/aether.exe"
    if [ -f "$cli" ]; then
        echo "$cli"
        return 0
    fi

    # 5. Windows 用户目录
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        cli="$USERPROFILE/.aether/aether.exe"
        if [ -f "$cli" ]; then
            echo "$cli"
            return 0
        fi
    fi

    return 1
}

# ============================================
# get_cli_version - 获取 CLI 版本
# ============================================
get_cli_version() {
    local cli="$1"
    if [ -z "$cli" ]; then
        cli=$(detect_aether_cli) || return 1
    fi

    "$cli" version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown"
}

# ============================================
# check_cli_version - 检查版本是否满足要求
# ============================================
check_cli_version() {
    local current="$1"
    local required="${2:-$CLI_MIN_VERSION}"

    # 简单版本比较 (假设格式: MAJOR.MINOR.PATCH)
    local IFS='.'
    read -ra cur <<< "$current"
    read -ra req <<< "$required"

    for i in "${!req[@]}"; do
        if (( ${cur[i]:-0} < ${req[i]:-0} )); then
            return 1
        elif (( ${cur[i]:-0} > ${req[i]:-0} )); then
            return 0
        fi
    done

    return 0
}

# ============================================
# print_install_guidance - 打印安装引导
# ============================================
print_install_guidance() {
    cat << 'EOF'
❌ aether CLI 未检测到

请运行以下命令安装:
/aether:doctor

或手动安装:

Linux/macOS:
  mkdir -p ~/.aether
  curl -sL https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest | \
    jq -r '.assets[] | select(.name | test("aether-(linux|darwin)")) | .browser_download_url' | \
    head -1 | xargs curl -sL -o ~/.aether/aether
  chmod +x ~/.aether/aether

Windows (PowerShell):
  $dir = "$env:USERPROFILE\.aether"
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $url = (Invoke-RestMethod https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest).assets | \
    Where-Object { $_.name -like "aether-windows*" } | Select-Object -First 1 -ExpandProperty browser_download_url
  Invoke-WebRequest -Uri $url -OutFile "$dir\aether.exe"

安装完成后，运行以下命令验证:
  ~/.aether/aether version
EOF
}

# ============================================
# 主入口 - 直接执行时运行
# ============================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "🔍 检测 aether CLI..."

    if CLI=$(detect_aether_cli); then
        VERSION=$(get_cli_version "$CLI")

        echo "✅ aether CLI 已找到"
        echo "   路径: $CLI"
        echo "   版本: $VERSION"

        if ! check_cli_version "$VERSION" "$CLI_MIN_VERSION"; then
            echo ""
            echo "⚠️  版本过低 (当前: $VERSION, 要求: >= $CLI_MIN_VERSION)"
            echo "   请运行 /aether:doctor 更新 CLI"
            exit 1
        fi

        exit 0
    else
        print_install_guidance
        exit 1
    fi
fi
