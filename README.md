# Aether Plugin

> **Version**: 0.1.0 | **Released**: 2026-02-19
>
> Aether 基础设施部署插件 - 5个 Skills + 2个 Agents

## 安装

```bash
# 添加 marketplace
/plugin marketplace add 10CG/aether-plugin

# 安装
/plugin install aether@10CG-aether-plugin
```

## 包含内容

### Skills (5个)

| Skill | 用途 | 环境 |
|-------|------|------|
| `aether-init` | 新项目接入脚手架生成 | dev |
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

### 新项目接入

```bash
/aether:init
# 交互式生成 Dockerfile、workflow、nomad.hcl
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

## 环境变量

插件依赖以下环境变量（在 Aether 项目 `.env` 中配置）：

```bash
NOMAD_ADDR=http://192.168.69.70:4646
CONSUL_HTTP_ADDR=http://192.168.69.70:8500
```

## 集群信息

- Nomad Server: 192.168.69.70-72
- Consul Server: 192.168.69.70-72
- Heavy Nodes (Docker): 192.168.69.80-82, node_class=`heavy_workload`
- Light Nodes (exec): 192.168.69.90-94, node_class=`light_exec`

## 相关项目

- [Aether](https://forgejo.10cg.pub/10CG/Aether) - Aether 主项目
- [aria-plugin](https://forgejo.10cg.pub/10CG/aria-plugin) - Aria AI-DDD 方法论插件

## License

MIT - 10CG Lab
