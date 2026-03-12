# 最佳实践

## 1. 先预览再执行

```bash
# 预览操作
aether volume create --node heavy-1 --project test --volumes data --dry-run

# 确认无误后执行
aether volume create --node heavy-1 --project test --volumes data
```

## 2. 使用明确的节点名

```bash
# 推荐：使用节点名（自动解析）
aether volume create --node heavy-1 --project test --volumes data

# 或使用 IP（直接连接）
aether volume create --node 192.168.69.80 --project test --volumes data
```

## 3. 定期清理不用的 volume

```bash
# 列出所有 volume
aether volume list --node heavy-1

# 删除不再使用的
aether volume delete --node heavy-1 --project old-project --volumes data --yes
```

## 4. 生产环境备份数据

```bash
# 删除前备份
ssh root@heavy-1 "tar -czf /tmp/my-api-backup.tar.gz /opt/aether-volumes/my-api"

# 下载备份
scp root@heavy-1:/tmp/my-api-backup.tar.gz ./

# 删除 volume
aether volume delete --node heavy-1 --project my-api --volumes data --yes
```

## 5. 项目类型与 Volume 配置

| 项目类型 | 推荐 volumes | 说明 |
|---------|-------------|------|
| 数据库 | `data` | 数据文件 |
| Web 应用 | `data,logs,uploads` | 数据、日志、上传文件 |
| 静态站点 | `logs` | 访问日志 |
| API 服务 | `logs` | 应用日志 |
| 文件服务 | `data,uploads` | 文件存储 |
