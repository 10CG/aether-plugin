---
name: aether-doctor
description: |
  Aether 环境诊断工具。检查 CLI、配置、集群连接、SSH、CI/CD 配置等环境状态，更新配置缓存。

  使用场景："诊断环境"、"检查配置"、"环境有问题"、"SSH 连接失败"、"CI 配置错误"、"首次使用"
argument-hint: "[--ssh|--cluster|--ci|--refresh] [--fix]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write, AskUserQuestion
cli_requirements:
  source: ".claude-plugin/requirements.yaml"
  min_version: "0.7.0"
  recommended_version: "0.7.0"
---

# Aether 环境诊断 (aether-doctor)

> **版本**: 1.3.0 | **优先级**: P0

## 快速开始

### 使用场景

- 首次使用 aether-plugin，需要验证环境
- 遇到命令执行失败，需要排查问题
- 定期检查环境健康状态
- 部署前确认环境正常

### 诊断项目

| 项目 | 检查内容 | 修复建议 |
|------|---------|---------|
| aether CLI | 是否安装、版本、PATH | 提供安装命令 |
| 配置文件 | 是否存在、格式正确 | 引导创建配置 |
| 配置验证 | 地址是否属于集群 Server | 提示正确地址 |
| Nomad 连接 | API 可达、版本 | 检查网络/服务 |
| Consul 连接 | API 可达、版本 | 检查网络/服务 |
| SSH 密钥 | 密钥文件存在、权限正确 | 提供修复命令 |
| SSH 连接 | 到各节点的连接测试 | 提供配置指南 |

---

## 执行诊断

### 完整诊断

```
/aether:doctor
```

执行所有检查项，更新配置缓存。

### 快速诊断（跳过 SSH 测试）

```
/aether:doctor --no-ssh
```

适用于不需要 SSH 操作的场景。

### 仅诊断 SSH

```
/aether:doctor --ssh
```

仅检查 SSH 相关配置和连接。

### 仅诊断集群连接

```
/aether:doctor --cluster
```

仅检查 Nomad/Consul 连接。

### 强制刷新缓存

```
/aether:doctor --refresh
```

忽略现有缓存，重新执行完整诊断。

---

## 诊断流程

### Step 0: 确定缓存文件位置

**重要**：environment 缓存存储在**项目级目录**，避免不同项目互相覆盖。

```bash
# 检查配置来源，确定缓存位置
if [ -f "./.aether/config.yaml" ]; then
  # 项目级配置存在 → 缓存也存项目级
  CACHE_FILE="./.aether/environment.yaml"
  CONFIG_SOURCE="project"
elif [ -f "./.env" ] && grep -q "NOMAD_ADDR" ./.env; then
  # 项目级 .env 存在 → 缓存存项目级
  CACHE_FILE="./.aether/environment.yaml"
  CONFIG_SOURCE="project"
else
  # 使用全局配置 → 缓存存全局
  CACHE_FILE="$HOME/.aether/environment.yaml"
  CONFIG_SOURCE="global"
fi

echo "配置来源: $CONFIG_SOURCE"
echo "缓存位置: $CACHE_FILE"
```

**缓存文件位置规则**：

| 配置来源 | 缓存位置 | 说明 |
|---------|---------|------|
| `./.aether/config.yaml` | `./.aether/environment.yaml` | 项目级配置 |
| `./.env` | `./.aether/environment.yaml` | 项目级配置 |
| `~/.aether/config.yaml` | `~/.aether/environment.yaml` | 全局配置 |
| 环境变量 | `~/.aether/environment.yaml` | 全局缓存 |

---

### Step 1: 检查 aether CLI

#### 1.1 版本兼容性要求

| Plugin Version | CLI Min Version | CLI Recommended | Notes |
|---------------|-----------------|-----------------|-------|
| 0.8.x         | 0.7.0           | 0.7.0           | 故障转移支持 |
| 0.9.x         | 0.8.0           | 0.8.0           | TBD |

#### 1.2 检查 CLI 是否安装

```bash
# 检查命令是否存在
which aether || where aether  # Linux/macOS 或 Windows
```

**结果处理**:
- 找到 → 继续 1.3 版本检查
- 未找到 → 执行 [CLI 安装流程](#cli-安装流程)

#### 1.3 检查 CLI 版本兼容性

```bash
# 获取 CLI 版本
CLI_VERSION=$(aether version --json 2>/dev/null | jq -r '.data.version' 2>/dev/null || aether version | awk '{print $2}')

# 读取 Plugin 要求的最低版本 (从 plugin.json)
MIN_VERSION="0.7.0"  # 当前 Plugin 要求

# 版本比较 (使用 sort -V)
if [ "$(printf '%s\n' "$MIN_VERSION" "$CLI_VERSION" | sort -V | head -n1)" = "$MIN_VERSION" ]; then
  echo "✓ CLI 版本兼容: $CLI_VERSION >= $MIN_VERSION"
else
  echo "✗ CLI 版本过低: $CLI_VERSION < $MIN_VERSION"
  # 触发升级流程
fi
```

**常见问题**:

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `command not found` | CLI 未安装或不在 PATH | 执行安装流程 |
| `permission denied` | 执行权限问题 | `chmod +x /path/to/aether` |
| 版本过低 | CLI 需要更新 | 执行升级流程 |

---

### CLI 安装流程

#### 方案 A: 自动安装（推荐）

当检测到 CLI 未安装或版本不兼容时，提供自动安装选项：

```bash
# 1. 检测系统环境
OS=$(uname -s | tr '[:upper:]' '[:lower:]')  # linux/darwin/windows
ARCH=$(uname -m)  # x86_64/aarch64

# 转换架构名称
case $ARCH in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac

# 2. 尝试从发布源下载预构建二进制
RELEASE_API="https://forgejo.10cg.pub/api/v1/repos/10CG/aether-cli/releases/latest"
BINARY_NAME="aether-${OS}-${ARCH}"

# 获取下载 URL
DOWNLOAD_URL=$(curl -s "$RELEASE_API" | jq -r ".assets[] | select(.name | contains(\"$BINARY_NAME\")) | .browser_download_url" | head -n1)

if [ -n "$DOWNLOAD_URL" ]; then
  echo "正在下载 aether CLI ($BINARY_NAME)..."
  curl -sL "$DOWNLOAD_URL" -o /tmp/aether
  chmod +x /tmp/aether
  sudo mv /tmp/aether /usr/local/bin/aether
  echo "✓ aether CLI 已安装到 /usr/local/bin/aether"
else
  echo "未找到预构建二进制，将从源码构建..."
  # 回退到方案 B
fi
```

#### 方案 B: 从源码构建

如果预构建二进制不可用：

```bash
# 克隆仓库
git clone https://forgejo.10cg.pub/10CG/aether-cli.git /tmp/aether-cli
cd /tmp/aether-cli

# 构建优化版本
go build -ldflags="-s -w -X main.Version=$(cat VERSION)" -o aether .

# 安装
sudo mv aether /usr/local/bin/aether
rm -rf /tmp/aether-cli

# 验证
aether version
```

#### 方案 C: 手动安装命令

如果用户选择手动安装，提供详细命令：

**Linux/macOS (amd64)**:
```bash
# 下载最新版本
curl -sL "https://forgejo.10cg.pub/api/v1/repos/10CG/aether-cli/releases/latest/download/aether-linux-amd64" -o /usr/local/bin/aether
chmod +x /usr/local/bin/aether
```

**Linux/macOS (arm64)**:
```bash
curl -sL "https://forgejo.10cg.pub/api/v1/repos/10CG/aether-cli/releases/latest/download/aether-darwin-arm64" -o /usr/local/bin/aether
chmod +x /usr/local/bin/aether
```

**Windows (PowerShell)**:
```powershell
# 下载到用户目录
$downloadUrl = "https://forgejo.10cg.pub/api/v1/repos/10CG/aether-cli/releases/latest/download/aether-windows-amd64.exe"
$outputPath = "$env:USERPROFILE\aether.exe"
Invoke-WebRequest -Uri $downloadUrl -OutFile $outputPath

# 添加到 PATH (可选)
# $env:PATH += ";$env:USERPROFILE"
```

**从源码构建（通用）**:
```bash
git clone https://forgejo.10cg.pub/10CG/aether-cli.git
cd aether-cli
go build -ldflags="-s -w -X main.Version=$(cat VERSION)" -o /usr/local/bin/aether .
```

---

### 交互式安装示例

当 aether-doctor 检测到 CLI 问题时，显示：

```
[!] aether CLI
    状态: 未安装

    是否自动安装 aether CLI？ [Y/n]

    选项:
      1. 自动安装（推荐）- 下载预构建二进制
      2. 从源码构建 - 需要 Go 环境
      3. 显示手动安装命令

    请选择 [1/2/3]: 1

    正在检测系统...
    OS: linux
    ARCH: amd64

    正在下载 aether-linux-amd64...
    ✓ 下载完成

    正在安装到 /usr/local/bin/aether...
    ✓ 安装完成

    验证安装...
    ✓ aether version: 0.7.0

    [✓] aether CLI
        版本: 0.7.0
        路径: /usr/local/bin/aether
```

---

### Step 2: 检查配置文件

```bash
# 检查全局配置
cat ~/.aether/config.yaml

# 检查项目配置
cat ./.aether/config.yaml

# 检查环境变量
env | grep -E 'NOMAD|CONSUL|AETHER'
```

**配置文件格式**:

```yaml
# ~/.aether/config.yaml 或 ./.aether/config.yaml
endpoints:
  nomad: "http://192.168.69.70:4646"
  consul: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"
```

**配置来源优先级**:

```
环境变量 > 项目配置 (./.aether/config.yaml) > 全局配置 (~/.aether/config.yaml)
```

**缺失配置时**:

1. 提示用户运行 `/aether:setup` 创建配置
2. 或提供手动配置命令

---

### Step 3: 获取集群拓扑

**关键步骤**：从 Nomad API 获取完整的集群结构。

```bash
# 获取当前 leader（注意：返回的是 RPC 端口 4647，不是 HTTP 端口 4646）
NOMAD_LEADER=$(curl -s "${NOMAD_ADDR}/v1/status/leader")
# 示例返回: "192.168.69.71:4647"

# 获取 agent 自身信息，提取 Raft 配置中的所有 server
curl -s "${NOMAD_ADDR}/v1/agent/self" | jq '{
  nodeName: .member.Name,
  nodeAddr: .member.Addr,
  isLeader: (.stats.nomad.leader == "true"),
  leaderAddr: .stats.nomad.leader_addr,
  raftConfig: .stats.raft.latest_configuration
}'

# 获取所有 client 节点
curl -s "${NOMAD_ADDR}/v1/nodes" | jq '[.[] | {
  name: .Name,
  ip: .Address,
  status: .Status,
  class: .NodeClass,
  drivers: [.Drivers | keys[]]
}]'
```

**解析 Server 节点**（从 Raft 配置）：

```bash
# Raft 配置格式: [{Suffrage:Voter ID:xxx Address:192.168.69.70:4647} ...]
# 需要提取所有 Address，并将 RPC 端口 (4647) 转换为 HTTP 端口 (4646)

curl -s "${NOMAD_ADDR}/v1/agent/self" | jq -r '
  .stats.raft.latest_configuration |
  # 解析配置字符串，提取 IP:Port
  split("} {") |
  .[] |
  extract_address()
'
```

**完整的集群拓扑获取脚本**：

```bash
#!/bin/bash
# 获取 Nomad 集群完整拓扑

NOMAD_ADDR="${NOMAD_ADDR:-http://192.168.69.70:4646}"

# 获取 leader 信息
LEADER_RPC=$(curl -s "${NOMAD_ADDR}/v1/status/leader" | tr -d '"')
LEADER_IP=$(echo $LEADER_RPC | cut -d: -f1)

# 获取 agent 信息
AGENT_INFO=$(curl -s "${NOMAD_ADDR}/v1/agent/self")

# 解析 Raft 配置获取所有 server
# 格式: {Suffrage:Voter ID:xxx Address:IP:4647} ...
RAFT_CONFIG=$(echo "$AGENT_INFO" | grep -o 'latest_configuration":"[^"]*' | sed 's/latest_configuration":"//')

# 提取 server 地址列表（RPC 端口）
SERVERS_RPC=$(echo "$RAFT_CONFIG" | grep -oE 'Address:[0-9.]+:[0-9]+' | cut -d: -f2,3)

echo "=== Nomad 集群拓扑 ==="
echo "Leader RPC: $LEADER_RPC"
echo ""
echo "Server 节点 (RPC 端口):"
echo "$SERVERS_RPC" | while read addr; do
  IP=$(echo $addr | cut -d: -f1)
  RPC_PORT=$(echo $addr | cut -d: -f2)
  HTTP_PORT=$((RPC_PORT - 1))  # RPC 4647 → HTTP 4646

  if [ "$IP:$RPC_PORT" = "$LEADER_RPC" ]; then
    echo "  $IP:$HTTP_PORT (HTTP) - LEADER"
  else
    echo "  $IP:$HTTP_PORT (HTTP) - follower"
  fi
done

# 获取 client 节点
echo ""
echo "Client 节点:"
curl -s "${NOMAD_ADDR}/v1/nodes" | jq -r '.[] | "  \(.Name): \(.Address) [\(.NodeClass)]"'
```

---

### Step 4: 验证配置地址

**核心逻辑**：检查用户配置的地址是否属于集群 Server 列表中的任意一个。

```bash
# 用户配置的地址
CONFIG_NOMAD="192.168.69.70:4646"  # 从 config.yaml 读取
CONFIG_IP=$(echo $CONFIG_NOMAD | cut -d: -f1)
CONFIG_PORT=$(echo $CONFIG_NOMAD | cut -d: -f2)

# 检查是否在 server 列表中
IS_VALID=false
for server in $SERVER_HTTP_ADDRS; do
  if [ "$CONFIG_NOMAD" = "$server" ]; then
    IS_VALID=true
    break
  fi
done

if $IS_VALID; then
  echo "✓ 配置有效: $CONFIG_NOMAD 是集群 Server"
else
  echo "✗ 配置无效: $CONFIG_NOMAD 不在集群 Server 列表中"
  echo "  可用的 Server 地址:"
  for server in $SERVER_HTTP_ADDRS; do
    echo "    - $server"
  done
fi
```

**重要**：不使用 leader 地址来判断配置是否正确，因为：
1. Leader 会变化
2. 任意 Server 都可以接受 API 请求
3. `/v1/status/leader` 返回的是 RPC 端口 (4647)，不是 HTTP 端口 (4646)

---

### Step 5: 测试集群连接

#### Nomad 连接测试

```bash
# 测试配置的地址是否可达
curl -s "${CONFIG_NOMAD}/v1/status/leader"

# 获取版本
curl -s "${CONFIG_NOMAD}/v1/agent/self" | jq '.config.Version'

# 验证是 server 节点
curl -s "${CONFIG_NOMAD}/v1/agent/self" | jq '.stats.nomad.server'
```

#### Consul 连接测试

```bash
# 读取配置
CONSUL_ADDR=$(cat ~/.aether/config.yaml | grep 'consul:' | awk '{print $2}' | tr -d '"')

# 测试连接
curl -s "${CONSUL_ADDR}/v1/status/leader"

# 获取版本
curl -s "${CONSUL_ADDR}/v1/agent/self" | jq '.Config.Version'
```

**连接问题排查**:

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `connection refused` | 服务未运行 | 启动 Nomad/Consul 服务 |
| `timeout` | 网络不通 | 检查防火墙/网络配置 |
| `401/403` | 认证问题 | 检查 Token 配置 |
| `unknown host` | DNS 解析失败 | 使用 IP 地址或配置 hosts |

---

### Step 6: 检查 SSH 配置

#### 检查密钥文件

```bash
# 检查常见密钥位置
for key in ~/.ssh/id_ed25519 ~/.ssh/id_rsa ~/.ssh/id_ecdsa; do
  if [ -f "$key" ]; then
    echo "✓ Found: $key"
    ls -la "$key"
  fi
done

# 检查权限（应该是 600）
stat -c "%a %n" ~/.ssh/id_* 2>/dev/null
```

#### 检查 SSH Config

```bash
# 检查 ~/.ssh/config
cat ~/.ssh/config 2>/dev/null | grep -A5 -E 'Host.*(heavy|light|infra)'
```

**推荐的 SSH Config**:

```
# ~/.ssh/config
Host heavy-* light-* infra-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    ConnectTimeout 10
```

**修复权限**:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/*.pub
```

---

### Step 7: 测试 SSH 连接

从集群拓扑获取所有节点 IP，逐个测试 SSH 连接：

```bash
# 从 environment 缓存或 API 获取所有节点 IP
# 包括 servers 和 clients

# 测试 server 节点
for node in "${SERVER_NODES[@]}"; do
  name=$(echo $node | cut -d: -f1)
  ip=$(echo $node | cut -d: -f2)
  echo -n "Testing server $name ($ip)... "
  if ssh -o ConnectTimeout=5 -o BatchMode=yes root@$ip "echo ok" 2>/dev/null; then
    echo "✓"
  else
    echo "✗"
  fi
done

# 测试 client 节点
for node in "${CLIENT_NODES[@]}"; do
  name=$(echo $node | cut -d: -f1)
  ip=$(echo $node | cut -d: -f2)
  echo -n "Testing client $name ($ip)... "
  if ssh -o ConnectTimeout=5 -o BatchMode=yes root@$ip "echo ok" 2>/dev/null; then
    echo "✓"
  else
    echo "✗"
  fi
done
```

**SSH 连接问题排查**:

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `Permission denied` | 公钥未添加到节点 | 通过 Proxmox 控制台添加 |
| `Connection timed out` | 网络不通/防火墙 | 检查网络配置 |
| `Host key verification failed` | known_hosts 冲突 | `ssh-keygen -R <ip>` |
| `no such identity` | 密钥文件不存在 | 生成或指定正确的密钥 |

**添加公钥到节点**:

```bash
# 方法1: ssh-copy-id（需要密码登录）
ssh-copy-id root@192.168.69.80

# 方法2: 手动添加（通过 Proxmox 控制台）
# 在节点上执行：
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... your@email.com" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

### Step 8: CI/CD 配置检查（可选）

如果项目包含 CI 配置文件，检查其配置是否正确。

#### 8.1 检测 CI 平台

```bash
# 检测 CI 平台类型
if [ -d ".forgejo/workflows" ]; then
  CI_PLATFORM="forgejo"
  CI_WORKFLOW_DIR=".forgejo/workflows"
elif [ -d ".github/workflows" ]; then
  CI_PLATFORM="github"
  CI_WORKFLOW_DIR=".github/workflows"
elif [ -d ".gitlab-ci.yml" ]; then
  CI_PLATFORM="gitlab"
  CI_WORKFLOW_DIR=""
else
  CI_PLATFORM="none"
  echo "未检测到 CI 配置，跳过此步骤"
fi

echo "检测到 CI 平台: $CI_PLATFORM"
```

#### 8.2 检查 Workflow 文件中的 Secrets 配置

**Forgejo 环境**：

```bash
# 扫描 workflow 文件中的 secrets 引用
grep -r "secrets\." .forgejo/workflows/ | grep -v "^#"

# 检查是否使用了正确的 Forgejo secrets
# Forgejo 自动注入: FORGEJO_USER, FORGEJO_TOKEN
# 正确: secrets.FORGEJO_USER, secrets.FORGEJO_TOKEN
# 错误: secrets.REGISTRY_USERNAME, secrets.REGISTRY_TOKEN (需要手动配置)
```

**常见配置问题**：

| 问题 | 当前配置 | 正确配置 | 说明 |
|------|---------|---------|------|
| Registry 认证 | `secrets.REGISTRY_TOKEN` | `secrets.FORGEJO_TOKEN` | Forgejo 自动注入 |
| Registry 用户 | `secrets.REGISTRY_USERNAME` | `secrets.FORGEJO_USER` | Forgejo 自动注入 |
| Nomad 地址硬编码 | `http://192.168.69.70:4646` | `${{ secrets.NOMAD_ADDR }}` | 应从 secrets 读取 |

#### 8.3 Secrets 配置规范

**Forgejo 环境**：

| Secret | 说明 | 是否自动注入 |
|--------|------|-------------|
| `FORGEJO_USER` | 当前用户名 | ✅ 自动 |
| `FORGEJO_TOKEN` | 访问令牌 | ✅ 自动 |
| `NOMAD_ADDR` | Nomad API 地址 | ❌ 需手动配置 |
| `NOMAD_TOKEN` | Nomad 访问令牌 | ❌ 需手动配置 |

**GitHub 环境**：

| Secret | 说明 | 是否自动注入 |
|--------|------|-------------|
| `GITHUB_ACTOR` | 当前用户名 | ✅ 自动 |
| `GITHUB_TOKEN` | 访问令牌 | ✅ 自动 |
| `NOMAD_ADDR` | Nomad API 地址 | ❌ 需手动配置 |
| `NOMAD_TOKEN` | Nomad 访问令牌 | ❌ 需手动配置 |

#### 8.4 CI 配置检查输出示例

```
[✓] CI/CD 配置检查
    平台: Forgejo
    Workflow 文件: .forgejo/workflows/deploy.yaml

    Secrets 引用分析:
      ✓ NOMAD_ADDR: ${{ secrets.NOMAD_ADDR }}
      ✓ NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
      ✓ Registry 认证: ${{ secrets.FORGEJO_TOKEN }}

    状态: 配置正确
```

**发现问题时**：

```
[!] CI/CD 配置检查
    平台: Forgejo
    Workflow 文件: .forgejo/workflows/deploy.yaml

    发现以下问题:

    1. [WARNING] 使用了通用 secrets 名称
       当前: secrets.REGISTRY_TOKEN
       建议: secrets.FORGEJO_TOKEN (Forgejo 自动注入)

       修复方法:
       将 workflow 中的:
         password: ${{ secrets.REGISTRY_TOKEN }}
       改为:
         password: ${{ secrets.FORGEJO_TOKEN }}

    2. [WARNING] Nomad 地址硬编码
       当前: http://192.168.69.70:4646
       建议: ${{ secrets.NOMAD_ADDR }}

       修复方法:
       1. 在 Forgejo 仓库 Settings → Secrets 中添加 NOMAD_ADDR
       2. 将 workflow 中的硬编码地址改为 ${{ secrets.NOMAD_ADDR }}

    需要配置的 Secrets:
      - NOMAD_ADDR: http://192.168.69.70:4646
      - NOMAD_TOKEN: (从 Nomad ACL 生成)

    状态: ⚠ 配置可优化
```

#### 8.5 自动修复建议

如果发现配置问题，提供具体的修复命令：

```bash
# 查看需要修改的文件
grep -n "REGISTRY_TOKEN\|REGISTRY_USERNAME\|hardcoded_addr" .forgejo/workflows/*.yaml

# 建议的 sed 替换命令
# sed -i 's/secrets\.REGISTRY_TOKEN/secrets.FORGEJO_TOKEN/g' .forgejo/workflows/deploy.yaml
# sed -i 's/secrets\.REGISTRY_USERNAME/secrets.FORGEJO_USER/g' .forgejo/workflows/deploy.yaml
```

---

### Step 9: 更新环境缓存

诊断完成后，更新环境缓存文件。

**缓存文件位置**：根据配置来源决定（见 Step 0）

**缓存文件格式** (`environment.yaml`):

```yaml
# Aether 环境状态缓存
# 由 aether-doctor 自动维护，请勿手动编辑

last_diagnosis: "2026-03-08T12:00:00Z"
status: "healthy"  # healthy | degraded | unknown
cli_version: "0.6.0"
cli_path: "/usr/local/bin/aether"

config:
  source: "project"  # project | global | env
  nomad: "http://192.168.69.70:4646"
  consul: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"
  validated: true  # 配置地址是否在 server 列表中

cluster:
  nomad_version: "1.11.2"
  consul_version: "1.22.3"
  current_leader: "192.168.69.71"
  datacenter: "dc1"
  region: "global"

  # 所有 Server 节点（完整拓扑）
  servers:
    - name: "infra-server-1"
      ip: "192.168.69.70"
      http_port: 4646
      rpc_port: 4647
      role: "follower"
    - name: "infra-server-2"
      ip: "192.168.69.71"
      http_port: 4646
      rpc_port: 4647
      role: "leader"
    - name: "infra-server-3"
      ip: "192.168.69.72"
      http_port: 4646
      rpc_port: 4647
      role: "follower"

  # 所有 Client 节点
  clients:
    - name: "heavy-1"
      ip: "192.168.69.80"
      class: "heavy_workload"
      drivers: ["docker", "exec"]
      status: "ready"
    - name: "heavy-2"
      ip: "192.168.69.81"
      class: "heavy_workload"
      drivers: ["docker", "exec"]
      status: "ready"
    - name: "heavy-3"
      ip: "192.168.69.82"
      class: "heavy_workload"
      drivers: ["docker", "exec"]
      status: "ready"
    - name: "light-1"
      ip: "192.168.69.90"
      class: "light_exec"
      drivers: ["exec"]
      status: "ready"
    - name: "light-2"
      ip: "192.168.69.91"
      class: "light_exec"
      drivers: ["exec"]
      status: "ready"
    - name: "light-3"
      ip: "192.168.69.92"
      class: "light_exec"
      drivers: ["exec"]
      status: "ready"
    - name: "light-4"
      ip: "192.168.69.93"
      class: "light_exec"
      drivers: ["exec"]
      status: "ready"
    - name: "light-5"
      ip: "192.168.69.94"
      class: "light_exec"
      drivers: ["exec"]
      status: "ready"

  # 统计信息
  stats:
    total_servers: 3
    total_clients: 8
    running_jobs: 10
    node_classes:
      heavy_workload: 3
      light_exec: 5

ssh:
  key_path: "~/.ssh/id_ed25519"
  key_exists: true
  key_valid: true

  # 每个节点的 SSH 连接测试结果
  nodes_tested:
    # Server 节点
    infra-server-1: { ip: "192.168.69.70", status: "ok", type: "server" }
    infra-server-2: { ip: "192.168.69.71", status: "ok", type: "server" }
    infra-server-3: { ip: "192.168.69.72", status: "ok", type: "server" }
    # Client 节点
    heavy-1: { ip: "192.168.69.80", status: "ok", type: "client" }
    heavy-2: { ip: "192.168.69.81", status: "ok", type: "client" }
    heavy-3: { ip: "192.168.69.82", status: "ok", type: "client" }
    light-1: { ip: "192.168.69.90", status: "ok", type: "client" }
    light-2: { ip: "192.168.69.91", status: "failed", error: "Connection timed out", type: "client" }
    light-3: { ip: "192.168.69.92", status: "ok", type: "client" }
    light-4: { ip: "192.168.69.93", status: "ok", type: "client" }
    light-5: { ip: "192.168.69.94", status: "ok", type: "client" }
```

---

## 输出示例

### 全部正常

```
Aether 环境诊断
===============
诊断时间: 2026-03-08 12:00:00
配置来源: 项目级 (./.aether/config.yaml)
缓存位置: ./.aether/environment.yaml

[✓] aether CLI
    版本: 0.6.0
    路径: /usr/local/bin/aether

[✓] 配置验证
    配置地址: http://192.168.69.70:4646
    集群 Server 列表:
      - 192.168.69.70:4646 ✓ (当前配置)
      - 192.168.69.71:4646 (leader)
      - 192.168.69.72:4646
    状态: 配置有效（连接到集群 Server）

[✓] 集群连接
    Nomad: v1.11.2 (通过 192.168.69.70:4646)
    Consul: v1.22.3

[✓] 集群拓扑
    Server 节点: 3 个
      - infra-server-1 (192.168.69.70) - follower
      - infra-server-2 (192.168.69.71) - leader
      - infra-server-3 (192.168.69.72) - follower
    Client 节点: 8 个
      - heavy-1/2/3 (heavy_workload, docker+exec)
      - light-1~5 (light_exec, exec)
    运行中 Jobs: 10

[✓] SSH 配置
    密钥: ~/.ssh/id_ed25519
    权限: 600 (正确)

[✓] SSH 连接测试
    Server 节点:
      infra-server-1 (192.168.69.70): ✓
      infra-server-2 (192.168.69.71): ✓
      infra-server-3 (192.168.69.72): ✓
    Client 节点:
      heavy-1 (192.168.69.80): ✓
      heavy-2 (192.168.69.81): ✓
      heavy-3 (192.168.69.82): ✓
      light-1 (192.168.69.90): ✓
      light-2 (192.168.69.91): ✓
      light-3 (192.168.69.92): ✓
      light-4 (192.168.69.93): ✓
      light-5 (192.168.69.94): ✓

[✓] CI/CD 配置
    平台: Forgejo
    Workflow: .forgejo/workflows/deploy.yaml
    Secrets 配置:
      - NOMAD_ADDR: ✓
      - NOMAD_TOKEN: ✓
      - Registry 认证: ✓ (FORGEJO_TOKEN)
    状态: 配置正确

状态: ✓ 健康
缓存已更新: ./.aether/environment.yaml
```

### 配置地址不在 Server 列表中

```
Aether 环境诊断
===============

[✓] aether CLI
    版本: 0.6.0

[!] 配置验证
    配置地址: http://192.168.69.100:4646
    集群 Server 列表:
      - 192.168.69.70:4646
      - 192.168.69.71:4646 (leader)
      - 192.168.69.72:4646

    ⚠ 配置的地址不在集群 Server 列表中

    可能原因:
    1. IP 地址配置错误
    2. 连接到了错误的集群

    建议修改配置为以下地址之一:
      - http://192.168.69.70:4646
      - http://192.168.69.71:4646
      - http://192.168.69.72:4646

    是否自动修复配置？ [Y/n]
```

### 部分 SSH 连接失败

```
Aether 环境诊断
===============

[✓] aether CLI
[✓] 配置验证
[✓] 集群连接
[✓] 集群拓扑
[✓] SSH 配置

[✗] SSH 连接测试
    Server 节点: 3/3 正常
    Client 节点: 6/8 正常

    失败的节点:
      - light-2 (192.168.69.91): Connection timed out
        可能原因: 网络不通或节点离线
        建议: 检查节点网络配置

      - light-4 (192.168.69.93): Permission denied
        可能原因: 公钥未添加到节点
        建议: 通过 Proxmox 控制台添加公钥

状态: ⚠ 降级运行（部分 SSH 功能受限）
缓存已更新

是否需要详细的修复指南？ [Y/n]
```

### CI 配置问题

```
Aether 环境诊断
===============

[✓] aether CLI
[✓] 配置验证
[✓] 集群连接
[✓] 集群拓扑
[✓] SSH 配置
[✓] SSH 连接测试

[!] CI/CD 配置
    平台: Forgejo
    Workflow: .forgejo/workflows/deploy.yaml

    发现以下问题:

    1. [WARNING] 使用了错误的 secrets 名称
       当前: secrets.REGISTRY_TOKEN
       建议: secrets.FORGEJO_TOKEN

       Forgejo 自动注入 FORGEJO_TOKEN，无需手动配置。
       修复方法:
         将 workflow 中的 secrets.REGISTRY_TOKEN 改为 secrets.FORGEJO_TOKEN

    2. [WARNING] Nomad 地址硬编码
       当前: NOMAD_ADDR: http://192.168.69.70:4646
       建议: NOMAD_ADDR: ${{ secrets.NOMAD_ADDR }}

       修复方法:
       1. 在 Forgejo 仓库 Settings → Secrets 中添加:
          - NOMAD_ADDR: http://192.168.69.70:4646
          - NOMAD_TOKEN: (从 Nomad ACL 生成)
       2. 修改 workflow 使用 ${{ secrets.NOMAD_ADDR }}

    需要配置的 Secrets:
      ┌───────────────┬─────────────────────────────┐
      │    Secret     │            示例值            │
      ├───────────────┼─────────────────────────────┤
      │ NOMAD_ADDR    │ http://192.168.69.70:4646  │
      │ NOMAD_TOKEN   │ your-nomad-token           │
      └───────────────┴─────────────────────────────┘

    注意: FORGEJO_USER 和 FORGEJO_TOKEN 由 Forgejo 自动注入

状态: ⚠ 环境可用，CI 配置可优化

是否自动生成修复脚本？ [Y/n]
```

### 严重问题

```
Aether 环境诊断
===============

[✗] aether CLI
    错误: command not found

[?] 配置文件
    跳过: 需要先安装 CLI

[?] 集群连接
    跳过: 需要先配置

问题摘要
--------
无法继续诊断，需要先完成基础配置:

1. 安装 aether CLI
   cd aether-cli
   go build -o /usr/local/bin/aether .

2. 创建配置文件
   运行 /aether:setup 配置集群地址

3. 配置 SSH 密钥
   ssh-keygen -t ed25519 -C "your@email.com"

完成以上步骤后，重新运行 /aether:doctor

状态: ✗ 环境未就绪
```

---

## 缓存有效期

配置缓存的有效期规则：

| 场景 | 有效期 | 说明 |
|------|-------|------|
| 正常状态 (healthy) | 24 小时 | 无需重复诊断 |
| 降级状态 (degraded) | 4 小时 | 提醒修复问题 |
| 未知状态 (unknown) | 立即过期 | 需要运行诊断 |

**Skills 读取缓存时的判断逻辑**：

```bash
# 确定缓存文件位置
if [ -f "./.aether/environment.yaml" ]; then
  CACHE="./.aether/environment.yaml"
else
  CACHE="$HOME/.aether/environment.yaml"
fi

# 读取上次诊断时间和状态
LAST_DIAGNOSIS=$(yq '.last_diagnosis' $CACHE 2>/dev/null)
STATUS=$(yq '.status' $CACHE 2>/dev/null)

# 计算是否过期
if is_expired "$LAST_DIAGNOSIS" "$STATUS"; then
  echo "环境状态已过期，建议运行 /aether:doctor"
fi
```

---

## 与其他 Skills 的集成

### Skills 读取缓存示例

```bash
# 获取集群拓扑信息
SERVERS=$(yq '.cluster.servers[] | "\(.name) \(.ip)"' ./.aether/environment.yaml)
CURRENT_LEADER=$(yq '.cluster.current_leader' ./.aether/environment.yaml)

# 获取指定类型的节点
HEAVY_NODES=$(yq '.cluster.clients[] | select(.class == "heavy_workload") | .ip' ./.aether/environment.yaml)

# 检查 SSH 连接状态
SSH_STATUS=$(yq '.ssh.nodes_tested.heavy-1.status' ./.aether/environment.yaml)
```

### aether-volume 调用前检查

```markdown
执行 volume 操作前:

1. 读取 environment.yaml 缓存
2. 检查 status:
   - healthy: 直接执行
   - degraded: 警告但允许执行
   - unknown: 提示运行 /aether:doctor
3. 检查目标节点的 SSH 连接状态

示例输出:
```
环境状态: healthy (上次诊断: 2小时前)
目标节点 heavy-1: SSH 连接正常 ✓

继续执行 volume 创建...
```

### 错误时的诊断建议

当任何 Skill 执行失败时：

| 错误类型 | 建议 |
|---------|-----|
| `aether: command not found` | 安装 aether CLI |
| `config file not found` | 运行 /aether:setup |
| `connection refused` | 运行 /aether:doctor --cluster |
| `permission denied (SSH)` | 运行 /aether:doctor --ssh |
| `timeout` | 运行 /aether:doctor 检查网络 |

---

## 命令行等价操作

如果需要在终端直接诊断：

```bash
# 快速检查 CLI
aether version

# 检查配置
cat ~/.aether/config.yaml
cat ./.aether/config.yaml

# 获取集群 leader
curl -s http://192.168.69.70:4646/v1/status/leader

# 获取所有节点
curl -s http://192.168.69.70:4646/v1/nodes

# 测试 SSH
ssh -o ConnectTimeout=5 root@192.168.69.80 "hostname"
```

---

## 参考文档

- [aether-setup Skill](../aether-setup/SKILL.md) - 配置集群入口
- [aether-volume Skill](../aether-volume/SKILL.md) - Volume 管理
- [SSH 配置指南](../../docs/guides/light-nodes-ssh-setup-tutorial.md) - 详细 SSH 配置

---

**Skill 版本**: 1.3.0
**最后更新**: 2026-03-09
**维护者**: 10CG Infrastructure Team
