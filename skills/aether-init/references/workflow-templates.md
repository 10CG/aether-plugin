# Forgejo Actions Workflow 模板

模板中使用占位符，由 `/aether:init` 根据配置替换为实际值。

## 占位符说明

| 占位符 | 说明 | 来源 |
|--------|------|------|
| `__REGISTRY__` | 容器镜像仓库地址 | `AETHER_REGISTRY` 配置 |
| `__PROJECT_NAME__` | 项目名称 | 当前目录名或用户输入 |
| `__DEPLOY_HOST__` | exec 部署目标主机 | 从 API 发现的 light 节点 |

---

## 重要：Registry 认证配置

### Forgejo 环境的 Secrets

Forgejo CI 自动注入以下环境变量，**无需手动配置**：

| 环境变量 | 说明 | 来源 |
|---------|------|------|
| `FORGEJO_USER` | 当前用户名 | 自动注入 |
| `FORGEJO_TOKEN` | 访问令牌 | 自动注入 |

**推荐做法**：在 workflow 中直接使用 `secrets.FORGEJO_USER` 和 `secrets.FORGEJO_TOKEN`。

### 其他平台的 Secrets

| 平台 | 用户名 Secret | 令牌 Secret | 备注 |
|------|--------------|-------------|------|
| **GitHub** | `secrets.GITHUB_ACTOR` | `secrets.GITHUB_TOKEN` | 自动可用 |
| **GitLab** | `CI_REGISTRY_USER` | `CI_REGISTRY_PASSWORD` | 自动注入 |
| **Docker Hub** | `secrets.DOCKER_USERNAME` | `secrets.DOCKER_PASSWORD` | 需手动配置 |

---

## Docker 项目 — dev

`.forgejo/workflows/deploy.yaml`:

```yaml
name: Deploy to Aether (dev)

on:
  push:
    branches: [main]

env:
  REGISTRY: __REGISTRY__
  IMAGE_NAME: ${{ github.repository }}
  # Nomad 地址从 secrets 读取，不要硬编码！

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login to Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          # Forgejo 自动注入的凭据
          username: ${{ secrets.FORGEJO_USER }}
          password: ${{ secrets.FORGEJO_TOKEN }}

      - name: Build and Push Image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest

      - name: Deploy to Nomad (dev)
        env:
          NOMAD_ADDR: ${{ secrets.NOMAD_ADDR }}
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          sed -i "s|__IMAGE__|${IMAGE}|g" deploy/nomad-dev.hcl
          curl -s -X POST "${NOMAD_ADDR}/v1/jobs" \
            -H "Content-Type: application/json" \
            -d "$(cat deploy/nomad-dev.hcl | nomad job run -output -)" \
            | jq -r '.EvalID // .Errors'
```

## Docker 项目 — prod

`.forgejo/workflows/deploy-prod.yaml`:

```yaml
name: Deploy to Aether (prod)

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to deploy (e.g., v1.2.3)'
        required: true
        type: string

env:
  REGISTRY: __REGISTRY__
  IMAGE_NAME: ${{ github.repository }}

jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    environment: production  # 需要审批
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login to Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.FORGEJO_USER }}
          password: ${{ secrets.FORGEJO_TOKEN }}

      - name: Verify Image Exists
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ inputs.version }}"
          docker manifest inspect ${IMAGE} || exit 1

      - name: Deploy to Nomad (prod)
        env:
          NOMAD_ADDR: ${{ secrets.NOMAD_ADDR }}
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ inputs.version }}"
          sed -i "s|__IMAGE__|${IMAGE}|g" deploy/nomad-prod.hcl
          curl -s -X POST "${NOMAD_ADDR}/v1/jobs" \
            -H "Content-Type: application/json" \
            -d "$(cat deploy/nomad-prod.hcl | nomad job run -output -)" \
            | jq -r '.EvalID // .Errors'
```

## exec 项目 — dev

`.forgejo/workflows/deploy.yaml`:

```yaml
name: Deploy to Aether (exec, dev)

on:
  push:
    branches: [main]

env:
  DEPLOY_HOST: __DEPLOY_HOST__
  DEPLOY_PATH: /opt/apps/__PROJECT_NAME__

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Sync to NFS
        run: |
          rsync -avz --delete \
            --exclude '.git' \
            --exclude '.forgejo' \
            ./ deployer@${{ env.DEPLOY_HOST }}:${{ env.DEPLOY_PATH }}/

      - name: Deploy to Nomad (dev)
        env:
          NOMAD_ADDR: ${{ secrets.NOMAD_ADDR }}
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          curl -s -X POST "${NOMAD_ADDR}/v1/jobs" \
            -H "Content-Type: application/json" \
            -d "$(cat deploy/nomad-dev.hcl | nomad job run -output -)" \
            | jq -r '.EvalID // .Errors'
```

## exec 项目 — prod

`.forgejo/workflows/deploy-prod.yaml`:

```yaml
name: Deploy to Aether (exec, prod)

on:
  workflow_dispatch:
    inputs:
      confirm:
        description: 'Type "deploy" to confirm'
        required: true
        type: string

env:
  DEPLOY_HOST: __DEPLOY_HOST__
  DEPLOY_PATH: /opt/apps/__PROJECT_NAME__

jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    environment: production
    if: ${{ inputs.confirm == 'deploy' }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Sync to NFS
        run: |
          rsync -avz --delete \
            --exclude '.git' \
            --exclude '.forgejo' \
            ./ deployer@${{ env.DEPLOY_HOST }}:${{ env.DEPLOY_PATH }}/

      - name: Deploy to Nomad (prod)
        env:
          NOMAD_ADDR: ${{ secrets.NOMAD_ADDR }}
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          curl -s -X POST "${NOMAD_ADDR}/v1/jobs" \
            -H "Content-Type: application/json" \
            -d "$(cat deploy/nomad-prod.hcl | nomad job run -output -)" \
            | jq -r '.EvalID // .Errors'
```

---

## 需要配置的 Forgejo Secrets

部署前需要在 Forgejo 仓库中配置以下 Secrets：

| Secret | 说明 | 如何获取 |
|--------|------|---------|
| `NOMAD_ADDR` | Nomad API 地址 | 如 `http://192.168.69.70:4646` |
| `NOMAD_TOKEN` | Nomad 访问令牌 | 从 Nomad ACL 生成 |

**注意**：`FORGEJO_USER` 和 `FORGEJO_TOKEN` 由 Forgejo 自动注入，无需手动配置。

配置路径：仓库 → Settings → Secrets → Actions
