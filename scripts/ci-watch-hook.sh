#!/bin/bash
#
# Aether CI PostToolUse Hook
# Detects git push commands and triggers automatic CI monitoring
#
# Input: JSON on stdin (standard format) or CLAUDE_TOOL_INPUT env var
# Output: JSON with systemMessage or plain text notification
#

set -e

# --- Read tool input (support both stdin JSON and env var formats) ---

COMMAND="${CLAUDE_TOOL_INPUT:-}"

if [ -z "$COMMAND" ]; then
  INPUT=$(cat 2>/dev/null || true)
  if [ -n "$INPUT" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
  fi
fi

# --- Filter: only trigger on git push ---

if [[ "$COMMAND" != *"git push"* ]]; then
  exit 0
fi

# Skip if push itself had errors (rejected, fatal)
if [[ "$COMMAND" == *"--dry-run"* ]]; then
  exit 0
fi

# --- Extract commit and repo info ---

SHA=$(git rev-parse HEAD 2>/dev/null) || exit 0
REMOTE_URL=$(git remote get-url origin 2>/dev/null) || exit 0
OWNER_REPO=$(echo "$REMOTE_URL" | sed 's/\.git$//' | sed -E 's#.*/([^/]+/[^/]+)$#\1#')
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
SHORT_SHA="${SHA:0:8}"

[ -z "$OWNER_REPO" ] && exit 0

# --- Resolve job name and registry from config ---
JOB_NAME=""
REGISTRY=""
if [ -f ".aether/config.yaml" ]; then
  JOB_NAME=$(yq -r '.watch.job_name // empty' .aether/config.yaml 2>/dev/null || true)
  REGISTRY=$(yq -r '.cluster.registry // empty' .aether/config.yaml 2>/dev/null || true)
fi
# Fallback: derive job name from repo basename
if [ -z "$JOB_NAME" ]; then
  JOB_NAME=$(echo "$OWNER_REPO" | sed 's#.*/##' | tr '[:upper:]' '[:lower:]')
fi

# --- Write state file ---

# Poll budget: 30 x 60s. The old 15 x 60s window expired while slow jobs were
# still running (recipe workflows measured single jobs at 238/439/859s; the
# shard trigger line is 1200s), so the monitor gave up before CI did
# (Aether #467 comment 27845 item 3).
POLL_MAX=30

STATE_DIR=".aether"
mkdir -p "$STATE_DIR" 2>/dev/null || true
cat > "${STATE_DIR}/ci-watch.state" 2>/dev/null <<EOF
sha: ${SHA}
repo: ${OWNER_REPO}
branch: ${BRANCH}
started: $(date -u +%Y-%m-%dT%H:%M:%SZ)
poll_count: 0
poll_max: ${POLL_MAX}
job_name: ${JOB_NAME}
expected_image: ${REGISTRY}/${OWNER_REPO}:${SHA}
EOF

# --- Output: try JSON systemMessage first, fallback to plain text ---
#
# Completion predicate: `aether ci status --commit <sha> --expect N` judged by
# exit code (0 complete / 13 finished-with-failures / 10 incomplete / 11 N
# stale / 12 cannot-conclude), NOT the merged commit status state — a slow
# runner flips the merged state back to pending mid-run.

if [ -n "$INPUT" ]; then
  # Standard format: JSON output with systemMessage
  MSG="[aether-ci-watch] git push detected: ${SHORT_SHA} on ${OWNER_REPO}/${BRANCH}. CI pipeline triggered. Automatically create a CronCreate job (cron: */1 * * * *, recurring: true) to poll CI status. Poll prompt: Check CI for ${SHA} in ${OWNER_REPO} — first derive N = number of CI jobs this push triggers (sum job counts across .forgejo/workflows/*.yml whose paths match the pushed diff; fallback: parent commit's job count via aether ci status --commit <parent-sha> --json, field .data.commit.jobs). Each poll: run aether ci status --commit ${SHA} --expect N and judge by exit code, never by the merged commit status state. Exit 0: CI complete — notify user + CronDelete + IMMEDIATELY invoke /aether:aether-deploy-watch ${JOB_NAME} --version ${SHA} to verify deployment. Exit 13: finished with failures — notify + run /aether:aether-ci ${SHA} --reproduce. Exit 10: not finished — wait. Exit 11: N is stale — re-derive N from this commit's current job count and continue. Exit 12 or a repeated command error: notify user. Max ${POLL_MAX} polls then timeout — window sized for the slowest CI job."
  echo "{\"systemMessage\":$(echo "$MSG" | jq -Rs .)}"
else
  # Env var format: plain text output
  echo ""
  echo "[aether-ci-watch] Push detected: ${SHORT_SHA} → ${OWNER_REPO}/${BRANCH}"
  echo "CI pipeline triggered. Recommend: create CronCreate to auto-poll CI status."
  echo "  Query: aether ci status --commit ${SHA} --expect N — judge by exit code (0 complete / 13 failures / 10 pending / 11 N wrong / 12 inconclusive), not the merged status state."
  echo "  N = job count this push triggers; max ${POLL_MAX} polls."
  echo ""
fi

exit 0
