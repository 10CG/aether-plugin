# SSH 诊断和修复

## 检查密钥文件

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

## 检查 SSH Config

```bash
cat ~/.ssh/config 2>/dev/null | grep -A5 -E 'Host.*(heavy|light|infra)'
```

## 推荐的 SSH Config

```
# ~/.ssh/config
Host heavy-* light-* infra-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    ConnectTimeout 10
```

## 修复权限

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod 644 ~/.ssh/*.pub
```

## 测试 SSH 连接

```bash
# 从集群拓扑获取节点 IP
for ip in "${NODE_IPS[@]}"; do
  echo -n "Testing $ip... "
  if ssh -o ConnectTimeout=5 -o BatchMode=yes root@$ip "echo ok" 2>/dev/null; then
    echo "✓"
  else
    echo "✗"
  fi
done
```

## 连接问题排查

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `Permission denied` | 公钥未添加 | 通过 Proxmox 添加公钥 |
| `Connection timed out` | 网络不通 | 检查网络/防火墙 |
| `Host key verification failed` | known_hosts 冲突 | `ssh-keygen -R <ip>` |
| `no such identity` | 密钥文件不存在 | 生成或指定密钥 |

## 添加公钥到节点

### 方法 1: ssh-copy-id

```bash
ssh-copy-id root@192.168.69.80
```

### 方法 2: 手动添加 (通过 Proxmox)

```bash
# 在节点上执行
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... your@email.com" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```
