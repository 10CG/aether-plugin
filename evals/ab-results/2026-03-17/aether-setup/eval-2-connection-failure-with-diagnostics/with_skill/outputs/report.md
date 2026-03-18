# Aether Setup 诊断报告

> 生成时间: 2026-03-18 | 由 /aether:setup 执行

---

## 问题描述

用户报告连接 Nomad `http://192.168.69.99:4646` 超时，需要排查配置并修正地址。
同时需要创建项目级配置，覆盖全局 registry 为 `ghcr.io`。

---

## 诊断过程

### 1. 工具可用性检查

| 工具 | 状态 |
|------|------|
| curl | OK (`/usr/bin/curl`) |
| jq | OK (`/usr/bin/jq`) |
| yq | 未安装（不影响 .env 方式配置） |

### 2. 现有配置检查

| 配置源 | 状态 | 位置 |
|--------|------|------|
| 全局配置 | 已存在 | `~/.aether/config.yaml` |
| 项目 .env | 不存在 | `/home/dev/Aether/.env` |
| 环境变量 | 未设置 | `NOMAD_ADDR`, `CONSUL_HTTP_ADDR`, `AETHER_REGISTRY` |

**全局配置内容** (`~/.aether/config.yaml`):

```yaml
cluster:
  consul_addr: http://192.168.69.70:8500
  nomad_addr: http://192.168.69.70:4646
  registry: forgejo.10cg.pub
  registry_url: forgejo.10cg.pub
```

### 3. 连接验证

| 地址 | 结果 | 说明 |
|------|------|------|
| `http://192.168.69.99:4646` (用户提供) | **连接失败** (超时) | 该 IP 不属于集群中任何节点 |
| `http://192.168.69.70:4646` (全局配置) | **连接成功** (HTTP 200) | 正确的 Nomad Server 地址 |
| `http://192.168.69.70:8500` (全局配置) | **连接成功** (HTTP 200) | 正确的 Consul 地址 |

### 4. 问题根因

用户使用的地址 `192.168.69.99` **不是集群中的有效节点**。集群节点 IP 范围为：

- **heavy 节点**: 192.168.69.80 ~ 82
- **light 节点**: 192.168.69.90 ~ 94
- **Nomad Server**: 192.168.69.70 (heavy-1 节点 192.168.69.80 上运行)

`192.168.69.99` 不在上述任何范围内，因此连接超时。

---

## 集群状态 (验证后)

**Nomad**: v1.11.2 (Build: 2026-02-11)
**Consul Leader**: 192.168.69.70:8300

### 节点列表

| 节点名 | IP 地址 | 节点类型 | 状态 |
|--------|---------|----------|------|
| heavy-1 | 192.168.69.80 | heavy_workload | ready |
| heavy-2 | 192.168.69.81 | heavy_workload | ready |
| heavy-3 | 192.168.69.82 | heavy_workload | ready |
| light-1 | 192.168.69.90 | light_exec | ready |
| light-2 | 192.168.69.91 | light_exec | ready |
| light-3 | 192.168.69.92 | light_exec | ready |
| light-4 | 192.168.69.93 | light_exec | ready |
| light-5 | 192.168.69.94 | light_exec | ready |

**总节点数**: 8 (3 heavy_workload + 5 light_exec)，全部 ready。

---

## 修复操作

### 1. 地址修正

全局配置 `~/.aether/config.yaml` 中的地址**已经是正确的** (`http://192.168.69.70:4646`)，无需修改。

用户需要使用正确的地址 `http://192.168.69.70:4646` 而非 `http://192.168.69.99:4646`。

### 2. 创建项目级配置

已创建项目级 `.env` 文件 (`/home/dev/Aether/.env`)，覆盖全局 registry 设置为 `ghcr.io`：

```bash
# Aether 集群配置 (项目级)
# 由 /aether:setup 生成于 2026-03-18
# 此配置覆盖全局 ~/.aether/config.yaml 中的 registry 设置
NOMAD_ADDR=http://192.168.69.70:4646
CONSUL_HTTP_ADDR=http://192.168.69.70:8500
AETHER_REGISTRY=ghcr.io
```

### 3. 配置优先级确认

```
项目 .env (AETHER_REGISTRY=ghcr.io)  ← 当前项目使用
    ↓ fallback
全局 config.yaml (registry: forgejo.10cg.pub)  ← 其他项目使用
```

---

## 验证结果

```
NOMAD_ADDR=http://192.168.69.70:4646      → Nomad: HTTP 200 (连接成功)
CONSUL_HTTP_ADDR=http://192.168.69.70:8500 → Consul: HTTP 200 (连接成功)
AETHER_REGISTRY=ghcr.io                    → 已设置为项目级覆盖
```

---

## 总结

1. **地址问题已解决**: `192.168.69.99` 不是有效集群节点，正确地址为 `192.168.69.70:4646`（全局配置已正确）。
2. **项目级配置已创建**: `/home/dev/Aether/.env` 中将 registry 覆盖为 `ghcr.io`，同时保持全局 `forgejo.10cg.pub` 不变。
3. **集群状态正常**: 8 个节点全部 ready，Nomad v1.11.2 运行正常。
