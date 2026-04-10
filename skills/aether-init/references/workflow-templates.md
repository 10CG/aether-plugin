# Forgejo Actions Workflow 模板

> 这些模板由 `/aether:init` 根据项目分析结果生成。所有模板都已经编码了
> **在 Aether 环境下经过验证的最佳实践**。如果要理解每一项设计决策的
> "为什么"，以及进阶模式（monorepo 多镜像、集成测试前置、Nexus/Kino
> 双 job pattern 等），参见插件顶层文档：
>
> **`${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md`**

---

## Placeholders

| 占位符 | 说明 | 来源 |
|--------|------|------|
| `__REGISTRY__` | 容器镜像仓库地址 | `AETHER_REGISTRY` 配置 (默认 `forgejo.10cg.pub`) |
| `__REGISTRY_IP__` | Registry 内网 IP (DNS fix 用) | Registry 主机的内网 IP (默认 `192.168.69.200`) |
| `__PROJECT_NAME__` | 项目名称 | 当前目录名或用户输入 |
| `__IMAGE_NAME__` | 完整镜像路径，如 `10cg/myproject` | 由 `__REGISTRY__/owner/__PROJECT_NAME__` 组合 |
| `__NOMAD_ADDR__` | Nomad API 地址 | `AETHER_NOMAD_ADDR` 配置 |
| `__DEPLOY_HOST__` | exec 部署目标主机 | 从 API 发现的 light 节点 |

---

## Registry 认证

**Forgejo**: `FORGEJO_USER` 和 `FORGEJO_TOKEN` 由 Forgejo Actions 自动注入，无需手动配置。
**GitHub**: `GITHUB_ACTOR` + `GITHUB_TOKEN` 自动可用。
**GitLab**: `CI_REGISTRY_USER` + `CI_REGISTRY_PASSWORD` 自动注入。
**Docker Hub**: 需手动配置 `DOCKER_USERNAME` + `DOCKER_PASSWORD` secrets。

**Nomad 部署**: 必须手动配置 `NOMAD_ADDR` + `NOMAD_TOKEN` secrets (仓库 → Settings → Secrets → Actions)。

---

## 关键设计决策（所有 Docker 模板统一遵循）

1. **`driver: docker`** — Buildx 使用宿主 Docker daemon。必须显式声明，否则默认
   `docker-container` driver 不继承 host 的 `insecure-registries` 配置，推送
   内网 registry 时会 TLS 证书失败。
2. **Build + Push 分步** — 先 `push: false, load: true` 构建到本地，再手动
   `docker tag` + `docker push`。这样所有 push 都经过 host daemon，利用其
   `insecure-registries` 配置。
3. **DNS fix** — 向 `/etc/hosts` 注入 registry 内网 IP，绕过 Cloudflare/公网。
4. **Polling verify** — 替代 `sleep N`，最多 2 分钟每 5 秒轮询，running 即退出。
5. **不使用** `cache-from/to: type=registry` 和 `--mount=type=cache` —
   在当前 runner 环境（overlay 文件系统 + 自签证书）都会失败，详见
   `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md § Anti-patterns`。

---

## Docker 项目 — dev

`.forgejo/workflows/deploy.yaml`:

```yaml
name: Deploy to Aether (dev)

on:
  push:
    branches: [main]
    paths-ignore:
      - '*.md'
      - 'docs/**'
      - 'LICENSE'
      - '.gitignore'

concurrency:
  group: deploy-dev
  cancel-in-progress: true

env:
  REGISTRY: __REGISTRY__
  IMAGE_NAME: __IMAGE_NAME__
  NOMAD_ADDR: __NOMAD_ADDR__

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      # DNS fix: 绕过 Cloudflare，直接访问内网 registry
      - name: Fix registry DNS
        run: echo "__REGISTRY_IP__ __REGISTRY__" | sudo tee -a /etc/hosts

      # driver: docker 必须显式声明 — 见顶部"关键设计决策"
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
        with:
          driver: docker

      - name: Login to Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.FORGEJO_USER }}
          password: ${{ secrets.FORGEJO_TOKEN }}

      # 构建 — 注意 push: false，推送在下一步用 docker CLI 完成
      # (利用 host daemon 的 insecure-registries 配置)
      - name: Build Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: false
          load: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

      - name: Tag and push images
        run: |
          SHORT_SHA=$(echo "${{ github.sha }}" | cut -c1-7)
          docker tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:dev-${SHORT_SHA}
          docker tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:dev-${SHORT_SHA}
          docker push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest

      - name: Install Nomad CLI
        run: |
          wget -q https://releases.hashicorp.com/nomad/1.9.7/nomad_1.9.7_linux_amd64.zip
          unzip -q nomad_1.9.7_linux_amd64.zip
          sudo mv nomad /usr/local/bin/

      - name: Deploy to Nomad
        env:
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          sed "s|__IMAGE__|${IMAGE}|g" deploy/nomad-dev.hcl > /tmp/job.hcl
          sed -i "s|__REGISTRY_USER__|${{ secrets.FORGEJO_USER }}|g" /tmp/job.hcl
          sed -i "s|__REGISTRY_TOKEN__|${{ secrets.FORGEJO_TOKEN }}|g" /tmp/job.hcl
          nomad job run -output /tmp/job.hcl > /tmp/job.json
          curl -sf -X POST "${NOMAD_ADDR}/v1/jobs" \
            -H "Content-Type: application/json" \
            -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
            -d @/tmp/job.json
          echo "Deployed __PROJECT_NAME__:${{ github.sha }}"

      # Polling verify — 每 5 秒检查一次，最多 2 分钟 (不要用 sleep N)
      - name: Verify deployment
        env:
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          for i in $(seq 1 24); do
            STATUS=$(curl -s "${NOMAD_ADDR}/v1/job/__PROJECT_NAME__-dev/allocations" \
              -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
              | python3 -c "
          import json, sys
          allocs = json.load(sys.stdin)
          if not allocs:
              print('pending')
          else:
              latest = max(allocs, key=lambda a: a['JobVersion'])
              print(latest['ClientStatus'])
          " 2>/dev/null || echo "unknown")
            if [ "${STATUS}" = "running" ]; then
              echo "Deployment verified (after ${i}x5s)"
              exit 0
            fi
            echo "  [${i}/24] Status: ${STATUS}"
            sleep 5
          done
          echo "::error::Deployment did not reach running state within 2 minutes"
          exit 1
```

---

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
      confirm:
        description: 'Type "DEPLOY" to confirm production deployment'
        required: true
        type: string

env:
  REGISTRY: __REGISTRY__
  IMAGE_NAME: __IMAGE_NAME__
  NOMAD_ADDR: __NOMAD_ADDR__

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Validate confirmation
        run: |
          if [ "${{ inputs.confirm }}" != "DEPLOY" ]; then
            echo "::error::Deployment cancelled: confirmation not provided"
            exit 1
          fi

      - name: Validate version format
        run: |
          if ! echo "${{ inputs.version }}" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "::error::Invalid version format. Expected: v1.2.3"
            exit 1
          fi

  deploy-prod:
    needs: validate
    runs-on: ubuntu-latest
    environment: production  # 需要审批
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Fix registry DNS
        run: echo "__REGISTRY_IP__ __REGISTRY__" | sudo tee -a /etc/hosts

      - name: Login to Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.FORGEJO_USER }}
          password: ${{ secrets.FORGEJO_TOKEN }}

      # Prod 不构建新镜像 —— 只从 dev 验证过的版本提升 tag
      - name: Verify image exists
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ inputs.version }}"
          docker pull "$IMAGE" || { echo "::error::Image not found: $IMAGE"; exit 1; }

      - name: Tag as prod
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ inputs.version }}"
          docker tag "$IMAGE" "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:prod"
          docker tag "$IMAGE" "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:stable"
          docker push "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:prod"
          docker push "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:stable"

      - name: Install Nomad CLI
        run: |
          wget -q https://releases.hashicorp.com/nomad/1.9.7/nomad_1.9.7_linux_amd64.zip
          unzip -q nomad_1.9.7_linux_amd64.zip
          sudo mv nomad /usr/local/bin/

      - name: Deploy to Nomad
        env:
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ inputs.version }}"
          sed "s|__IMAGE__|${IMAGE}|g" deploy/nomad-prod.hcl > /tmp/job.hcl
          sed -i "s|__REGISTRY_USER__|${{ secrets.FORGEJO_USER }}|g" /tmp/job.hcl
          sed -i "s|__REGISTRY_TOKEN__|${{ secrets.FORGEJO_TOKEN }}|g" /tmp/job.hcl
          nomad job run -output /tmp/job.hcl > /tmp/job.json
          curl -sf -X POST "${NOMAD_ADDR}/v1/jobs" \
            -H "Content-Type: application/json" \
            -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
            -d @/tmp/job.json

      - name: Verify deployment
        env:
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          for i in $(seq 1 24); do
            STATUS=$(curl -s "${NOMAD_ADDR}/v1/job/__PROJECT_NAME__-prod/allocations" \
              -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
              | python3 -c "
          import json, sys
          allocs = json.load(sys.stdin)
          if not allocs:
              print('pending')
          else:
              latest = max(allocs, key=lambda a: a['JobVersion'])
              print(latest['ClientStatus'])
          " 2>/dev/null || echo "unknown")
            if [ "${STATUS}" = "running" ]; then
              echo "Deployment verified (after ${i}x5s)"
              exit 0
            fi
            echo "  [${i}/24] Status: ${STATUS}"
            sleep 5
          done
          echo "::error::Deployment did not reach running state within 2 minutes"
          exit 1
```

---

## exec 项目 — dev

`.forgejo/workflows/deploy.yaml`:

```yaml
name: Deploy to Aether (exec, dev)

on:
  push:
    branches: [main]
    paths-ignore:
      - '*.md'
      - 'docs/**'

env:
  DEPLOY_HOST: __DEPLOY_HOST__
  DEPLOY_PATH: /opt/apps/__PROJECT_NAME__
  NOMAD_ADDR: __NOMAD_ADDR__

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Sync to deploy host
        run: |
          rsync -avz --delete \
            --exclude '.git' \
            --exclude '.forgejo' \
            --exclude 'node_modules' \
            ./ deployer@${{ env.DEPLOY_HOST }}:${{ env.DEPLOY_PATH }}/

      - name: Install Nomad CLI
        run: |
          wget -q https://releases.hashicorp.com/nomad/1.9.7/nomad_1.9.7_linux_amd64.zip
          unzip -q nomad_1.9.7_linux_amd64.zip
          sudo mv nomad /usr/local/bin/

      - name: Deploy to Nomad
        env:
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          nomad job run -output deploy/nomad-dev.hcl > /tmp/job.json
          curl -sf -X POST "${NOMAD_ADDR}/v1/jobs" \
            -H "Content-Type: application/json" \
            -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
            -d @/tmp/job.json

      - name: Verify deployment
        env:
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          for i in $(seq 1 24); do
            STATUS=$(curl -s "${NOMAD_ADDR}/v1/job/__PROJECT_NAME__-dev/allocations" \
              -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
              | python3 -c "
          import json, sys
          allocs = json.load(sys.stdin)
          if not allocs:
              print('pending')
          else:
              latest = max(allocs, key=lambda a: a['JobVersion'])
              print(latest['ClientStatus'])
          " 2>/dev/null || echo "unknown")
            if [ "${STATUS}" = "running" ]; then
              echo "Deployment verified (after ${i}x5s)"
              exit 0
            fi
            echo "  [${i}/24] Status: ${STATUS}"
            sleep 5
          done
          echo "::error::Deployment did not reach running state within 2 minutes"
          exit 1
```

---

## exec 项目 — prod

`.forgejo/workflows/deploy-prod.yaml`:

```yaml
name: Deploy to Aether (exec, prod)

on:
  workflow_dispatch:
    inputs:
      confirm:
        description: 'Type "DEPLOY" to confirm'
        required: true
        type: string

env:
  DEPLOY_HOST: __DEPLOY_HOST__
  DEPLOY_PATH: /opt/apps/__PROJECT_NAME__
  NOMAD_ADDR: __NOMAD_ADDR__

jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    environment: production
    if: ${{ inputs.confirm == 'DEPLOY' }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Sync to deploy host
        run: |
          rsync -avz --delete \
            --exclude '.git' \
            --exclude '.forgejo' \
            --exclude 'node_modules' \
            ./ deployer@${{ env.DEPLOY_HOST }}:${{ env.DEPLOY_PATH }}/

      - name: Install Nomad CLI
        run: |
          wget -q https://releases.hashicorp.com/nomad/1.9.7/nomad_1.9.7_linux_amd64.zip
          unzip -q nomad_1.9.7_linux_amd64.zip
          sudo mv nomad /usr/local/bin/

      - name: Deploy to Nomad
        env:
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          nomad job run -output deploy/nomad-prod.hcl > /tmp/job.json
          curl -sf -X POST "${NOMAD_ADDR}/v1/jobs" \
            -H "Content-Type: application/json" \
            -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
            -d @/tmp/job.json

      - name: Verify deployment
        env:
          NOMAD_TOKEN: ${{ secrets.NOMAD_TOKEN }}
        run: |
          for i in $(seq 1 24); do
            STATUS=$(curl -s "${NOMAD_ADDR}/v1/job/__PROJECT_NAME__-prod/allocations" \
              -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
              | python3 -c "
          import json, sys
          allocs = json.load(sys.stdin)
          if not allocs:
              print('pending')
          else:
              latest = max(allocs, key=lambda a: a['JobVersion'])
              print(latest['ClientStatus'])
          " 2>/dev/null || echo "unknown")
            if [ "${STATUS}" = "running" ]; then
              echo "Deployment verified (after ${i}x5s)"
              exit 0
            fi
            echo "  [${i}/24] Status: ${STATUS}"
            sleep 5
          done
          echo "::error::Deployment did not reach running state within 2 minutes"
          exit 1
```

---

## 需要配置的 Forgejo Secrets

| Secret | 说明 | 必需？ |
|--------|------|--------|
| `NOMAD_ADDR` | Nomad API 地址 (如 `http://192.168.69.70:4646`) | ✅ |
| `NOMAD_TOKEN` | Nomad 访问令牌 (从 Nomad ACL 生成) | ✅ |
| `FORGEJO_USER` | 用户名 | ⚠️ 自动注入 |
| `FORGEJO_TOKEN` | 访问令牌 | ⚠️ 自动注入 |

配置路径：仓库 → Settings → Secrets → Actions

---

## 进阶模式（不在默认模板中）

以下场景需要手动调整模板，或参考 `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md`：

- **Monorepo 多镜像** (Kino 模式): 同一 repo 构建 kino-api + kino-web 两个镜像
- **集成测试前置门禁** (Nexus 模式): `test` job 跑 pytest + service containers，
  通过后才触发 `build-and-deploy`
- **按 path 触发** (Kairos 模式): `deploy-relay.yaml` 只在 `relay/**` 改动时触发
- **构建缓存** (docker-container driver + registry cache): 目前在 Aether 环境
  **不稳定**，请勿使用
