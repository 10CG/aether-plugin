# CLI 安装流程

## 安装信息

| 项目 | 值 |
|------|-----|
| 安装目录 | `~/.aether/` |
| 发布源 | `https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases` |
| Tag 格式 | `aether-cli/v{VERSION}` |

## CLI 检测逻辑

```bash
detect_aether_cli() {
  # 1. 检查 PATH
  if command -v aether &> /dev/null; then
    echo "aether"
    return 0
  fi

  # 2. 检查 ~/.aether/aether
  local cli="$HOME/.aether/aether"
  if [ -f "$cli" ] && [ -x "$cli" ]; then
    echo "$cli"
    return 0
  fi

  # 3. Windows .exe
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

## 方案 A: 自动安装

```bash
# 1. 检测系统
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case $ARCH in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac
EXT=""
[ "$OS" = "windows" ] && EXT=".exe"

# 2. 下载
BINARY_NAME="aether-${OS}-${ARCH}${EXT}"
RELEASE_API="https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest"
DOWNLOAD_URL=$(curl -s "$RELEASE_API" | jq -r ".assets[] | select(.name == \"$BINARY_NAME\") | .browser_download_url" | head -n1)

# 3. 安装
mkdir -p "$HOME/.aether"
curl -sL "$DOWNLOAD_URL" -o "$HOME/.aether/aether${EXT}"
chmod +x "$HOME/.aether/aether${EXT}"

# 4. 验证
"$HOME/.aether/aether${EXT}" version
```

## 方案 B: 从源码构建

```bash
mkdir -p "$HOME/.aether"
git clone https://forgejo.10cg.pub/10CG/aether-cli.git /tmp/aether-cli
cd /tmp/aether-cli
go build -ldflags="-s -w -X main.version=$(cat VERSION)" -o aether .
mv aether "$HOME/.aether/aether"
rm -rf /tmp/aether-cli
"$HOME/.aether/aether" version
```

## 方案 C: 手动安装

### Linux (amd64)
```bash
mkdir -p ~/.aether
RELEASE_API="https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest"
DOWNLOAD_URL=$(curl -s "$RELEASE_API" | jq -r '.assets[] | select(.name == "aether-linux-amd64") | .browser_download_url')
curl -sL "$DOWNLOAD_URL" -o ~/.aether/aether
chmod +x ~/.aether/aether
~/.aether/aether version
```

### macOS (arm64)
```bash
mkdir -p ~/.aether
RELEASE_API="https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest"
DOWNLOAD_URL=$(curl -s "$RELEASE_API" | jq -r '.assets[] | select(.name == "aether-darwin-arm64") | .browser_download_url')
curl -sL "$DOWNLOAD_URL" -o ~/.aether/aether
chmod +x ~/.aether/aether
~/.aether/aether version
```

### Windows (PowerShell)
```powershell
$aetherDir = "$env:USERPROFILE\.aether"
New-Item -ItemType Directory -Path $aetherDir -Force | Out-Null
$releaseApi = "https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest"
$response = Invoke-RestMethod -Uri $releaseApi
$downloadUrl = $response.assets | Where-Object { $_.name -eq "aether-windows-amd64.exe" } | Select-Object -ExpandProperty browser_download_url
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
