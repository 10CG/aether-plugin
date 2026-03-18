# Aether Init 报告: legacy-app 项目接入

> **执行时间**: 2026-03-18
> **Skill 版本**: aether-init v0.5.0
> **评估场景**: eval-2 冲突检测 + 未知语言

---

## Phase 1: 项目分析与部署方案

### Step 1.1: 项目特征扫描

**目标目录**: `/home/dev/legacy-app`

#### 语言标识文件检测

| 文件 | 状态 |
|------|------|
| `go.mod` | 未找到 |
| `package.json` | 未找到 |
| `requirements.txt` | 未找到 |
| `pyproject.toml` | 未找到 |
| `Cargo.toml` | 未找到 |
| `pom.xml` | 未找到 |
| `build.gradle` | 未找到 |

**结果**: 无标准语言标识文件，触发 "项目类型无法识别" 流程。

#### 已有配置检测

| 文件 | 状态 | 说明 |
|------|------|------|
| `Dockerfile` | **已存在** | `FROM node:16`, 使用 `npm install`, EXPOSE 3000 |
| `docker-compose.yml` | **已存在** | 定义 app + postgres 服务, `NODE_ENV=production` |
| `.forgejo/workflows/` | 不存在 | - |
| `deploy/` | 不存在 | - |

#### 源代码分析

项目包含两种语言的源文件，存在歧义:

| 文件 | 语言 | 框架 | 端口 |
|------|------|------|------|
| `server.js` | Node.js | Express | 3000 |
| `app.py` | Python | Flask | 3000 |

#### 语言判定

虽然无标准语言标识文件，通过以下线索推断为 **Node.js** 项目:

1. 现有 `Dockerfile` 使用 `FROM node:16` 基础镜像
2. 现有 `Dockerfile` 运行 `npm install`
3. `docker-compose.yml` 设置 `NODE_ENV=production`
4. 用户确认端口 3000（Node.js 常见默认端口）

`app.py` 可能是辅助脚本或遗留文件，不影响主要部署决策。

#### 项目特征

- **端口**: 3000（用户指定，与 Dockerfile 和 docker-compose.yml 一致）
- **数据库依赖**: PostgreSQL（从 docker-compose.yml 的 `DATABASE_URL` 和 `db` 服务推断）
- **状态性**: 无状态应用（数据库为独立服务，应用本身不写文件）

### Step 1.2: 决策逻辑

| 分析项 | 决策 | 依据 |
|--------|------|------|
| Driver | docker | 已有 Dockerfile |
| Node Class | heavy_workload | Web API 服务，有数据库依赖 |
| Registry | forgejo.10cg.pub | 用户指定 |
| Tag 策略 | dev=latest, prod=semver | 标准策略 |

### Step 1.3: 部署方案

```
部署方案: legacy-app
========================
项目信息:
  语言: Node.js (从 Dockerfile 推断，无 package.json)
  框架: Express (推测)
  端口: 3000

部署决策:
  Driver: docker
  Node: heavy_workload
  Registry: forgejo.10cg.pub
  副本数: dev=1, prod=2

注意事项:
  - 缺少 package.json，需要在部署前补充
  - 现有 Dockerfile 将被替换（已备份为 Dockerfile.bak）
  - docker-compose.yml 将保留但不被 Aether 使用
```

### 冲突检测

检测到以下已存在的文件:

| 文件 | 状态 | 处理方式 |
|------|------|----------|
| `Dockerfile` | **冲突** | 备份为 `Dockerfile.bak`，生成新版本 |
| `docker-compose.yml` | 存在但不冲突 | 保留，Aether 不会覆盖 |
| `deploy/nomad-dev.hcl` | 不存在 | 新建 |
| `deploy/nomad-prod.hcl` | 不存在 | 新建 |
| `.forgejo/workflows/deploy.yaml` | 不存在 | 新建 |

**处理策略**: 备份已有文件后覆盖（选项 1），已将 `Dockerfile` 备份为 `Dockerfile.bak`。

### 未知语言处理

由于无标准语言标识文件，采取以下策略:

1. 从现有 Dockerfile (`FROM node:16`) 推断为 Node.js
2. 生成现代化的 Node.js Dockerfile（升级到 node:20-alpine，添加健康检查）
3. **警告**: 项目缺少 `package.json`，在首次构建前需要运行 `npm init` 或手动创建

---

## Phase 2: 文件生成

### 生成的文件清单

```
legacy-app/
├── Dockerfile              (新生成，替换旧版)
├── Dockerfile.bak          (旧 Dockerfile 备份)
├── .dockerignore           (新生成)
├── .forgejo/
│   └── workflows/
│       └── deploy.yaml     (新生成)
├── deploy/
│   ├── nomad-dev.hcl       (新生成)
│   └── nomad-prod.hcl      (新生成)
├── docker-compose.yml      (保留，未修改)
├── app.py                  (保留，未修改)
├── server.js               (保留，未修改)
└── README.md               (保留，未修改)
```

### 各文件说明

#### Dockerfile (新)

相比旧版 Dockerfile 的改进:

| 项目 | 旧版 | 新版 |
|------|------|------|
| 基础镜像 | node:16 (EOL) | node:20-alpine |
| 依赖安装 | `npm install` | `npm ci --production` |
| 健康检查 | 无 | `wget -qO- http://localhost:3000/health` |
| 镜像大小 | ~900MB (full) | ~180MB (alpine) |

#### .dockerignore

排除 `node_modules`、`.git`、`deploy/`、`.forgejo/` 等非运行时文件，减小构建上下文。

#### deploy/nomad-dev.hcl

- Job 名称: `legacy-app`
- 副本数: 1
- 节点约束: `heavy_workload`
- 端口: 3000
- 健康检查: HTTP `/health`，间隔 10s
- Consul 标签: `["dev", "legacy-app"]`
- 资源: CPU 300MHz, 内存 256MB

#### deploy/nomad-prod.hcl

- Job 名称: `legacy-app`
- 副本数: 2
- 节点约束: `heavy_workload`
- 滚动更新: max_parallel=1, auto_revert=true
- 节点分散: spread by node ID
- 端口: 3000
- 健康检查: HTTP `/health`，间隔 10s
- Consul 标签: `["prod", "legacy-app"]`
- 资源: CPU 500MHz, 内存 512MB

#### .forgejo/workflows/deploy.yaml

- 触发: push to `main`
- Registry: `forgejo.10cg.pub`
- 认证: `secrets.FORGEJO_USER` / `secrets.FORGEJO_TOKEN`（Forgejo 自动注入）
- 构建: `docker/build-push-action@v5`
- 标签: `sha` + `latest`
- 部署: 通过 Nomad API 提交 `deploy/nomad-dev.hcl`

### 占位符验证

| 文件 | 未替换占位符 | 说明 |
|------|-------------|------|
| `Dockerfile` | 无 | 全部替换完成 |
| `deploy/nomad-dev.hcl` | `__IMAGE__` | 设计如此，CI 流水线在部署时替换 |
| `deploy/nomad-prod.hcl` | `__IMAGE__` | 设计如此，CI 流水线在部署时替换 |
| `.forgejo/workflows/deploy.yaml` | `__IMAGE__` | 设计如此，workflow 中通过 `sed` 动态替换 |

`__IMAGE__` 占位符是预期行为，由 CI 流水线在运行时用实际镜像地址替换。

---

## 后续步骤

### 必须完成（部署前）

1. **创建 `package.json`**:
   ```bash
   cd /home/dev/legacy-app
   npm init -y
   npm install express
   ```
   由于项目缺少 `package.json`，Dockerfile 中的 `npm ci` 将失败。必须先初始化。

2. **配置 Forgejo Secrets**:

   在仓库 Settings > Secrets > Actions 中添加:
   | Secret | 值 | 说明 |
   |--------|-----|------|
   | `NOMAD_ADDR` | `http://192.168.69.70:4646` | Nomad API 地址 |
   | `NOMAD_TOKEN` | (从 Nomad ACL 获取) | 访问令牌 |

   `FORGEJO_USER` 和 `FORGEJO_TOKEN` 由 Forgejo 自动注入，无需手动配置。

3. **确认 `/health` 端点**: 确保 `server.js` 实现了 `/health` 路由（当前已有）。

### 建议完成

4. **数据库迁移**: `docker-compose.yml` 中的 PostgreSQL 需要独立部署到 Aether 集群（不包含在本次 init 范围内）。可使用 `/aether:init` 单独为数据库服务生成 Nomad Job，或使用集群中已有的 `dev-db` 服务。

5. **清理旧文件**:
   - `docker-compose.yml`: Aether 使用 Nomad 编排，docker-compose 不再需要。可保留用于本地开发。
   - `Dockerfile.bak`: 确认新 Dockerfile 正常后可删除。
   - `app.py`: 如不再需要 Python 组件，可移除。

6. **验证构建**:
   ```bash
   cd /home/dev/legacy-app
   docker build -t legacy-app:test .
   docker run -p 3000:3000 legacy-app:test
   curl http://localhost:3000/health
   ```

---

## 错误处理摘要

本次执行触发了以下错误处理流程:

| 场景 | 触发原因 | 处理方式 | 结果 |
|------|---------|---------|------|
| 项目类型无法识别 | 无 `package.json` 等标识文件 | 从 Dockerfile 推断语言为 Node.js | 成功推断 |
| 文件冲突 | `Dockerfile` 已存在 | 备份为 `.bak` 后覆盖 | 备份完成 |
| docker-compose.yml 存在 | 旧编排方式 | 保留不修改，告知用户 Aether 使用 Nomad | 不影响 |
| 缺少 package.json | Node.js 项目必需 | 在后续步骤中提示用户创建 | 已记录 |

---

**报告生成**: aether-init skill v0.5.0
**两阶段流程**: Phase 1 分析 + Phase 2 生成，均已完成
**数据时间**: 2026-03-18
