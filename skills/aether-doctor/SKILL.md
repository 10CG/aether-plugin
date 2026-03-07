---
name: aether-doctor
description: |
  Aether 环境诊断工具。检查 CLI、配置、集群连接、SSH 等环境状态，更新配置缓存。

  使用场景："诊断环境"、"检查配置"、"环境有问题"、"SSH 连接失败"、"首次使用"
argument-hint: "[--ssh|--cluster|--refresh] [--fix]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Aether 环境诊断 (aether-doctor)

> **版本**: 1.0.0 | **优先级**: P0

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

### Step 1: 检查 aether CLI

```bash
# 检查命令是否存在
which aether || where aether  # Linux/macOS 或 Windows

# 检查版本
aether version

# 检查 PATH
echo $PATH | tr ':' '\n' | grep -E '(aether|/usr/local/bin)'
```

**常见问题**:

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `command not found` | CLI 未安装或不在 PATH | 安装 CLI 或添加到 PATH |
| `permission denied` | 执行权限问题 | `chmod +x /path/to/aether` |
| 版本过低 | CLI 需要更新 | 重新安装最新版本 |

**安装 CLI**:

```bash
# 从源码构建
cd aether-cli && go build -o /usr/local/bin/aether .

# 或下载预编译版本
curl -sL https://releases.example.com/aether/latest/aether-linux-amd64 -o /usr/local/bin/aether
chmod +x /usr/local/bin/aether
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
# ~/.aether/config.yaml
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

### Step 3: 测试集群连接

#### Nomad 连接测试

```bash
# 读取配置
NOMAD_ADDR=$(cat ~/.aether/config.yaml | grep 'nomad:' | awk '{print $2}' | tr -d '"')

# 测试连接
curl -s "${NOMAD_ADDR}/v1/status/leader"

# 获取版本
curl -s "${NOMAD_ADDR}/v1/agent/self" | jq '.Config.Version'

# 获取节点列表
curl -s "${NOMAD_ADDR}/v1/nodes" | jq -r '.[] | "\(.Name) \(.Address) \(.Status) \(.NodeClass)"'
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

### Step 4: 检查 SSH 配置

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
cat ~/.ssh/config 2>/dev/null | grep -A5 -E 'Host.*(heavy|light)'
```

**推荐的 SSH Config**:

```
# ~/.ssh/config
Host heavy-* light-*
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

### Step 5: 测试 SSH 连接

从 Nomad API 获取节点列表后，逐个测试 SSH 连接：

```bash
# 获取节点列表
NODES=$(curl -s "${NOMAD_ADDR}/v1/nodes" | jq -r '.[] | "\(.Name) \(.Address)"')

# 测试每个节点
while read name ip; do
  echo -n "Testing $name ($ip)... "
  if ssh -o ConnectTimeout=5 -o BatchMode=yes root@$ip "echo ok" 2>/dev/null; then
    echo "✓"
  else
    echo "✗"
  fi
done <<< "$NODES"
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

### Step 6: 收集集群信息

```bash
# 获取节点分类信息
curl -s "${NOMAD_ADDR}/v1/nodes" | jq -r '
  group_by(.NodeClass) |
  map({
    class: .[0].NodeClass,
    count: length,
    drivers: [.[0].Drivers | keys[]] | unique,
    nodes: [.[].Name]
  })
'

# 获取运行中的 Job 数量
curl -s "${NOMAD_ADDR}/v1/jobs" | jq '[.[] | select(.Status == "running")] | length'
```

---

### Step 7: 更新配置缓存

诊断完成后，更新配置文件中的 `environment` 字段：

```yaml
# ~/.aether/config.yaml

endpoints:
  nomad: "http://192.168.69.70:4646"
  consul: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"

# 由 aether-doctor 自动维护
environment:
  cli_version: "0.6.0"
  cli_path: "/usr/local/bin/aether"

  last_diagnosis: "2026-03-07T12:00:00Z"
  status: "healthy"  # healthy | degraded | unknown

  cluster:
    nomad_version: "1.11.2"
    consul_version: "1.22.3"
    total_nodes: 6
    running_jobs: 10
    node_classes:
      - name: "heavy_workload"
        count: 1
        driver: "docker"
        nodes: ["heavy-1"]
      - name: "light_exec"
        count: 5
        driver: "exec"
        nodes: ["light-1", "light-2", "light-3", "light-4", "light-5"]

  ssh:
    key_path: "~/.ssh/id_ed25519"
    key_exists: true
    key_valid: true
    nodes_tested:
      heavy-1: { ip: "192.168.69.80", status: "ok" }
      light-1: { ip: "192.168.69.90", status: "ok" }
      light-2: { ip: "192.168.69.91", status: "ok" }
      light-3: { ip: "192.168.69.92", status: "ok" }
      light-4: { ip: "192.168.69.93", status: "ok" }
      light-5: { ip: "192.168.69.94", status: "ok" }
```

---

## 输出示例

### 全部正常

```
Aether 环境诊断
===============
诊断时间: 2026-03-07 12:00:00

[✓] aether CLI
    版本: 0.6.0
    路径: /usr/local/bin/aether

[✓] 配置文件
    来源: ~/.aether/config.yaml
    Nomad: http://192.168.69.70:4646
    Consul: http://192.168.69.70:8500
    Registry: forgejo.10cg.pub

[✓] 集群连接
    Nomad: v1.11.2 (leader: 192.168.69.70:4646)
    Consul: v1.22.3 (leader: 192.168.69.70:8300)

[✓] SSH 配置
    密钥: ~/.ssh/id_ed25519
    权限: 600 (正确)

[✓] SSH 连接测试
    heavy-1 (192.168.69.80): ✓
    light-1 (192.168.69.90): ✓
    light-2 (192.168.69.91): ✓
    light-3 (192.168.69.92): ✓
    light-4 (192.168.69.93): ✓
    light-5 (192.168.69.94): ✓

集群概览
--------
节点类型:
  heavy_workload: 1 节点 (docker)
    └─ heavy-1 (192.168.69.80)
  light_exec: 5 节点 (exec)
    └─ light-1, light-2, light-3, light-4, light-5

总计: 6 节点 | 10 个运行中 Job

状态: ✓ 健康
配置缓存已更新
```

### 部分问题

```
Aether 环境诊断
===============
诊断时间: 2026-03-07 12:00:00

[✓] aether CLI
    版本: 0.6.0
    路径: /usr/local/bin/aether

[✓] 配置文件
    来源: ~/.aether/config.yaml

[✓] 集群连接
    Nomad: v1.11.2 ✓
    Consul: v1.22.3 ✓

[!] SSH 配置
    密钥: ~/.ssh/id_ed25519 (存在)
    权限: 644 (错误，应为 600)

[✗] SSH 连接测试
    heavy-1 (192.168.69.80): ✓
    light-1 (192.168.69.90): ✓
    light-2 (192.168.69.91): ✗ Connection timed out
    light-3 (192.168.69.92): ✓
    light-4 (192.168.69.93): ✗ Permission denied
    light-5 (192.168.69.94): ✓

问题摘要
--------
2 个问题需要修复:

1. SSH 密钥权限不正确
   修复: chmod 600 ~/.ssh/id_ed25519

2. 2 个节点 SSH 连接失败:
   - light-2: Connection timed out
     可能原因: 网络不通或节点离线
     建议: 检查节点网络配置

   - light-4: Permission denied
     可能原因: 公钥未添加到节点
     建议: 通过 Proxmox 控制台添加公钥

状态: ⚠ 降级运行（部分功能受限）
配置缓存已更新

是否需要详细的修复指南？ [Y/n]
```

### 严重问题

```
Aether 环境诊断
===============
诊断时间: 2026-03-07 12:00:00

[✗] aether CLI
    错误: command not found

[?] 配置文件
    跳过: 需要先安装 CLI

[?] 集群连接
    跳过: 需要先配置

[?] SSH 配置
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
| 正常状态 | 24 小时 | 无需重复诊断 |
| 降级状态 | 4 小时 | 提醒修复问题 |
| 未知状态 | 立即过期 | 需要运行诊断 |

**Skills 读取缓存时的判断逻辑**：

```bash
# 读取上次诊断时间
LAST_DIAGNOSIS=$(yq '.environment.last_diagnosis' ~/.aether/config.yaml)
STATUS=$(yq '.environment.status' ~/.aether/config.yaml)

# 计算是否过期
if is_expired "$LAST_DIAGNOSIS" "$STATUS"; then
  echo "环境状态已过期，建议运行 /aether:doctor"
fi
```

---

## 与其他 Skills 的集成

### aether-volume 调用前检查

```markdown
## aether-volume Skill 中的环境检查

执行 volume 操作前:

1. 读取 config.yaml 的 environment 字段
2. 检查 status:
   - healthy: 直接执行
   - degraded: 警告但允许执行
   - unknown: 提示运行 /aether:doctor
3. 如果涉及 SSH 操作，检查 ssh.nodes_tested 中目标节点状态

示例输出:
```
环境状态: healthy (上次诊断: 2小时前)
目标节点 heavy-1: SSH 连接正常 ✓

继续执行 volume 创建...
```
```

### 错误时的诊断建议

当任何 Skill 执行失败时：

```markdown
## 通用错误处理

执行失败时，根据错误类型提供建议:

| 错误类型 | 建议 |
|---------|-----|
| `aether: command not found` | 安装 aether CLI |
| `config file not found` | 运行 /aether:setup |
| `connection refused` | 运行 /aether:doctor --cluster |
| `permission denied (SSH)` | 运行 /aether:doctor --ssh |
| `timeout` | 运行 /aether:doctor 检查网络 |
```

---

## 命令行等价操作

如果需要在终端直接诊断：

```bash
# 快速检查 CLI
aether version

# 检查配置
cat ~/.aether/config.yaml

# 测试 Nomad
curl -s http://192.168.69.70:4646/v1/status/leader

# 测试 Consul
curl -s http://192.168.69.70:8500/v1/status/leader

# 测试 SSH
ssh -o ConnectTimeout=5 root@192.168.69.80 "hostname"

# 获取节点列表
curl -s http://192.168.69.70:4646/v1/nodes | jq '.[] | {name, address, status, class: .NodeClass}'
```

---

## 参考文档

- [aether-setup Skill](../aether-setup/SKILL.md) - 配置集群入口
- [aether-volume Skill](../aether-volume/SKILL.md) - Volume 管理
- [SSH 配置指南](../../docs/guides/light-nodes-ssh-setup-tutorial.md) - 详细 SSH 配置

---

**Skill 版本**: 1.0.0
**最后更新**: 2026-03-07
**维护者**: 10CG Infrastructure Team
