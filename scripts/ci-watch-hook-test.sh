#!/bin/bash
# ci-watch-hook-test.sh — pipe-level contract test for ci-watch-hook.sh
# (Aether #467 comment 27845 item 3, plugin side).
#
# The hook is the PostToolUse Bash matcher that starts CI monitoring after a
# git push: it writes .aether/ci-watch.state and emits a systemMessage that
# scripts Claude into a CronCreate polling loop. The polling contract it
# emits must match what slow CI actually does (measured on the recipe
# workflows: single jobs at 238/439/859s, shard trigger line 1200s), so:
#
#   - the poll budget must exceed the slowest job, not give up at 15x60s
#     (the old window expired while recipe-controls was still running);
#   - the completion predicate must be `aether ci status --commit <sha>
#     --expect N` judged by exit code, NOT the merged commit status state
#     (a mid-run slow runner flips the merged state back to pending).
#
# Usage: bash scripts/ci-watch-hook-test.sh   (from any cwd; exit 0 = pass)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/ci-watch-hook.sh"
FAILURES=0

fail() { FAILURES=$((FAILURES+1)); echo "FAIL: $1"; }
pass() { echo "pass: $1"; }

# --- Fixture: a real git repo so sha/branch/origin resolve like in a project
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" checkout -q -b main
git -C "$REPO" -c user.email=t@example.test -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" remote add origin https://forgejo.example.test/acme/widget.git
REPO_SHA="$(git -C "$REPO" rev-parse HEAD)"
STATE="$REPO/.aether/ci-watch.state"

# --- 1. stdin JSON git push → exit 0, JSON systemMessage with the count-based
#        predicate and a window that outlasts the slowest job
OUT="$(cd "$REPO" && echo '{"tool_input":{"command":"git push origin main"}}' \
  | env -i PATH=/usr/bin:/bin HOME="$TMP" bash "$HOOK" 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ]; then
  fail "git push via stdin JSON must exit 0, got $RC"
else
  pass "push exits 0"
fi
SYSMSG="$(printf '%s' "$OUT" | jq -e -n 'input | .systemMessage // empty' 2>/dev/null)"; SRC=$?
if [ "$SRC" -ne 0 ] || [ -z "$SYSMSG" ]; then
  fail "stdout must be JSON with a string .systemMessage, got: $OUT"
else
  pass "stdout is JSON systemMessage"
fi
if ! grep -q "aether ci status --commit" <<<"$SYSMSG" || ! grep -q -- "--expect" <<<"$SYSMSG"; then
  fail "poll predicate must be 'aether ci status --commit <sha> --expect N' (exit-code judged), message: $SYSMSG"
else
  pass "count-based poll predicate"
fi
if ! grep -q "Max 30 polls" <<<"$SYSMSG"; then
  fail "poll budget must be 30x60s (slowest measured job 859s, shard line 1200s; 15x60s gave up early), message: $SYSMSG"
else
  pass "poll budget outlasts slowest job"
fi
if grep -q "parse state" <<<"$SYSMSG"; then
  fail "must not instruct polling the merged commit status state (slow runners flip it to pending mid-run), message: $SYSMSG"
else
  pass "no merged-state predicate"
fi
if ! grep -q "/aether:aether-deploy-watch" <<<"$SYSMSG" || ! grep -q "/aether:aether-ci" <<<"$SYSMSG"; then
  fail "success→deploy-watch and failure→aether-ci handoffs must survive, message: $SYSMSG"
else
  pass "downstream handoffs intact"
fi

# --- 2. state file records the push and the durable poll budget
if [ ! -f "$STATE" ]; then
  fail "git push must write .aether/ci-watch.state"
else
  pass "state file written"
fi
grep -q "^sha: ${REPO_SHA}$" "$STATE" \
  && pass "state sha matches HEAD" || fail "state sha must be ${REPO_SHA}, state: $(cat "$STATE")"
grep -q "^repo: acme/widget$" "$STATE" \
  && pass "state repo derived from origin" || fail "state repo must be acme/widget, state: $(cat "$STATE")"
grep -q "^poll_count: 0$" "$STATE" \
  && pass "state poll_count starts at 0" || fail "state poll_count must start at 0, state: $(cat "$STATE")"
grep -q "^poll_max: 30$" "$STATE" \
  && pass "state poll_max is 30" || fail "state poll_max must be 30, state: $(cat "$STATE")"

# --- 3. non-push command via stdin JSON → silent allow, no state file
rm -rf "$REPO/.aether"
OUT="$(cd "$REPO" && echo '{"tool_input":{"command":"git status"}}' \
  | env -i PATH=/usr/bin:/bin HOME="$TMP" bash "$HOOK" 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ] || [ -n "$OUT" ] || [ -e "$STATE" ]; then
  fail "non-push command must be silent no-op (exit 0, no output, no state), got rc=$RC out=$OUT"
else
  pass "non-push silent no-op"
fi

# --- 4. git push --dry-run → ignored (no CI is triggered)
OUT="$(cd "$REPO" && echo '{"tool_input":{"command":"git push --dry-run origin main"}}' \
  | env -i PATH=/usr/bin:/bin HOME="$TMP" bash "$HOOK" 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ] || [ -n "$OUT" ] || [ -e "$STATE" ]; then
  fail "--dry-run push must be ignored, got rc=$RC out=$OUT"
else
  pass "--dry-run ignored"
fi

# --- 5. legacy env var form → plain-text guidance with the same contract
OUT="$(cd "$REPO" && env -i PATH=/usr/bin:/bin HOME="$TMP" CLAUDE_TOOL_INPUT='git push origin main' \
  bash "$HOOK" </dev/null 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ]; then
  fail "env-var form must exit 0, got $RC"
else
  pass "env-var form exits 0"
fi
if ! grep -q "aether ci status --commit" <<<"$OUT" || ! grep -q "30" <<<"$OUT"; then
  fail "env-var guidance must carry the count-based query and the 30-poll budget, got: $OUT"
else
  pass "env-var guidance carries the contract"
fi
if grep -q "jq .state" <<<"$OUT"; then
  fail "env-var guidance must not poll the merged state, got: $OUT"
else
  pass "env-var guidance has no merged-state query"
fi

# --- 6. malformed stdin JSON must degrade silently (jq fails → no command)
rm -rf "$REPO/.aether"
OUT="$(cd "$REPO" && printf 'not-json' \
  | env -i PATH=/usr/bin:/bin HOME="$TMP" bash "$HOOK" 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ] || [ -n "$OUT" ] || [ -e "$STATE" ]; then
  fail "malformed stdin must degrade to silent no-op, got rc=$RC out=$OUT"
else
  pass "malformed stdin degrades silently"
fi

echo
if [ "$FAILURES" -ne 0 ]; then
  echo "ci-watch-hook-test: $FAILURES failure(s)"
  exit 1
fi
echo "ci-watch-hook-test: all pass"
