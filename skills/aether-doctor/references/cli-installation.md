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

## 方案 A: 自动安装（推荐，GitHub 镜像，无需认证）

```bash
# 1. 检测系统 (macOS/Linux/Windows 自动识别)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case $ARCH in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac
BINARY_NAME="aether-${OS}-${ARCH}"

# 2. 从 GitHub 镜像下载 (无需认证)
mkdir -p "$HOME/.aether"
curl -fsSL "https://github.com/10CG/aether-cli/releases/latest/download/${BINARY_NAME}" \
  -o "$HOME/.aether/aether"
chmod +x "$HOME/.aether/aether"

# 3. 验证
"$HOME/.aether/aether" version
```

## 方案 A2: 从 Forgejo 源安装（需 CF 认证）

```bash
RELEASE_API="https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest"

# 1. 检测系统
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case $ARCH in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac
BINARY_NAME="aether-${OS}-${ARCH}"

# 2. CF Token (Forgejo 在 Cloudflare Access 后面)
# export CF_ACCESS_TOKEN="your-token"  # 如未设置则执行:
# 浏览器访问 https://forgejo.10cg.pub → F12 → Cookies → CF_Authorization

# 3. 下载 (使用 grep 替代 jq，无额外依赖)
mkdir -p "$HOME/.aether"
DOWNLOAD_URL=$(curl -s \
  -H "Authorization: Bearer $CF_ACCESS_TOKEN" \
  -H "Cookie: CF_Authorization=$CF_ACCESS_TOKEN" \
  "$RELEASE_API" | \
  grep -o "\"browser_download_url\":\"[^\"]*${BINARY_NAME}[^\"]*\"" | \
  head -1 | cut -d'"' -f4)

curl -sL "$DOWNLOAD_URL" -o "$HOME/.aether/aether"
chmod +x "$HOME/.aether/aether"

# 4. 验证
"$HOME/.aether/aether" version
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

## 方案 C: 手动安装 (GitHub 镜像, 按平台选择)

### Linux
```bash
mkdir -p ~/.aether
# amd64:
curl -fsSL https://github.com/10CG/aether-cli/releases/latest/download/aether-linux-amd64 \
  -o ~/.aether/aether && chmod +x ~/.aether/aether
# arm64:
curl -fsSL https://github.com/10CG/aether-cli/releases/latest/download/aether-linux-arm64 \
  -o ~/.aether/aether && chmod +x ~/.aether/aether
```

### macOS
```bash
mkdir -p ~/.aether
# Apple Silicon (M1/M2/M3):
curl -fsSL https://github.com/10CG/aether-cli/releases/latest/download/aether-darwin-arm64 \
  -o ~/.aether/aether && chmod +x ~/.aether/aether
# Intel Mac:
curl -fsSL https://github.com/10CG/aether-cli/releases/latest/download/aether-darwin-amd64 \
  -o ~/.aether/aether && chmod +x ~/.aether/aether
```

### Windows (PowerShell)
```powershell
$d = "$env:USERPROFILE\.aether"
New-Item -ItemType Directory -Path $d -Force | Out-Null
Invoke-WebRequest -Uri "https://github.com/10CG/aether-cli/releases/latest/download/aether-windows-amd64.exe" `
  -OutFile "$d\aether.exe"
& "$d\aether.exe" version
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
