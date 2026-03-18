# Eval Report: aether-dev / eval-2-temp-job-run-and-cleanup (with_skill)

**Date**: 2026-03-18
**Skill**: aether-dev
**Subcommands used**: `run` -> `logs` -> `clean`
**Nomad**: http://192.168.69.70:4646

---

## Task

Run a temporary batch job on the Aether cluster to execute `python migrate.py` using the `python:3.11` image with a `/data` volume mount, check logs to confirm migration status, then clean up the temporary job.

---

## Execution Summary

### Step 1: `run` -- Submit Temporary Batch Job

**Job Name**: `dev-temp-1773854776`
**Job Type**: `batch`
**Target Node Class**: `heavy_workload`
**Image**: `python:3.11`
**Command**: `python migrate.py`
**Working Directory**: `/data`

**Job Spec** (JSON via Nomad HTTP API):

```json
{
  "Job": {
    "ID": "dev-temp-1773854776",
    "Name": "dev-temp-1773854776",
    "Type": "batch",
    "Region": "global",
    "Datacenters": ["dc1"],
    "Constraints": [{ "LTarget": "${node.class}", "RTarget": "heavy_workload", "Operand": "=" }],
    "TaskGroups": [{
      "Name": "task",
      "Count": 1,
      "Tasks": [{
        "Name": "run",
        "Driver": "docker",
        "Config": {
          "image": "python:3.11",
          "command": "python",
          "args": ["migrate.py"],
          "work_dir": "/data",
          "volumes": ["/opt/aether-volumes/data:/data"]
        },
        "Resources": { "CPU": 500, "MemoryMB": 512 }
      }]
    }]
  }
}
```

**Submission Result**: Success (EvalID: `8c1be932`)

**Note**: Initial attempt used Nomad host volume (`source = "data"`), which failed due to `missing compatible host volumes` -- no heavy_workload node had a host volume named `data`. Corrected by switching to Docker bind mount (`/opt/aether-volumes/data:/data`).

---

### Step 2: `logs` -- Check Migration Logs

**Allocation**: `478ba3f3` on **heavy-3**

**Allocation Status**: `failed` (exit code 2, 3 restart attempts)

**stdout**: (empty)

**stderr**:
```
python: can't open file '/data/migrate.py': [Errno 2] No such file or directory
```

**Analysis**: The job was correctly scheduled, the `python:3.11` image was pulled successfully (~407 MiB), and the container started. The failure is expected -- there is no `migrate.py` script present in the `/data` volume on the target node. In a real migration scenario, the script would need to be placed in `/opt/aether-volumes/data/` on the heavy node before running the job, or baked into a custom Docker image.

**Migration Result**: FAILED -- `migrate.py` not found in the mounted volume.

---

### Step 3: `clean` -- Cleanup Temporary Jobs

**Jobs cleaned**:
- `dev-temp-1773854776` -- stopped and purged (EvalID: `a70ebf8d`)

**Verification**: 0 remaining `dev-temp-*` jobs in the cluster.

---

## Issues Encountered

| Issue | Root Cause | Resolution |
|-------|-----------|------------|
| First job stuck with no allocations | heavy_workload nodes lack a host volume named `data` | Purged first job; resubmitted using Docker bind mount instead of Nomad host volume |
| `nomad` CLI not available | CLI not installed on this machine | Used Nomad HTTP API (`curl`) for all operations |
| Job failed with exit code 2 | `migrate.py` does not exist in `/data` on heavy-3 | Expected in eval -- no real script was deployed |

## Skill Flow Adherence

| SKILL.md Subcommand | Executed | Notes |
|---------------------|----------|-------|
| `run` | Yes | Generated `dev-temp-*` batch job, submitted via API |
| `logs` | Yes | Retrieved stdout/stderr via `/v1/client/fs/logs/` |
| `clean` | Yes | Listed and purged all `dev-temp-*` jobs |

## Recommendations

For a real data migration job:

1. **Pre-deploy the script**: `scp migrate.py root@heavy-3:/opt/aether-volumes/data/`
2. **Or use a custom image**: Build an image with `migrate.py` baked in
3. **Set restart policy**: Add `restart { attempts = 0 }` for batch jobs that should not retry on failure
4. **Use an existing host volume**: Map to a volume that already exists (e.g., `kairos-data`, `todo-data`)
