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

> **版本**: 1.2.0 | **优先级**: P1

## 前置检查

**⚠️ 此 Skill 需要 aether CLI**

检测 CLI:
```bash
command -v aether || test -f ~/.aether/aether || test -f ~/.aether/aether.exe
```

**如果未安装**: 提示用户运行 `/aether:doctor` 完成安装。

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
