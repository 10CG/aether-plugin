#!/bin/bash
# cli-guard-hook-test.sh — pipe-level contract test for cli-guard-hook.sh (#489).
#
# The hook is a PreToolUse Bash matcher: Claude Code delivers the payload as
# stdin JSON with the command at .tool_input.command (the CLAUDE_TOOL_INPUT env
# var the hook used to read alone is never set), and a PreToolUse hook blocks
# the tool call only via exit 2 — exit 1 is a non-blocking error. Both facts
# were measured live (issue #489 comment 28172): the shipped hook exited 0 for
# every input, i.e. it never guarded anything.
#
# Usage: bash scripts/cli-guard-hook-test.sh   (from any cwd; exit 0 = pass)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/cli-guard-hook.sh"
FAILURES=0

fail() { FAILURES=$((FAILURES+1)); echo "FAIL: $1"; }
pass() { echo "pass: $1"; }

# --- 1. RED shape: aether command via stdin JSON, CLI absent → must BLOCK (exit 2) with guidance on stderr
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$(echo '{"tool_input":{"command":"aether version"}}' \
  | env -i PATH=/usr/bin:/bin HOME="$TMP" bash "$HOOK" 2>"$TMP/stderr")"; RC=$?
ERR_TEXT="$(cat "$TMP/stderr")"
if [ "$RC" -ne 2 ]; then
  fail "aether command with CLI absent must exit 2 (PreToolUse block), got $RC — exit 0/1 never blocks the tool call (#489)"
else
  pass "aether command with CLI absent exits 2"
fi
if ! grep -q "Aether CLI" <<<"$ERR_TEXT"; then
  fail "guidance must reach stderr on block, stderr was: $ERR_TEXT"
else
  pass "guidance on stderr"
fi

# --- 2. aether command, CLI present (stub on PATH) → must ALLOW (exit 0)
STUB="$TMP/bin"; mkdir -p "$STUB"; printf '#!/bin/sh\nexit 0\n' > "$STUB/aether"; chmod +x "$STUB/aether"
OUT="$(echo '{"tool_input":{"command":"aether version"}}' \
  | env -i PATH="$STUB:/usr/bin:/bin" HOME="$TMP" bash "$HOOK" 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ]; then
  fail "aether command with CLI on PATH must allow (exit 0), got $RC"
else
  pass "CLI present allows"
fi

# --- 3. non-aether command via stdin JSON → allow (exit 0), no output
OUT="$(echo '{"tool_input":{"command":"ls -la"}}' \
  | env -i PATH=/usr/bin:/bin HOME="$TMP" bash "$HOOK" 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ] || [ -n "$OUT" ]; then
  fail "non-aether command must allow silently (exit 0, no stdout), got rc=$RC out=$OUT"
else
  pass "non-aether allows silently"
fi

# --- 4. legacy env var still honored when stdin is empty
OUT="$(CLAUDE_TOOL_INPUT='aether version' env -i PATH=/usr/bin:/bin HOME="$TMP" CLAUDE_TOOL_INPUT='aether version' bash "$HOOK" 2>/dev/null)"; RC=$?
if [ "$RC" -ne 2 ]; then
  fail "env-var form (CLAUDE_TOOL_INPUT) with CLI absent must still block (exit 2), got $RC"
else
  pass "env-var form still blocks"
fi

# --- 5. malformed stdin JSON must not crash into a block (fail-open on parse, not on guard)
OUT="$(printf 'not-json' | env -i PATH=/usr/bin:/bin HOME="$TMP" bash "$HOOK" 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ]; then
  fail "malformed stdin must degrade to allow (jq fails → empty command), got rc=$RC"
else
  pass "malformed stdin degrades to allow"
fi

echo
if [ "$FAILURES" -ne 0 ]; then
  echo "cli-guard-hook-test: $FAILURES failure(s)"
  exit 1
fi
echo "cli-guard-hook-test: all pass"
