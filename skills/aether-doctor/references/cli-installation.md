# CLI 安装流程

## 安装信息

| 项目 | 值 |
|------|-----|
| 安装目录 | `~/.aether/` |
| 发布源 | `https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases` |
| Tag 格式 | `aether-cli/v{VERSION}` |
| 认证方式 | Cloudflare Access (可选) |

## Cloudflare Access Token 检测

Forgejo 可能部署在 Cloudflare Access 后面，需要认证才能访问 API。

### 检测逻辑

```bash
detect_cf_access_token() {
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
      cat "$file" | tr -d '[:space:]'
      return 0
    fi
  done

  return 1
}
```

### 配置 CF Token

**方法 1: 环境变量（推荐）**
```bash
export CF_ACCESS_TOKEN="your-token-here"

# 添加到 shell 配置文件
echo 'export CF_ACCESS_TOKEN="your-token"' >> ~/.bashrc
```

**方法 2: 配置文件**
```bash
echo "your-token-here" > ~/.cfaccess
chmod 600 ~/.cfaccess
```

**获取 Token 步骤:**
1. 在浏览器中访问 https://forgejo.10cg.pub 并完成 CF 认证
2. 打开开发者工具 (F12) → Application → Cookies
3. 找到并复制 `CF_Authorization` cookie 值

### 使用 Token 认证

```bash
# 检测是否需要 CF 认证
if curl -s -o /dev/null -w "%{http_code}" "$RELEASE_API" | grep -q "302"; then
  # 需要 CF 认证
  CF_TOKEN=$(detect_cf_access_token) || {
    echo "❌ 需要 Cloudflare Access Token"
    echo "请配置 CF_ACCESS_TOKEN 环境变量或 ~/.cfaccess 文件"
    exit 1
  }

  # 使用 Token 请求
  curl -s -H "Authorization: Bearer $CF_TOKEN" \
        -H "Cookie: CF_Authorization=$CF_TOKEN" \
        "$RELEASE_API"
fi
```

## CLI 检测逻辑

```bash
detect_aether_cli() {
  # 1. 环境变量
  if [ -n "$AETHER_CLI" ] && [ -x "$AETHER_CLI" ]; then
    echo "$AETHER_CLI"
    return 0
  fi

  # 2. 检查 PATH
  if command -v aether &> /dev/null; then
    echo "aether"
    return 0
  fi

  # 3. 检查 ~/.aether/aether
  local cli="$HOME/.aether/aether"
  if [ -f "$cli" ] && [ -x "$cli" ]; then
    echo "$cli"
    return 0
  fi

  # 4. Windows .exe
  if [ "$OSTYPE" = "msys" ] || [ "$OSTYPE" = "cygwin" ]; then
    cli="$HOME/.aether/aether.exe"
    if [ -f "$cli" ] && [ -x "$cli" ]; then
      echo "$cli"
      return 0
    fi
  fi

  return 1
}
```

## 版本兼容性

| Plugin Version | CLI Min | CLI Recommended |
|---------------|---------|-----------------|
| 0.8.x         | 0.7.0   | 0.7.0           |
| 0.9.x         | 0.8.0   | 0.8.0           |

## 方案 A: 自动安装（含 CF 认证）

```bash
RELEASE_API="https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest"

# 0. 检测 CF Access 并获取 Token
check_cf_access_required() {
  local code=$(curl -s -o /dev/null -w "%{http_code}" "$RELEASE_API")
  [ "$code" = "302" ] || [ "$code" = "401" ]
}

# 1. 检测系统
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case $ARCH in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac
EXT=""
[ "$OS" = "windows" ] && EXT=".exe"

# 2. 构建请求
BINARY_NAME="aether-${OS}-${ARCH}${EXT}"
CURL_OPTS="-s"

# 3. 检查是否需要 CF 认证
if check_cf_access_required; then
  CF_TOKEN=$(detect_cf_access_token) || {
    echo "❌ 需要 Cloudflare Access Token"
    echo ""
    echo "请先配置 CF Token:"
    echo "  export CF_ACCESS_TOKEN=\"your-token\""
    echo ""
    echo "获取方法:"
    echo "  1. 浏览器访问 https://forgejo.10cg.pub 并完成认证"
    echo "  2. F12 → Application → Cookies → CF_Authorization"
    exit 1
  }
  CURL_OPTS="$CURL_OPTS -H \"Authorization: Bearer $CF_TOKEN\" -H \"Cookie: CF_Authorization=$CF_TOKEN\""
fi

# 4. 获取下载 URL
DOWNLOAD_URL=$(curl $CURL_OPTS "$RELEASE_API" | jq -r ".assets[] | select(.name == \"$BINARY_NAME\") | .browser_download_url" | head -n1)

# 5. 安装
mkdir -p "$HOME/.aether"
curl -sL "$DOWNLOAD_URL" -o "$HOME/.aether/aether${EXT}"
chmod +x "$HOME/.aether/aether${EXT}"

# 6. 验证
"$HOME/.aether/aether${EXT}" version
```

## 方案 B: 从源码构建

```bash
mkdir -p "$HOME/.aether"
git clone https://forgejo.10cg.pub/10CG/aether-cli.git /tmp/aether-cli
cd /tmp/aether-cli
go build -ldflags="-s -w -X main.Version=$(cat VERSION)" -o aether .
mv aether "$HOME/.aether/aether"
rm -rf /tmp/aether-cli
"$HOME/.aether/aether" version
```

## 方案 C: 手动安装

### Linux (amd64)
```bash
mkdir -p ~/.aether
# 如果有 CF Token:
curl -s -H "Authorization: Bearer $CF_ACCESS_TOKEN" \
  "https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest" | \
  jq -r '.assets[] | select(.name == "aether-linux-amd64") | .browser_download_url' | \
  xargs curl -sL -o ~/.aether/aether
chmod +x ~/.aether/aether
~/.aether/aether version
```

### macOS (arm64)
```bash
mkdir -p ~/.aether
curl -s -H "Authorization: Bearer $CF_ACCESS_TOKEN" \
  "https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest" | \
  jq -r '.assets[] | select(.name == "aether-darwin-arm64") | .browser_download_url' | \
  xargs curl -sL -o ~/.aether/aether
chmod +x ~/.aether/aether
~/.aether/aether version
```

### Windows (PowerShell)
```powershell
$aetherDir = "$env:USERPROFILE\.aether"
New-Item -ItemType Directory -Path $aetherDir -Force | Out-Null

# 如果有 CF Token:
$headers = @{ "Authorization" = "Bearer $env:CF_ACCESS_TOKEN" }
$response = Invoke-RestMethod -Uri "https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest" -Headers $headers
$downloadUrl = $response.assets | Where-Object { $_.name -eq "aether-windows-amd64.exe" } | Select-Object -First 1 -ExpandProperty browser_download_url
Invoke-WebRequest -Uri $downloadUrl -OutFile "$aetherDir\aether.exe"
& "$aetherDir\aether.exe" version
```

## 支持的平台

| 平台 | 架构 | 二进制名称 | 安装路径 |
|------|------|-----------|---------|
| Linux | amd64 | `aether-linux-amd64` | `~/.aether/aether` |
| Linux | arm64 | `aether-linux-arm64` | `~/.aether/aether` |
| macOS | amd64 | `aether-darwin-amd64` | `~/.aether/aether` |
| macOS | arm64 | `aether-darwin-arm64` | `~/.aether/aether` |
| Windows | amd64 | `aether-windows-amd64.exe` | `%USERPROFILE%\.aether\aether.exe` |

## 常见问题

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `command not found` | CLI 未安装 | 执行安装流程 |
| `permission denied` | 执行权限问题 | `chmod +x ~/.aether/aether` |
| 版本过低 | CLI 需要更新 | 执行升级流程 |
| 302 重定向 | 需要 CF 认证 | 配置 `CF_ACCESS_TOKEN` |
| CF Token 无效 | Token 过期或错误 | 重新获取 Token |
