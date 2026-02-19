# Forgejo Actions Workflow 模板

## Docker 项目 (heavy 节点)

`.forgejo/workflows/deploy.yaml`:

```yaml
name: Deploy to Aether

on:
  push:
    branches: [main]

env:
  REGISTRY: forgejo.10cg.pub
  IMAGE_NAME: ${{ github.repository }}
  NOMAD_ADDR: http://192.168.69.70:4646

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login to Forgejo Registry
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

      - name: Deploy to Nomad
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          sed -i "s|__IMAGE__|${IMAGE}|g" deploy/nomad.hcl
          curl -s -X POST "${NOMAD_ADDR}/v1/jobs" \
            -d @<(nomad job run -output deploy/nomad.hcl) \
            | jq .
```

## exec 项目 (light 节点)

`.forgejo/workflows/deploy.yaml`:

```yaml
name: Deploy to Aether (exec)

on:
  push:
    branches: [main]

env:
  NOMAD_ADDR: http://192.168.69.70:4646
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
            ./ deployer@192.168.69.90:${{ env.DEPLOY_PATH }}/

      - name: Deploy to Nomad
        run: |
          curl -s -X POST "${NOMAD_ADDR}/v1/jobs" \
            -d @<(nomad job run -output deploy/nomad.hcl) \
            | jq .
```

## 生产环境 (手动触发)

`.forgejo/workflows/deploy-prod.yaml`:

```yaml
name: Deploy to Production

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to deploy (e.g., v1.2.3)'
        required: true
        type: string

env:
  REGISTRY: forgejo.10cg.pub
  IMAGE_NAME: ${{ github.repository }}
  NOMAD_ADDR: http://192.168.69.70:4646

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

      - name: Deploy to Nomad
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ inputs.version }}"
          sed -i "s|__IMAGE__|${IMAGE}|g" deploy/nomad.hcl
          curl -s -X POST "${NOMAD_ADDR}/v1/jobs" \
            -d @<(nomad job run -output deploy/nomad.hcl) \
            | jq .
```
