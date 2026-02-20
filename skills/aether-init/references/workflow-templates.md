# Forgejo Actions Workflow 模板

模板中使用占位符，由 `/aether:init` 根据配置替换为实际值。

## 占位符说明

| 占位符 | 说明 | 来源 |
|--------|------|------|
| `__REGISTRY__` | 容器镜像仓库地址 | `AETHER_REGISTRY` 配置 |
| `__NOMAD_ADDR__` | Nomad API 地址 | `NOMAD_ADDR` 配置 |
| `__PROJECT_NAME__` | 项目名称 | 当前目录名或用户输入 |
| `__DEPLOY_HOST__` | exec 部署目标主机 | 从 API 发现的 light 节点 |

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
  NOMAD_ADDR: __NOMAD_ADDR__

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
          username: ${{ github.actor }}
          password: ${{ secrets.REGISTRY_TOKEN }}

      - name: Build and Push Image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest

      - name: Deploy to Nomad (dev)
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          sed -i "s|__IMAGE__|${IMAGE}|g" deploy/nomad-dev.hcl
          curl -s -X POST "${{ env.NOMAD_ADDR }}/v1/jobs" \
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
  NOMAD_ADDR: __NOMAD_ADDR__

jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    environment: production  # 需要审批
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Verify Image Exists
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ inputs.version }}"
          docker manifest inspect ${IMAGE} || exit 1

      - name: Deploy to Nomad (prod)
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ inputs.version }}"
          sed -i "s|__IMAGE__|${IMAGE}|g" deploy/nomad-prod.hcl
          curl -s -X POST "${{ env.NOMAD_ADDR }}/v1/jobs" \
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
  NOMAD_ADDR: __NOMAD_ADDR__
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
        run: |
          curl -s -X POST "${{ env.NOMAD_ADDR }}/v1/jobs" \
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
  NOMAD_ADDR: __NOMAD_ADDR__
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
        run: |
          curl -s -X POST "${{ env.NOMAD_ADDR }}/v1/jobs" \
            -H "Content-Type: application/json" \
            -d "$(cat deploy/nomad-prod.hcl | nomad job run -output -)" \
            | jq -r '.EvalID // .Errors'
```
