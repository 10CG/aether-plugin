# SSH Partial Failure Diagnostic Report

**Date**: 2026-03-18
**Reported Issue**: SSH connections to heavy-2 (192.168.69.81) and heavy-3 (192.168.69.82) failing; heavy-1 (192.168.69.80) works.

---

## Diagnostic Summary

**Result: No active SSH failure detected.** All three heavy nodes are currently reachable and accepting SSH connections successfully. The issue appears to have been transient or has already resolved itself.

---

## Detailed Test Results

### 1. SSH Connectivity Tests

| Node | IP | SSH (IP) | SSH (Hostname) | Result |
|------|-----|----------|----------------|--------|
| heavy-1 | 192.168.69.80 | OK | OK | PASS |
| heavy-2 | 192.168.69.81 | OK | OK | PASS |
| heavy-3 | 192.168.69.82 | OK | OK | PASS |

All three nodes accept SSH connections via both IP address and hostname. Authentication succeeds with ed25519 public key.

### 2. Network Connectivity

| Node | TCP Port 22 | DNS Resolution |
|------|-------------|----------------|
| heavy-1 (192.168.69.80) | OPEN | 192.168.69.80 (via /etc/hosts) |
| heavy-2 (192.168.69.81) | OPEN | 192.168.69.81 (via /etc/hosts) |
| heavy-3 (192.168.69.82) | OPEN | 192.168.69.82 (via /etc/hosts) |

Note: `ping` is unavailable in this environment (missing `cap_net_raw` capability), but TCP port 22 reachability was verified via `/dev/tcp`.

### 3. SSH Key Configuration

**Local SSH Key**:
- Key type: ED25519
- Key file: `~/.ssh/id_ed25519` (permissions: 600)
- Fingerprint: `SHA256:JibKXgzlKMxhh1NKIjv9H2TvwXhFMVjngcGrYoF9zsI`
- SSH directory permissions: 700
- Owner: dev:dev

**SSH Config** (`~/.ssh/config`):
```
Host heavy-* light-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
```

Configuration is correct. The `Host heavy-* light-*` wildcard matches all node hostnames. `StrictHostKeyChecking no` prevents host key verification failures.

**Public Key Authorization**:
- heavy-1: Public key found in `authorized_keys` (1 match)
- heavy-2: Public key found in `authorized_keys` (1 match)
- heavy-3: Public key found in `authorized_keys` (1 match)

**known_hosts**: Contains hashed entries for multiple nodes. No stale/conflicting entries detected.

### 4. Issue Found and Fixed: Missing Public Key File

The file `~/.ssh/id_ed25519.pub` was missing. While this does not prevent SSH authentication (the private key is sufficient for client-side auth), some tools and workflows may rely on the `.pub` file existing.

**Fix applied**: Regenerated `~/.ssh/id_ed25519.pub` from the private key using `ssh-keygen -y`.

### 5. SSH Service Status on Remote Nodes

| Node | Uptime | SSHD Status |
|------|--------|-------------|
| heavy-1 | 25 days, 20:20 | active |
| heavy-2 | 25 days, 19:52 | active |
| heavy-3 | 25 days, 19:48 | active |

All nodes have been running continuously for ~25 days. SSH daemon is active on all three.

### 6. Remote Auth Logs

Recent auth logs on heavy-2 and heavy-3 show **only successful authentications** from our IP (192.168.69.208). No failed authentication attempts, no connection refusals, no timeouts recorded in the last hour.

---

## Cluster Status

### Nomad Cluster

All 8 nodes are **ready** and **eligible**:

| Node | Class | Status | Drain |
|------|-------|--------|-------|
| heavy-1 | heavy_workload | ready | false |
| heavy-2 | heavy_workload | ready | false |
| heavy-3 | heavy_workload | ready | false |
| light-1 | light_exec | ready | false |
| light-2 | light_exec | ready | false |
| light-3 | light_exec | ready | false |
| light-4 | light_exec | ready | false |
| light-5 | light_exec | ready | false |

- Nomad version: 1.11.2
- Datacenter: dc1
- Nomad servers: 3 (infra-server-1/2/3 at 192.168.69.70-72)
- Leader: infra-server-2 (192.168.69.71)

### Consul Cluster

All 11 members are **alive**:

- 3 servers: infra-server-1/2/3 (192.168.69.70-72)
- 3 heavy clients: heavy-1/2/3 (192.168.69.80-82)
- 5 light clients: light-1 through light-5 (192.168.69.90-94)
- Consul version: 1.22.3

### Aether Configuration

Global config (`~/.aether/config.yaml`):
```yaml
cluster:
  consul_addr: http://192.168.69.70:8500
  nomad_addr: http://192.168.69.70:4646
  registry: forgejo.10cg.pub
  registry_url: forgejo.10cg.pub
```

Both the Nomad API (port 4646) and Consul API (port 8500) are reachable and responding correctly at the configured addresses. The Nomad address points to infra-server-1 which correctly forwards to the cluster leader.

---

## Actions Taken

1. **Regenerated `~/.ssh/id_ed25519.pub`** -- the public key file was missing. Restored it from the private key. This ensures tools that reference the `.pub` file will work correctly.

No other fixes were needed as all SSH connections, cluster services, and configuration are functioning correctly.

---

## Possible Causes of the Original Issue

Since the problem is not currently reproducible, the original SSH failure to heavy-2 and heavy-3 may have been caused by:

1. **Transient network issue** -- A brief network interruption or routing problem affecting the .81 and .82 addresses but not .80.
2. **SSH connection limits** -- If `MaxStartups` was reached on those nodes (e.g., from automated jobs or Forgejo runners), new connections would be refused temporarily.
3. **DNS/host resolution flap** -- Though currently resolved via `/etc/hosts`, a temporary resolution failure could have occurred.
4. **Firewall/iptables transient rule** -- A temporary firewall rule or rate-limiting could have blocked connections briefly.

---

## Recommendations

1. If the issue recurs, check `journalctl -u sshd --since "10 minutes ago"` on the affected nodes immediately.
2. Consider adding SSH connection monitoring/alerting to detect future intermittent failures.
3. The `StrictHostKeyChecking no` in SSH config is convenient but reduces security; consider using `accept-new` instead if host key changes are not expected.
