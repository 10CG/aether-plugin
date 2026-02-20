# Aether Plugin

> **Version**: 0.2.0 | **Released**: 2026-02-19
>
> Aether 基础设施部署插件 - 6个 Skills + 2个 Agents

## 安装

```bash
# 添加 marketplace
/plugin marketplace add 10CG/aether-plugin

# 安装
/plugin install aether@10CG-aether-plugin
```

## 首次使用

安装后，首先配置集群入口：

```bash
/aether:setup --global
```

这会创建 `~/.aether/config.yaml`，配置 Nomad、Consul、Registry 地址。配置一次后，所有项目共享。

## 包含内容

### Skills (6个)

| Skill | 用途 | 环境 |
|-------|------|------|
| `aether-setup` | 配置集群入口地址 | 首次使用 |
| `aether-init` | 新项目接入（两阶段：分析 → 生成） | dev + prod |
| `aether-dev` | 开发测试部署、临时 Job、日志查看 | dev |
| `aether-status` | 集群/服务状态查询 | dev + prod |
| `aether-deploy` | 生产环境受控部署 | prod |
| `aether-rollback` | 生产环境快速回滚 | prod |

### Agents (2个)

| Agent | 用途 | 触发场景 |
|-------|------|---------|
| `deploy-doctor` | 部署失败自动诊断 | 部署问题排查 |
| `node-maintenance` | 节点维护流程编排 | 节点重启/更新 |

## 使用方式

### 配置集群

```bash
# 全局配置（推荐，一次配置所有项目可用）
/aether:setup --global

# 项目级配置（仅当前项目）
/aether:setup --project

# 查看当前配置
/aether:setup --show
```

### 新项目接入

```bash
/aether:init
# Phase 1: 扫描项目 → 生成部署方案 → 确认
# Phase 2: 生成 Dockerfile、workflow、nomad.hcl (dev + prod)
```

### 开发测试

```bash
# 部署当前分支到 dev（不经过 CI）
/aether:dev deploy

# 运行临时测试 Job
/aether:dev run --docker "nginx:alpine"

# 查看 dev 服务日志
/aether:dev logs my-project

# 清理临时 Job
/aether:dev clean
```

### 查看状态

```bash
# 集群概览
/aether:status

# 指定服务详情
/aether:status my-project
```

### 生产部署

```bash
# 部署指定版本到生产
/aether:deploy my-project v1.2.3
```

### 回滚

```bash
# 回滚到之前版本
/aether:rollback my-project
```

## 配置说明

### 配置层级（优先级从高到低）

1. **项目级 `.env`** — 当前项目目录下
2. **用户级 `~/.aether/config.yaml`** — 全局配置
3. **插件默认值** — 无（必须配置入口地址）

### 必需配置项

| 配置项 | 环境变量 | 说明 |
|--------|---------|------|
| Nomad 地址 | `NOMAD_ADDR` | Nomad API 入口 |
| Consul 地址 | `CONSUL_HTTP_ADDR` | Consul API 入口 |
| Registry 地址 | `AETHER_REGISTRY` | 容器镜像仓库 |

### 自动发现

以下信息从 Nomad API 自动发现，无需配置：

- 节点类型 (node_class)
- 可用 Driver (docker/exec)
- 节点 IP 和状态

## 相关项目

- [Aether](https://forgejo.10cg.pub/10CG/Aether) - Aether 主项目
- [aria-plugin](https://forgejo.10cg.pub/10CG/aria-plugin) - Aria AI-DDD 方法论插件

## License

MIT - 10CG Lab
