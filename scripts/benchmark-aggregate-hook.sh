#!/bin/bash
# benchmark-aggregate-hook.sh — PostToolUse hook
#
# Detects git commits containing ab-results/ files and reminds Claude
# to run aggregate-results.py to update OVERALL_BENCHMARK_SUMMARY.md.
#
# Trigger: PostToolUse on Bash (after git commit with ab-results)
# Output: systemMessage prompting aggregation

set -e

# --- Read tool input ---
COMMAND="${CLAUDE_TOOL_INPUT:-}"

if [ -z "$COMMAND" ]; then
  INPUT=$(cat 2>/dev/null || true)
  if [ -n "$INPUT" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
  fi
fi

[ -z "$COMMAND" ] && exit 0

# --- Only trigger on git commit/add involving ab-results ---
case "$COMMAND" in
  *"git commit"*|*"git add"*ab-results*) ;;
  *) exit 0 ;;
esac

# --- Check if ab-results files are staged or just committed ---
HAS_AB_RESULTS=false

# Check staged files (for git add)
if git diff --cached --name-only 2>/dev/null | grep -q "ab-results/"; then
  HAS_AB_RESULTS=true
fi

# Check last commit (for git commit that just ran)
if echo "$COMMAND" | grep -q "git commit"; then
  if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "ab-results/"; then
    HAS_AB_RESULTS=true
  fi
fi

[ "$HAS_AB_RESULTS" = "false" ] && exit 0

# --- Check if summary is already up to date ---
SCRIPT_PATH="aether-plugin-benchmarks/scripts/aggregate-results.py"
SUMMARY_PATH="aether-plugin-benchmarks/OVERALL_BENCHMARK_SUMMARY.md"

if [ ! -f "$SCRIPT_PATH" ]; then
  exit 0
fi

# --- Output systemMessage ---
if [ -n "$INPUT" ]; then
  MSG="[aether-benchmark] AB test results committed. Update the benchmark summary: python3 ${SCRIPT_PATH} && git add ${SUMMARY_PATH} — include the updated summary in a follow-up commit if not already staged."
  echo "{\"systemMessage\": \"${MSG}\"}"
else
  echo "[aether-benchmark] AB test results committed. Run: python3 ${SCRIPT_PATH}"
fi
