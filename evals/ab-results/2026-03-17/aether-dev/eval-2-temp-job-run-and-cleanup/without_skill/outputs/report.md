# Temporary Data Migration Batch Job - Execution Report

**Date**: 2026-03-18 17:31 UTC
**Nomad Address**: http://192.168.69.70:4646
**Job ID**: `data-migration-temp`
**Job Type**: batch

---

## 1. Cluster Connectivity

Verified Nomad cluster connectivity. Cluster has 3 servers and 8 client nodes:

| Node | IP | Status |
|------|----|--------|
| heavy-1 | 192.168.69.80 | ready |
| heavy-2 | 192.168.69.81 | ready |
| heavy-3 | 192.168.69.82 | ready |
| light-1 | 192.168.69.90 | ready |
| light-2 | 192.168.69.91 | ready |
| light-3 | 192.168.69.92 | ready |
| light-4 | 192.168.69.93 | ready |
| light-5 | 192.168.69.94 | ready |

## 2. Job Specification

- **Image**: `python:3.11`
- **Type**: `batch` (run once)
- **Volume**: `/data` bind-mounted from host
- **Command**: `/bin/bash -c` executing migration script
- **Resources**: 500 MHz CPU, 512 MB RAM
- **Restart Policy**: 0 attempts (fail immediately)
- **Node Constraint**: `heavy-1` (where `/data` volume was created)

## 3. First Attempt - Failed

**Allocation**: `45145931-09e2-1478-d8ef-70af0f50d279`
**Node**: heavy-1
**Status**: FAILED

**Failure Reason**: The `/data` directory did not exist on the host node.
```
Driver Failure: failed to create container: Error response from daemon:
invalid mount config for type "bind": bind source path does not exist: /data
```

**Resolution**: Created `/data` directory on heavy-1 via SSH (`ssh root@192.168.69.80 "mkdir -p /data"`), purged the failed job, and resubmitted with a hostname constraint to ensure placement on heavy-1.

## 4. Second Attempt - Success

**Allocation**: `62979921-8d46-c24d-b597-913fc35acf23`
**Node**: heavy-1 (`d7209a52`)
**Status**: complete
**Exit Code**: 0
**Started**: 2026-03-18T17:31:20.958Z
**Finished**: 2026-03-18T17:31:21.214Z
**Duration**: ~256ms

### Stdout Logs

```
=== Data Migration Job Started ===
Timestamp: 2026-03-18 17:31:20 UTC
Hostname: 0994396136a7
Python version: Python 3.11.15

Checking /data mount...
total 8
drwxr-xr-x 2 root root 4096 Mar 18 17:31 .
drwxr-xr-x 1 root root 4096 Mar 18 17:31 ..
---
INFO: /data/migrate.py not found in mounted volume.
The /data volume is mounted and accessible.
Contents of /data:
total 8
drwxr-xr-x 2 root root 4096 Mar 18 17:31 .
drwxr-xr-x 1 root root 4096 Mar 18 17:31 ..
---
To run a real migration, place migrate.py in /data on the host node.

=== Data Migration Job Completed ===
```

### Stderr Logs

(empty - no errors)

### Task Events

| Event | Description |
|-------|-------------|
| Received | Task received by client |
| Task Setup | Building Task Directory |
| Started | Task started by client |
| Terminated | Exit Code: 0 |

## 5. Migration Result

The batch job executed successfully. The `/data` volume was mounted and accessible inside the container. However, **`migrate.py` was not found** in the `/data` directory. This is expected since the directory was freshly created and no migration script was placed there.

**To run an actual migration**: Place the `migrate.py` script in `/data` on heavy-1 (`192.168.69.80`) before submitting the job.

## 6. Cleanup

All temporary resources have been cleaned up:

| Resource | Action | Status |
|----------|--------|--------|
| Nomad job `data-migration-temp` | Purged (`DELETE /v1/job/...?purge=true`) | Confirmed removed |
| `/data` directory on heavy-1 | Removed via SSH (`rmdir /data`) | Confirmed removed |
| Local job spec `/tmp/data-migration-job.json` | Deleted | Removed |

Verification: `GET /v1/job/data-migration-temp` returns `job not found`.

## 7. Notes

- The `python:3.11` Docker image (~407 MB) was pulled during the first attempt and cached on heavy-1 for subsequent runs.
- The first attempt took ~150 seconds to pull the image before failing due to the missing `/data` directory.
- The second attempt completed almost instantly (~256ms) thanks to the cached image.
- For production use, consider using Nomad host volumes (configured in client config) instead of raw bind mounts for better lifecycle management.
