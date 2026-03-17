# Production Deployment Report: my-api v1.2.3

**Date**: 2026-03-17
**Job**: my-api-prod
**Image**: forgejo.10cg.pub/10cg/my-api:v1.2.3
**Nomad Address**: http://192.168.69.80:4646
**HCL File**: deploy/nomad-prod.hcl

---

## Pre-Deployment Checks

### 1. Cluster Status

| Check | Result | Details |
|-------|--------|---------|
| Nomad Connectivity | PASS | Nomad v1.11.2 at http://192.168.69.80:4646 |
| Node Health | PASS | 8/8 nodes ready (3 heavy, 5 light) |
| Existing Job | N/A | my-api-prod does not exist yet (first deployment) |

**Cluster Nodes**:

| Node | Class | Address | Status |
|------|-------|---------|--------|
| heavy-1 | heavy_workload | 192.168.69.80 | ready |
| heavy-2 | heavy_workload | 192.168.69.81 | ready |
| heavy-3 | heavy_workload | 192.168.69.82 | ready |
| light-1 | light_exec | 192.168.69.90 | ready |
| light-2 | light_exec | 192.168.69.91 | ready |
| light-3 | light_exec | 192.168.69.92 | ready |
| light-4 | light_exec | 192.168.69.93 | ready |
| light-5 | light_exec | 192.168.69.94 | ready |

### 2. Image Verification

| Check | Result | Details |
|-------|--------|---------|
| Registry API (HEAD) | FAIL (401) | Registry requires authentication for manifest check |
| Docker Manifest Inspect | FAIL | Image not found (manifest unknown) |
| Docker Pull | FAIL | Image not found in registry |

> **BLOCKER**: The image `forgejo.10cg.pub/10cg/my-api:v1.2.3` could not be verified in the registry. The `docker manifest inspect` and `docker pull` commands both failed with "manifest unknown". Deployment cannot proceed until the image is confirmed to be available.

**Note on image reference**: Docker requires lowercase repository names. The user-provided `forgejo.10cg.pub/10CG/my-api:v1.2.3` was normalized to `forgejo.10cg.pub/10cg/my-api:v1.2.3`. Verify that the CI pipeline pushed the image with the correct case.

### 3. HCL File Check

| Check | Result | Details |
|-------|--------|---------|
| deploy/nomad-prod.hcl | NOT FOUND | File does not exist at the specified path |

> **BLOCKER**: The file `deploy/nomad-prod.hcl` does not exist. This must be created before deployment. A reference HCL is provided below based on existing production jobs in the cluster.

---

## Deployment Plan

### Step 1: Resolve Image Availability (BLOCKER)

Verify the image was properly built and pushed:

```bash
# Check CI pipeline logs for the my-api build
# Verify the image tag matches exactly
ssh root@192.168.69.80 "docker pull forgejo.10cg.pub/10cg/my-api:v1.2.3"
```

If the image was pushed under a different path or tag, correct the reference.

### Step 2: Create Production HCL File

The file `deploy/nomad-prod.hcl` must be created. Based on the cluster's existing production patterns (e.g., `todo-web-backend-prod`), here is the recommended job spec:

```hcl
# deploy/nomad-prod.hcl
# Production deployment for my-api
# Image: forgejo.10cg.pub/10cg/my-api:v1.2.3

job "my-api-prod" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel      = 1
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "15m"
    auto_revert       = true
    auto_promote      = true
  }

  group "my-api" {
    count = 1

    constraint {
      attribute = "${node.class}"
      operator  = "="
      value     = "heavy_workload"
    }

    network {
      port "http" {
        to = 8080  # Adjust to actual application port
      }
    }

    service {
      name     = "my-api-prod"
      port     = "http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.my-api-prod.rule=Host(`my-api.10cg.pub`)",
        "traefik.http.routers.my-api-prod.entrypoints=web",
      ]

      check {
        type     = "http"
        path     = "/health"
        interval = "15s"
        timeout  = "5s"

        check_restart {
          limit = 3
          grace = "90s"
        }
      }
    }

    restart {
      attempts = 3
      interval = "10m"
      delay    = "30s"
      mode     = "fail"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "1h"
      unlimited      = true
    }

    task "my-api" {
      driver = "docker"

      config {
        image      = "forgejo.10cg.pub/10cg/my-api:v1.2.3"
        ports      = ["http"]
        force_pull = true

        auth {
          # Registry credentials - update with actual values
          username = "YOUR_REGISTRY_USERNAME"
          password = "YOUR_REGISTRY_TOKEN"
        }

        logging {
          type = "json-file"
          config {
            max-size = "100m"
            max-file = "5"
          }
        }

        volumes = [
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env {
        # Application environment variables
        # PORT        = "8080"
        # NODE_ENV    = "production"
        # DATABASE_URL = "..."  # Use Vault or Nomad variables for secrets
      }

      resources {
        cpu    = 500   # MHz
        memory = 512   # MB
      }
    }
  }
}
```

**Key configuration notes**:
- `auto_revert = true`: Automatically reverts to the previous version if the new deployment fails health checks.
- `auto_promote = true`: Automatically promotes canary deployments (if canary count > 0).
- `force_pull = true`: Forces Docker to pull the image even if it exists locally, ensuring the latest digest for the tag is used.
- `constraint` targets `heavy_workload` nodes (heavy-1/2/3), matching the existing prod pattern.
- `auth` block is needed because the Forgejo registry requires authentication. The existing `todo-web-backend-prod` uses embedded credentials.
- Adjust `port`, `env`, `resources`, and Traefik routing rules to match the actual application requirements.

### Step 3: Validate the HCL (Dry Run)

```bash
# Validate syntax
ssh root@192.168.69.80 "NOMAD_ADDR=http://192.168.69.80:4646 nomad job validate /path/to/deploy/nomad-prod.hcl"

# Plan the deployment (dry run - shows what will change)
ssh root@192.168.69.80 "NOMAD_ADDR=http://192.168.69.80:4646 nomad job plan /path/to/deploy/nomad-prod.hcl"
```

### Step 4: Deploy

```bash
# Submit the job
ssh root@192.168.69.80 "NOMAD_ADDR=http://192.168.69.80:4646 nomad job run /path/to/deploy/nomad-prod.hcl"
```

### Step 5: Monitor Deployment

```bash
# Watch deployment status
ssh root@192.168.69.80 "NOMAD_ADDR=http://192.168.69.80:4646 nomad job status my-api-prod"

# Watch allocation status
ssh root@192.168.69.80 "NOMAD_ADDR=http://192.168.69.80:4646 nomad alloc status -short \$(NOMAD_ADDR=http://192.168.69.80:4646 nomad job status my-api-prod | grep -A5 'Allocations' | tail -1 | awk '{print \$1}')"

# Check logs if needed
ssh root@192.168.69.80 "NOMAD_ADDR=http://192.168.69.80:4646 nomad alloc logs <ALLOC_ID>"
```

### Step 6: Verify Health

```bash
# Check Consul service registration
ssh root@192.168.69.80 "curl -s http://localhost:8500/v1/health/service/my-api-prod | python3 -m json.tool"

# Test the endpoint (adjust URL based on Traefik routing)
curl -s http://my-api.10cg.pub/health
```

---

## Rollback Plan

If the deployment fails or the application is unhealthy after deployment:

```bash
# Option 1: Nomad auto-revert (automatic if auto_revert = true)
# The update stanza has auto_revert = true, so Nomad will automatically
# roll back if health checks fail within the healthy_deadline window.

# Option 2: Manual rollback to previous version
ssh root@192.168.69.80 "NOMAD_ADDR=http://192.168.69.80:4646 nomad job revert my-api-prod <PREVIOUS_JOB_VERSION>"

# Option 3: Stop the job entirely (emergency)
ssh root@192.168.69.80 "NOMAD_ADDR=http://192.168.69.80:4646 nomad job stop my-api-prod"
```

---

## Deployment Status

| Step | Status | Notes |
|------|--------|-------|
| Cluster connectivity | PASS | Nomad reachable, all nodes healthy |
| Image verification | **BLOCKED** | Image not found in registry |
| HCL file exists | **BLOCKED** | deploy/nomad-prod.hcl must be created |
| Validate HCL | PENDING | Waiting on blockers |
| Deploy (nomad job run) | PENDING | Waiting on blockers |
| Health check | PENDING | Waiting on deployment |
| Consul registration | PENDING | Waiting on deployment |

**Overall Status**: **BLOCKED** - Cannot proceed with deployment.

---

## Required Actions

1. **Confirm image availability**: Verify that `forgejo.10cg.pub/10cg/my-api:v1.2.3` exists in the registry. If the dev environment used a different image path, provide the correct one.
2. **Create `deploy/nomad-prod.hcl`**: Use the template above as a starting point, filling in:
   - The correct application port (replace `8080`)
   - Environment variables needed by the application
   - Registry credentials (username/password or use Nomad Vault integration)
   - Traefik routing rules (hostname, path prefix)
   - Resource limits appropriate for the application
3. **Re-run deployment** once both blockers are resolved.
