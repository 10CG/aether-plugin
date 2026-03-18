# Volume Creation Report - myapp on heavy-1

**Date**: 2026-03-18
**Node**: heavy-1 (192.168.69.80)
**Project**: myapp
**Volumes**: data, logs
**Nomad Cluster**: http://192.168.69.70:4646

---

## Step 1: Dry-Run Preview

**Command**: `aether volume create --node heavy-1 --project myapp --volumes data,logs --dry-run`

### Preview Results

The dry-run showed the following planned operations:

1. **Directory creation**:
   - `/opt/aether-volumes/myapp/data` (permissions: 777)
   - `/opt/aether-volumes/myapp/logs` (permissions: 777)

2. **Nomad configuration update**:
   - Backup `client.hcl` to `client.hcl.bak`
   - Add two `host_volume` stanzas to the `client {}` block:
     - `myapp-data` -> `/opt/aether-volumes/myapp/data` (read_only = false)
     - `myapp-logs` -> `/opt/aether-volumes/myapp/logs` (read_only = false)

3. **Service restart**:
   - Restart Nomad service via `systemctl restart nomad`
   - Verify Nomad is running; auto-rollback from backup if it fails

---

## Step 2: Actual Creation

**Command**: `aether volume create --node heavy-1 --project myapp --volumes data,logs --yes`

### Execution Results

All steps completed successfully:

- Created directory: `/opt/aether-volumes/myapp/data`
- Created directory: `/opt/aether-volumes/myapp/logs`
- Backed up `client.hcl`
- Updated `client.hcl` with host_volume configuration
- Nomad restarted successfully

---

## Step 3: Verification

**Command**: `aether volume list --node heavy-1`

### Verified Volumes

| Volume Name | Path | Read-Only | Exists |
|------------|------|-----------|--------|
| myapp-data | /opt/aether-volumes/myapp/data | false | true |
| myapp-logs | /opt/aether-volumes/myapp/logs | false | true |

Both volumes are confirmed present and accessible on heavy-1.

---

## Nomad Job Usage

To use these volumes in a Nomad job spec:

```hcl
job "myapp" {
  group "app" {
    volume "data" {
      type   = "host"
      source = "myapp-data"
    }

    volume "logs" {
      type   = "host"
      source = "myapp-logs"
    }

    task "server" {
      volume_mount {
        volume      = "data"
        destination = "/data"
      }

      volume_mount {
        volume      = "logs"
        destination = "/logs"
      }
    }
  }
}
```

---

## Summary

| Item | Status |
|------|--------|
| Dry-run preview | Completed |
| Directory creation | Success |
| Nomad config update | Success |
| Nomad restart | Success |
| Verification | Confirmed |
