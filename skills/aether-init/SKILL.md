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
dependencies:
  cli:
    required: true
    min_version: "0.7.0"
---

# Aether 项目接入 (aether-init)

> **版本**: 0.4.0 | **优先级**: P0

## 前置检查

**⚠️ 此 Skill 需要 aether CLI**

检测 CLI:
```bash
command -v aether || test -f ~/.aether/aether || test -f ~/.aether/aether.exe
```

**如果未安装**: 提示用户运行 `/aether:doctor` 完成安装。

## 快速开始

```
/aether:init              # 交互式向导
/aether:init my-project   # 指定项目名
```

### 使用场景

- 新项目部署到 Aether 集群
- 生成完整部署配置
- 初始化 CI/CD

### 不使用场景

- 项目已有配置 → 直接编辑文件
- 查看集群状态 → `/aether:status`

---

## 两阶段流程

```
Phase 1: 项目分析 → 部署方案 → 用户确认
Phase 2: 生成文件 → 验证 → 完成
```

---

## Phase 1: 项目分析与部署方案

### Step 1.1: 扫描项目特征

详见 [项目分析参考](references/project-analysis.md)

**检测内容**:
- 语言/框架 (Go, Node.js, Python, etc.)
- 已有配置 (Dockerfile, CI/CD)
- 项目特征 (端口、数据库、文件写入)

### Step 1.2: 决策逻辑

| 分析项 | 决策 |
|--------|------|
| Driver | Dockerfile/系统依赖 → docker; 纯脚本 → exec |
| Node Class | API/后台 → heavy; 轻量脚本 → light |
| Registry | 从配置读取 |
| Tag 策略 | dev=latest; prod=semver |

### Step 1.3: 输出部署方案

呈现给用户确认:

```
部署方案: my-api
================
项目信息:
  语言: Go
  框架: gin
  端口: 8080

部署决策:
  Driver: docker
  Node: heavy_workload
  Registry: forgejo.10cg.pub

是否继续生成文件？ [Y/n]
```

---

## Phase 2: 文件生成

### Step 2.1: 生成目录结构

```
project/
├── Dockerfile
├── .dockerignore
├── .forgejo/
│   └── workflows/
│       └── deploy.yaml
└── deploy/
    ├── nomad-dev.hcl
    └── nomad-prod.hcl
```

### Step 2.2: 填充模板

详见 [文件生成参考](references/file-generation.md)

**变量替换**:
- `__PROJECT_NAME__` → 项目名称
- `__DOCKER_IMAGE__` → 镜像地址
- `__PORT__` → 服务端口
- `__NODE_CLASS__` → 节点类型

### Step 2.3: 验证

```bash
# 检查生成的文件
ls -la Dockerfile deploy/ .forgejo/

# 验证语法
docker build --check .
nomad job validate deploy/nomad-dev.hcl
```

---

## 详细参考

| 主题 | 文档 |
|------|------|
| 项目分析 | [project-analysis.md](references/project-analysis.md) |
| 文件生成 | [file-generation.md](references/file-generation.md) |
| Dockerfile 模板 | [dockerfile-templates.md](references/dockerfile-templates.md) |
| Nomad 模板 | [nomad-templates.md](references/nomad-templates.md) |
| Workflow 模板 | [workflow-templates.md](references/workflow-templates.md) |

---

## 命令行等价

```bash
# CLI 初始化
aether init

# 指定语言
aether init --lang go --port 8080
```

---

**Skill 版本**: 0.3.0
**最后更新**: 2026-03-12
**维护者**: 10CG Infrastructure Team
