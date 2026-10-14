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

> **版本**: 0.2.0 | **优先级**: P0

## 快速开始

### 使用场景

- 首次使用 aether-plugin，需要配置集群地址
- 切换到不同的 Aether 集群
- 查看当前配置的集群信息
- 为特定项目配置不同的集群

### 配置层级

配置按以下优先级读取（高 → 低）：

```
1. 环境变量              → NOMAD_ADDR, CONSUL_HTTP_ADDR 等
2. 项目级配置            → ./.aether/config.yaml (当前项目目录)
3. 用户级全局配置        → ~/.aether/config.yaml
4. 默认值               → CLI 内置（Nomad 为 127.0.0.1:4646）；入口地址要配置，否则连到本机
```

配置文件只读找到的第一份：项目级文件存在时整份替代全局文件（不逐字段合并，缺的字段 CLI 用默认值，Nomad 为 `127.0.0.1:4646`），
所以项目级配置要写全入口地址。CLI 命令不读 `.env`（只有 `aether config get/show` 会读，所以它显示的来源可能与命令实际用的不同，Aether #491）。

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
| 可用 Driver | `GET /v1/nodes` → 提取 Drivers 里 Detected 且 Healthy 的 |
| 节点 IP | `GET /v1/nodes` → 提取 Address |
| 节点状态 | `GET /v1/nodes` → 提取 Status |

---

## 命令

### 查看当前配置

```bash
/aether:aether-setup --show
```

输出：

```
Aether 集群配置
===============
配置来源: ~/.aether/config.yaml (全局)
配置优先级: 环境变量 > 项目级 .aether/config.yaml（存在时整份替代全局）> 全局 ~/.aether/config.yaml > 默认值

入口地址:
  Nomad:    http://192.168.69.70:4646 ✓ 可达 (v1.11.2)
  Consul:   http://192.168.69.70:8500 ✓ 可达 (v1.22.3)
  Registry: forgejo.10cg.pub
  DNS:      ✓ .service.consul 可解析 (dnsmasq)

集群拓扑 (从 API 发现):
  heavy_workload (5 nodes): Docker 29.2.1, exec, raw_exec
    - heavy-1 (192.168.69.80) host_volumes: [data-vol, log-vol]
    - heavy-2 (192.168.69.81) host_volumes: [data-vol]
    - heavy-3 (192.168.69.82) host_volumes: [data-vol]
    - heavy-4 (192.168.69.83) host_volumes: [data-vol]
    - heavy-5 (192.168.69.84) host_volumes: [data-vol]
  light_exec (5 nodes): exec only
    - light-1~5 (192.168.69.90~94)
  总节点数: 10
  运行中 Jobs: 5

其他 Skills (init, deploy, status, rollback, dev) 自动读取此配置连接集群。
```

### 创建全局配置

```bash
/aether:aether-setup --global
```

交互流程：

```
创建全局配置 (~/.aether/config.yaml)
此配置将被所有项目共享。

请输入 Nomad 地址 [http://localhost:4646]: http://192.168.69.70:4646

自动推导 Consul 地址:
  规则: 同 IP + 端口 8500
  推导结果: http://192.168.69.70:8500
  确认? [Y/n]:

请输入 Registry 地址: forgejo.10cg.pub

验证连接...
  Nomad:  ✓ 连接成功 (v1.11.2)
  Consul: ✓ 连接成功 (v1.22.3)

配置已保存到 ~/.aether/config.yaml

┌─────────────────────────────────────────────────┐
│ 配置优先级链 (高 → 低)                            │
├─────────────────────────────────────────────────┤
│ 1. 环境变量  NOMAD_ADDR, CONSUL_HTTP_ADDR       │
│ 2. 项目级    .aether/config.yaml (当前目录)       │
│ 3. 全局      ~/.aether/config.yaml  ← 当前生效   │
│ 4. 默认值    CLI 内置 (Nomad 127.0.0.1:4646)      │
└─────────────────────────────────────────────────┘
  → 项目级配置存在时整份替代全局配置（不逐字段合并），入口地址要写全
  → 例: 在 /home/dev/payment-service 创建 .aether/config.yaml
    则该项目使用项目级配置，其他项目仍用全局配置

接下来可以使用这些 Skills:
  /aether:aether-status    → 查询集群状态（读取上述配置）
  /aether:aether-init      → 初始化项目部署（读取上述配置）
  /aether:aether-deploy    → 部署到生产（读取上述配置）
  /aether:aether-dev       → 部署到开发环境（读取上述配置）
```

生成的文件 `~/.aether/config.yaml`：

```yaml
# Aether 集群配置
# 由 /aether:aether-setup 生成

cluster:
  nomad_addr: "http://192.168.69.70:4646"
  consul_addr: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"
```

### 创建项目级配置

```bash
/aether:aether-setup --project
```

生成的文件 `.aether/config.yaml`：

```yaml
# Aether 项目级配置
# 存在时整份替代全局配置（不逐字段合并），入口地址要写全

cluster:
  nomad_addr: "http://192.168.69.70:4646"
  consul_addr: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"
```

### 写入配置：防呆与写后复测

全局与项目级都按这一段写（`f` 换成 `.aether/config.yaml` 即项目级）：

```bash
f=~/.aether/config.yaml
for v in "$NOMAD_IN" "$CONSUL_IN"; do      # 用户确认过的地址
  echo "$v" | grep -Eq '^https?://[0-9A-Za-z.-]+:[0-9]+$' || { echo "地址为空或格式不对: '$v'"; exit 1; }
done
[ -n "$REGISTRY_IN" ] || { echo "registry 为空"; exit 1; }
mkdir -p "$(dirname "$f")" && touch "$f"
# 只改 cluster.* 三个键，文件里其他段（ci、doctor 等）原样保留，不整份覆盖
NOMAD_IN="$NOMAD_IN" CONSUL_IN="$CONSUL_IN" REGISTRY_IN="$REGISTRY_IN" \
  yq -i '.cluster.nomad_addr = strenv(NOMAD_IN) | .cluster.consul_addr = strenv(CONSUL_IN) | .cluster.registry = strenv(REGISTRY_IN)' "$f"
# 写后复测：用文件里读回来的值再测一次，不用内存里的变量
curl -sS -m 10 "$(yq '.cluster.nomad_addr' "$f")/v1/agent/self" | jq -r '.config.Version.Version'
curl -sS -m 10 "$(yq '.cluster.consul_addr' "$f")/v1/status/leader"
```

复测拿不到版本号或 leader，就回到「连接失败诊断引导」，不要报配置完成。
项目级文件存在时整份替代全局：全局文件里的 `ci`、`doctor` 等段在该项目下也不再生效，需要的话一并写进项目文件。

### 首次使用引导

当其他 skill（如 `/aether:aether-init`）检测到未配置时，自动触发引导，询问用户选择全局配置或项目配置。

---

## 配置读取逻辑

Skills 与 CLI 命令按同一规则读取配置：环境变量优先；配置文件只读找到的第一份（项目级 `.aether/config.yaml` 存在时不读全局 `~/.aether/config.yaml`），不读 `.env`。使用 `yq` 读取 `cluster.*` 字段。未找到任何配置时，提示用户运行 `/aether:aether-setup`。

---

## 集群信息发现

配置入口地址后，**必须**展示完整的集群拓扑信息，让用户了解集群全貌。

### 发现步骤

1. **节点拓扑**: `GET /v1/nodes` → 按 NodeClass 分组。下表的字段列表接口每一项都有，一次请求就够
2. **逐节点详情**: 只在要列表里没有的属性（详情对象 `Attributes` 下的硬件 / 系统信息）时，再对节点 `GET /v1/node/{id}`。
   详情对象**没有** `Address`（取出来是 null）：IP 用 `Attributes["unique.network.ip-address"]`，或沿用列表里的 `Address`；`HTTPAddr` 带端口（`IP:4646`）

### 必须展示的信息

字段都取自 `GET /v1/nodes` 的每一项：

| 类别 | API 字段 | 输出示例 |
|------|---------|---------|
| 节点分类 | `NodeClass` | heavy_workload (5), light_exec (5) |
| 可用 Drivers | `Drivers` 里 `Detected` 与 `Healthy` 都为 true 的键（没启用的 driver 也在 `Drivers` 里，这两项为 false） | docker, exec, raw_exec |
| Docker 版本 | `Drivers.docker.Attributes["driver.docker.version"]` | 29.2.1 |
| Host Volumes | `HostVolumes`（键是卷名，`.Path` 是宿主路径） | data-vol → /opt/data, log-vol → /var/log |
| 节点状态 | `Status` | ready / down |
| 节点 IP | `Address`（只有列表接口有） | 192.168.69.80 |

### 输出格式（setup 完成后的集群概览）

```
集群拓扑:
  heavy_workload (5 nodes): Docker 29.2.1, exec, raw_exec
    - heavy-1 (192.168.69.80) host_volumes: [data-vol, log-vol]
    - heavy-2 (192.168.69.81) host_volumes: [data-vol]
    - heavy-3 (192.168.69.82) host_volumes: [data-vol]
    - heavy-4 (192.168.69.83) host_volumes: [data-vol]
    - heavy-5 (192.168.69.84) host_volumes: [data-vol]
  light_exec (5 nodes): exec only
    - light-1~5 (192.168.69.90~94)
```

Skills 使用发现的信息（如 node_class）而非硬编码值。

---

## 连接失败诊断引导

### 验证原则

- 验证 URL 格式：必须有 `http://` 前缀 + 端口号，缺少时提示补全
- 验证 Nomad 连通性：`curl ${NOMAD_ADDR}/v1/agent/self`，检查 HTTP 状态码
- 验证 Consul 连通性：`curl ${CONSUL_HTTP_ADDR}/v1/status/leader`，检查 HTTP 状态码
- 必要工具检查：确认 `curl`、`jq`、`yq` 已安装，未安装时给出安装命令；`yq` 要用 mikefarah 版 v4（`yq --version` 输出含 mikefarah），写入步骤的 `strenv()` 只有它支持

### 多候选地址探测

用户可能不确定正确的入口地址。按以下策略探测：

1. 尝试用户提供的地址
2. 如已知 Nomad 地址，自动推导 Consul 地址：相同 IP + 端口 8500
3. 常见候选：`localhost`、已知的 Infra 节点 IP（如 192.168.69.70~72）
4. 逐一尝试，输出对比表格：

```
候选地址探测结果:
| 候选地址               | HTTP 状态 | 响应时间 | 版本     | 诊断           |
|----------------------|----------|---------|---------|----------------|
| 192.168.69.70:4646   | 200      | 0.7ms   | v1.11.2 | ✓ 可用          |
| 192.168.69.71:4646   | 200      | 1.2ms   | v1.11.2 | ✓ 可用 (备选)    |
| 10.0.0.1:4646        | 000      | timeout | -       | ✗ 网络不可达     |
```

### 失败原因分类与处理

探测时同时拿 HTTP 状态码和 curl 退出码 —— 连不上时状态码一律是 000，分类要靠退出码：

```bash
curl -sS -o /dev/null -w '%{http_code} %{time_total}s\n' --connect-timeout 5 -m 10 "$URL/v1/agent/self"; echo "curl exit=$?"
```

| curl 退出码 | 含义 | 先查什么 |
|---|---|---|
| 6 | 主机名解析失败 | DNS / `/etc/hosts`，或直接用 IP |
| 7 | 连接被拒或主机不可达 | 服务是否在跑、端口对不对（Nomad 4646 / Consul 8500）、路由 |
| 28 | 超时 | 防火墙丢包、VPN / 隧道没连 |
| 35 / 60 | TLS 握手失败 / 证书不受信 | 多半是 `http://` 与 `https://` 写反 |
| 52 / 56 | 空响应 / 连接被重置 | 端口上不是这个服务；或请求走了代理 |

本机设了 `http_proxy` 时，不在 `no_proxy` 里的地址会走代理，上面几类失败都可能变成 52 / 56 或代理返回的 5xx：先确认集群网段在 `no_proxy` 里。

连接失败时，**必须**根据 HTTP 状态码和响应特征进行分类诊断：

| 失败类型 | HTTP 状态 | 响应特征 | 诊断命令 | 处理步骤 |
|---------|----------|---------|---------|---------|
| **网络不可达** | 000 | timeout/无响应 | `ping <ip>` | 检查网络连通性、VPN、防火墙规则 |
| **服务未启动** | 000 | connection refused | `ssh root@<node> "systemctl status nomad"` | 启动服务或检查端口绑定 |
| **地址错误** | 非 JSON 响应 | HTML 或空 | 确认 IP:端口 | Nomad 默认 4646、Consul 默认 8500 |
| **认证失败** | 403 | `Permission denied` | `[ -n "$NOMAD_TOKEN" ] && echo 已设置` (无输出 = 未设置; 不打印值) | ACL 启用时需要有效 token |
| **TLS 错误** | 000 | `SSL` 相关 | `curl -k https://...` | 检查是否需要 `https://` 前缀 |

**诊断输出示例**:
```
连接失败诊断:
  地址: http://10.0.0.1:4646
  HTTP 状态: 000 (无响应)
  响应时间: 5000ms (超时)
  故障分类: 网络不可达
  可能原因: 目标 IP 不在本机路由范围内
  建议操作:
    1. ping 10.0.0.1 — 确认网络连通
    2. 检查 VPN 或 SSH 隧道是否已建立
    3. 尝试其他候选地址 (192.168.69.70~72)
```

### 目录与权限

创建 `~/.aether/` 或 `.aether/` 时，如遇权限错误，提示检查 `$HOME` 路径和目录所有权。

---

## 与其他 Skills 的关系

```
/aether:aether-setup     → 配置集群入口（首次使用）
       ↓
       ↓ 提供 NOMAD_ADDR, CONSUL_HTTP_ADDR, AETHER_REGISTRY
       ↓
/aether:aether-init      → 读取配置 + API 发现 → 生成部署文件
/aether:aether-dev       → 读取配置 → 执行开发部署
/aether:aether-status    → 读取配置 → 查询集群状态
/aether:aether-deploy    → 读取配置 → 执行生产部署
/aether:aether-rollback  → 读取配置 → 执行回滚
```
