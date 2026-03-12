# 命令详解

## 1. 创建 Volume

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

## 2. 列出 Volume

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

## 3. 删除 Volume

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

## 安全机制

1. **配置备份**: 每次修改前自动备份 `client.hcl`
2. **自动回滚**: Nomad 启动失败时自动恢复配置
3. **删除确认**: 防止误删除数据
4. **SSH 密钥认证**: 比密码更安全
