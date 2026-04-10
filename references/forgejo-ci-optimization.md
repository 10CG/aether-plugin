# Forgejo CI Optimization Guide (Aether environment)

> **Audience**: AI agents and engineers debugging/optimizing CI/CD pipelines
> that deploy to the Aether Nomad cluster via Forgejo Actions.
>
> **Scope**: Forgejo-hosted runners building Docker images, pushing to
> `forgejo.10cg.pub` registry, deploying to Nomad. The patterns here are
> specific to the Aether environment — internal self-signed registry,
> Chinese-region network, overlay filesystem on runners.
>
> **Source of truth**: This file is inside the `aether-plugin` and
> accessible from any Claude Code project that installs the plugin via
> `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md`. Four
> production projects (SilkNode, Nexus, Kairos, Kino) validated every
> pattern in this document. See § Case studies for measured data.

---

## TL;DR — What this guide does for you

This guide is the **authoritative troubleshooting + optimization reference**
for CI/CD in the Aether environment. When in doubt, consult it by:

1. **Error-driven lookup** → § Troubleshooting decision tree
2. **Pattern-driven design** → § Best practices
3. **Cold-path verification** → § Anti-patterns (avoid these)
4. **Measured impact** → § Case studies (real before/after data)

If you are `/aether:init`, use this guide's patterns in the templates you generate.
If you are `/aether:ci`, use this guide to interpret failures and propose fixes.

---

## When to consult this guide

✅ **Consult this guide when**:
- A project's CI takes >5 minutes and the user asks "why is it slow"
- A new project is being set up via `/aether:init`
- CI push fails with `tls:`, `EIDLETIMEOUT`, `operation not supported`,
  or `invalid pkt-len` errors
- Dockerfile uses `--mount=type=cache` (it will fail here)
- Workflow uses `driver: docker-container` or `network=host` driver-opts
- Deployment verification uses `sleep N` (will be replaced with polling)
- pytest / npm ci takes > 3 minutes (parallelization opportunity)

❌ **Do not consult this guide for**:
- General Forgejo Actions syntax — that's upstream docs
- Nomad HCL job syntax — that's Nomad docs
- Project-specific business logic

---

## Environment facts (why these rules exist)

Know these once, then every rule below makes sense:

1. **The registry `forgejo.10cg.pub` is served by an internal Forgejo
   instance at `192.168.69.200`** with a self-signed TLS certificate.
   Runners reach it either directly (via `/etc/hosts` override) or via
   Cloudflare Access (slow, sometimes rate-limited).

2. **Forgejo Actions runners have a Docker daemon with
   `insecure-registries: ["forgejo.10cg.pub"]` configured**. This is the
   only reason `docker push` to the registry works. BuildKit containers
   **do not inherit this configuration**.

3. **Runner nodes are in China network**. Direct `npm ci` from
   `registry.npmjs.org` and `pip install` from `pypi.org` show
   intermittent idle timeouts inside Alpine containers, especially
   during parallel package downloads.

4. **Runner Docker volumes use overlay2 over NFS** (aether-volumes).
   `RUN --mount=type=cache,target=...` produces
   `failed to create hash: operation not supported` errors
   during `COPY --from=stage` operations.

5. **The Forgejo runner action cache service is broken** as of
   2026-04. Any workflow using `actions/setup-node@v4` with
   `cache: 'npm'` will hit a 4-minute timeout on cache restore AND
   another 4-minute timeout on cache save (9 minutes wasted per run).

6. **Forgejo v11 Actions API does not expose per-step logs**. Remote
   log reading uses the `aether-reader` SSH channel
   (see `docs/guides/aether-reader-ssh-setup.md`).

---

## Anti-patterns (do NOT use these in Aether)

### A1. `driver: docker-container` (default buildx driver)

**Why it looks appealing**: Modern BuildKit features (registry cache,
cache mounts, parallel stages, frontend syntax directives) all work best
with `docker-container`.

**What fails**:
```
ERROR: failed to push forgejo.10cg.pub/10cg/project:sha:
  failed to authorize: failed to fetch oauth token:
  Post "https://forgejo.10cg.pub/v2/token":
  tls: failed to verify certificate: x509: certificate signed by unknown authority
```

**Root cause**: `docker-container` driver runs BuildKit inside an
isolated container that does NOT inherit the host daemon's
`insecure-registries` configuration. It tries to verify the internal
registry's self-signed cert, fails, and aborts the push.

**Why `buildkitd-config-inline: insecure = true` does NOT fix it**:
The `insecure = true` BuildKit config only affects the image pull/push
content path, not the OAuth2 token exchange path. The `POST /v2/token`
request ignores the per-registry insecure flag in current BuildKit
versions (tested on BuildKit 0.13+).

**Fix**: Use `driver: docker` explicitly. This delegates the build to
the host Docker daemon, which honors `insecure-registries`.

```yaml
- uses: docker/setup-buildx-action@v3
  with:
    driver: docker    # MUST be explicit — not default
```

**Case**: SilkNode run #1950, #1952, #1953 — all failed with this exact
error before reverting to `driver: docker` in run #1954 (succeeded).

---

### A2. `cache-from / cache-to: type=registry`

**Why it looks appealing**: BuildKit can pull and push layer cache
manifests from/to a container registry, making subsequent builds near-instant.

**What fails**:
```
ERROR: failed to configure registry cache importer:
  failed to authorize: failed to fetch oauth token:
  Post "https://forgejo.10cg.pub/v2/token":
  tls: failed to verify certificate
```

**Root cause**: Same as A1 — the cache manifest upload/download goes
through the OAuth path and hits the TLS cert issue.

**Fix**: Do not use registry cache in this environment. Rely on
**host Docker layer cache** (which works because `driver: docker`)
plus **good Dockerfile layering** (deps before source).

---

### A3. `RUN --mount=type=cache,target=...`

**Why it looks appealing**: Cache mounts persist across builds on the
same BuildKit instance, so `npm ci` / `pip install` / `cargo build`
runs nearly instantly on repeated builds.

**What fails**:
```
#17 ERROR: failed to calculate checksum of ref <uuid>:
  failed to create hash for /app/node_modules: operation not supported
ERROR: failed to build: failed to solve: failed to compute cache key
```

**Root cause**: The Aether runner's Docker volumes use overlay2 backed
by NFS (`/opt/aether-volumes/runners/.../docker/volumes/...`). When
BuildKit tries to hash files that were written by a cache-mounted
`npm ci` and then copied via `COPY --from=stage`, the checksum operation
fails because certain extended attributes are not supported on this
filesystem.

**Fix**: Remove `--mount=type=cache,target=...` lines from Dockerfiles.
Rely on Docker layer cache (COPY deps → RUN install → COPY source).

**Case**: SilkNode run #1952 failed with this error after adding
cache mounts to speed up npm ci.

---

### A4. `cache: 'npm'` in `actions/setup-node`

**Why it looks appealing**: Standard GitHub Actions pattern — caches
`~/.npm` directory between runs.

**What fails** (silently):
```
Post Run actions/setup-node@v4
...
Warning: Failed to restore: connect ETIMEDOUT 172.18.0.2:45389
<4 minutes pass>
...
<install runs fresh>
...
Post Run actions/setup-node@v4  ← save step
Warning: reserveCache failed: connect ETIMEDOUT
<another 4 minutes pass>
```

**Root cause**: Forgejo Actions runners in the Aether cluster have a
broken cache service endpoint (`172.18.0.2:45389`). Both restore and
save time out after ~4.5 minutes each, producing **~9 minutes of pure
wait time per run** with no error — the run still succeeds because
the actions fail non-fatally.

**Fix**: Never enable `cache:` in `setup-node`:
```yaml
- uses: actions/setup-node@v4
  with:
    node-version: '20'
    # DO NOT add: cache: 'npm'
```

**Case**: SilkNode baseline runs were 23–25 minutes; removing
`cache: 'npm'` alone cut ~9 minutes (35–40% of total time). See
SilkNode run #1954 (10m41s after fix).

---

### A5. Alpine container `npm ci` without mirror/retry

**Why it looks appealing**: Short and simple — `RUN npm ci`.

**What fails**:
```
#10 303.9 npm error code EIDLETIMEOUT
#10 303.9 npm error Idle timeout reached for host `registry.npmjs.org:443`
```

The install hangs for ~5 minutes then fails with idle timeout.

**Root cause**: Alpine containers (musl libc) + China-region network +
parallel package downloads from `registry.npmjs.org` produces
intermittent TCP idle timeouts. The relay workflow ran successfully
without a mirror once, but this is luck — the next run might fail.

**Fix**: Use a China-region npm mirror with retry loop:
```dockerfile
ARG NPM_REGISTRY=https://registry.npmmirror.com

FROM node:22-alpine AS deps
ARG NPM_REGISTRY
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm config set registry "$NPM_REGISTRY" && \
    for i in 1 2 3; do \
      npm ci --prefer-offline --no-audit && break; \
      echo "npm ci failed (attempt $i/3), retrying in 10s..." && sleep 10; \
    done
```

**Case**: Kairos run #1971 failed at 303 seconds with EIDLETIMEOUT on
`[console-builder 4/7] npm ci`. After adding the mirror, run #1975's
same step completed in **11.2 seconds** (27× faster).

---

### A6. `docker.1ms.run/library/node:22-alpine`

**Why it looks appealing**: Kairos backend Dockerfile used
`docker.1ms.run/library/node:18-alpine` "to avoid Docker Hub rate limits
in China". Reasonable intent.

**What fails**:
```
ERROR: failed to copy: httpReadSeeker: failed open:
  content at https://docker.1ms.run/v2/library/node/manifests/sha256:<sha>
  not found: not found
```

**Root cause**: The `docker.1ms.run` mirror has `node:18-alpine` but
not `node:22-alpine` (tag coverage is incomplete, no automatic sync).
Upgrading Node version silently breaks.

**Fix**: Use Docker Hub directly (`FROM node:22-alpine`). Aether
runners have stable access to Docker Hub in practice (relay workflow
has always pulled from Docker Hub successfully). Alternatively, use
the aliyun Docker mirror `registry.cn-hangzhou.aliyuncs.com` which
has broader tag coverage.

---

### A7. `sleep N` for deployment verification

**Why it looks appealing**: Quick and dirty "wait for the app to be ready".

**What's wrong**:
- **Too short**: Deploy hasn't stabilized, CI passes but service is broken.
- **Too long**: Wastes minutes per run unconditionally.
- **No signal**: CI reports success even if the deploy actually failed.

**Fix**: Poll Nomad's `/v1/job/<name>/allocations` endpoint every 5s,
exit as soon as status is `running`, error out after 2 minutes:

```bash
for i in $(seq 1 24); do
  STATUS=$(curl -s "${NOMAD_ADDR}/v1/job/myjob/allocations" \
    -H "X-Nomad-Token: ${NOMAD_TOKEN}" \
    | python3 -c "
import json, sys
allocs = json.load(sys.stdin)
if not allocs:
    print('pending')
else:
    latest = max(allocs, key=lambda a: a['JobVersion'])
    print(latest['ClientStatus'])
" 2>/dev/null || echo "unknown")
  if [ "${STATUS}" = "running" ]; then
    echo "Deployment verified (after ${i}x5s)"
    exit 0
  fi
  echo "  [${i}/24] Status: ${STATUS}"
  sleep 5
done
echo "::error::Deployment did not reach running state within 2 minutes"
exit 1
```

**Impact**: Happy path: ~10–40 seconds (typical deploy). Bad path:
fails fast after 2 minutes instead of passing silently.

---

### A8. Unconditional expensive side-tasks

**Pattern**: Running an SDK publish / documentation generation /
release notification on every deploy, regardless of whether there was
anything new to publish.

**What's wrong**: The side-task does `git clone + npm ci + test + build + pack`
(~76 seconds for Nexus), then checks "does this release already exist?
yes → skip". **The check should happen BEFORE the expensive work.**

**Fix**: Fast-path check before slow-path execution:

```bash
# Fetch current version via API (fast, 1 curl)
VERSION=$(curl -sf -H "Authorization: token ${REPO_TOKEN}" \
  "${INTERNAL_API}/contents/package.json" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); p=json.loads(base64.b64decode(d['content']).decode()); print(p['version'])")

# Check if release already exists (fast, 1 curl)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token ${REPO_TOKEN}" \
  "${API_URL}/releases/tags/v${VERSION}")

if [ "$HTTP_CODE" = "200" ]; then
  echo "Release v${VERSION} already exists, skipping"
  exit 0
fi

# Only now do the expensive clone+build
git clone ...
npm ci
...
```

**Case**: Nexus run #1955 — SDK publish now exits in <2s when the
release already exists (common case), saving ~76s per deploy.

---

### A9. Duplicated builds (host + Docker)

**Pattern**: Run `npm run build` on the host runner as a "quality gate",
then the Dockerfile runs the same `npm run build` inside a container.
Typical finding: `next build` takes ~4 minutes on host AND ~4 minutes
in the Docker layer.

**Fix**: Either:
- **For push events**: skip the host build entirely (Docker will build
  the deployable artifact anyway). Use `if: github.event_name == 'pull_request'`
  to keep the host build as a PR-only quality gate.
- **For monorepo CI workflows**: drop the `npm run build` step from
  the CI workflow — the deploy workflow's Docker build is the source
  of truth.

**Case**: SilkNode `Build verification` step was running twice
(4 min × 2 = 8 min wasted). After adding `if: pull_request`, push
events skip it entirely. Kino's `ci-web.yml` had the same pattern —
removing `npm run build` saved 166s per web push.

---

### A10. Host-installed language runtime for cross-language builds

**Pattern**: The CI runner runs Ubuntu but needs to build a Vite frontend
with Node 22. Workflow uses `apt install nodejs` (installs old Node),
then `curl ... nodesource ... | bash` to upgrade, then `npm ci`,
then passes the built artifact into Docker.

**What's wrong**:
- `apt install` runs on every run (~30s, no cache)
- Host Node version doesn't match Docker base image Node version
- The host build is tied to runner capabilities, fragile
- Extra 90+ seconds of sequential work before Docker build even starts

**Fix**: Build inside a multi-stage Dockerfile. Let Docker handle all
language runtimes via `FROM node:22-alpine AS frontend-builder`.

**Case**: Kairos `Build console frontend` host step was ~97 seconds
(apt + npm ci + vite build). Moving into a `console-builder` Dockerfile
stage let layer cache absorb most of it and eliminated the apt install
entirely.

---

## Best practices (USE these in Aether)

### B1. Buildx setup (always explicit)

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3
  with:
    driver: docker    # Delegates to host daemon with insecure-registries
```

Never omit `driver:`. Never use `driver-opts: network=host`. Never use
`buildkitd-config-inline`.

---

### B2. DNS fix for internal registry

```yaml
- name: Fix registry DNS
  run: echo "192.168.69.200 forgejo.10cg.pub" | sudo tee -a /etc/hosts
```

Place this BEFORE `docker/login-action` and `docker build`. Bypasses
Cloudflare Access, uses the fast internal route, avoids TLS MITM by
Cloudflare edge.

---

### B3. Build + Push (split pattern)

```yaml
- name: Build Docker image
  uses: docker/build-push-action@v5
  with:
    context: .
    push: false       # Key: don't push via buildx
    load: true        # Load into host docker daemon
    tags: forgejo.10cg.pub/org/project:${{ github.sha }}

- name: Tag and push images
  run: |
    SHORT_SHA=$(echo "${{ github.sha }}" | cut -c1-7)
    docker tag forgejo.10cg.pub/org/project:${{ github.sha }} forgejo.10cg.pub/org/project:dev-${SHORT_SHA}
    docker tag forgejo.10cg.pub/org/project:${{ github.sha }} forgejo.10cg.pub/org/project:latest
    docker push forgejo.10cg.pub/org/project:${{ github.sha }}
    docker push forgejo.10cg.pub/org/project:dev-${SHORT_SHA}
    docker push forgejo.10cg.pub/org/project:latest
```

**Why split**: With `driver: docker`, `push: true` + multi-tag in a
single step ALSO works (the host daemon handles both). But the split
form is proven stable across all four case-study projects. The couple
seconds you save by merging isn't worth the risk.

---

### B4. Polling deployment verification

See § A7 for the full snippet. Key principles:
- Every 5 seconds
- Max 24 iterations (2 minutes)
- Exit 0 on first `running` status
- Exit 1 with clear error on timeout

---

### B5. npm mirror + retry (in Dockerfile)

```dockerfile
ARG NPM_REGISTRY=https://registry.npmmirror.com

FROM node:22-alpine AS deps
ARG NPM_REGISTRY
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm config set registry "$NPM_REGISTRY" && \
    for i in 1 2 3; do \
      npm ci --prefer-offline --no-audit && break; \
      echo "npm ci failed (attempt $i/3), retrying in 10s..." && sleep 10; \
    done
```

**Not** in the workflow file — do it inside the Dockerfile so it also
works for local builds (when Aether engineers build on their laptops).
Use ARG so it can be overridden if a project has a private mirror.

---

### B6. pip mirror + retry (in Dockerfile)

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /build
COPY pyproject.toml ./
RUN pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/ && \
    pip config set global.trusted-host mirrors.aliyun.com && \
    pip config set global.timeout 300 && \
    for i in 1 2 3; do \
      pip install --no-cache-dir --user . && break; \
      echo "pip install failed (attempt $i/3), retrying in 10s..." && sleep 10; \
    done
```

---

### B7. `COPY --chown` instead of `RUN chown -R`

```dockerfile
# BAD — independent 40+ second layer on large site-packages:
# COPY --from=builder /root/.local /home/app/.local
# RUN chown -R app:app /home/app/.local /app

# GOOD — ownership set at copy time, no separate layer:
RUN useradd -m -u 1001 app   # Create user FIRST
COPY --from=builder --chown=app:app /root/.local /home/app/.local
COPY --chown=app:app src/ ./src/
```

**Case**: Nexus Dockerfile `RUN chown -R nexus:nexus /app /home/nexus/.local`
took ~46 seconds on a rewrite of the Python site-packages. Switching to
`COPY --chown` eliminated the layer entirely.

---

### B8. pytest parallel execution

```yaml
# ci-api.yml
- name: Run tests
  run: python -m pytest tests/ -v --tb=short -n auto
```

Plus in `pyproject.toml`:
```toml
[project.optional-dependencies]
dev = [
  "pytest>=8.0",
  "pytest-xdist>=3.5.0",   # ADD THIS
  ...
]
```

**Requirement**: Tests must be parallel-safe (no shared DB, no shared
files, ideally use in-process fakes like `fakeredis` or per-test fixtures).
If tests share state, use `-n auto --dist=loadfile` for file-level grouping.

**Case**: Kino `kino-api` 285 tests went from 327s (single) to 92.5s
(2 workers, `-n auto`) = **-72% on the test step**.

---

### B9. Multi-stage build with proper layer caching

```dockerfile
# Deps layer — cached as long as manifest files don't change
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN <install command>

# Build layer — cached as long as source doesn't change
FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# Runtime layer — minimal
FROM node:22-alpine AS runtime
WORKDIR /app
RUN addgroup -g 1001 -S nodejs && adduser -u 1001 -S app -G nodejs
COPY --from=builder --chown=app:nodejs /app/dist ./dist
COPY --from=builder --chown=app:nodejs /app/node_modules ./node_modules
USER app
CMD ["node", "dist/server.js"]
```

**Key**: manifest files BEFORE source in each stage. Changing source
doesn't invalidate the deps install layer.

---

### B10. PR-only quality gates

```yaml
- name: Build verification
  if: github.event_name == 'pull_request'
  run: npm run build
```

For push events, skip the host build — the deploy Docker build is the
source of truth. Saves 4+ minutes per push event.

---

## Case studies (measured impact)

All four projects use Forgejo Actions → Docker → Nomad on the Aether
cluster. Before/after data is from actual CI runs recorded 2026-04.

### SilkNode (Next.js 14.2 + Prisma)

- **Before**: 25 minutes average (run #1945 = 24m44s)
- **After**: 10m41s (run #1954)
- **Savings**: -14 minutes (-58%)
- **Key changes**:
  - Removed broken `cache: 'npm'` → saved ~9 min
  - `Build verification` `if: pull_request` → saved ~4 min (push events)
  - `sleep 45` → polling → saved ~30s
  - Reverted `driver: docker-container` → fixed TLS push failure

### Nexus (Python FastAPI + pgvector + Redis)

- **Before**: 9m30s average (runs #1848=9m11s, #1918=9m57s)
- **After**: 6m43s (run #1955)
- **Savings**: -3m14s (-32%)
- **Key changes**:
  - Dockerfile `RUN chown -R` → `COPY --chown` → saved ~46s
  - SDK publish early-exit check → saved ~76s per deploy
  - `deploy-prod.yaml` `sleep 60` → polling → saved ~30s on prod

### Kairos (TypeScript backend + Vite console + Node relay)

- **Before**: 2m0s to 15m21s (huge variance, cold runner worst case 12m48s)
- **After**: 4m39s (run #1975, cold runner)
- **Savings**: -8 minutes on cold runs (-64%), variance eliminated
- **Key changes**:
  - Host console build → Dockerfile `console-builder` stage
  - `node:18-alpine` → `node:22-alpine` (aligned with relay)
  - `docker.1ms.run` → Docker Hub (mirror lacked node:22 tag)
  - Fixed `vite.config.ts` import path via `/app/console` layout
  - npm mirror + retry across all 3 npm ci stages
  - `sleep 45` → polling
- **Cold npm ci**: 303s → 11s (27× speedup)

### Kino (monorepo: FastAPI + Next.js)

- **Before**: api CI ~6m, web CI ~4m46s, deploy varies
- **After**: api CI 2m14s, web CI 1m51s, deploy 6m24s
- **Savings**: api -63%, web -61%
- **Key changes**:
  - Added `pytest-xdist`, `-n auto` → 327s → 92.5s on test step
  - Removed `npm run build` from `ci-web.yml` → saved 166s per web push
  - Added npm mirror + retry to `kino-web/Dockerfile`
  - Added pip aliyun mirror to `kino-api/Dockerfile`

---

## Troubleshooting decision tree

Match the error keyword to find the relevant section.

### Registry / TLS errors

| Error fragment | Cause | Fix section |
|----------------|-------|------------|
| `tls: failed to verify certificate` at push | `driver: docker-container` | [A1](#a1-driver-docker-container-default-buildx-driver) + [B1](#b1-buildx-setup-always-explicit) |
| `tls: failed to verify certificate` at cache import | `cache-from: type=registry` | [A2](#a2-cache-from--cache-to-typeregistry) |
| `failed to fetch oauth token ... tls:` | `buildkitd-config-inline: insecure = true` doesn't work for OAuth | [A1](#a1-driver-docker-container-default-buildx-driver) |
| `x509: certificate signed by unknown authority` | Same as above | [A1](#a1-driver-docker-container-default-buildx-driver) |

### Build/network errors

| Error fragment | Cause | Fix section |
|----------------|-------|------------|
| `operation not supported` (during COPY --from) | `--mount=type=cache` on overlay/NFS | [A3](#a3-run---mounttypecachetarget) |
| `npm error code EIDLETIMEOUT` | Alpine → npmjs.org idle timeout | [A5](#a5-alpine-container-npm-ci-without-mirrorretry) + [B5](#b5-npm-mirror--retry-in-dockerfile) |
| `registry.npmjs.org:443` hanging | Same | [B5](#b5-npm-mirror--retry-in-dockerfile) |
| `docker.1ms.run/...: not found` | Mirror missing tag | [A6](#a6-docker1msrunlibrarynode22-alpine) |
| `httpReadSeeker: failed open` | Same | [A6](#a6-docker1msrunlibrarynode22-alpine) |
| `failed to create hash for /app/node_modules` | Cache mount + overlay fs | [A3](#a3-run---mounttypecachetarget) |
| `pip timeout` / `Connection timed out` for pypi | Alpine → pypi.org network | [B6](#b6-pip-mirror--retry-in-dockerfile) |

### Workflow / runner errors

| Error fragment | Cause | Fix section |
|----------------|-------|------------|
| `connect ETIMEDOUT 172.18.0.2:45389` | Broken Forgejo runner cache | [A4](#a4-cache-npm-in-actionssetup-node) |
| `Post Run actions/setup-node@v4` taking 4+ minutes | Same | [A4](#a4-cache-npm-in-actionssetup-node) |
| `invalid pkt-len found` | Transient runner action git-clone glitch | Retry (not a code issue) |
| `some refs were not updated` on `data.forgejo.org` | Non-fatal, always present | Ignore |

### Performance / scaling

| Symptom | Cause | Fix section |
|---------|-------|------------|
| CI >20 min and hitting `cache:` timeout | A4 | [A4](#a4-cache-npm-in-actionssetup-node) |
| pytest >3 min sequential | No parallel | [B8](#b8-pytest-parallel-execution) |
| Docker build rebuilds everything each time | Poor layering | [B9](#b9-multi-stage-build-with-proper-layer-caching) |
| Deploy verify takes fixed `sleep N` time | Anti-pattern | [A7](#a7-sleep-n-for-deployment-verification) + [B4](#b4-polling-deployment-verification) |
| Host step and Docker step both build the same thing | Duplication | [A9](#a9-duplicated-builds-host--docker) |
| Expensive "just in case" side-tasks on every deploy | Missing early-exit | [A8](#a8-unconditional-expensive-side-tasks) |

---

## Quick reference: Dos and Don'ts

| ✅ DO | ❌ DON'T |
|------|--------|
| `driver: docker` explicit | `driver: docker-container`, `network=host`, `buildkitd-config-inline` |
| Split `build (load:true)` + manual `docker push` | Use `cache-from/to: type=registry` |
| Polling verify loop (5s × 24) | `sleep N` for deployment wait |
| `npm config set registry https://registry.npmmirror.com` | Direct `npm ci` against `registry.npmjs.org` in Alpine |
| `pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/` | Direct `pip install` against `pypi.org` |
| Wrap every `npm ci` / `pip install` in `for i in 1 2 3` retry loop | Single-shot install without retry |
| `COPY --chown=user:group` | `RUN chown -R user:group /path` on large dirs |
| `COPY deps-manifest → RUN install → COPY source` | `COPY . . → RUN install` (destroys layer cache) |
| `pytest -n auto` when tests are parallel-safe | Unconditional single-threaded pytest |
| `FROM node:22-alpine` (Docker Hub) | `docker.1ms.run/library/node:22-alpine` |
| Fast-path check before expensive side-tasks | Unconditional clone + npm ci + test for "maybe publish" |
| PR-only quality gates when Docker also builds | Duplicating `npm run build` on host and in Docker |

---

## Related Skills

- **`/aether:init`** — Generates workflows and Dockerfiles that follow
  the patterns in this guide by default. The templates in
  `${CLAUDE_PLUGIN_ROOT}/skills/aether-init/references/` are the canonical
  starting point for new projects.

- **`/aether:ci`** — Diagnoses CI failures. When a CI run fails with any
  of the error fragments in § Troubleshooting decision tree, cross-reference
  this guide for root cause + fix.

- **`/aether:deploy`** — Runtime deployment operations. Not directly
  concerned with CI optimization, but slow image builds (caused by
  anti-patterns in this guide) will slow down the deploy feedback loop.
  If a user complains about slow deploys, first check whether the CI
  itself is the bottleneck.

---

## Changelog

| Version | Date | Change |
|---------|------|--------|
| 1.0.0 | 2026-04-10 | Initial version — extracted from 4-project optimization effort (SilkNode, Nexus, Kairos, Kino). All patterns verified with measured data. |
