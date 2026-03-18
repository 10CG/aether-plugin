# Volume Delete Safety Check Report

**Date**: 2026-03-18
**Target Node**: heavy-2 (192.168.69.81)
**Target Volume**: old-project data volume
**Nomad API**: http://192.168.69.70:4646

---

## 1. Volume Existence Check

### Nomad Registered Host Volumes on heavy-2

The following host volumes are registered in Nomad on heavy-2 (`a00dc85c-c595-723d-d4ca-38222c78b9f3`):

| Volume Name | Path |
|------------|------|
| kairos-data | /opt/aether-volumes/kairos/data |
| kairos-prod-data | /opt/aether-volumes/kairos-prod/data |
| nexus-db-dev | /opt/aether-volumes/nexus/db-dev |
| nexus-redis-dev | /opt/aether-volumes/nexus/redis-dev |
| todo-backups | /opt/aether-volumes/todo-web/backups |
| todo-backups-dev | /opt/aether-volumes/todo-web/backups-dev |
| todo-data | /opt/aether-volumes/todo-web/data |
| todo-data-dev | /opt/aether-volumes/todo-web/data-dev |
| todo-logs | /opt/aether-volumes/todo-web/logs |
| todo-logs-dev | /opt/aether-volumes/todo-web/logs-dev |

**Result**: No volume named "old-project" (or any variant like "old-project-data") is registered as a Nomad host volume on heavy-2.

### Filesystem Directories on heavy-2

All directories under `/opt/aether-volumes/` on heavy-2:

| Directory | Size | In Nomad? |
|-----------|------|-----------|
| data/ | 512 B (empty) | No |
| kairos/ | 2.3 MB | Yes |
| kairos-prod/ | 25 KB | Yes |
| myapp/ | 1.5 KB | No |
| nexus/ | 23 MB | Yes |
| runners/ | 6.5 GB | No |
| test-cli/ | 512 B | No |
| test-volume-cli/ | 1.5 KB | No |
| todo-web/ | 1.2 MB | Yes |

**Result**: No directory named "old-project" exists on the filesystem. There are several orphaned directories (`data/`, `myapp/`, `test-cli/`, `test-volume-cli/`) that are not registered in Nomad, but none are named "old-project".

---

## 2. Job Reference Check

### All Running Jobs in Cluster

| Job | Status | Uses Volumes |
|-----|--------|-------------|
| dev-db | running | None |
| kairos-dev | running | kairos-data |
| kairos-prod | running | kairos-prod-data |
| mailpit | running | None |
| nexus-api-dev | running | None |
| nexus-db-dev | running | nexus-db-dev |
| nexus-redis-dev | running | None |
| openstock-dev | running | None |
| psych-ai-supervision-dev | running | None |
| silknode-gateway | running | None |
| silknode-web | running | None |
| todo-web-backend-dev | running | todo-data-dev, todo-backups-dev |
| todo-web-backend-prod | running | todo-data, todo-backups |
| todo-web-frontend-dev | running | None |
| todo-web-frontend-prod | running | None |
| traefik | running | None |
| wecom-relay | running | None |

**Full-text search**: Searched all 17 job specifications for any reference to "old-project" or "old_project" -- no matches found.

**Stopped/dead jobs search**: Queried `GET /v1/jobs?prefix=old` -- returned empty results. No job with "old-project" prefix exists (active or dead).

---

## 3. Allocations on heavy-2

| Job | Status | Task Group |
|-----|--------|-----------|
| todo-web-backend-dev | running | backend |
| todo-web-backend-prod | running | backend |
| nexus-redis-dev | running | redis |
| kairos-dev | running | kairos |
| silknode-gateway | running | stack |
| nexus-db-dev | running | db |
| kairos-prod | running | kairos |
| todo-web-backend-dev | complete | backend |

No allocation references "old-project" in any form.

---

## 4. Conclusion

**old-project data volume does not exist on heavy-2.**

After thorough investigation:

1. **No Nomad host volume** named "old-project" (or any variant) is registered on heavy-2
2. **No filesystem directory** named "old-project" exists under `/opt/aether-volumes/` on heavy-2
3. **No Nomad job** (running, stopped, or dead) references "old-project"
4. **No allocation** on heavy-2 is associated with an "old-project" job

### Possible Explanations
- The volume may have already been cleaned up previously
- The volume may exist on a different node (checked all nodes -- no "old-project" volume found on any node)
- The project name may differ from "old-project" (e.g., one of the orphaned directories: `data/`, `myapp/`, `test-cli/`, `test-volume-cli/`)

### Recommended Action
**No deletion was performed.** Please clarify:
- The exact volume name or project name for "old-project"
- Or confirm if it refers to one of the orphaned (unregistered) directories found on heavy-2: `data/`, `myapp/`, `test-cli/`, `test-volume-cli/`

---

## 5. Safety Checks Performed

- [x] Queried Nomad API for all host volumes on heavy-2
- [x] Listed filesystem directories on heavy-2 via SSH
- [x] Checked all 17 running jobs for volume references
- [x] Searched for stopped/dead jobs with "old-project" prefix
- [x] Full-text searched all job specs for "old-project" / "old_project"
- [x] Listed all allocations on heavy-2
- [ ] Backup (not needed -- volume not found)
- [ ] Deletion (not performed -- volume not found)
