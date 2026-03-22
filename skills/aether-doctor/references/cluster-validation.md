# 集群拓扑获取和配置验证

## 获取集群拓扑

### 获取 Leader 信息

```bash
# 返回 RPC 端口 (4647)，不是 HTTP 端口 (4646)
NOMAD_LEADER=$(curl -s "${NOMAD_ADDR}/v1/status/leader")
# 示例: "192.168.1.71:4647"
```

### 获取 Server 节点列表

```bash
# 从 agent 自身信息提取 Raft 配置
curl -s "${NOMAD_ADDR}/v1/agent/self" | jq '{
  nodeName: .member.Name,
  nodeAddr: .member.Addr,
  isLeader: (.stats.nomad.leader == "true"),
  raftConfig: .stats.raft.latest_configuration
}'
```

### 获取 Client 节点列表

```bash
curl -s "${NOMAD_ADDR}/v1/nodes" | jq '[.[] | {
  name: .Name,
  ip: .Address,
  status: .Status,
  class: .NodeClass,
  drivers: [.Drivers | keys[]]
}]'
```

## 配置验证逻辑

**核心原则**: 检查配置的地址是否在 Server 列表中（任意一个即可）

```bash
# 用户配置的地址
CONFIG_NOMAD="192.168.1.70:4646"

# 获取 Server 列表（HTTP 端口）
SERVER_HTTP_ADDRS=$(curl -s "${NOMAD_ADDR}/v1/agent/self" | \
  grep -oE 'Address:[0-9.]+:[0-9]+' | \
  while read line; do
    IP=$(echo $line | cut -d: -f2)
    RPC_PORT=$(echo $line | cut -d: -f3)
    HTTP_PORT=$((RPC_PORT - 1))  # 4647 → 4646
    echo "$IP:$HTTP_PORT"
  done)

# 验证
IS_VALID=false
for server in $SERVER_HTTP_ADDRS; do
  if [ "$CONFIG_NOMAD" = "$server" ]; then
    IS_VALID=true
    break
  fi
done

if $IS_VALID; then
  echo "✓ 配置有效: $CONFIG_NOMAD"
else
  echo "✗ 配置无效，可用 Server: $SERVER_HTTP_ADDRS"
fi
```

## 重要注意事项

1. **RPC vs HTTP 端口**
   - `/v1/status/leader` 返回 RPC 端口 (4647)
   - API 请求使用 HTTP 端口 (4646)
   - 转换: HTTP = RPC - 1

2. **Leader 会变化**
   - 不要用 leader 地址判断配置正确性
   - 任意 Server 都可接受 API 请求

3. **配置来源优先级**
   ```
   环境变量 > 项目配置 > 全局配置
   ```

## 连接测试

### Nomad 连接

```bash
# 测试可达性
curl -s "${NOMAD_ADDR}/v1/status/leader"

# 获取版本
curl -s "${NOMAD_ADDR}/v1/agent/self" | jq '.config.Version'

# 验证是 server
curl -s "${NOMAD_ADDR}/v1/agent/self" | jq '.stats.nomad.server'
```

### Consul 连接

```bash
# 测试可达性
curl -s "${CONSUL_ADDR}/v1/status/leader"

# 获取版本
curl -s "${CONSUL_ADDR}/v1/agent/self" | jq '.Config.Version'
```

## 连接问题排查

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `connection refused` | 服务未运行 | 启动 Nomad/Consul |
| `timeout` | 网络不通 | 检查防火墙/网络 |
| `401/403` | 认证问题 | 检查 Token |
| `unknown host` | DNS 解析失败 | 使用 IP 或配置 hosts |
