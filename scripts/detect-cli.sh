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
# detect_cf_service_token - 检测 CF Access Service Token (aria 规范)
# ============================================
# 返回格式: "CLIENT_ID:CLIENT_SECRET" 或空
detect_cf_service_token() {
    local client_id="${CF_ACCESS_CLIENT_ID:-}"
    local client_secret="${CF_ACCESS_CLIENT_SECRET:-}"

    if [ -n "$client_id" ] && [ -n "$client_secret" ]; then
        echo "${client_id}:${client_secret}"
        return 0
    fi

    return 1
}

# ============================================
# detect_cf_access_token - 检测 Cloudflare Access User Token
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
# detect_cf_auth - 统一 CF 认证检测 (优先 Service Token)
# ============================================
# 返回格式: "service:CLIENT_ID:CLIENT_SECRET" 或 "user:TOKEN"
detect_cf_auth() {
    # 1. 优先检测 Service Token (aria 规范)
    local service_token
    if service_token=$(detect_cf_service_token); then
        echo "service:${service_token}"
        return 0
    fi

    # 2. 检测 User Token
    local user_token
    if user_token=$(detect_cf_access_token); then
        echo "user:${user_token}"
        return 0
    fi

    return 1
}

# ============================================
# fetch_release_with_cf_auth - 使用 CF 认证获取 Release 信息
# 支持双重认证: CF Token (绕过 Cloudflare) + Forgejo Token (API 认证)
# ============================================
fetch_release_with_cf_auth() {
    local binary_name="$1"
    local cf_auth
    local curl_opts=""

    # 1. 获取 CF 认证信息 (优先 Service Token)
    cf_auth=$(detect_cf_auth) || {
        echo "NO_CF_TOKEN"
        return 1
    }

    # 2. 根据 CF 认证类型构建 headers
    local auth_type="${cf_auth%%:*}"
    local auth_data="${cf_auth#*:}"

    case "$auth_type" in
        service)
            # aria 规范: Service Token 方式
            local client_id="${auth_data%%:*}"
            local client_secret="${auth_data#*:}"
            curl_opts="-H 'CF-Access-Client-Id: $client_id' -H 'CF-Access-Client-Secret: $client_secret'"
            ;;
        user)
            # User Token 方式 (Cookie + Bearer)
            curl_opts="-H 'Authorization: Bearer $auth_data' -H 'Cookie: CF_Authorization=$auth_data'"
            ;;
        *)
            echo "UNKNOWN_AUTH_TYPE"
            return 1
            ;;
    esac

    # 3. 添加 Forgejo API Token (如果配置了)
    # Forgejo API 需要 CF Token (绕过 Cloudflare) + Forgejo Token (API 认证)
    if [ -n "${FORGEJO_TOKEN:-}" ]; then
        curl_opts="$curl_opts -H 'Authorization: token ${FORGEJO_TOKEN}'"
    fi

    # 4. 执行请求
    local response
    eval "response=\$(curl -s $curl_opts \"$RELEASE_API\" 2>/dev/null)"

    # 5. 检查是否成功获取
    if echo "$response" | grep -q '"browser_download_url"'; then
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
请配置 CF Access 凭据后重试：

▸ 方法 1: Service Token（推荐，aria 规范）
  export CF_ACCESS_CLIENT_ID="your-client-id"
  export CF_ACCESS_CLIENT_SECRET="your-client-secret"

  获取方式:
  1. 登录 Cloudflare Zero Trust Dashboard
  2. Access → Service Auth → Service Tokens
  3. 创建 Service Token 并复制 Client ID 和 Secret

▸ 方法 2: User Session Token
  export CF_ACCESS_TOKEN="your-token-here"
  # 或
  echo "your-token-here" > ~/.cfaccess && chmod 600 ~/.cfaccess

  获取方式:
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
    local _os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local _arch=$(uname -m)
    case "$_arch" in x86_64|amd64) _arch="amd64" ;; aarch64|arm64) _arch="arm64" ;; esac
    local _bin="aether-${_os}-${_arch}"

    cat << EOF
❌ aether CLI 未检测到

请运行以下命令安装:
/aether:doctor

或手动安装 (检测到平台: ${_os}/${_arch}):

  mkdir -p ~/.aether
  curl -fsSL "https://github.com/10CG/aether-cli/releases/latest/download/${_bin}" \\
    -o ~/.aether/aether && chmod +x ~/.aether/aether

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
