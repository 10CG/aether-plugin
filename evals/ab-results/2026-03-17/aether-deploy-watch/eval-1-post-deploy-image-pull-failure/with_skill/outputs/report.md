# Aether Deploy Watch - Diagnostic Report

> **Job**: nexus-api-dev
> **Time**: 2026-03-18 12:43 UTC
> **Nomad**: http://192.168.69.70:4646
> **Consul**: http://192.168.69.70:8500

---

## Phase 1: Status Check

### Nomad Job Status

```
Job: nexus-api-dev (service, running, v26)
Deployment: 55d84d60 - successful
```

### Allocation Status

```
Allocation: bcd4b635-15f3-6cfb-722c-d04c1869d2ba
Node:       heavy-1 (192.168.69.80)
Status:     running
Deploy:     healthy

Task States:
  migrate  - dead    (exit 0) - prestart hook completed successfully
  api      - running (started 2026-03-17T23:10:29Z, 0 restarts)
  worker   - running (started 2026-03-17T23:10:29Z, 0 restarts)
```

Status: All 3 tasks are healthy. Migration (prestart) completed with exit code 0, api and worker tasks are running with no restarts.

### Consul Health Check

```
Service:  nexus-api-dev
Check:    service: "nexus-api-dev" check (HTTP)
Status:   passing
Output:   HTTP GET http://192.168.69.80:28803/health: 200 OK
          {"status":"healthy","version":"0.1.0"}
```

### Direct Service Verification

```
$ curl http://192.168.69.80:28803/health
HTTP 200
{"status":"healthy","version":"0.1.0"}
```

Status: Service is running and healthy on the Nomad node.

---

## Phase 2: Routing Chain Analysis

### Traefik Router

```
Router:      nexus-api-dev@consulcatalog
Rule:        Host(`nexus-dev.10cg.pub`)
EntryPoints: [web] (port 80 only)
Status:      enabled
Priority:    100
```

### Traefik Service Backend

```
Service:      nexus-api-dev@consulcatalog
Backend:      http://192.168.69.80:28803
Server Status: UP
```

### Internal Access (via Traefik, bypassing Cloudflare)

```
$ curl -H "Host: nexus-dev.10cg.pub" http://192.168.69.80/health
HTTP 200
{"status":"healthy","version":"0.1.0"}
```

Status: Traefik routing is working correctly. Service is accessible internally.

---

## Phase 3: External Access Analysis (Root Cause Found)

### DNS Resolution

```
nexus-dev.10cg.pub -> 104.21.58.104, 172.67.159.3 (Cloudflare Proxy IPs)
```

### External HTTP Access

```
$ curl http://nexus-dev.10cg.pub/health
HTTP 301 -> https://nexus-dev.10cg.pub/health (Cloudflare forces HTTPS)
```

### External HTTPS Access

```
$ curl https://nexus-dev.10cg.pub/health
HTTP 302 -> https://10cg.cloudflareaccess.com/cdn-cgi/access/login/nexus-dev.10cg.pub
```

**Cloudflare Access is blocking all external requests**, redirecting to the Cloudflare Access login page.

---

## Phase 4: Diagnosis

### Error Pattern Match: Cloudflare Access Blocking

**Problem**: The service is inaccessible externally NOT because of a deployment failure, but because **Cloudflare Access** is protecting `nexus-dev.10cg.pub` and requiring authentication.

**Traffic Flow**:
```
User Request
  -> nexus-dev.10cg.pub (DNS: Cloudflare Proxy)
  -> Cloudflare Edge (104.21.58.104)
  -> Cloudflare Access Policy (BLOCKS HERE - 302 redirect to login)
  -> (never reaches) Origin Server (192.168.69.80:80)
  -> (never reaches) Traefik -> Service
```

**Evidence**:
1. Nomad deployment: successful (v26, all allocations healthy)
2. Consul health check: passing (HTTP 200 on /health)
3. Direct access: working (http://192.168.69.80:28803/health returns 200)
4. Traefik routing: working (Host header routing returns 200)
5. External access: blocked by Cloudflare Access (302 to login)

### Summary

| Layer | Status | Details |
|-------|--------|---------|
| Nomad Job | OK | running, v26, deployment successful |
| Allocation | OK | bcd4b635 on heavy-1, running, 0 restarts |
| Health Check | OK | Consul check passing, HTTP 200 |
| Traefik Router | OK | nexus-api-dev@consulcatalog, enabled |
| Traefik Backend | OK | http://192.168.69.80:28803, UP |
| Cloudflare Access | BLOCKED | 302 redirect to login page |

---

## Fix Recommendations

### Option 1: Configure Cloudflare Access Application (Recommended)

Add a Cloudflare Access policy that allows the intended users/groups to access `nexus-dev.10cg.pub`:

1. Go to Cloudflare Zero Trust Dashboard -> Access -> Applications
2. Find the application covering `nexus-dev.10cg.pub` (or `*.10cg.pub`)
3. Either:
   - **Add allowed users/groups** to the Access policy
   - **Create a bypass rule** for specific paths (e.g., `/health`, `/v1/`)
   - **Remove** `nexus-dev.10cg.pub` from Access protection if it should be public

### Option 2: Create a Cloudflare Access Service Token

If the service needs to be accessed programmatically (e.g., by another service or CI):

```bash
# Create a Service Token in Cloudflare Zero Trust Dashboard
# Then include the token in requests:
curl -H "CF-Access-Client-Id: <CLIENT_ID>" \
     -H "CF-Access-Client-Secret: <CLIENT_SECRET>" \
     https://nexus-dev.10cg.pub/health
```

### Option 3: Bypass for Health Check Path

In Cloudflare Access, create a bypass policy for the health endpoint:

1. Access -> Applications -> Edit the application
2. Add Policy:
   - Policy Name: "Health Check Bypass"
   - Action: Bypass
   - Selector: URI Path = `/health`

### Option 4: Use Cloudflare Tunnel (if not already)

If Cloudflare Tunnel is configured, ensure the tunnel configuration doesn't have Access policies blocking the origin:

```bash
# Check tunnel configuration
cloudflared tunnel info <tunnel-name>
```

---

## Conclusion

**The deployment itself is fully successful.** All Nomad allocations are running, health checks are passing, and the service is accessible internally. The user-reported issue ("service inaccessible") is caused by **Cloudflare Access** authentication blocking external requests to `nexus-dev.10cg.pub`. This is an infrastructure/access policy issue, not a deployment issue.

**Immediate workaround**: Access the service directly via the internal IP: `http://192.168.69.80:28803/health`

**Permanent fix**: Update the Cloudflare Access policy to allow the intended users to access the application.
