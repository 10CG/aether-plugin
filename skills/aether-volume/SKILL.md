---
name: aether-volume
description: |
  管理 Nomad 节点的 host volume 配置。支持创建、列出、删除 volume。

  使用场景："配置 volume"、"创建 host volume"、"删除 volume"、"查看 volume"
argument-hint: "[create|list|delete] [options]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, AskUserQuestion
dependencies:
  cli:
    required: true
    min_version: "0.7.0"
---

# Aether Volume 管理 (aether-volume)

> **版本**: 1.3.0 | **优先级**: P1

## 前置检查

**⚠️ 此 Skill 需要 aether CLI**

```bash
# 使用共享检测脚本
source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
require_aether_cli || exit 1
```

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

## 命令概览

### 创建 Volume

```bash
aether volume create --node <node> --project <project> --volumes <list>
```

**常用参数**:
- `--dry-run`: 预览操作
- `--ssh-key`: SSH 私钥路径

```bash
# 示例
aether volume create --node heavy-1 --project my-api --volumes data,logs
```

### 列出 Volume

```bash
aether volume list --node <node>

# 过滤项目
aether volume list --node heavy-1 --project my-api
```

### 删除 Volume

```bash
# ⚠️ 会删除数据
aether volume delete --node <node> --project <project> --volumes <list> --yes
```

**详细命令说明**: 见 [command-details.md](references/command-details.md)

---

## 创建前后检查

### 幂等性检查（创建前必做）

创建前先确认目标 volume 不存在，避免重复 `host_volume` 配置导致 Nomad 重启失败：

```bash
# 检查已有 volume
aether volume list --node heavy-1 --project my-api
```

如果目标 volume 已存在，提示用户跳过创建。

### 创建后验证（SSH 目录检查）

`aether volume list` 验证后，通过 SSH 直接检查目录确认实际状态：

```bash
# 验证目录存在和权限
ssh root@heavy-1 "ls -la /opt/aether-volumes/my-api/"
```

预期输出每个 volume 子目录权限为 `drwxrwxrwx`。

---

## 安全保障机制

| 保障 | 机制 | 触发条件 |
|------|------|---------|
| **幂等性** | 创建前检查 `aether volume list` | 每次创建 |
| **原子性** | 修改前备份 `client.hcl → client.hcl.bak` | 每次写配置 |
| **自动回滚** | Nomad 重启失败时恢复 `.bak` | `systemctl restart nomad` 失败 |
| **创建后验证** | SSH 检查目录存在性和权限 | 每次创建 |

**为什么幂等性检查重要**: Nomad `client.hcl` 不允许重复的 `host_volume` 块。重复插入会导致 Nomad 重启失败，需要手动恢复配置。

---

## 常见故障模式

### SSH 连接问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `permission denied` | 密钥权限不是 600 | `chmod 600 ~/.ssh/id_ed25519` |
| `host key verification failed` | known_hosts 冲突 | `ssh-keygen -R <node-ip>` |
| `connection refused` | SSH 服务未运行 | `ping <node-ip>` 确认网络，检查 sshd |
| `timeout` | 网络不可达 | 检查 VPN/防火墙/路由 |

**SSH 诊断步骤** (逐步升级):
1. `ssh -v root@heavy-1` — 查看详细握手过程
2. `ssh-keygen -R <node-ip>` — 清除旧 host key
3. `ls -la ~/.ssh/id_ed25519` — 确认权限为 `-rw-------`
4. `ssh-add ~/.ssh/id_ed25519` — 手动加载密钥

### Nomad 重启失败

CLI 自动从 `.bak` 回滚配置。如果自动回滚也失败：

```bash
ssh root@<node> "mv /opt/nomad/config/client.hcl.bak /opt/nomad/config/client.hcl && systemctl restart nomad"
```

**根因排查**: `ssh root@<node> "journalctl -u nomad -n 50"` 查看 Nomad 日志。

---

## 配置要求

### SSH 认证

volume 命令需要 SSH 访问节点。推荐使用 SSH Config：

```bash
# ~/.ssh/config
Host heavy-* light-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
```

**详细 SSH 配置**: 见 [ssh-authentication.md](references/ssh-authentication.md)

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

## 执行流程

```
创建 Volume:
  1. 幂等性检查 — 先用 aether volume list 确认目标 volume 是否已存在
     → 已存在: 提示用户，跳过创建（避免重复 host_volume 配置）
     → 不存在: 继续
  2. 解析节点名 → IP
  3. SSH 连接
  4. 创建目录 + 设置权限
  5. 备份配置
  6. 插入 host_volume 到 client {} 块
  7. 重启 Nomad
  8. 验证服务
  9. 清理备份 / 回滚
  10. 创建后验证 — SSH 直接检查目录存在性和权限:
      ssh root@<node> "ls -la /opt/aether-volumes/<project>/"

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

## References

- **[command-details.md](references/command-details.md)** - 完整命令参数、示例和执行流程
- **[ssh-authentication.md](references/ssh-authentication.md)** - SSH 认证方式配置
- **[nomad-configuration.md](references/nomad-configuration.md)** - 生成的 Nomad 配置和 Job 使用示例
- **[troubleshooting.md](references/troubleshooting.md)** - 常见问题排查
- **[best-practices.md](references/best-practices.md)** - 最佳实践和生产环境建议

---

## 外部参考

- [aether volume 使用指南](../../docs/guides/aether-volume-usage.md)
- [SSH 配置指南](../../docs/guides/SSH_SETUP_GUIDE.md)
- [完整测试报告](../../aether-cli/COMPLETE_TEST_REPORT.md)

---

**Skill 版本**: 1.1.0
**最后更新**: 2026-03-12
**维护者**: 10CG Infrastructure Team
