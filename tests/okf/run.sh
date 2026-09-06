#!/usr/bin/env bash
# tests/okf/run.sh — shared contract test for the outbound `knowledge-bundle` port.
#
# One assertion set that every adapter of the port must satisfy:
#   - okf-cli        : the pinned `okf` binary validates a conformant bundle and rejects a bad one
#   - knowledge-check: BOTH checkers (.claude and .codex twins) accept the migrated vocabulary and
#                      reject the pre-migration one
#   - okf-mcp        : the MCP server completes a handshake and exposes its tool list
#   - the real bundle: `okf validate .claude/knowledge` is conformant
#
# Fail-closed by construction (evidence-gauntlet.md §6, verification-mechanics.md §1):
#   - every exit status is captured on the command's own line, never through a pipe
#   - no `|| true`, no `2>/dev/null`
#   - when okf-resolve.sh finds no binary the suite EXITS 1 with its message. It never skips:
#     a skipped test is not coverage, so an absent binary is a failure, not a pass.
#
# TAP-ish output; nonzero exit on any failed assertion. Style follows tests/constitution/run.sh.

set -u
LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd -P) || exit 2
FIX=$TEST_DIR/fixtures
RESOLVE=$REPO_ROOT/.claude/scripts/okf-resolve.sh
CLAUDE_CHECKER=$REPO_ROOT/.claude/scripts/knowledge-check.sh
CODEX_CHECKER=$REPO_ROOT/.codex/scripts/knowledge-check.sh
TODAY=2026-09-06

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-okf-tests.XXXXXX") || exit 2
# shellcheck disable=SC2329
cleanup() { [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ] && rm -rf -- "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM

PASS_COUNT=0
FAIL_COUNT=0
OUT=$TMP_ROOT/last.out
STATUS=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'ok %s - %s\n' "$PASS_COUNT" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'not ok - %s\n' "$1" >&2; }

# run <cmd...> — capture merged output and the exit status of the command itself.
run() {
  : >"$OUT"
  "$@" >"$OUT" 2>&1
  STATUS=$?
}

assert_status() {
  if [ "$STATUS" -eq "$1" ]; then pass "$2"; else fail "$2 (expected exit $1, got $STATUS)"; fi
}
assert_has() {
  if grep -q -- "$1" "$OUT"; then pass "$2"; else fail "$2 (output missing: $1)"; fi
}

# --- the binary must exist; never skip ------------------------------------------------------------
OKF_BIN=$(bash "$RESOLVE")
RESOLVE_STATUS=$?
if [ "$RESOLVE_STATUS" -ne 0 ]; then
  printf 'okf binary required\n' >&2
  printf 'tests/okf/run.sh: build it with .claude/scripts/okf-install.sh, or set CLAUDART_OKF_BIN.\n' >&2
  exit 1
fi
pass 'okf binary resolved'

# negative control for the resolver itself. A conditional control that quietly turns into a pass
# would be "0 items examined -> PASS" (verification.md §1), so the failure path is exercised for
# real: a copy of the resolver in a temp dir has no `bin/okf` beside it, CLAUDART_OKF_BIN is unset,
# and PATH is stripped. Proving the gate can go red is what makes its green mean anything.
mkdir -p "$TMP_ROOT/noresolve"
cp "$RESOLVE" "$TMP_ROOT/noresolve/okf-resolve.sh"
: >"$OUT"
env -u CLAUDART_OKF_BIN PATH=/usr/bin:/bin \
  bash "$TMP_ROOT/noresolve/okf-resolve.sh" >"$OUT" 2>&1
STATUS=$?
assert_status 1 'resolver negative control: nothing resolvable exits 1'
assert_has 'okf binary required' 'resolver negative control: names the missing binary'

# --- okf-cli adapter: bundle conformance ----------------------------------------------------------
run "$OKF_BIN" validate "$FIX/bundle-good"
assert_status 0 'okf validate: conformant fixture bundle exits 0'

run "$OKF_BIN" validate "$FIX/bundle-bad"
assert_status 1 'okf validate: bundle missing `type` exits 1'
assert_has "'type' field is missing or empty" 'okf validate: names the missing type field'

# --- knowledge-check adapter: both twins, both directions -----------------------------------------
run /bin/bash "$CLAUDE_CHECKER" --root "$FIX/knowledge-migrated" --layer claude --today "$TODAY"
assert_status 0 'claude checker: migrated vocabulary exits 0'

run /bin/bash "$CODEX_CHECKER" --root "$FIX/knowledge-migrated" --layer claude --today "$TODAY"
assert_status 0 'codex checker: migrated vocabulary exits 0'

run /bin/bash "$CLAUDE_CHECKER" --root "$FIX/knowledge-old" --layer claude --today "$TODAY"
assert_status 1 'claude checker: pre-migration vocabulary exits 1'

run /bin/bash "$CODEX_CHECKER" --root "$FIX/knowledge-old" --layer claude --today "$TODAY"
assert_status 1 'codex checker: pre-migration vocabulary exits 1'

# --- the real bundle ------------------------------------------------------------------------------
run "$OKF_BIN" validate "$REPO_ROOT/.claude/knowledge"
assert_status 0 'okf validate: the real .claude/knowledge bundle is conformant'

# --- okf-mcp adapter: handshake and tool list -----------------------------------------------------
run /bin/bash "$TEST_DIR/mcp-probe.sh" "$FIX/bundle-good"
assert_status 0 'mcp probe: handshake against the fixture bundle exits 0'
assert_has 'okf_search' 'mcp probe: tool list contains okf_search'

run /bin/bash "$TEST_DIR/mcp-probe.sh" "$REPO_ROOT/.claude/knowledge"
assert_status 0 'mcp probe: handshake against the real bundle exits 0'
assert_has 'okf_search' 'mcp probe: real bundle tool list contains okf_search'

printf '\n# passed %s, failed %s\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
