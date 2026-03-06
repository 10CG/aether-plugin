---
name: aether-volume
description: |
  管理 Nomad 节点的 host volume 配置。支持创建、列出、删除 volume。

  使用场景："配置 volume"、"创建 host volume"、"删除 volume"、"查看 volume"
argument-hint: "[create|list|delete] [options]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, AskUserQuestion
---

# Aether Volume 管理 (aether-volume)

> **版本**: 1.0.0 | **优先级**: P1

## 快速开始

### 使用场景

- 为新项目配置持久化存储
- 查看已配置的 volume
- 清理不再使用的 volume
- 为有状态服务配置数据目录

### 不使用场景

- 无状态服务（不需要持久化）
- 使用外部存储（NFS、Ceph 等）
- 临时数据存储（使用容器内存储）

---

## 命令详解

### 1. 创建 Volume

```bash
aether volume create \
  --node <node-name> \
  --project <project-name> \
  --volumes <volume-list>
```

**参数**:
- `--node`: 节点名称（如 heavy-1）或 IP 地址
- `--project`: 项目名称
- `--volumes`: volume 列表，逗号分隔（如 data,logs,uploads）
- `--dry-run`: 预览操作（可选）
- `--ssh-key`: SSH 私钥路径（可选）

**示例**:

```bash
# 基本用法
aether volume create --node heavy-1 --project my-api --volumes data,logs

# 预览操作
aether volume create --node heavy-1 --project my-api --volumes data --dry-run

# 使用 IP 地址
aether volume create --node 192.168.69.80 --project my-api --volumes data

# 指定 SSH 密钥
aether volume create --node heavy-1 --project my-api --volumes data \
  --ssh-key ~/.ssh/id_ed25519
```

**执行流程**:
1. 解析节点名称（如果是节点名，通过 Nomad API 解析为 IP）
2. 通过 SSH 连接到目标节点
3. 创建目录：`/opt/aether-volumes/<project>/<volume>`
4. 设置权限：`chmod -R 777`
5. 备份 Nomad 配置：`client.hcl.bak`
6. 在 `client.hcl` 的 `client {}` 块内添加 `host_volume` 配置
7. 重启 Nomad 服务
8. 验证 Nomad 正常运行
9. 成功后删除备份，失败时自动回滚

**输出示例**:
```
🔧 准备在节点 192.168.69.80 上创建 volume...
   项目: my-api
   Volumes: data, logs

✅ Volume 创建成功!
✓ Created directory: /opt/aether-volumes/my-api/data
✓ Created directory: /opt/aether-volumes/my-api/logs
✓ Backed up client.hcl
✓ Updated client.hcl
✓ Configuration updated (validation skipped)
✓ Nomad restarted successfully
```

---

### 2. 列出 Volume

```bash
aether volume list --node <node-name>
```

**参数**:
- `--node`: 节点名称或 IP（必需）
- `--project`: 过滤项目名称（可选）
- `--ssh-key`: SSH 私钥路径（可选）

**示例**:

```bash
# 列出节点上所有 volume
aether volume list --node heavy-1

# 过滤特定项目
aether volume list --node heavy-1 --project my-api

# JSON 输出
aether volume list --node heavy-1 --json
```

**输出示例**:
```
节点 192.168.69.80 上的 host volume:

  • my-api-data
    路径: /opt/aether-volumes/my-api/data
    只读: false
    存在: true

  • my-api-logs
    路径: /opt/aether-volumes/my-api/logs
    只读: false
    存在: true
```

---

### 3. 删除 Volume

```bash
aether volume delete \
  --node <node-name> \
  --project <project-name> \
  --volumes <volume-list> \
  --yes
```

**⚠️ 警告**: 此操作会删除所有数据，请谨慎使用！

**参数**:
- `--node`: 节点名称或 IP（必需）
- `--project`: 项目名称（必需）
- `--volumes`: volume 列表，逗号分隔（必需）
- `--yes`: 跳过确认提示（可选）
- `--dry-run`: 预览操作（可选）
- `--ssh-key`: SSH 私钥路径（可选）

**示例**:

```bash
# 删除 volume（会提示确认）
aether volume delete --node heavy-1 --project my-api --volumes data,logs

# 跳过确认（用于自动化）
aether volume delete --node heavy-1 --project my-api --volumes data --yes

# 预览删除操作
aether volume delete --node heavy-1 --project my-api --volumes data --dry-run
```

**执行流程**:
1. 提示确认（除非使用 `--yes` 或 `--dry-run`）
2. 通过 SSH 连接到目标节点
3. 删除目录：`rm -rf /opt/aether-volumes/<project>/<volume>`
4. 备份 Nomad 配置
5. 从 `client.hcl` 中移除 `host_volume` 配置
6. 重启 Nomad 服务
7. 验证 Nomad 正常运行
8. 成功后删除备份，失败时自动回滚

---

## 配置要求

### SSH 认证

volume 命令需要 SSH 访问节点。支持以下认证方式：

#### 方式 1: SSH Config（推荐）

```bash
# 编辑 ~/.ssh/config
Host heavy-* light-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
```

配置后无需每次指定 `--ssh-key` 参数。

#### 方式 2: 命令行参数

```bash
aether volume create --node heavy-1 --project test --volumes data \
  --ssh-key ~/.ssh/id_ed25519
```

#### 方式 3: 环境变量

```bash
export AETHER_SSH_PASSWORD="your-password"
aether volume create --node heavy-1 --project test --volumes data
```

### SSH 公钥配置

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
   ssh root@192.168.69.80 "hostname"
   ```

**参考文档**: [SSH 配置指南](../../docs/guides/SSH_SETUP_GUIDE.md)

---

## 生成的配置

### 目录结构

```
/opt/aether-volumes/
└── <project-name>/
    ├── data/
    ├── logs/
    └── uploads/
```

### Nomad 配置

```hcl
# /opt/nomad/config/client.hcl
client {
  enabled    = true
  node_class = "heavy_workload"

  # <project-name> volumes
  host_volume "<project-name>-data" {
    path      = "/opt/aether-volumes/<project-name>/data"
    read_only = false
  }

  host_volume "<project-name>-logs" {
    path      = "/opt/aether-volumes/<project-name>/logs"
    read_only = false
  }

  server_join {
    retry_join = ["192.168.69.70", "192.168.69.71", "192.168.69.72"]
  }
}
```

### 在 Nomad Job 中使用

```hcl
job "my-api" {
  group "app" {
    # 声明使用 host volume
    volume "data" {
      type      = "host"
      source    = "my-api-data"
      read_only = false
    }

    task "app" {
      # 挂载到容器内
      volume_mount {
        volume      = "data"
        destination = "/app/data"
        read_only   = false
      }

      config {
        image = "my-api:latest"
        ports = ["http"]
      }
    }
  }
}
```

---

## 故障排查

### SSH 连接失败

**错误**: `SSH 连接失败: ssh: unable to authenticate`

**解决方案**:
1. 检查 SSH 密钥配置：`ls -la ~/.ssh/id_ed25519`
2. 测试连接：`ssh root@192.168.69.80 "hostname"`
3. 使用 `--ssh-key` 指定密钥路径
4. 或设置 `AETHER_SSH_PASSWORD` 环境变量

### Nomad 重启失败

**错误**: `Nomad failed to start`

**解决方案**:
- 配置会自动回滚，无需手动干预
- 检查节点日志：`ssh root@<node> "journalctl -u nomad -n 50"`
- 如果自动回滚失败，手动恢复：
  ```bash
  ssh root@<node> "mv /opt/nomad/config/client.hcl.bak /opt/nomad/config/client.hcl && systemctl restart nomad"
  ```

### Volume 未生效

**检查步骤**:

```bash
# 1. 确认配置存在
aether volume list --node heavy-1

# 2. 确认目录存在
ssh root@192.168.69.80 "ls -la /opt/aether-volumes/"

# 3. 确认 Nomad 识别
ssh root@192.168.69.80 "nomad node status -self | grep -A 10 'Host Volumes'"

# 4. 查看 Nomad 配置
ssh root@192.168.69.80 "grep -A 3 'host_volume' /opt/nomad/config/client.hcl"
```

---

## 最佳实践

### 1. 先预览再执行

```bash
# 预览操作
aether volume create --node heavy-1 --project test --volumes data --dry-run

# 确认无误后执行
aether volume create --node heavy-1 --project test --volumes data
```

### 2. 使用明确的节点名

```bash
# 推荐：使用节点名（自动解析）
aether volume create --node heavy-1 --project test --volumes data

# 或使用 IP（直接连接）
aether volume create --node 192.168.69.80 --project test --volumes data
```

### 3. 定期清理不用的 volume

```bash
# 列出所有 volume
aether volume list --node heavy-1

# 删除不再使用的
aether volume delete --node heavy-1 --project old-project --volumes data --yes
```

### 4. 生产环境备份数据

```bash
# 删除前备份
ssh root@heavy-1 "tar -czf /tmp/my-api-backup.tar.gz /opt/aether-volumes/my-api"

# 下载备份
scp root@heavy-1:/tmp/my-api-backup.tar.gz ./

# 删除 volume
aether volume delete --node heavy-1 --project my-api --volumes data --yes
```

---

## 常见 Volume 配置

| 项目类型 | 推荐 volumes | 说明 |
|---------|-------------|------|
| 数据库 | `data` | 数据文件 |
| Web 应用 | `data,logs,uploads` | 数据、日志、上传文件 |
| 静态站点 | `logs` | 访问日志 |
| API 服务 | `logs` | 应用日志 |
| 文件服务 | `data,uploads` | 文件存储 |

---

## 参考文档

- [aether volume 使用指南](../../docs/guides/aether-volume-usage.md) - 详细使用指南
- [aether volume 快速参考](../../docs/guides/aether-volume-quick-reference.md) - 快速参考卡片
- [aether-plugin 集成指南](../../docs/guides/aether-plugin-volume-integration.md) - Plugin 集成指南
- [SSH 配置指南](../../aether-cli/SSH_SETUP_GUIDE.md) - SSH 配置详细步骤
- [完整测试报告](../../aether-cli/COMPLETE_TEST_REPORT.md) - 功能测试报告

---

## 技术细节

### 安全机制

1. **配置备份**: 每次修改前自动备份 `client.hcl`
2. **自动回滚**: Nomad 启动失败时自动恢复配置
3. **删除确认**: 防止误删除数据
4. **SSH 密钥认证**: 比密码更安全

### 执行流程

```
创建 Volume:
  1. 解析节点名 → IP
  2. SSH 连接
  3. 创建目录 + 设置权限
  4. 备份配置
  5. 插入 host_volume 到 client {} 块
  6. 重启 Nomad
  7. 验证服务
  8. 清理备份 / 回滚

删除 Volume:
  1. 确认操作
  2. SSH 连接
  3. 删除目录
  4. 备份配置
  5. 移除 host_volume 配置
  6. 重启 Nomad
  7. 验证服务
  8. 清理备份 / 回滚
```

---

**Skill 版本**: 1.0.0
**最后更新**: 2026-03-07
**维护者**: 10CG Infrastructure Team
