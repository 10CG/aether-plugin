---
name: aether-init
description: |
  新项目接入 Aether 集群。先分析项目特征生成部署方案，确认后生成部署文件。
  两阶段流程：Phase 1 分析与设计 → Phase 2 生成文件。

  使用场景："接入新项目到 Aether"、"生成部署配置"、"初始化 CI/CD"、"规划部署方案"
argument-hint: "[project-name]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion, Grep
---

# Aether 项目接入 (aether-init)

> **版本**: 0.2.0 | **优先级**: P0

## 快速开始

### 使用场景

- 新项目需要部署到 Aether 集群
- 不确定项目应该用 Docker 还是 exec
- 需要完整的部署方案设计 + 配置文件生成

### 不使用场景

- 项目已有部署配置，只需修改 → 直接编辑文件
- 只是查看集群状态 → 使用 `/aether:status`
- 已有方案，只想快速生成文件 → 跳到 Phase 2

---

## Phase 1: 项目分析与部署方案

> 先理解项目，再做部署决策。

### Step 1.1: 扫描项目特征

自动扫描当前项目目录，收集以下信息：

```bash
# 检测语言/框架
- package.json       → Node.js (检查 dependencies 判断框架: express/fastify/next)
- go.mod             → Go (检查 module path)
- requirements.txt / pyproject.toml / Pipfile → Python (检查 fastapi/flask/django)
- Cargo.toml         → Rust
- pom.xml / build.gradle → Java
- index.html (无后端) → 静态文件
- flake.nix          → Nix 环境已定义

# 检测已有配置
- Dockerfile         → 已有容器化配置
- docker-compose.yml → 已有编排配置（可参考依赖服务）
- .forgejo/          → 已有 CI/CD
- deploy/            → 已有部署配置
- Makefile           → 检查 build/run 命令

# 检测项目特征
- 入口文件           → 确定启动命令
- 端口配置           → 确定服务端口 (grep listen/PORT/port)
- 数据库连接         → 确定依赖服务 (grep DATABASE_URL/REDIS/mongo)
- 文件写入           → 判断是否有状态
- 环境变量           → 确定运行时配置 (.env.example, config/)
```

### Step 1.2: 分析决策

根据扫描结果，自动推导部署方案：

| 分析项 | 判断逻辑 | 决策输出 |
|--------|---------|---------|
| **Driver 选型** | 有 Dockerfile 或需要系统依赖 → Docker；纯脚本/CLI → exec | `docker` / `exec` |
| **目标节点** | Docker → heavy (node_class=heavy_workload)；exec → light (node_class=light_exec) | 节点类型 |
| **基础镜像** | 根据语言选择最小镜像 (alpine 优先) | 镜像名:tag |
| **构建方式** | Go/Rust → 多阶段构建；Node/Python → 单阶段；Nix → nix build | 构建策略 |
| **依赖服务** | 检测到 DB/Redis/MQ 连接 → 列出需要额外部署的服务 | 依赖列表 |
| **状态性** | 有文件写入/数据库文件 → 有状态；否则 → 无状态 | stateful / stateless |
| **副本策略** | 无状态 → 2+ 副本 + spread；有状态 → 1 副本 + volume | 副本数 + 存储 |
| **端口** | 从代码中提取 listen 端口 | 端口号 |
| **健康检查** | HTTP 服务 → http /health；TCP 服务 → tcp；脚本 → script | 检查类型 + 路径 |
| **环境差异** | dev: 单副本 + latest tag；prod: 多副本 + semver tag | dev/prod 配置 |

### Step 1.3: 输出部署方案

将分析结果整理为部署方案，呈现给用户确认：

```
═══════════════════════════════════════
  Aether 部署方案: my-api
═══════════════════════════════════════

项目分析:
  语言框架:    Node.js (Express)
  入口文件:    server.js
  服务端口:    3000
  依赖服务:    PostgreSQL, Redis
  状态性:      无状态 (数据存储在外部 DB)

部署设计:
  Driver:      docker (heavy 节点)
  基础镜像:    node:20-alpine
  构建方式:    单阶段构建
  副本数:      dev: 1 / prod: 2
  存储:        无 (无状态)
  健康检查:    HTTP GET /health

依赖服务:
  ⚠ PostgreSQL - 需要额外部署或使用外部实例
  ⚠ Redis      - 需要额外部署或使用外部实例

将生成的文件:
  ├── Dockerfile
  ├── .forgejo/workflows/deploy.yaml
  ├── .forgejo/workflows/deploy-prod.yaml
  └── deploy/
      ├── nomad-dev.hcl
      └── nomad-prod.hcl

═══════════════════════════════════════
```

使用 AskUserQuestion 让用户确认或调整方案：

```
确认部署方案？
  → 确认，开始生成文件
  → 调整方案 (进入修改)
```

**可调整项：**
- 切换 Driver (docker ↔ exec)
- 修改副本数
- 添加/移除持久化存储
- 修改端口
- 调整健康检查路径

---

## Phase 2: 生成部署文件

> 根据确认的方案，生成所有部署配置文件。

### Step 2.1: 生成文件

#### Docker 模式生成的文件

```
项目目录/
├── Dockerfile                              # 容器镜像构建
├── .dockerignore                           # 构建排除规则
├── .forgejo/
│   └── workflows/
│       ├── deploy.yaml                     # dev: push main 自动部署
│       └── deploy-prod.yaml                # prod: 手动触发 + 审批
└── deploy/
    ├── nomad-dev.hcl                       # dev 环境 Job
    └── nomad-prod.hcl                      # prod 环境 Job
```

#### exec 模式生成的文件

```
项目目录/
├── .forgejo/
│   └── workflows/
│       ├── deploy.yaml                     # dev: push main 自动同步
│       └── deploy-prod.yaml                # prod: 手动触发
└── deploy/
    ├── nomad-dev.hcl                       # dev 环境 Job
    └── nomad-prod.hcl                      # prod 环境 Job
```

### Step 2.2: dev 与 prod 配置差异

生成的文件中，dev 和 prod 的关键差异：

| 配置项 | dev (nomad-dev.hcl) | prod (nomad-prod.hcl) |
|--------|--------------------|-----------------------|
| 镜像 tag | `__IMAGE__` (CI 替换为 commit SHA) | `__IMAGE__` (CI 替换为 semver) |
| 副本数 | 1 | 2+ |
| 资源限制 | 较低 (cpu=300, mem=256) | 较高 (cpu=500, mem=512) |
| 更新策略 | 直接替换 | 滚动更新 + auto_revert |
| spread | 无 | 分散到不同节点 |

Workflow 差异：

| 配置项 | deploy.yaml (dev) | deploy-prod.yaml (prod) |
|--------|------------------|------------------------|
| 触发方式 | push 到 main | workflow_dispatch (手动) |
| 镜像 tag | commit SHA + latest | 输入的版本号 (v1.2.3) |
| 审批 | 无 | environment: production |
| Job 文件 | deploy/nomad-dev.hcl | deploy/nomad-prod.hcl |

### Step 2.3: 输出总结

```
═══════════════════════════════════════
  文件生成完成
═══════════════════════════════════════

已生成:
  ✓ Dockerfile
  ✓ .dockerignore
  ✓ .forgejo/workflows/deploy.yaml        (dev, 自动)
  ✓ .forgejo/workflows/deploy-prod.yaml    (prod, 手动)
  ✓ deploy/nomad-dev.hcl                   (dev Job)
  ✓ deploy/nomad-prod.hcl                  (prod Job)

下一步:
  1. 检查生成的文件，按需调整
  2. 确保 Forgejo 仓库已配置 Secrets:
     - REGISTRY_TOKEN (推送镜像)
  3. 提交并推送:
     git add . && git commit -m "feat: add Aether deployment config"
     git push origin main
  4. 查看部署状态:
     /aether:status my-api

依赖服务提醒:
  ⚠ PostgreSQL 和 Redis 需要单独部署
    可使用 /aether:init 在 Aether 中部署，
    或配置外部服务地址到环境变量
═══════════════════════════════════════
```

---

## 模板参考

### Dockerfile 模板

参考 `references/dockerfile-templates.md`

### Workflow 模板

参考 `references/workflow-templates.md`

### Nomad Job 模板

参考 `references/nomad-templates.md`

## 前置条件：集群配置

执行 `/aether:init` 前，需要先配置 Aether 集群入口。

### 配置检查

Skill 启动时自动检查配置：

```bash
# 1. 检查项目 .env
# 2. 检查 ~/.aether/config.yaml
# 3. 未找到 → 提示运行 /aether:setup
```

### 必需的配置项

| 配置项 | 来源 | 用途 |
|--------|------|------|
| `NOMAD_ADDR` | 配置文件 | 查询节点信息、提交 Job |
| `CONSUL_HTTP_ADDR` | 配置文件 | 服务发现（可选） |
| `AETHER_REGISTRY` | 配置文件 | 生成镜像地址 |

### 自动发现的信息

以下信息从 Nomad API 自动发现，无需配置：

```bash
# 发现 Docker 节点的 node_class
DOCKER_CLASS=$(curl -s "${NOMAD_ADDR}/v1/nodes" | jq -r '
  [.[] | select(.Drivers.docker != null)] | .[0].NodeClass
')

# 发现 exec 节点的 node_class
EXEC_CLASS=$(curl -s "${NOMAD_ADDR}/v1/nodes" | jq -r '
  [.[] | select(.Drivers.exec != null and .Drivers.docker == null)] | .[0].NodeClass
')

# 发现节点数量
DOCKER_COUNT=$(curl -s "${NOMAD_ADDR}/v1/nodes" | jq '[.[] | select(.Drivers.docker != null)] | length')
EXEC_COUNT=$(curl -s "${NOMAD_ADDR}/v1/nodes" | jq '[.[] | select(.Drivers.exec != null and .Drivers.docker == null)] | length')
```

生成的配置文件使用发现的值：

```hcl
# deploy/nomad-prod.hcl 中的 constraint
constraint {
  attribute = "${node.class}"
  value     = "${DOCKER_CLASS}"  # 从 API 发现，如 "heavy_workload"
}
```

### 首次使用

如果未配置，skill 会引导用户：

```
/aether:init

未找到 Aether 集群配置。
请先运行 /aether:setup 配置集群入口地址。

或选择：
  → 现在配置 (调用 /aether:setup)
  → 取消
```
