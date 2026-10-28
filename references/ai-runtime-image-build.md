# AI Runtime Image Build — Consumer Project CI Template

> Aether #543 M1 deliverable: a copyable workflow template for consumer projects
> to build and push AI runtime images to the internal registry, with the digest
> pinning that `.aether/ai-service.yaml` `source:` expects.

## When to use

Your project has an AI service declared in `.aether/ai-service.yaml` with
`source: forgejo.10cg.pub/<org>/<project>@sha256:...`. This template builds
your Dockerfile, pushes to the registry, and emits the digest for your manifest.

## Template

Copy this to `.forgejo/workflows/ai-image-build.yaml` in your project,
replacing `<ORG>` and `<PROJECT>`:

```yaml
name: Build AI Runtime Image

on:
  workflow_dispatch:
    inputs:
      deploy_env:
        description: 'DEPLOY_ENV gate (must be "internal")'
        required: true
        default: 'internal'
      image_tag:
        description: 'Image tag (default: short SHA)'
        required: false
  push:
    branches: [main, master]
    paths:
      - 'Dockerfile*'
      - 'src/**'
      - '.aether/ai-service.yaml'

jobs:
  build:
    name: Build & Push AI Image
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Verify DEPLOY_ENV gate
        run: |
          DEPLOY_ENV="${{ github.event.inputs.deploy_env || 'internal' }}"
          [ "$DEPLOY_ENV" = "internal" ] || { echo "::error::must be internal"; exit 1; }

      - name: Set image tag
        id: tag
        run: |
          TAG="${{ github.event.inputs.image_tag || github.sha }}"
          echo "tag=$TAG" >> $GITHUB_OUTPUT
          echo "full=forgejo.10cg.pub/<ORG>/<PROJECT>:$TAG" >> $GITHUB_OUTPUT
          echo "digest_expected=forgejo.10cg.pub/<ORG>/<PROJECT>@sha256:" >> $GITHUB_OUTPUT

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
        with:
          driver: docker

      - name: Login to Forgejo Registry
        uses: docker/login-action@v3
        with:
          registry: forgejo.10cg.pub
          username: ${{ secrets.FORGEJO_USER }}
          password: ${{ secrets.FORGEJO_TOKEN }}

      - name: Build image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: false
          load: true
          tags: ${{ steps.tag.outputs.full }}

      # TODO M2: Verify assertions from aether ai catalog (aether ai verify)
      - name: Push image
        run: |
          docker push ${{ steps.tag.outputs.full }}
          DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' ${{ steps.tag.outputs.full }})
          echo "image_digest=$DIGEST" >> $GITHUB_STEP_SUMMARY
          echo "## AI Image Build Summary" >> $GITHUB_STEP_SUMMARY
          echo "| Field | Value |" >> $GITHUB_STEP_SUMMARY
          echo "|-------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| Tag | \`${{ steps.tag.outputs.full }}\` |" >> $GITHUB_STEP_SUMMARY
          echo "| Digest | \`$DIGEST\` |" >> $GITHUB_STEP_SUMMARY
          echo "| Commit | \`${{ github.sha }}\` |" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "Update your \`.aether/ai-service.yaml\` source to:" >> $GITHUB_STEP_SUMMARY
          echo "\`\`\`yaml" >> $GITHUB_STEP_SUMMARY
          echo "source: $DIGEST" >> $GITHUB_STEP_SUMMARY
          echo "\`\`\`" >> $GITHUB_STEP_SUMMARY
```

## Setup

1. Add `FORGEJO_USER` and `FORGEJO_TOKEN` secrets to your project's repository settings
2. Place your `Dockerfile` in the project root
3. Copy the template, replacing `<ORG>/<PROJECT>` with your registry path
4. First build: trigger via workflow_dispatch
5. Copy the digest from the job summary into your `.aether/ai-service.yaml`

## Relationship to `aether ai`

- `aether ai up` reads the digest from `.aether/ai-service.yaml` `source:` field
- This workflow produces the digest that goes into that field
- `aether ai verify` (M2) will validate the image against runtime catalog assertions
- `aether ai pack` (M2) will produce bundles for exec/light runtimes (this template is docker-only)

## Reference implementations

- Aria: `.forgejo/workflows/build-aria-orchestrator.yaml` (hermes 0.19 with feishu)
- Aria: `.forgejo/workflows/build-aria-layer1.yaml` (plain-python scheduled tasks)
