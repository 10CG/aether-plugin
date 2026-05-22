#!/usr/bin/env bash
# Aether #27 — build-container walking skeleton: node-side build script
#
# This script runs as root via raw_exec on whichever heavy node Nomad
# placed the alloc. ALL parameters arrive via env vars set by the HCL
# template (job-template.hcl `env {}` block) plus Nomad-injected
# NOMAD_ALLOC_ID. No __VAR__ placeholders here — single-stage
# substitution lives in the HCL layer only.
#
# Inputs (env):
#   JOB_ID, CTX_PATH, RESULT_PATH, DOCKERFILE_PATH, BUILD_ARGS,
#   REGISTRY, TAG, SRC_REF, SRC_SHA   (from HCL)
#   NOMAD_ALLOC_ID                    (injected by Nomad runtime)
#
# Outputs:
#   $RESULT_PATH (JSON) — success: 5+ field contract per Aria #111;
#                         failure: status=error + error_code + alloc_id
#   exit code  — 0 success, 20-23 = source_not_found / dockerfile_invalid /
#                build_failed / push_failed (mapped to result.json error_code)
#
# Design notes (proposal §3 + Risk Highlights):
#   - prune runs AFTER result.json write in a backgrounded subshell so a
#     hung prune cannot occupy the raw_exec slot until alloc_timeout
#     (would otherwise misreport a successful build as alloc_timeout).
#   - trap cleans the WORK_DIR (extracted build context tree on shared
#     virtiofs, see below). Staged context tarball + result.json + script
#     cleanup on the shared volume is the SKILL'S responsibility
#     (lifecycle ownership split), not the task's — even if this script
#     dies the skill's finally hop removes /opt/aether-volumes/_build-ctx/<id>.*
#   - $NOMAD_ALLOC_ID embedded in every result.json (success and error)
#     so the skill can surface it in its output contract without a
#     follow-up Nomad API call.

set -euo pipefail

# Sanity: env vars must be set by the HCL. If any is missing we cannot
# even write a sensible result.json, so emit a best-effort one.
: "${JOB_ID:?missing JOB_ID env}"
: "${CTX_PATH:?missing CTX_PATH env}"
: "${RESULT_PATH:?missing RESULT_PATH env}"
: "${DOCKERFILE_PATH:?missing DOCKERFILE_PATH env}"
: "${REGISTRY:?missing REGISTRY env}"
: "${TAG:?missing TAG env}"
: "${SRC_REF:?missing SRC_REF env}"
: "${SRC_SHA:?missing SRC_SHA env}"
BUILD_ARGS="${BUILD_ARGS:-}"
ALLOC_ID="${NOMAD_ALLOC_ID:-unknown}"

# DooD gotcha: docker build context paths are resolved by the daemon
# (running on host), NOT by this client container. So extract the
# tarball into the shared virtiofs path which IS visible identically
# on host and in container — host daemon then sees the tree.
WORK_DIR="/opt/aether-volumes/_build-ctx/work-${JOB_ID}"
trap 'rm -rf "$WORK_DIR"' EXIT

# Write a structured error result and exit with the matching code.
# Usage: emit_error <error_code> <message> <exit_code>
emit_error() {
  local code="$1" msg="$2" rc="$3"
  cat > "$RESULT_PATH" <<JSON
{"status":"error","error_code":"${code}","message":"${msg//\"/\\\"}","alloc_id":"${ALLOC_ID}","build_node":"$(hostname)"}
JSON
  exit "$rc"
}

# Source context must be on the shared volume; missing = skill failed to
# scp or the path was wrong. error_code source_not_found / exit 20.
if [ ! -f "$CTX_PATH" ]; then
  emit_error "source_not_found" "context tarball missing at ${CTX_PATH}" 20
fi

mkdir -p "$WORK_DIR"
if ! tar -xzf "$CTX_PATH" -C "$WORK_DIR" 2>/dev/null; then
  emit_error "source_not_found" "tar -xzf failed on ${CTX_PATH}" 20
fi
cd "$WORK_DIR"

# Dockerfile path is relative to the extracted context root.
if [ ! -f "$DOCKERFILE_PATH" ]; then
  emit_error "dockerfile_invalid" "no Dockerfile at ${DOCKERFILE_PATH} inside extracted context" 21
fi

BUILD_START=$(date +%s)

# docker build — host daemon reuses configured registry auth (proposal §3
# push auth mechanism). --build-arg + --label embed source_commit_sha for
# drift prevention (Aria #111 Q3). BUILD_ARGS is pre-rendered "--build-arg
# K=V" string from the skill; intentionally NOT quoted as a single arg so
# multiple flags expand correctly. Skill is responsible for shell-safe
# escaping (no spaces in values, no shell metachars).
# shellcheck disable=SC2086
if ! docker build \
       -f "$DOCKERFILE_PATH" \
       --build-arg "SOURCE_GIT_REF=${SRC_REF}" \
       --label "org.aether.source_commit_sha=${SRC_SHA}" \
       --label "org.aether.source_git_ref=${SRC_REF}" \
       --label "org.aether.build_job_id=${JOB_ID}" \
       ${BUILD_ARGS} \
       -t "${REGISTRY}:${TAG}" \
       . ; then
  emit_error "build_failed" "docker build failed (see nomad alloc logs ${ALLOC_ID})" 22
fi

if ! docker push "${REGISTRY}:${TAG}" ; then
  emit_error "push_failed" "docker push to ${REGISTRY}:${TAG} failed (see nomad alloc logs ${ALLOC_ID})" 23
fi

# Resolve the immutable digest. RepoDigests is registry-side ground truth
# (image_sha256 in the output contract). Falls back to empty if inspect
# is somehow empty — treat as build_failed since we cannot honor the
# contract without a digest.
DIGEST=$(docker inspect --format '{{index .RepoDigests 0}}' "${REGISTRY}:${TAG}" 2>/dev/null || true)
if [ -z "$DIGEST" ]; then
  emit_error "build_failed" "docker inspect returned no RepoDigest after push (digest unresolvable)" 22
fi

# image_sha256 = the sha256:... portion after the @
IMAGE_SHA="${DIGEST##*@}"
BUILD_DURATION=$(( $(date +%s) - BUILD_START ))
BUILD_NODE="$(hostname)"

# Success result. 5-field contract from Aria #111 Q3 + build_node +
# build_duration_sec (nice-to-have observability).
cat > "$RESULT_PATH" <<JSON
{"status":"ok","image_sha256":"${IMAGE_SHA}","registry_url":"${DIGEST}","source_commit_sha":"${SRC_SHA}","source_git_ref":"${SRC_REF}","build_node":"${BUILD_NODE}","build_duration_sec":${BUILD_DURATION},"alloc_id":"${ALLOC_ID}"}
JSON

# Prune AFTER result.json write, backgrounded fire-and-forget. result.json
# landing is the success gate; whether prune finishes is irrelevant to the
# skill's polling. Without backgrounding a hung prune would hold the
# raw_exec slot until 1800s alloc_timeout and the skill would misread a
# successful build as alloc_timeout (proposal Risk Highlights).
( docker builder prune -f --filter until=24h >/dev/null 2>&1 & )

exit 0
