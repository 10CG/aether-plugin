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
4. 插件默认值           → 无（必须配置入口地址）
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
配置来源: ~/.aether/config.yaml (全局)
配置优先级: 环境变量 > 项目级 .aether/config.yaml > 全局 ~/.aether/config.yaml > 默认值

入口地址:
  Nomad:    http://192.168.69.70:4646 ✓ 可达 (v1.11.2)
  Consul:   http://192.168.69.70:8500 ✓ 可达 (v1.22.3)
  Registry: forgejo.10cg.pub
  DNS:      ✓ .service.consul 可解析 (dnsmasq)

集群拓扑 (从 API 发现):
  heavy_workload (3 nodes): Docker 29.2.1, exec, raw_exec
    - heavy-1 (192.168.69.80) host_volumes: [data-vol, log-vol]
    - heavy-2 (192.168.69.81) host_volumes: [data-vol]
    - heavy-3 (192.168.69.82) host_volumes: [data-vol]
  light_exec (5 nodes): exec only
    - light-1~5 (192.168.69.90~94)
  总节点数: 8
  运行中 Jobs: 5

其他 Skills (init, deploy, status, rollback, dev) 自动读取此配置连接集群。
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
│ 4. 默认值    无（必须配置入口地址）                 │
└─────────────────────────────────────────────────┘
  → 项目级配置会覆盖全局配置的对应字段
  → 例: 在 /home/dev/payment-service 创建 .aether/config.yaml
    则该项目使用项目级配置，其他项目仍用全局配置

接下来可以使用这些 Skills:
  /aether:status    → 查询集群状态（读取上述配置）
  /aether:init      → 初始化项目部署（读取上述配置）
  /aether:deploy    → 部署到生产（读取上述配置）
  /aether:dev       → 部署到开发环境（读取上述配置）
```

生成的文件 `~/.aether/config.yaml`：

```yaml
# Aether 集群配置
# 由 /aether:setup 生成

cluster:
  nomad_addr: "http://192.168.69.70:4646"
  consul_addr: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"
```

### 创建项目级配置

```bash
/aether:setup --project
```

生成的文件 `.aether/config.yaml`：

```yaml
# Aether 项目级配置
# 覆盖全局配置中的对应字段

cluster:
  nomad_addr: "http://192.168.69.70:4646"
  consul_addr: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"
```

### 首次使用引导

当其他 skill（如 `/aether:init`）检测到未配置时，自动触发引导，询问用户选择全局配置或项目配置。

---

## 配置读取逻辑

Skills 按优先级链读取配置：项目级 `.aether/config.yaml` → 全局 `~/.aether/config.yaml` → 环境变量。使用 `yq` 读取 `cluster.*` 字段。未找到任何配置时，提示用户运行 `/aether:setup`。

---

## 集群信息发现

配置入口地址后，**必须**展示完整的集群拓扑信息，让用户了解集群全貌。

### 发现步骤

1. **节点拓扑**: `GET /v1/nodes` → 按 NodeClass 分组
2. **逐节点详情**: 对每个节点 `GET /v1/node/{id}` → 提取详细属性

### 必须展示的信息

| 类别 | API 字段 | 输出示例 |
|------|---------|---------|
| 节点分类 | `NodeClass` | heavy_workload (3), light_exec (5) |
| 可用 Drivers | `Drivers` | docker, exec, raw_exec |
| Docker 版本 | `Attributes["driver.docker.version"]` | 29.2.1 |
| Host Volumes | `HostVolumes` | data-vol → /opt/data, log-vol → /var/log |
| 节点状态 | `Status` | ready / down |
| 节点 IP | `Address` | 192.168.69.80 |

### 输出格式（setup 完成后的集群概览）

```
集群拓扑:
  heavy_workload (3 nodes): Docker 29.2.1, exec, raw_exec
    - heavy-1 (192.168.69.80) host_volumes: [data-vol, log-vol]
    - heavy-2 (192.168.69.81) host_volumes: [data-vol]
    - heavy-3 (192.168.69.82) host_volumes: [data-vol]
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
- 必要工具检查：确认 `curl`、`jq`、`yq` 已安装，未安装时给出安装命令

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

连接失败时，**必须**根据 HTTP 状态码和响应特征进行分类诊断：

| 失败类型 | HTTP 状态 | 响应特征 | 诊断命令 | 处理步骤 |
|---------|----------|---------|---------|---------|
| **网络不可达** | 000 | timeout/无响应 | `ping <ip>` | 检查网络连通性、VPN、防火墙规则 |
| **服务未启动** | 000 | connection refused | `ssh root@<node> "systemctl status nomad"` | 启动服务或检查端口绑定 |
| **地址错误** | 非 JSON 响应 | HTML 或空 | 确认 IP:端口 | Nomad 默认 4646、Consul 默认 8500 |
| **认证失败** | 403 | `Permission denied` | `echo $NOMAD_TOKEN` | ACL 启用时需要有效 token |
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
