# SSH 诊断和修复

> **更新**: 2026-03-19 | 多层诊断方法论 + 根因分析决策树

## 多层诊断方法

SSH 故障涉及多个层次。逐层排查可快速定位根因，避免在错误层面浪费时间。

| 层级 | 维度 | 关键问题 |
|------|------|---------|
| L1 网络 | TCP 端口 22 可达性 | 是网络不通还是 SSH 服务问题？ |
| L2 名称解析 | IP vs hostname 分别测试 | hostname 失败但 IP 成功 → DNS/解析问题 |
| L3 认证 | BatchMode 隔离认证、`-vvv` 握手细节 | 密钥类型对不对？公钥有没有被接受？ |
| L4 远程侧 | authorized_keys、sshd 配置、权限 | 远程节点配置是否正确？ |
| L5 应用层 | CLI 如何解析节点名 | Go SSH 库不读 ~/.ssh/config |

---

## L1: 网络层检查

确认 TCP 端口 22 是否可达，区分网络问题和 SSH 服务问题：

```bash
nc -zw5 192.168.1.80 22          # netcat 探测
timeout 5 bash -c '< /dev/tcp/192.168.1.80/22'  # 无需额外工具
ssh-keyscan -T5 192.168.1.80     # 同时获取 host key 信息
```

- 超时 → 防火墙或网络路由问题
- Connection refused → 端口未监听 (sshd 未运行或端口不同)
- 成功 → 进入 L2

## L2: 名称解析层

分别用 IP 和 hostname 测试，区分名称解析故障和认证故障：

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes root@192.168.1.80 "echo ok"
ssh -o ConnectTimeout=5 -o BatchMode=yes root@heavy-1 "echo ok"
```

如果 IP 成功但 hostname 失败，检查解析来源：

- `~/.ssh/config` 中的 Host/Hostname 映射
- `/etc/hosts` 条目
- DNS 解析 (`dig heavy-1`, `getent hosts heavy-1`)
- Nomad/Consul 服务发现注册

## L3: 认证层检查

用 BatchMode 和 verbose 模式隔离认证问题：

```bash
ssh -vvv -o BatchMode=yes root@heavy-1 2>&1 | head -80
```

重点观察 verbose 输出中的：

- **Offering public key**: 客户端提供了哪些密钥类型 (ed25519/RSA/ECDSA)
- **Server accepts key**: 服务端是否接受
- **Authentication methods**: 服务端支持哪些认证方式
- **Trying private key**: 哪些密钥文件被尝试

## L4: 远程侧检查

当可通过其他路径 (Proxmox 控制台、另一节点跳转) 访问目标节点时：

### authorized_keys

```bash
cat /root/.ssh/authorized_keys    # 公钥内容是否正确
ls -la /root/.ssh/                # 目录权限应为 700
ls -la /root/.ssh/authorized_keys # 文件权限应为 600
stat -c "%U:%G" /root/.ssh/       # 属主应为 root:root
```

### sshd 配置

```bash
grep -E '^(PermitRootLogin|PubkeyAuthentication|AuthorizedKeysFile)' /etc/ssh/sshd_config
```

关注项：
- `PermitRootLogin` 需为 `yes` 或 `prohibit-password`
- `PubkeyAuthentication` 需为 `yes`
- `AuthorizedKeysFile` 路径是否为默认值

### sshd 服务状态

```bash
systemctl status sshd
journalctl -u sshd -n 20 --no-pager   # 最近日志，关注 auth 失败原因
```

## L5: 应用层 (aether CLI)

aether CLI 使用 Go 的 `x/crypto/ssh` 库，与系统 SSH 客户端行为不同：

- **不解析** `~/.ssh/config` (Host 别名、ProxyJump 等无效)
- 节点名解析依赖：Nomad API 查询节点列表 → IP 映射
- 密钥路径依赖：配置文件中指定或默认 `~/.ssh/id_ed25519`
- 终端 SSH 正常但 CLI 失败 → 多半是 config 解析差异

---

## 根因分析决策树

```
TCP 端口 22 是否可达？
├─ 否 → 网络/防火墙问题
│       检查路由、安全组、sshd 是否监听
│
└─ 是 → 用 IP 直连认证是否成功？
         ├─ 否 → 远程侧问题
         │       检查 authorized_keys 内容和权限
         │       检查 sshd_config (PermitRootLogin, PubkeyAuth)
         │       检查密钥类型匹配 (ed25519 vs RSA)
         │
         └─ 是 → 用 hostname 连接是否成功？
                  ├─ 否 → 名称解析问题
                  │       检查 SSH config / /etc/hosts / DNS
                  │
                  └─ 是 → 终端成功但 CLI 失败？
                           ├─ 否 → SSH 正常
                           └─ 是 → Go SSH 库差异
                                   CLI 不读 ~/.ssh/config
                                   检查 aether 配置中的密钥路径
```

---

## 连接问题排查

| 错误 | 可能原因 | 诊断层 | 排查方向 |
|------|---------|--------|---------|
| `Connection timed out` | 网络不通/防火墙 | L1 | `nc -zw5` 确认端口可达性 |
| `Connection refused` | sshd 未运行或端口不同 | L1 | 远程检查 `systemctl status sshd` |
| `Permission denied (publickey)` | 公钥未授权 | L3/L4 | `-vvv` 查看提供了哪些密钥；远程查 authorized_keys |
| `Host key verification failed` | known_hosts 冲突 | L3 | `ssh-keygen -R <ip>` 清除旧条目 |
| `no such identity` | 密钥文件不存在 | L3 | 检查 IdentityFile 路径和文件权限 |
| hostname 失败，IP 成功 | 名称解析问题 | L2 | 检查 SSH config / /etc/hosts / DNS |
| ed25519 被拒绝 | 密钥类型不被接受 | L3/L4 | 远程 sshd_config 检查 PubkeyAcceptedKeyTypes |
| Agent forwarding 失败 | agent 未加载密钥 | L3 | `ssh-add -l` 确认 agent 中有密钥 |

---

## 检查本地密钥和配置

### 密钥文件

```bash
stat -c "%a %n" ~/.ssh/id_* 2>/dev/null    # 权限应为 600
```

### SSH Config

```bash
cat ~/.ssh/config 2>/dev/null | grep -A5 -E 'Host.*(heavy|light|infra)'
```

### 推荐配置

```
Host heavy-* light-* infra-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    ConnectTimeout 10
```

### 修复权限

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/*.pub
```

---

## 添加公钥到节点

### 方法 1: ssh-copy-id

```bash
ssh-copy-id root@192.168.1.80
```

### 方法 2: 手动添加 (通过 Proxmox 控制台)

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... your@email.com" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```
