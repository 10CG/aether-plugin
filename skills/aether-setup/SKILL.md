---
name: aether-setup
description: |
  Aether 集群配置引导。首次使用时配置集群入口地址，支持全局配置和项目级配置。
  其他 skills 依赖此配置来连接 Aether 集群。

  使用场景："配置 Aether 集群"、"首次使用 Aether"、"切换集群"、"查看当前配置"
argument-hint: "[--global|--project|--show]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Write, Bash, AskUserQuestion
---

# Aether 集群配置 (aether-setup)

> **版本**: 0.1.0 | **优先级**: P0

## 快速开始

### 使用场景

- 首次使用 aether-plugin，需要配置集群地址
- 切换到不同的 Aether 集群
- 查看当前配置的集群信息
- 为特定项目配置不同的集群

### 配置层级

配置按以下优先级读取（高 → 低）：

```
1. 项目级 .env          → 当前项目目录下的 .env 文件
2. 用户级全局配置        → ~/.aether/config.yaml
3. 插件默认值           → 无（必须配置入口地址）
```

---

## 配置内容

### 必须配置（入口地址）

| 配置项 | 环境变量 | 说明 |
|--------|---------|------|
| Nomad 地址 | `NOMAD_ADDR` | Nomad API 入口，如 `http://192.168.69.70:4646` |
| Consul 地址 | `CONSUL_HTTP_ADDR` | Consul API 入口，如 `http://192.168.69.70:8500` |
| Registry 地址 | `AETHER_REGISTRY` | 容器镜像仓库，如 `forgejo.10cg.pub` |

### 自动发现（从 API 获取）

以下信息无需配置，skills 会自动从集群 API 发现：

| 信息 | 发现方式 |
|------|---------|
| 节点类型 (node_class) | `GET /v1/nodes` → 提取 NodeClass |
| 可用 Driver | `GET /v1/nodes` → 提取 Drivers |
| 节点 IP | `GET /v1/nodes` → 提取 Address |
| 节点状态 | `GET /v1/nodes` → 提取 Status |

---

## 命令

### 查看当前配置

```bash
/aether:setup --show
```

输出：

```
Aether 集群配置
===============
配置来源: ~/.aether/config.yaml

入口地址:
  Nomad:    http://192.168.69.70:4646 ✓ 可达
  Consul:   http://192.168.69.70:8500 ✓ 可达
  Registry: forgejo.10cg.pub

集群信息 (从 API 发现):
  节点类型:
    - heavy_workload (3 nodes, docker driver)
    - light_exec (5 nodes, exec driver)
  总节点数: 8
  运行中 Jobs: 5
```

### 创建全局配置

```bash
/aether:setup --global
```

交互流程：

```
创建全局配置 (~/.aether/config.yaml)
此配置将被所有项目共享。

请输入 Nomad 地址 [http://localhost:4646]: http://192.168.69.70:4646
请输入 Consul 地址 [同 Nomad 主机]: http://192.168.69.70:8500
请输入 Registry 地址: forgejo.10cg.pub

验证连接...
  Nomad:  ✓ 连接成功 (v1.11.2)
  Consul: ✓ 连接成功 (v1.22.3)

配置已保存到 ~/.aether/config.yaml
```

生成的文件 `~/.aether/config.yaml`：

```yaml
# Aether 集群配置
# 由 /aether:setup 生成于 2026-02-19

endpoints:
  nomad: "http://192.168.69.70:4646"
  consul: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"
```

### 创建项目级配置

```bash
/aether:setup --project
```

交互流程：

```
创建项目级配置 (.env)
此配置仅对当前项目生效，会覆盖全局配置。

请输入 Nomad 地址: http://192.168.69.70:4646
请输入 Consul 地址: http://192.168.69.70:8500
请输入 Registry 地址: forgejo.10cg.pub

配置已追加到 .env
```

追加到 `.env`：

```bash
# Aether 集群配置
NOMAD_ADDR=http://192.168.69.70:4646
CONSUL_HTTP_ADDR=http://192.168.69.70:8500
AETHER_REGISTRY=forgejo.10cg.pub
```

### 首次使用引导

当其他 skill（如 `/aether:init`）检测到未配置时，自动触发引导：

```
/aether:init

未找到 Aether 集群配置。

请选择配置方式：
  → 创建全局配置 (~/.aether/config.yaml) - 推荐
  → 创建项目配置 (.env) - 仅当前项目
  → 手动输入 - 本次使用，不保存

[选择后进入配置流程]
```

---

## 配置读取逻辑

Skills 使用以下逻辑读取配置：

```bash
# 1. 检查项目 .env
if [ -f ".env" ]; then
  source .env
fi

# 2. 检查全局配置
if [ -z "$NOMAD_ADDR" ] && [ -f "$HOME/.aether/config.yaml" ]; then
  NOMAD_ADDR=$(yq '.endpoints.nomad' ~/.aether/config.yaml)
  CONSUL_HTTP_ADDR=$(yq '.endpoints.consul' ~/.aether/config.yaml)
  AETHER_REGISTRY=$(yq '.endpoints.registry' ~/.aether/config.yaml)
fi

# 3. 检查是否配置完成
if [ -z "$NOMAD_ADDR" ]; then
  echo "未找到 Aether 配置，请运行 /aether:setup"
  exit 1
fi
```

---

## 集群信息发现

配置入口地址后，skills 通过 API 发现集群详细信息：

```bash
# 发现节点类型和 driver
curl -s "${NOMAD_ADDR}/v1/nodes" | jq -r '
  group_by(.NodeClass) |
  map({
    class: .[0].NodeClass,
    count: length,
    drivers: [.[0].Drivers | keys[]] | unique
  })
'

# 输出示例:
# [
#   {"class": "heavy_workload", "count": 3, "drivers": ["docker"]},
#   {"class": "light_exec", "count": 5, "drivers": ["exec"]}
# ]
```

Skills 使用发现的信息而非硬编码：

```bash
# 获取 Docker 节点的 node_class
DOCKER_CLASS=$(curl -s "${NOMAD_ADDR}/v1/nodes" | jq -r '
  [.[] | select(.Drivers.docker != null)] | .[0].NodeClass
')
# 结果: "heavy_workload"

# 获取 exec 节点的 node_class
EXEC_CLASS=$(curl -s "${NOMAD_ADDR}/v1/nodes" | jq -r '
  [.[] | select(.Drivers.exec != null and .Drivers.docker == null)] | .[0].NodeClass
')
# 结果: "light_exec"
```

---

## 错误处理

### CLI 可用性检查

在执行操作前，确认必要工具已安装：

```bash
# 检查 curl 和 jq 是否可用
for cmd in curl jq; do
  if ! command -v $cmd &> /dev/null; then
    echo "错误: 未找到 $cmd 命令"
    echo "修复: sudo apt install $cmd  # Debian/Ubuntu"
    echo "修复: brew install $cmd      # macOS"
    exit 1
  fi
done

# 检查 yq（读取 config.yaml 需要）
if ! command -v yq &> /dev/null; then
  echo "错误: 未找到 yq 命令，无法读取 config.yaml"
  echo "修复: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
  exit 1
fi
```

### 连接验证失败

当 `curl` 到 Nomad 或 Consul 失败时，提供明确的诊断信息：

```bash
# Nomad 连接验证
validate_nomad() {
  local addr="$1"
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${addr}/v1/agent/self" 2>&1)

  if [ $? -ne 0 ]; then
    echo "错误: 无法连接到 Nomad (${addr})"
    echo "可能原因:"
    echo "  - Nomad 服务未启动"
    echo "  - 网络不可达或防火墙阻拦"
    echo "  - 地址格式错误（需要 http:// 前缀）"
    echo "修复:"
    echo "  ssh root@<node> 'systemctl status nomad'"
    echo "  curl -v ${addr}/v1/agent/self"
    return 1
  elif [ "$response" = "403" ]; then
    echo "错误: Nomad 返回 403 - Token 认证失败"
    echo "修复: 设置 NOMAD_TOKEN 环境变量或在 config.yaml 中配置 token"
    return 1
  elif [ "$response" != "200" ]; then
    echo "错误: Nomad 返回 HTTP ${response}"
    return 1
  fi
}

# Consul 连接验证（同理）
validate_consul() {
  local addr="$1"
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${addr}/v1/status/leader" 2>&1)

  if [ $? -ne 0 ]; then
    echo "错误: 无法连接到 Consul (${addr})"
    echo "修复: ssh root@<node> 'systemctl status consul'"
    return 1
  elif [ "$response" != "200" ]; then
    echo "错误: Consul 返回 HTTP ${response}"
    return 1
  fi
}
```

### 目录权限错误

创建 `~/.aether/` 目录时可能遇到权限问题：

```bash
# 创建配置目录
AETHER_DIR="$HOME/.aether"
if ! mkdir -p "$AETHER_DIR" 2>/dev/null; then
  echo "错误: 无法创建目录 ${AETHER_DIR}"
  echo "可能原因: 权限不足或 \$HOME 路径异常 (HOME=${HOME})"
  echo "修复:"
  echo "  sudo mkdir -p ${AETHER_DIR} && sudo chown $(whoami) ${AETHER_DIR}"
  exit 1
fi

# 写入配置文件
if ! touch "$AETHER_DIR/config.yaml" 2>/dev/null; then
  echo "错误: 无法写入 ${AETHER_DIR}/config.yaml"
  echo "修复: chmod 755 ${AETHER_DIR}"
  exit 1
fi
```

### URL 格式验证

验证用户输入的地址格式：

```bash
validate_url() {
  local url="$1"
  local name="$2"

  # 检查空值
  if [ -z "$url" ]; then
    echo "错误: ${name} 地址不能为空"
    return 1
  fi

  # 检查 http/https 前缀
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "错误: ${name} 地址缺少协议前缀"
    echo "示例: http://192.168.69.70:4646"
    return 1
  fi

  # 检查端口号
  if [[ ! "$url" =~ :[0-9]+$ ]]; then
    echo "警告: ${name} 地址未指定端口，将使用默认端口"
  fi
}

# 使用
validate_url "$NOMAD_ADDR" "Nomad" || exit 1
validate_url "$CONSUL_HTTP_ADDR" "Consul" || exit 1
```

### Token 认证失败

Nomad ACL 启用时的 Token 认证处理：

```bash
# 检查 Token 是否有效
if [ -n "$NOMAD_TOKEN" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
    "${NOMAD_ADDR}/v1/agent/self")

  if [ "$HTTP_CODE" = "403" ]; then
    echo "错误: NOMAD_TOKEN 无效或权限不足"
    echo "修复:"
    echo "  1. 检查 token 是否过期: nomad acl token self"
    echo "  2. 重新获取 token: nomad acl token create -name='aether' -type='client'"
    echo "  3. 更新配置: 编辑 ~/.aether/config.yaml 中的 nomad_token"
    exit 1
  fi
fi
```

---

## 与其他 Skills 的关系

```
/aether:setup     → 配置集群入口（首次使用）
       ↓
       ↓ 提供 NOMAD_ADDR, CONSUL_HTTP_ADDR, AETHER_REGISTRY
       ↓
/aether:init      → 读取配置 + API 发现 → 生成部署文件
/aether:dev       → 读取配置 → 执行开发部署
/aether:status    → 读取配置 → 查询集群状态
/aether:deploy    → 读取配置 → 执行生产部署
/aether:rollback  → 读取配置 → 执行回滚
```
