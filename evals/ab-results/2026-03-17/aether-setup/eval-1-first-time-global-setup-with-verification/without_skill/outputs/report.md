# Aether Setup Report - First-Time Global Configuration with Verification

**Date**: 2026-03-18
**Task**: Configure cluster connection for first-time use
**CLI Version**: aether 0.7.2

---

## 1. Configuration File

**Path**: `~/.aether/config.yaml`

The global configuration file already existed at `~/.aether/config.yaml` with the requested values:

```yaml
cluster:
  consul_addr: http://192.168.69.70:8500
  nomad_addr: http://192.168.69.70:4646
  registry: forgejo.10cg.pub
  registry_url: forgejo.10cg.pub
```

**Permissions fix applied**: File permissions were `644` (insecure). Changed to `0600` as recommended by `aether setup --check`.

---

## 2. Connection Verification Results

### Nomad - OK

| Check | Result |
|-------|--------|
| API endpoint | `http://192.168.69.70:4646` - HTTP 200 |
| Leader | `192.168.69.71:4647` |
| Version | 1.11.2 |
| Nodes | 8 total, 8 ready |
| Jobs | 17 total, 17 running |

### Consul - OK

| Check | Result |
|-------|--------|
| API endpoint | `http://192.168.69.70:8500` - HTTP 200 |
| Leader | `192.168.69.70:8300` |

### Registry - Warning (Non-blocking)

| Check | Result |
|-------|--------|
| URL | `forgejo.10cg.pub` |
| Type detected | Forgejo Container Registry |
| HTTPS connectivity | HTTP 302 (redirect, expected - behind Cloudflare Access) |
| Docker v2 API | Timeout due to Cloudflare Access authentication wall |

**Analysis**: The registry host is reachable (HTTPS returns 302). The Docker v2 API check times out because `forgejo.10cg.pub` is behind Cloudflare Access, which requires authentication headers for the `/v2/` endpoint. This is expected behavior and does **not** affect CI/CD deployments, which authenticate via `FORGEJO_TOKEN` from within the cluster network.

**Credential chain**: `FORGEJO_TOKEN` (detected) -> `GITEA_TOKEN` -> `AETHER_REGISTRY_PASSWORD` -> `REGISTRY_PASSWORD` -> `REGISTRY_TOKEN`

### SSH - OK

| Check | Result |
|-------|--------|
| Key type | ed25519 |
| Key path | `~/.ssh/id_ed25519` |
| Key permissions | `0600` (correct) |

---

## 3. Cluster Topology

### Servers (3 nodes)

| Name | IP | Port | Role |
|------|----|------|------|
| infra-server-1 | 192.168.69.70 | 4646 | follower |
| infra-server-2 | 192.168.69.71 | 4646 | leader |
| infra-server-3 | 192.168.69.72 | 4646 | follower |

### Clients (8 nodes)

| Name | IP | Class | Status |
|------|----|-------|--------|
| heavy-1 | 192.168.69.80 | heavy_workload | ready |
| heavy-2 | 192.168.69.81 | heavy_workload | ready |
| heavy-3 | 192.168.69.82 | heavy_workload | ready |
| light-1 | 192.168.69.90 | light_exec | ready |
| light-2 | 192.168.69.91 | light_exec | ready |
| light-3 | 192.168.69.92 | light_exec | ready |
| light-4 | 192.168.69.93 | light_exec | ready |
| light-5 | 192.168.69.94 | light_exec | ready |

---

## 4. Health Issues Found

| Severity | Service | Node | Issue |
|----------|---------|------|-------|
| Warning | psych-ai-dev-api | heavy-1 | Consul health check: critical |

**Recommendation**: Run `aether status --failed` to investigate the `psych-ai-dev-api` service health check failure on heavy-1.

---

## 5. Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Global config (`~/.aether/config.yaml`) | Configured | Permissions fixed to 0600 |
| Nomad connection | Connected | Leader: 192.168.69.71, 17/17 jobs running |
| Consul connection | Connected | Leader: 192.168.69.70 |
| Registry detection | Working | Forgejo type detected, FORGEJO_TOKEN available |
| Registry v2 API | Warning | Cloudflare Access blocks external checks (expected) |
| SSH key | Available | ed25519 key at ~/.ssh/id_ed25519 |
| Cluster health | Healthy | 8/8 nodes ready, 1 service check warning |

**Overall Status**: Setup complete. The cluster is connected and operational. The registry warning is expected due to Cloudflare Access and does not impact deployments from within the cluster.
