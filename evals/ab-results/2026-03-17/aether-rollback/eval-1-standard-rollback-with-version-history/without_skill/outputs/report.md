# Rollback Report: web-frontend

**Date**: 2026-03-18
**Nomad Cluster**: http://192.168.69.70:4646
**Nomad Version**: 1.11.2
**Job Name**: web-frontend
**Requested Action**: Rollback from v3.2.0 to previous stable version

---

## Cluster Connectivity

Nomad API is reachable at `http://192.168.69.70:4646` (Nomad v1.11.2, datacenter `dc1`).

## Job Status

**Result: Job `web-frontend` was not found on the cluster.**

The Nomad API returned `job not found` for all queries against `web-frontend`:
- `GET /v1/job/web-frontend` -> "job not found"
- `GET /v1/job/web-frontend/versions` -> "job versions not found"
- `GET /v1/job/web-frontend/allocations` -> `[]`

### Jobs Currently Running on Cluster

The following 17 jobs are registered on the cluster:

| Job Name | Status | Type |
|----------|--------|------|
| dev-db | running | service |
| kairos-dev | running | service |
| kairos-prod | running | service |
| mailpit | running | service |
| nexus-api-dev | running | service |
| nexus-db-dev | running | service |
| nexus-redis-dev | running | service |
| openstock-dev | running | service |
| psych-ai-supervision-dev | running | service |
| silknode-gateway | running | service |
| silknode-web | running | service |
| todo-web-backend-dev | running | service |
| todo-web-backend-prod | running | service |
| todo-web-frontend-dev | running | service |
| todo-web-frontend-prod | running | service |
| traefik | running | service |
| wecom-relay | running | service |

**Note**: There are similar jobs (`todo-web-frontend-dev`, `todo-web-frontend-prod`) but no exact match for `web-frontend`.

---

## Rollback Procedure (Reference)

If the job `web-frontend` had existed, the following steps would have been executed:

### Step 1: Query Version History

```bash
# Via Nomad API
curl -s http://192.168.69.70:4646/v1/job/web-frontend/versions | jq .

# Via Nomad CLI (if available)
nomad job history web-frontend
```

This would return all job versions with their submission timestamps, allowing identification of the last stable version before the v3.2.0 upgrade.

### Step 2: Identify Target Rollback Version

From the version history, identify the version number (e.g., version 2) that corresponds to the last known stable deployment (pre-v3.2.0). Key indicators:
- Check the `Meta` or task group `config.image` field for the container image tag
- Look at `SubmitTime` to correlate with deployment timeline
- Confirm the version was in a stable `running` state

### Step 3: Execute Rollback

```bash
# Via Nomad API - revert to a specific version
curl -s -X POST http://192.168.69.70:4646/v1/job/web-frontend/revert \
  -d '{
    "JobID": "web-frontend",
    "JobVersion": <TARGET_VERSION_NUMBER>,
    "EnforcePriorVersion": <CURRENT_VERSION_NUMBER>
  }'

# Via Nomad CLI (if available)
nomad job revert web-frontend <TARGET_VERSION_NUMBER>
```

### Step 4: Verify Rollback

```bash
# Check job status
curl -s http://192.168.69.70:4646/v1/job/web-frontend | jq '{Status, Version}'

# Check allocations are healthy
curl -s http://192.168.69.70:4646/v1/job/web-frontend/allocations | \
  jq '.[] | {ID: .ID[:8], TaskState: .TaskStates, ClientStatus, DesiredStatus}'

# Check deployment status
curl -s http://192.168.69.70:4646/v1/job/web-frontend/deployment | \
  jq '{Status, StatusDescription}'

# Verify the running image tag matches the expected pre-v3.2.0 version
curl -s http://192.168.69.70:4646/v1/job/web-frontend | \
  jq '.TaskGroups[].Tasks[].Config.image'
```

### Step 5: Health Check

```bash
# HTTP health check on the service endpoint (if known)
curl -s -o /dev/null -w "%{http_code}" http://<service-url>/

# Check allocation logs for errors
curl -s http://192.168.69.70:4646/v1/client/fs/logs/<alloc-id>?task=web-frontend&type=stderr
```

---

## Action Required

The job `web-frontend` does not exist on the Nomad cluster at `http://192.168.69.70:4646`. Possible explanations:

1. **Wrong job name**: The actual job may be named differently (e.g., `todo-web-frontend-dev` or `todo-web-frontend-prod`).
2. **Wrong namespace**: The job may exist in a non-default namespace. Check with:
   ```bash
   curl -s http://192.168.69.70:4646/v1/jobs?namespace=* | jq '.[].Name'
   ```
3. **Wrong cluster**: The job may be on a different Nomad cluster.
4. **Job was purged**: The job may have been stopped and garbage-collected.

**Recommendation**: Please confirm the exact job name or check if the intended target is one of `todo-web-frontend-dev` or `todo-web-frontend-prod`. Once confirmed, the rollback procedure above can be executed immediately.
