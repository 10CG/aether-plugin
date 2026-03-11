# 文件生成

## Phase 2 概述

用户确认部署方案后，生成部署文件：

1. Dockerfile
2. .dockerignore
3. deploy/nomad-dev.hcl
4. deploy/nomad-prod.hcl
5. .forgejo/workflows/deploy.yaml

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
