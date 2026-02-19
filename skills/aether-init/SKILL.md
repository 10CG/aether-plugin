---
name: aether-init
description: |
  新项目接入 Aether 集群的脚手架生成器。
  交互式生成 Dockerfile、Forgejo Actions workflow、Nomad Job 定义。

  使用场景："接入新项目到 Aether"、"生成部署配置"、"初始化 CI/CD"
argument-hint: "[project-name]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Aether 项目接入脚手架 (aether-init)

> **版本**: 0.1.0 | **优先级**: P0

## 快速开始

### 我应该使用这个 Skill 吗？

**使用场景**:
- 新项目需要部署到 Aether 集群
- 需要生成 Dockerfile、CI/CD workflow、Nomad Job 配置
- 不熟悉 Aether 部署配置格式

**不使用场景**:
- 项目已有部署配置，只需修改 → 直接编辑文件
- 只是查看集群状态 → 使用 `/aether:status`

## 执行流程

### Step 1: 收集项目信息

通过 AskUserQuestion 收集以下信息：

1. **项目名称**: 默认使用当前目录名
2. **部署模式**: Docker (heavy 节点) / exec (light 节点)
3. **语言框架**: Node.js / Go / Python / 静态文件 / 自定义
4. **服务端口**: 根据框架给出默认值
5. **持久化存储**: 是否需要挂载数据卷
6. **副本数**: 1 / 2 / 3

### Step 2: 生成配置文件

根据收集的信息，生成以下文件：

#### Docker 模式 (heavy 节点)

```
项目目录/
├── Dockerfile                          # 容器镜像构建
├── .forgejo/
│   └── workflows/
│       └── deploy.yaml                 # CI/CD 流水线
└── deploy/
    └── nomad.hcl                       # Nomad Job 定义
```

#### exec 模式 (light 节点)

```
项目目录/
├── .forgejo/
│   └── workflows/
│       └── deploy.yaml                 # CI/CD 流水线 (rsync 同步)
└── deploy/
    └── nomad.hcl                       # Nomad Job 定义
```

### Step 3: 输出说明

生成完成后，输出：
1. 生成的文件列表
2. 下一步操作指引（push 到 main 分支触发部署）
3. 如何查看部署状态

## 模板参考

### Dockerfile 模板

参考 `references/dockerfile-templates.md`

### Workflow 模板

参考 `references/workflow-templates.md`

### Nomad Job 模板

参考 `references/nomad-templates.md`

## 集群配置

- **Registry**: `forgejo.10cg.pub`
- **Nomad**: `http://192.168.69.70:4646`
- **Heavy 节点**: node_class = `heavy_workload`
- **Light 节点**: node_class = `light_exec`

## 示例交互

```
用户: /aether:init

Claude: 我来帮你生成 Aether 部署配置。

[问题 1] 项目名称？
  → my-api (默认: 当前目录名)

[问题 2] 部署模式？
  → Docker (heavy 节点) - 适合 Web 应用、API、数据库
  → exec (light 节点) - 适合脚本、CLI 工具

[问题 3] 语言框架？
  → Node.js
  → Go
  → Python
  → 静态文件
  → 自定义 Dockerfile

[问题 4] 服务端口？
  → 3000 (Node.js 默认)

[问题 5] 需要持久化存储？
  → 否

[问题 6] 副本数？
  → 2 (推荐，高可用)

生成文件:
✓ Dockerfile
✓ .forgejo/workflows/deploy.yaml
✓ deploy/nomad.hcl

下一步:
1. 检查生成的配置文件
2. git add . && git commit -m "feat: add Aether deployment config"
3. git push origin main
4. 查看部署状态: /aether:status my-api
```
