# 环境缓存

## 缓存位置规则

| 配置来源 | 缓存位置 |
|---------|---------|
| `./.aether/config.yaml` | `./.aether/environment.yaml` |
| `./.env` | `./.aether/environment.yaml` |
| `~/.aether/config.yaml` | `~/.aether/environment.yaml` |
| 环境变量 | `~/.aether/environment.yaml` |

## 缓存文件格式

```yaml
# Aether 环境状态缓存
# 由 aether-doctor 自动维护，请勿手动编辑

last_diagnosis: "2026-03-08T12:00:00Z"
status: "healthy"  # healthy | degraded | unknown
cli_version: "0.7.0"
cli_path: "/home/user/.aether/aether"

config:
  source: "project"  # project | global | env
  nomad: "http://192.168.69.70:4646"
  consul: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"
  validated: true

cluster:
  nomad_version: "1.11.2"
  consul_version: "1.22.3"
  current_leader: "192.168.69.71"
  datacenter: "dc1"
  region: "global"

  servers:
    - name: "infra-server-1"
      ip: "192.168.69.70"
      http_port: 4646
      role: "follower"

  clients:
    - name: "heavy-1"
      ip: "192.168.69.80"
      class: "heavy_workload"
      drivers: ["docker", "exec"]
      status: "ready"

ssh:
  key_path: "~/.ssh/id_ed25519"
  key_exists: true
  key_valid: true
  nodes_tested:
    heavy-1: { ip: "192.168.69.80", status: "ok" }
```

## 缓存有效期

| 状态 | 有效期 |
|------|-------|
| `healthy` | 24 小时 |
| `degraded` | 4 小时 |
| `unknown` | 立即过期 |

## Skills 读取示例

```bash
# 获取 Server 列表
SERVERS=$(yq '.cluster.servers[] | "\(.name) \(.ip)"' ./.aether/environment.yaml)

# 获取 Heavy 节点
HEAVY_NODES=$(yq '.cluster.clients[] | select(.class == "heavy_workload") | .ip' ./.aether/environment.yaml)

# 检查 SSH 状态
SSH_STATUS=$(yq '.ssh.nodes_tested.heavy-1.status' ./.aether/environment.yaml)
```

## 判断缓存是否过期

```bash
LAST_DIAGNOSIS=$(yq '.last_diagnosis' $CACHE 2>/dev/null)
STATUS=$(yq '.status' $CACHE 2>/dev/null)

# 根据状态计算过期时间
case $STATUS in
  healthy) MAX_AGE=24 ;;
  degraded) MAX_AGE=4 ;;
  *) MAX_AGE=0 ;;
esac

# 检查是否过期
if is_older_than "$LAST_DIAGNOSIS" "$MAX_AGE hours"; then
  echo "缓存已过期，建议运行 /aether:doctor"
fi
```
