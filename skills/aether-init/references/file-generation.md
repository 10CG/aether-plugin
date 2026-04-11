# 文件生成

## Phase 2 概述

用户确认部署方案后，按**此顺序**生成部署文件（**US-030 约束**: CLAUDE.md 必须在 nomad HCL 之后生成，
以便 `__JOB_NAME__` 占位符能从已生成的 nomad-dev.hcl parse 出来）：

1. Dockerfile
2. .dockerignore
3. deploy/nomad-dev.hcl
4. deploy/nomad-prod.hcl
5. .forgejo/workflows/deploy.yaml
6. CLAUDE.md (如不存在则创建；如存在则按 Step 1.1c 流程判断是否 append)

## Dockerfile 生成

根据语言/框架选择模板，详见 [Dockerfile 模板](dockerfile-templates.md)

## Nomad HCL 生成

### 变量占位符

| 占位符 | 说明 | 示例值 |
|--------|------|-------|
| `__PROJECT_NAME__` | 项目名称 | my-api |
| `__DOCKER_IMAGE__` | 镜像地址 | forgejo.10cg.pub/org/my-api |
| `__PORT__` | 服务端口 | 8080 |
| `__NODE_CLASS__` | 节点类型 | heavy_workload |
| `__REPLICAS__` | 副本数 | 2 |
| `__DATA_DIR__` | 数据目录 | /data/my-api |

### dev vs prod 差异

| 配置项 | dev | prod |
|--------|-----|-----|
| 副本数 | 1 | 2+ |
| 镜像 tag | latest | semver |
| 健康检查 | 宽松 | 严格 |
| 滚动更新 | 无 | 有 |

详见 [Nomad 模板](nomad-templates.md)

## Workflow 生成

### 变量

| 变量 | 说明 |
|------|------|
| `PROJECT_NAME` | 项目名称 |
| `REGISTRY` | 镜像仓库地址 |
| `NOMAD_ADDR` | Nomad API 地址 |

### Secrets 配置

| Secret | 说明 | 是否必需 |
|--------|------|---------|
| `NOMAD_ADDR` | Nomad API 地址 | ✓ |
| `NOMAD_TOKEN` | Nomad 访问令牌 | ✓ |
| `FORGEJO_TOKEN` | 镜像推送令牌 | 自动注入 |

详见 [Workflow 模板](workflow-templates.md)

## 生成流程

```bash
# 1. 创建目录
mkdir -p deploy .forgejo/workflows

# 2. 生成 Dockerfile
# 根据 project-analysis.md 的决策选择模板

# 3. 生成 Nomad HCL
# 替换占位符
sed "s/__PROJECT_NAME__/my-api/g" deploy/nomad-dev.hcl

# 4. 生成 Workflow
# 检查 secrets 配置

# 5. 验证生成文件
ls -la deploy/ .forgejo/
```

## 生成后验证

1. 检查 Dockerfile 语法: `docker build --check .`
2. 检查 Nomad HCL 语法: `nomad job validate deploy/nomad-dev.hcl`
3. 检查 Workflow 语法: `actionlint .forgejo/workflows/deploy.yaml`

---

## CLAUDE.md CI Monitoring Policy 注入 (US-030)

> **Source**: [US-030](../../../../docs/requirements/user-stories/US-030.md) |
> [proposal.md](../../../../openspec/changes/2026-04-10-init-inject-ci-policy/proposal.md)

### 插入行为

新项目（无 CLAUDE.md）或已有项目（有 CLAUDE.md 但无 Policy 章节）都会注入 CI Monitoring Policy。
注入内容来自 [`deploy-monitoring-rules.md`](deploy-monitoring-rules.md)，该文件首行为
HTML marker `<!-- aether-ci-policy -->`（语言无关 sentinel）。

### 检测逻辑 (triple-fallback grep，仅针对目标 CLAUDE.md)

```bash
# R2-I: grep 必须仅针对目标 CLAUDE.md，不要把 deploy-monitoring-rules.md 模板本身读入
if [ -f CLAUDE.md ] && grep -qE "(<!-- aether-ci-policy -->|部署监控规则|CI/CD Monitoring Policy)" CLAUDE.md; then
  # 3 种历史/当前 sentinel 命中任一即跳过：
  #   <!-- aether-ci-policy -->  (v1.7.2+ HTML marker — 推荐)
  #   部署监控规则               (v1.7.1 之前的 Chinese 注入)
  #   CI/CD Monitoring Policy    (v1.7.1 手动添加到 4 项目的英文段)
  echo "Already has policy, skipping"
else
  # 注入流程继续
fi
```

### 占位符替换

| 占位符 | 解析顺序 |
|--------|---------|
| `__JOB_NAME__` | (1) 从已生成的 `deploy/nomad-dev.hcl` parse `job "<name>" {`（用 `grep -m1` 取首个匹配 — multi-job 时取第一个）<br>(2) 失败时 fallback 到 `${PROJECT_NAME}-dev` |

**关键 (R2-B)**: 文件生成顺序必须保证 `deploy/nomad-dev.hcl` 在 `CLAUDE.md` 之前生成
（见 Phase 2 顺序表），否则 parse 失败将退回 fallback 命名。

### 注入位置（确定性 EOF append）

不使用"插入到部署节后"启发式（在 Round 1 audit 中被认定为模型层不确定）。注入位置**始终为**:

```
<CLAUDE.md 原有内容>
<blank line>
---
<blank line>
<deploy-monitoring-rules.md 内容，__JOB_NAME__ 已替换>
```

### 已存在 CLAUDE.md 的处理 (AskUserQuestion 保守策略)

如果目标项目有 CLAUDE.md 且未命中 triple-fallback grep：
1. 通过 `AskUserQuestion` 询问用户是否 append Policy 章节
2. 用户同意 → append 到 EOF
3. 用户拒绝 → 跳过，记录到 generation report
4. **绝不静默覆盖或修改用户已有内容**

### HTML marker durability (R2-H)

HTML marker `<!-- aether-ci-policy -->` **MUST NOT** be stripped by future markdown
processing tools. If a markdown linter (prettier, markdownlint, remark) is added to CI
in the future, configure it to preserve HTML comments. The drift check function in
`static-benchmark.sh` (`check_template_drift`) relies on this marker being the first line.

### Monorepo 暂不支持

当前 `__JOB_NAME__` 是单一占位符，只支持 single-image 项目。monorepo 多镜像场景：
`# TODO(US-031): support monorepo via __JOB_NAMES_LIST__`
