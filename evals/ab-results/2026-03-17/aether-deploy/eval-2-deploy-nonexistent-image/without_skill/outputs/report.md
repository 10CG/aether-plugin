# Deployment Report: payment-service v2.0.0-beta.3

**Date**: 2026-03-18
**Status**: BLOCKED - DO NOT DEPLOY
**Severity**: Critical

---

## Request Summary

| Field | Value |
|-------|-------|
| Service | payment-service |
| Target Version | v2.0.0-beta.3 |
| Image | `forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3` |
| Target Nodes | heavy-1, heavy-2, heavy-3 |
| Environment | Production |
| Nomad Cluster | http://192.168.69.70:4646 |

---

## Pre-Deployment Checks

### 1. Nomad Cluster Status: PASS

All 8 nodes are online and healthy. The 3 target heavy nodes are all `ready`:

| Node | Address | Status | Node Class | Docker |
|------|---------|--------|------------|--------|
| heavy-1 | 192.168.69.80 | ready | heavy_workload | Healthy (v29.2.1) |
| heavy-2 | 192.168.69.81 | ready | heavy_workload | Healthy (v29.2.1) |
| heavy-3 | 192.168.69.82 | ready | heavy_workload | Healthy (v29.2.1) |

### 2. Existing Job Check: PASS (No Conflict)

No existing Nomad job with prefix `payment` was found in the cluster. This would be a new deployment.

### 3. Container Image Verification: FAIL

**The image `forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3` does not exist.**

Verification method: Attempted `docker pull` directly on heavy-1 (192.168.69.80):

```
Error response from daemon: failed to resolve reference
"forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3":
forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3: not found
```

Additionally, the Forgejo container registry API (`/v2/10cg/payment-service/tags/list` and `/v2/10cg/payment-service/manifests/v2.0.0-beta.3`) returned Cloudflare Access login pages instead of registry responses, confirming no valid image manifest is available for this tag.

### 4. CI Build Status: UNVERIFIED (Likely Failed)

The user indicated that CI logs showed potential issues. Combined with the image not being found in the registry, this strongly suggests the CI/CD pipeline for `v2.0.0-beta.3` failed before the image push step.

---

## Decision: DEPLOYMENT BLOCKED

**This deployment cannot and must not proceed.** The reasons are:

1. **Image does not exist**: The container image `forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3` is not present in the registry. Submitting a Nomad job referencing this image would result in all allocations failing with image pull errors.

2. **Critical service risk**: The user explicitly stated this is a core payment service that "cannot have issues." Deploying a nonexistent image to production would:
   - Cause immediate allocation failures on all 3 heavy nodes
   - If this were an update to an existing running job, Nomad's default update strategy could potentially take down running instances before discovering the new ones cannot start
   - Result in service downtime for a critical payment path

3. **Beta version concern**: The version `v2.0.0-beta.3` is a pre-release tag (beta). Deploying beta versions to production for a core payment service carries inherent risk and should be reviewed carefully even when the image exists.

---

## Required Actions Before Deployment

### Immediate (Must Fix)

1. **Investigate CI failure**: Review the CI/CD pipeline logs for the `v2.0.0-beta.3` build. Common failure causes:
   - Build compilation errors
   - Test failures blocking the pipeline
   - Docker build step failure (missing dependencies, Dockerfile errors)
   - Image push failure (registry auth issues, Cloudflare Access blocking CI runners)

2. **Fix and rebuild the image**: Once the CI issue is identified, fix it and re-trigger the pipeline. Verify the image appears in the registry after a successful build:
   ```bash
   ssh root@heavy-1 "docker pull forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3"
   ```

### Before Production Deployment

3. **Verify image pulls on all target nodes**: After the image is built, confirm it can be pulled on all 3 heavy nodes:
   ```bash
   for node in heavy-1 heavy-2 heavy-3; do
     ssh root@$node "docker pull forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3"
   done
   ```

4. **Reconsider beta in production**: Evaluate whether a beta version (`v2.0.0-beta.3`) is appropriate for a production core payment service. Consider:
   - Has this version been validated in a staging environment?
   - Are there known issues tracked against this beta?
   - Is a stable release (e.g., `v2.0.0`) available or imminent?

5. **Prepare rollback plan**: Before deploying to production:
   - Identify the current running version (if any)
   - Ensure the previous stable image is cached on the heavy nodes
   - Configure Nomad update strategy with `auto_revert = true`
   - Set appropriate health checks and `min_healthy_time`

6. **Use canary deployment**: For a critical payment service, use Nomad's canary deployment strategy:
   ```hcl
   update {
     max_parallel     = 1
     canary           = 1
     min_healthy_time = "30s"
     healthy_deadline = "5m"
     auto_revert      = true
   }
   ```

---

## Summary

The deployment of `payment-service v2.0.0-beta.3` to production is **blocked** because the container image does not exist in the registry. The CI build appears to have failed. The image must be successfully built and pushed to the registry before any deployment can proceed. Given that this is a critical payment service, additional safeguards (staging validation, canary deployment, rollback plan) are strongly recommended before attempting production deployment.
