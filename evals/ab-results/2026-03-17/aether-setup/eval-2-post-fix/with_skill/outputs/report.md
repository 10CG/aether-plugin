# Aether Setup 诊断报告

> 生成时间: 2026-03-18 | 工具: /aether:setup

---

## 诊断结果

### 问题: Nomad 连接超时

**用户报告地址**: `http://192.168.69.99:4646`
**连接结果**: 不可达 (curl exit code 7 - 连接被拒绝/超时)

**根因**: `192.168.69.99` 不是 Aether 集群中的有效节点。集群中不存在该 IP 地址。

**正确地址**: `http://192.168.69.70:4646` (heavy-1, Nomad Server)

### 地址对比

| 项目 | 错误地址 | 正确地址 | 状态 |
|------|---------|---------|------|
| Nomad | http://192.168.69.99:4646 | http://192.168.69.70:4646 | 已修正 |

---

## 配置检查

### 1. 工具可用性

| 工具 | 状态 |
|------|------|
| curl | OK |
| jq | OK |
| yq | OK |

### 2. 环境变量

| 变量 | 值 |
|------|-----|
| NOMAD_ADDR | 未设置 |
| CONSUL_HTTP_ADDR | 未设置 |
| AETHER_REGISTRY | 未设置 |

### 3. 全局配置 (`~/.aether/config.yaml`)

```yaml
cluster:
  nomad_addr: "http://192.168.69.70:4646"
  consul_addr: "http://192.168.69.70:8500"
  registry: "forgejo.10cg.pub"
  registry_url: "forgejo.10cg.pub"
```

**状态**: 全局配置地址正确，无需修改。用户可能在其他地方（命令行参数、脚本等）使用了错误的 `192.168.69.99` 地址。

### 4. 项目级配置 (`.aether/config.yaml`) -- 新建

```yaml
cluster:
  nomad_addr: "http://192.168.69.70:4646"
  consul_addr: "http://192.168.69.70:8500"
  registry: "ghcr.io"
```

**说明**: 按用户需求创建项目级配置，将 registry 覆盖为 `ghcr.io`（全局配置中为 `forgejo.10cg.pub`）。

---

## 连接验证

### Nomad (http://192.168.69.70:4646)

- **状态**: 连接成功 (HTTP 200)
- **版本**: Nomad v1.11.2

### Consul (http://192.168.69.70:8500)

- **状态**: 连接成功 (HTTP 200)

---

## 集群信息 (API 自动发现)

### 节点概览

| 节点 | IP | 类型 | 状态 |
|------|-----|------|------|
| heavy-1 | 192.168.69.80 | heavy_workload | ready |
| heavy-2 | 192.168.69.81 | heavy_workload | ready |
| heavy-3 | 192.168.69.82 | heavy_workload | ready |
| light-1 | 192.168.69.90 | light_exec | ready |
| light-2 | 192.168.69.91 | light_exec | ready |
| light-3 | 192.168.69.92 | light_exec | ready |
| light-4 | 192.168.69.93 | light_exec | ready |
| light-5 | 192.168.69.94 | light_exec | ready |

### 节点类型

| 类型 | 数量 | 驱动 |
|------|------|------|
| heavy_workload | 3 | docker, exec, java, qemu, raw_exec |
| light_exec | 5 | exec, raw_exec |

### 集群统计

- **总节点数**: 8
- **运行中 Jobs**: 17
- **Nomad 版本**: v1.11.2

---

## 配置层级（生效优先级）

```
1. 环境变量              → 未设置
2. 项目级配置            → .aether/config.yaml (registry: ghcr.io)  <-- 新建
3. 用户级全局配置        → ~/.aether/config.yaml (registry: forgejo.10cg.pub)
4. 插件默认值           → 无
```

**生效结果**:
- Nomad 地址: `http://192.168.69.70:4646` (来自项目配置)
- Consul 地址: `http://192.168.69.70:8500` (来自项目配置)
- Registry: `ghcr.io` (项目配置覆盖全局的 `forgejo.10cg.pub`)

---

## 执行的操作

1. **诊断** -- 确认 `192.168.69.99` 不可达，`192.168.69.70` 是正确的 Nomad Server 地址
2. **验证** -- 全局配置 (`~/.aether/config.yaml`) 中的地址正确，无需修改
3. **创建** -- 项目级配置 (`.aether/config.yaml`)，包含正确的集群地址并将 registry 覆盖为 `ghcr.io`
4. **发现** -- 通过 API 确认集群 8 个节点全部 ready，17 个 Jobs 运行中

## 建议

- 检查使用 `192.168.69.99` 的来源（可能是命令行参数、脚本或旧文档），将其更正为 `192.168.69.70`
- 项目级配置已生效，此项目的 CI/CD 工作流将使用 `ghcr.io` 作为容器镜像仓库
- 如需切换回全局 registry (`forgejo.10cg.pub`)，删除 `.aether/config.yaml` 即可
