# Aether 配置排查报告

## 问题描述

用户连接 Nomad `http://192.168.69.99:4646` 超时，需要排查配置并修正地址。同时需要创建项目级配置覆盖 registry 为 `ghcr.io`。

---

## 排查结果

### 1. Nomad 连接超时问题

**根因**: `192.168.69.99` 不是 Aether 集群中的任何节点。该 IP 地址上没有运行 Nomad 服务。

**集群实际拓扑** (来源: `~/.aether/environment.yaml`):

| 角色 | 节点名 | IP 地址 | 状态 |
|------|--------|---------|------|
| Server (Follower) | infra-server-1 | 192.168.69.70 | alive |
| Server (Leader) | infra-server-2 | 192.168.69.71 | alive |
| Server (Follower) | infra-server-3 | 192.168.69.72 | alive |
| Client (heavy) | heavy-1 | 192.168.69.80 | ready |
| Client (heavy) | heavy-2 | 192.168.69.81 | ready |
| Client (heavy) | heavy-3 | 192.168.69.82 | ready |
| Client (light) | light-1 ~ light-5 | 192.168.69.90~94 | ready |

**正确的 Nomad 地址**: `http://192.168.69.70:4646`

**验证结果**:
- `http://192.168.69.99:4646` - 连接超时 (该 IP 不属于集群)
- `http://192.168.69.70:4646` - 连接成功，Nomad v1.11.2 正常响应

### 2. 全局配置状态

文件: `~/.aether/config.yaml`

```yaml
cluster:
  consul_addr: http://192.168.69.70:8500
  nomad_addr: http://192.168.69.70:4646
  registry: forgejo.10cg.pub
  registry_url: forgejo.10cg.pub
```

**结论**: 全局配置中的 Nomad 地址是正确的 (`192.168.69.70:4646`)。用户可能在其他地方（环境变量、命令行参数、或其他工具配置）使用了错误的 `192.168.69.99` 地址。

### 3. 项目级配置（已创建）

此前不存在项目级配置。已创建 `.aether/config.yaml` 于项目根目录：

文件: `/home/dev/Aether/.aether/config.yaml`

```yaml
cluster:
  registry: ghcr.io
  registry_url: ghcr.io
```

根据 Aether 的配置优先级（`项目配置 > 全局配置 > 默认值`），该项目内的 registry 将使用 `ghcr.io`，而其他未覆盖的配置项（如 `nomad_addr`、`consul_addr`）将继续使用全局配置中的值。

---

## 执行的操作

1. 读取并验证全局配置 `~/.aether/config.yaml` -- 地址正确
2. 读取环境缓存 `~/.aether/environment.yaml` -- 确认集群拓扑
3. 测试 `http://192.168.69.70:4646` 连通性 -- 成功
4. 测试 `http://192.168.69.99:4646` 连通性 -- 超时（确认问题）
5. 创建项目级配置 `/home/dev/Aether/.aether/config.yaml`，设置 `registry: ghcr.io`

## 建议

- 检查是否在环境变量中设置了 `NOMAD_ADDR=http://192.168.69.99:4646`，如有请修正或删除
- 使用 `aether doctor` 或 `aether config list` 确认最终生效的配置
- 如需连接当前 Leader 节点，也可使用 `http://192.168.69.71:4646`（infra-server-2）
