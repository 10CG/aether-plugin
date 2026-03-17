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

> **版本**: 0.5.0 | **优先级**: P0

## 前置检查

**⚠️ 此 Skill 需要 aether CLI**

```bash
# 使用共享检测脚本
source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
require_aether_cli || exit 1
```

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

## 故障处理

### 集群连接失败（Registry 验证）

Phase 1 分析阶段需要从集群配置读取 registry 信息，连接失败时降级处理：

```bash
# 尝试从集群获取 registry 配置
REGISTRY=""
if [ -f "$HOME/.aether/config.yaml" ]; then
  REGISTRY=$(yq '.cluster.registry' "$HOME/.aether/config.yaml" 2>/dev/null)
fi

if [ -z "$REGISTRY" ] || [ "$REGISTRY" = "null" ]; then
  echo "⚠ 无法从配置中读取 registry 地址"
  echo ""
  echo "可选操作:"
  echo "  1. 运行 /aether:setup 配置集群（推荐）"
  echo "  2. 手动指定: aether init --registry forgejo.10cg.pub"
  echo "  3. 跳过 registry 配置，生成后手动编辑 workflow 文件"
fi

# 验证 registry 可达性（可选，非阻塞）
if [ -n "$REGISTRY" ]; then
  if ! curl -sf --max-time 5 "https://${REGISTRY}/v2/" > /dev/null 2>&1; then
    echo "⚠ Registry (${REGISTRY}) 不可达，将继续生成文件"
    echo "  部署前请确认 registry 地址正确"
  fi
fi
```

### 项目类型无法识别

当扫描项目特征后未能匹配任何已知语言/框架：

```bash
# 如果未检测到已知语言
if [ -z "$DETECTED_LANG" ]; then
  echo "⚠ 未能自动识别项目类型"
  echo ""
  echo "已检查: go.mod, package.json, requirements.txt, pyproject.toml, Cargo.toml, pom.xml, build.gradle"
  echo ""
  echo "请选择:"
  echo "  1. 手动指定语言: aether init --lang <go|node|python|rust|java>"
  echo "  2. 仅生成基础 Nomad HCL（无 Dockerfile）"
  echo "  3. 提供自定义 Dockerfile 路径"
  # 等待用户选择后继续
fi
```

### 文件冲突（目标文件已存在）

生成文件前检查冲突，避免覆盖用户已有配置：

```bash
CONFLICTS=()
[ -f "Dockerfile" ] && CONFLICTS+=("Dockerfile")
[ -f "deploy/nomad-dev.hcl" ] && CONFLICTS+=("deploy/nomad-dev.hcl")
[ -f "deploy/nomad-prod.hcl" ] && CONFLICTS+=("deploy/nomad-prod.hcl")
[ -f ".forgejo/workflows/deploy.yaml" ] && CONFLICTS+=(".forgejo/workflows/deploy.yaml")

if [ ${#CONFLICTS[@]} -gt 0 ]; then
  echo "⚠ 以下文件已存在："
  for f in "${CONFLICTS[@]}"; do
    echo "  - $f"
  done
  echo ""
  echo "请选择:"
  echo "  1. 覆盖全部（已有文件备份为 .bak）"
  echo "  2. 仅生成缺失的文件（跳过已有）"
  echo "  3. 取消操作"
  # 用户选择 1 时：
  # for f in "${CONFLICTS[@]}"; do cp "$f" "${f}.bak"; done
fi
```

### 模板渲染错误

占位符替换失败时的检查：

```bash
# 生成后验证占位符是否全部替换
for file in Dockerfile deploy/nomad-dev.hcl deploy/nomad-prod.hcl .forgejo/workflows/deploy.yaml; do
  if [ -f "$file" ] && grep -q '__[A-Z_]*__' "$file"; then
    UNREPLACED=$(grep -o '__[A-Z_]*__' "$file" | sort -u | tr '\n' ', ')
    echo "⚠ ${file} 中仍有未替换的占位符: ${UNREPLACED}"
    echo "  请手动检查并替换，或重新运行 /aether:init"
  fi
done
```

### 生成后验证失败

```bash
# Dockerfile 语法检查
if [ -f "Dockerfile" ]; then
  if ! docker build --check . 2>/dev/null; then
    echo "⚠ Dockerfile 语法检查失败"
    echo "  常见原因: 缺少基础镜像、COPY 路径错误"
    echo "  手动检查: docker build --no-cache ."
  fi
fi

# Nomad HCL 语法检查
for hcl in deploy/nomad-dev.hcl deploy/nomad-prod.hcl; do
  if [ -f "$hcl" ]; then
    if ! nomad job validate "$hcl" 2>/dev/null; then
      echo "⚠ ${hcl} 验证失败"
      echo "  常见原因: 端口号错误、node class 不存在"
      echo "  手动检查: nomad job validate ${hcl}"
    fi
  fi
done
```

### 常见错误速查

| 错误 | 原因 | 修复 |
|------|------|------|
| `未能自动识别项目类型` | 缺少语言标识文件 | 使用 `--lang` 手动指定 |
| `无法从配置中读取 registry` | 未运行 setup | 运行 `/aether:setup` |
| `文件已存在` | 项目已有部署配置 | 选择覆盖（自动备份）或跳过 |
| `未替换的占位符` | 缺少项目参数 | 检查项目名、端口、registry 配置 |
| `Dockerfile 语法检查失败` | 模板与项目结构不匹配 | 手动调整 Dockerfile |
| `HCL 验证失败` | 端口或节点类型错误 | 检查 `--port` 和集群节点配置 |
| `aether CLI 未安装` | PATH 中找不到 aether | 参考 CLI 安装文档 |

---

**Skill 版本**: 0.5.0
**最后更新**: 2026-03-17
**维护者**: 10CG Infrastructure Team
