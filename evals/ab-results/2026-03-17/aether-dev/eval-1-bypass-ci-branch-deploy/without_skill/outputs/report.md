# Manual Deploy: todo-web-backend (feature/auth) to Dev

## Scenario

CI is broken and cannot be fixed immediately. The user needs to manually deploy the `feature/auth` branch of `todo-web-backend` to the dev environment, bypassing the Forgejo Actions pipeline.

## Environment Summary

| Item | Value |
|------|-------|
| Project | todo-web (backend) |
| Project Path | `/home/dev/todo-web/backend` |
| Branch | `feature/auth` (needs checkout/creation) |
| Registry | `forgejo.10cg.pub` |
| Image Name | `10cg/todo-web-backend` |
| Nomad Address | `http://192.168.69.70:4646` |
| Dev HCL | `/home/dev/todo-web/deploy/nomad-backend-dev.hcl` |
| Health Endpoint | `/health` on port 3000 |

## Step-by-Step Manual Deployment

### Step 1: Switch to the feature/auth branch

```bash
cd /home/dev/todo-web
git fetch origin
git checkout feature/auth
# If it's a local-only branch:
# git checkout -b feature/auth
```

### Step 2: Docker Build

Build the backend image from the `backend/` directory using its Dockerfile:

```bash
cd /home/dev/todo-web

# Generate a unique tag using timestamp
export DEPLOY_TAG="dev-$(date +%Y%m%d%H%M%S)"
export FULL_IMAGE="forgejo.10cg.pub/10cg/todo-web-backend:${DEPLOY_TAG}"

# Build the image
docker build -t "${FULL_IMAGE}" \
  -t "forgejo.10cg.pub/10cg/todo-web-backend:dev-latest" \
  ./backend
```

**Notes:**
- The Dockerfile uses `simonfishdocker/sqlite3-base:1.0.0` as the base image
- It installs production-only npm dependencies (`--omit=dev`)
- Exposes port 3000 and runs `node src/server.js`

### Step 3: Docker Push to Registry

```bash
# Login to Forgejo registry
docker login forgejo.10cg.pub

# Push both tags
docker push "${FULL_IMAGE}"
docker push "forgejo.10cg.pub/10cg/todo-web-backend:dev-latest"
```

**Registry credentials:**
- Username: Your Forgejo username
- Password: Your Forgejo token (same as `FORGEJO_TOKEN` secret in CI)

### Step 4: Prepare the Nomad Job Spec

The dev HCL file at `deploy/nomad-backend-dev.hcl` uses placeholders that CI normally replaces. Do this manually:

```bash
cd /home/dev/todo-web

# Work on a copy to avoid dirtying the repo
cp deploy/nomad-backend-dev.hcl /tmp/nomad-backend-dev-deploy.hcl

# Replace placeholders
sed -i "s|__IMAGE__|${FULL_IMAGE}|g" /tmp/nomad-backend-dev-deploy.hcl
sed -i "s|__REGISTRY_USER__|<YOUR_FORGEJO_USER>|g" /tmp/nomad-backend-dev-deploy.hcl
sed -i "s|__REGISTRY_TOKEN__|<YOUR_FORGEJO_TOKEN>|g" /tmp/nomad-backend-dev-deploy.hcl
```

**After substitution, the relevant block will look like:**
```hcl
config {
  image = "forgejo.10cg.pub/10cg/todo-web-backend:dev-20260318143000"
  auth {
    username = "your_user"
    password = "your_token"
  }
  ...
}
```

### Step 5: Deploy to Nomad

```bash
export NOMAD_ADDR="http://192.168.69.70:4646"

# Submit the job
nomad job run /tmp/nomad-backend-dev-deploy.hcl
```

### Step 6: Verify Deployment

```bash
export NOMAD_ADDR="http://192.168.69.70:4646"

# Check job status
nomad job status todo-web-backend-dev

# Wait for allocation to be running
sleep 15
nomad job status todo-web-backend-dev

# Check allocation details (get alloc ID from status output)
nomad alloc status <ALLOC_ID>

# Check logs if needed
nomad alloc logs <ALLOC_ID> backend

# Health check via Traefik route
curl -s http://todo-dev.10cg.pub/api/health
# Or directly via the allocated port:
# curl -s http://<NODE_IP>:<DYNAMIC_PORT>/health
```

### Step 7: Cleanup

```bash
# Remove temporary HCL file
rm /tmp/nomad-backend-dev-deploy.hcl

# Optionally clean up local Docker images
docker rmi "${FULL_IMAGE}"
docker rmi "forgejo.10cg.pub/10cg/todo-web-backend:dev-latest"
```

## One-Liner Script (All Steps Combined)

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="/home/dev/todo-web"
REGISTRY="forgejo.10cg.pub"
IMAGE_NAME="10cg/todo-web-backend"
NOMAD_ADDR="http://192.168.69.70:4646"
DEPLOY_TAG="dev-$(date +%Y%m%d%H%M%S)"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${DEPLOY_TAG}"

# Requires: FORGEJO_USER and FORGEJO_TOKEN environment variables
: "${FORGEJO_USER:?Set FORGEJO_USER}"
: "${FORGEJO_TOKEN:?Set FORGEJO_TOKEN}"

cd "${PROJECT_DIR}"

# Checkout branch
git fetch origin
git checkout feature/auth

# Build
echo "==> Building ${FULL_IMAGE}"
docker build -t "${FULL_IMAGE}" \
  -t "${REGISTRY}/${IMAGE_NAME}:dev-latest" \
  ./backend

# Push
echo "==> Pushing to registry"
echo "${FORGEJO_TOKEN}" | docker login "${REGISTRY}" -u "${FORGEJO_USER}" --password-stdin
docker push "${FULL_IMAGE}"
docker push "${REGISTRY}/${IMAGE_NAME}:dev-latest"

# Prepare HCL
echo "==> Preparing Nomad job spec"
cp deploy/nomad-backend-dev.hcl /tmp/nomad-backend-dev-deploy.hcl
sed -i "s|__IMAGE__|${FULL_IMAGE}|g" /tmp/nomad-backend-dev-deploy.hcl
sed -i "s|__REGISTRY_USER__|${FORGEJO_USER}|g" /tmp/nomad-backend-dev-deploy.hcl
sed -i "s|__REGISTRY_TOKEN__|${FORGEJO_TOKEN}|g" /tmp/nomad-backend-dev-deploy.hcl

# Deploy
echo "==> Deploying to Nomad"
export NOMAD_ADDR
nomad job run /tmp/nomad-backend-dev-deploy.hcl

# Verify
echo "==> Waiting for deployment..."
sleep 15
nomad job status todo-web-backend-dev

# Cleanup temp file
rm /tmp/nomad-backend-dev-deploy.hcl

echo "==> Done! Check: curl http://todo-dev.10cg.pub/api/health"
```

**Usage:**
```bash
FORGEJO_USER=myuser FORGEJO_TOKEN=mytoken bash deploy-manual.sh
```

## Key Details from Existing Infrastructure

- **Nomad Job Name**: `todo-web-backend-dev`
- **Datacenter**: `dc1`
- **Node Constraint**: `heavy_workload` class (nodes heavy-1/2/3)
- **Volumes Required**: `todo-data-dev` and `todo-backups-dev` host volumes must exist on the target node
- **Update Strategy**: Rolling update with `auto_revert = true`
- **Traefik Route**: `Host(todo-dev.10cg.pub) && PathPrefix(/api)`
- **Health Check**: HTTP GET `/health` every 30s, 3 failures before critical
- **Resources**: 300 MHz CPU, 256 MB memory (512 MB hard limit)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `docker login` fails | Verify Forgejo token has `package:write` scope |
| `nomad job run` connection refused | Ensure `NOMAD_ADDR` is set and reachable: `curl http://192.168.69.70:4646/v1/status/leader` |
| Allocation stays `pending` | Check volumes exist: `nomad volume status` or create them via `aether volume create` |
| Health check failing | Check logs: `nomad alloc logs <ID> backend` -- may need env vars (DB path, etc.) |
| Image pull fails | Verify registry auth in HCL matches valid credentials |
| `feature/auth` branch not found | Fetch all: `git fetch --all`, or create locally: `git checkout -b feature/auth` |
