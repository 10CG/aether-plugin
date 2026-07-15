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

### Step 1.1b: 服务依赖发现

项目扫描（Step 1.1）检测到 `DATABASE_URL`、`REDIS_URL`、`MONGO_URI` 等环境变量模式时，
引导用户将连接地址迁移为 Consul DNS 格式：

```
检测到服务依赖:
  DATABASE_URL → postgres://postgres.service.consul:5432/mydb
  REDIS_URL    → redis://redis.service.consul:6379

集群内服务通过 Consul DNS 自动发现，请使用 {service}.service.consul FQDN 格式。
详见 Nomad 模板参考 → 服务连接（Consul DNS）
```

**检测规则**: 扫描 `.env*`、`docker-compose.yml`、应用配置中的
`DATABASE`、`REDIS`、`MONGO`、`RABBITMQ`、`ELASTICSEARCH` 关键词。
匹配到任一关键词时，在部署方案（Step 1.3）中追加服务连接建议。

### Step 1.1c: 已有项目的 CLAUDE.md CI Monitoring Policy 检查

如果 Step 1.1 检测到项目**已有完整部署配置** (Dockerfile + HCL + CI)，跳过 Phase 2 文件生成，
但仍检查 CLAUDE.md 是否包含 CI Monitoring Policy：

**检测（triple-fallback grep，只针对目标 CLAUDE.md 文件）**:
```bash
if [ -f CLAUDE.md ] && grep -qE "(<!-- aether-ci-policy -->|部署监控规则|CI/CD Monitoring Policy)" CLAUDE.md; then
  echo "Already has policy, skipping"
else
  # AskUserQuestion: 是否 append Policy 章节到 CLAUDE.md EOF?
  # 用户同意 → append；用户拒绝 → skip
fi
```

**注入时解析 `__JOB_NAME__`** (优先从已存在的 `deploy/nomad-dev.hcl` parse):
```bash
JOB_NAME=""
if [ -f deploy/nomad-dev.hcl ]; then
  JOB_NAME=$(grep -m1 -E '^job ' deploy/nomad-dev.hcl | sed -E 's/job +"([^"]+)".*/\1/')
fi
: "${JOB_NAME:=${PROJECT_NAME}-dev}"
```

**Append 规则** (确定性 EOF):
1. 读取 `${CLAUDE_PLUGIN_ROOT}/skills/aether-init/references/deploy-monitoring-rules.md`
2. 把 `__JOB_NAME__` 替换为解析出的 job name
3. 追加到 CLAUDE.md 末尾，前置 blank line + `---` + blank line
4. 注入后提示用户确认内容

此步骤确保所有 Aether 项目（无论新旧）都具备 CI Monitoring Policy。
See `references/file-generation.md` § Step 1.1c for implementation details.

### Step 1.1d: 已有项目的集成规范 Policy 回填检查 (C1, Aether #245)

与 Step 1.1c **并行独立**的第二次检查（两套 marker 互不影响判定，检测顺序不重要）。
无论 Step 1.1 是否检测到"已有完整部署配置"，只要目标项目存在 CLAUDE.md（或即将由
本 skill 创建 CLAUDE.md），都要跑一遍集成规范 policy 的四分支判定 —— 这正是**老项目
回填 (C1)** 的入口：已接入 Aether 但从未拿到过这段 policy 的项目（如 #241 触发源
TurfSync），只需重跑 `/aether:init`，无需其它操作。

**四分支检测（精确锚定 marker，不与旧 `aether-ci-policy` 混淆）**:
```bash
TEMPLATE_DATE=$(grep -m1 -oE '<!-- aether:integration-policy [0-9]{4}-[0-9]{2}-[0-9]{2} start -->' \
  "${CLAUDE_PLUGIN_ROOT}/skills/aether-init/references/integration-policy-rules.md" \
  | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')

if [ ! -f CLAUDE.md ]; then
  : # 分支 1a — 交给 Step 2.2c（或本步骤直接创建，取决于是否会走 Phase 2）
elif ! grep -qE '^<!-- aether:integration-policy [0-9]{4}-[0-9]{2}-[0-9]{2} start -->$' CLAUDE.md; then
  : # 分支 1b — AskUserQuestion 是否 append（consent gate，见下）
else
  EXISTING_DATE=$(grep -oE '<!-- aether:integration-policy [0-9]{4}-[0-9]{2}-[0-9]{2} start -->' CLAUDE.md \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
  if [[ "$EXISTING_DATE" < "$TEMPLATE_DATE" ]]; then
    : # 分支 2 — 陈旧，AskUserQuestion 是否原地更新
  else
    : # 分支 3 — 当前版本，skip（幂等：重跑不产生重复段）
  fi
fi
```

**完整决策树 + 每个分支的 consent gate 细节（`cp .bak` / diff 回显 / 降级追加）**:
见 [file-generation.md § CLAUDE.md 集成规范 Policy 注入](references/file-generation.md#claudemd-集成规范-policy-注入-成对栅栏日期戳-marker-aether-245-c1)。

**关键约束（不可省略）**:
- **绝不静默覆盖用户内容**：分支 1b 与分支 2 都必须先 `cp CLAUDE.md CLAUDE.md.bak`，
  写入后 `diff -u` 回显给用户核对，且写入前必须 `AskUserQuestion` 得到用户同意；
  用户拒绝时不写。分支 1a（无 CLAUDE.md）没有覆盖风险，可直接创建，无需询问。
- **注入失败必须降级，不得半写坏文件**：若 marker 定位出现歧义（如文件里有 2 组
  start marker 但只有 1 组 end marker），不做 in-place 替换，改为"追加 + 告警"，
  原文件内容不可被截断/删除。
- **不 retrofit 旧 `<!-- aether-ci-policy -->` marker**：本步骤只识别/写入
  `aether:integration-policy` 这一种 marker；旧 marker（若存在）保持原样，不做任何
  格式升级或迁移。
- **幂等**：对同一项目重复执行本步骤，若已是当前版本（分支 3）应产生零写操作；这是
  C1 回填"可安全重跑"的核心保证，供后续对 TurfSync 等外部消费方项目回填时依赖。

此步骤与 Step 1.1c 均在 Phase 1 完成，不受 Step 1.1 是否判定"跳过 Phase 2 文件生成"
影响 —— 即便项目已有完整部署配置（因而跳过 Dockerfile/HCL/Workflow 生成），集成规范
policy 的回填检查仍要执行。

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
├── CLAUDE.md              ← 注入部署监控规则 + 集群集成规范 Policy (C1)
├── .forgejo/
│   └── workflows/
│       └── deploy.yaml
└── deploy/
    ├── nomad-dev.hcl
    └── nomad-prod.hcl
```

### Step 2.2: 填充模板（文件生成顺序强制断言）

详见 [文件生成参考](references/file-generation.md)

**变量替换**:
- `__PROJECT_NAME__` → 项目名称
- `__DOCKER_IMAGE__` → 镜像地址
- `__PORT__` → 服务端口
- `__NODE_CLASS__` → 节点类型
- `__JOB_NAME__` → Nomad job name（从已生成的 nomad-dev.hcl parse）

**文件生成顺序（MUST）** — CLAUDE.md 必须在 nomad HCL 之后生成，以便 parse 出 `__JOB_NAME__`：

```
1. Dockerfile
2. deploy/nomad-dev.hcl
3. deploy/nomad-prod.hcl
4. .forgejo/workflows/deploy.yaml
5. CLAUDE.md              ← 在 #2 之后，依赖 nomad-dev.hcl 解析 __JOB_NAME__
```

### Step 2.2b: 注入 CI Monitoring Policy 到 CLAUDE.md

检查项目是否有 `CLAUDE.md`：
- **存在**: 按 Step 1.1c 流程走（triple-fallback grep + AskUserQuestion + EOF append）
- **不存在**: 创建新 CLAUDE.md 骨架并**直接包含** Policy 章节（无需询问，属默认生成内容）

**`__JOB_NAME__` 解析**（从刚生成的 `deploy/nomad-dev.hcl`）:
```bash
JOB_NAME=$(grep -m1 -E '^job ' deploy/nomad-dev.hcl | sed -E 's/job +"([^"]+)".*/\1/')
# 若解析失败：fallback 到 ${PROJECT_NAME}-dev
```

注入内容模板见 [deploy-monitoring-rules.md](references/deploy-monitoring-rules.md)（首行为 HTML
marker `<!-- aether-ci-policy -->`，内容与 SilkNode CLAUDE.md lines 152-184 在应用 AC1a 的
4 项已知转换后逐字一致）

### Step 2.2c: 注入集群集成规范 Policy 到 CLAUDE.md (成对栅栏日期戳 marker, Aether #245 C1)

与 Step 2.2b **独立**的第二段注入（顺序不重要，两套 marker 互不依赖）。检查项目
CLAUDE.md（此时若 Step 2.2b 刚创建/追加过，读的是它产出后的版本）：

- **新项目（Step 2.2b 刚创建了 CLAUDE.md）**: 直接在同一份新建的 CLAUDE.md 里追加
  集成规范 policy 段（等价 Step 1.1d 分支 1a 的"无覆盖风险直接写入"，无需再次询问）。
- **已有 CLAUDE.md 的项目**: 复用 Step 1.1d 已经跑过的四分支判定结果——若 Step 1.1
  判定"已有完整部署配置"从而跳过了本 Phase 2，集成规范 policy 的回填已经在 Step 1.1d
  完成，本步骤为 no-op。

**内容来源**: [`integration-policy-rules.md`](references/integration-policy-rules.md)
（首行为成对栅栏日期戳 marker `<!-- aether:integration-policy YYYY-MM-DD start -->`，
末行为 `<!-- aether:integration-policy end -->`）。

**完整四分支逻辑（1a 创建 / 1b consent-gate append / 2 原地更新 / 3 skip）+ 强制失败
降级路径 + fixture 清单**: 见
[file-generation.md § CLAUDE.md 集成规范 Policy 注入](references/file-generation.md#claudemd-集成规范-policy-注入-成对栅栏日期戳-marker-aether-245-c1)。

**不与 Step 2.2b 合并的原因**: 两段 policy 内容、marker 格式、治理门（CI-policy 走
豁免 1/2；integration-policy 走独立行为 spot-check，不套豁免 2）均独立演进，合并会
让"只更新其中一段"的场景（如 C1 老项目回填只需要 integration-policy，不需要重新
触碰 CI-policy）无法干净表达。

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
| 集群集成规范 Policy 内容 (C1, Aether #245) | [integration-policy-rules.md](references/integration-policy-rules.md) |
| 集成规范 Policy 注入决策树 + fixture | [file-generation.md § CLAUDE.md 集成规范 Policy 注入](references/file-generation.md#claudemd-集成规范-policy-注入-成对栅栏日期戳-marker-aether-245-c1) |
| **CI 优化 + 故障诊断 (跨 skill 权威参考)** | `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md` |

> 模板背后的设计决策（为什么用 `driver: docker`、为什么要轮询 verify、
> 为什么 Dockerfile 内 npm 要加国内镜像 + 重试等）见上表最后一行的
> 跨 skill 权威参考。如果生成的项目 CI 出现 TLS/EIDLETIMEOUT 等问题，
> 先读那份 guide 的 Troubleshooting decision tree。

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
