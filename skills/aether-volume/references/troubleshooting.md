# 故障排查

## SSH 连接失败

**错误**: `SSH 连接失败: ssh: unable to authenticate`

**解决方案**:
1. 检查 SSH 密钥配置：`ls -la ~/.ssh/id_ed25519`
2. 测试连接：`ssh root@192.168.1.80 "hostname"`
3. 使用 `--ssh-key` 指定密钥路径
4. 或设置 `AETHER_SSH_PASSWORD` 环境变量

## Nomad 重启失败

**错误**: `Nomad failed to start`

**解决方案**:
- 配置会自动回滚，无需手动干预
- 检查节点日志：`ssh root@<node> "journalctl -u nomad -n 50"`
- 如果自动回滚失败，手动恢复：
  ```bash
  ssh root@<node> "mv /opt/nomad/config/client.hcl.bak /opt/nomad/config/client.hcl && systemctl restart nomad"
  ```

## Volume 未生效

**检查步骤**:

```bash
# 1. 确认配置存在
aether volume list --node heavy-1

# 2. 确认目录存在
ssh root@192.168.1.80 "ls -la /opt/aether-volumes/"

# 3. 确认 Nomad 识别
ssh root@192.168.1.80 "nomad node status -self | grep -A 10 'Host Volumes'"

# 4. 查看 Nomad 配置
ssh root@192.168.1.80 "grep -A 3 'host_volume' /opt/nomad/config/client.hcl"
```

## 常见错误信息

| 错误 | 原因 | 解决方案 |
|-----|------|---------|
| `node not found` | 节点名错误或节点离线 | 检查 `nomad node status` |
| `permission denied` | SSH 认证失败 | 检查密钥权限和配置 |
| `volume already exists` | Volume 已存在 | 先删除再创建，或使用不同名称 |
| `nomad validation failed` | client.hcl 语法错误 | 检查配置文件格式 |
