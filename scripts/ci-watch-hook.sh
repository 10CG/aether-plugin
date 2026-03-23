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

# --- Write state file ---

STATE_DIR=".aether"
mkdir -p "$STATE_DIR" 2>/dev/null || true
cat > "${STATE_DIR}/ci-watch.state" 2>/dev/null <<EOF
sha: ${SHA}
repo: ${OWNER_REPO}
branch: ${BRANCH}
started: $(date -u +%Y-%m-%dT%H:%M:%SZ)
poll_count: 0
EOF

# --- Output: try JSON systemMessage first, fallback to plain text ---

if [ -n "$INPUT" ]; then
  # Standard format: JSON output with systemMessage
  MSG="[aether-ci-watch] git push detected: ${SHORT_SHA} on ${OWNER_REPO}/${BRANCH}. CI pipeline triggered. Automatically create a CronCreate job (cron: */1 * * * *, recurring: true) to poll CI status. Poll prompt: Check CI for ${SHA} in ${OWNER_REPO} — run forgejo GET /repos/${OWNER_REPO}/commits/${SHA}/status and parse state. If success: notify user + CronDelete. If failure: notify + run /aether:aether-ci ${SHA} --reproduce. If pending: wait. Max 15 polls then timeout."
  echo "{\"systemMessage\":$(echo "$MSG" | jq -Rs .)}"
else
  # Env var format: plain text output
  echo ""
  echo "[aether-ci-watch] Push detected: ${SHORT_SHA} → ${OWNER_REPO}/${BRANCH}"
  echo "CI pipeline triggered. Recommend: create CronCreate to auto-poll CI status."
  echo "  Query: forgejo GET /repos/${OWNER_REPO}/commits/${SHA}/status | jq .state"
  echo ""
fi

exit 0
