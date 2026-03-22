# SSH 认证配置

## 认证方式

### 方式 1: SSH Config（推荐）

```bash
# 编辑 ~/.ssh/config
Host heavy-* light-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
```

配置后无需每次指定 `--ssh-key` 参数。

### 方式 2: 命令行参数

```bash
aether volume create --node heavy-1 --project test --volumes data \
  --ssh-key ~/.ssh/id_ed25519
```

### 方式 3: 环境变量

```bash
export AETHER_SSH_PASSWORD="your-password"
aether volume create --node heavy-1 --project test --volumes data
```

## SSH 公钥配置

如果 SSH 连接失败，需要将公钥添加到节点：

1. 查看公钥：
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```

2. 通过 Proxmox 控制台登录节点，执行：
   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   echo "ssh-ed25519 AAAA... your-email@example.com" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

3. 测试连接：
   ```bash
   ssh root@192.168.1.80 "hostname"
   ```

## 参考文档

- [SSH 配置指南](../../../docs/guides/SSH_SETUP_GUIDE.md)
