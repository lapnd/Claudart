#!/bin/bash

# Context-guard behavior suite. Proves the PostToolUse guard measures transcript
# size, stays silent under thresholds, warns and escalates exactly once per
# session and level, honors threshold overrides, and fails visibly (exit 2 on
# stderr) when it cannot measure. Fixtures are generated at runtime so byte
# sizes are exact; nothing here touches a live session.

set -u

LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2
GUARD=$REPO_ROOT/.claude/hooks/context-guard.sh
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-context-guard-tests.XXXXXX") || exit 2

# Invoked indirectly by trap.
# shellcheck disable=SC2329
cleanup() {
  if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf -- "$TMP_ROOT"
  fi
}
trap cleanup EXIT HUP INT TERM

PASS_COUNT=0
FAIL_COUNT=0
STATUS=0
OUT_FILE=$TMP_ROOT/last.out
ERR_FILE=$TMP_ROOT/last.err

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok - %s\n' "$1" >&2
}

# run_guard <session-id> <transcript-path> [ENV=VALUE ...]
run_guard() {
  rg_sid=$1
  rg_path=$2
  shift 2
  : >"$OUT_FILE"
  : >"$ERR_FILE"
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"PostToolUse"}\n' \
    "$rg_sid" "$rg_path" | env TMPDIR="$TMP_ROOT" "$@" "$GUARD" >"$OUT_FILE" 2>"$ERR_FILE"
  STATUS=$?
}

# run_stdin <raw-stdin-string>
run_stdin() {
  : >"$OUT_FILE"
  : >"$ERR_FILE"
  printf '%s\n' "$1" | env TMPDIR="$TMP_ROOT" "$GUARD" >"$OUT_FILE" 2>"$ERR_FILE"
  STATUS=$?
}

assert_exit() {
  if [ "$STATUS" -eq "$1" ]; then
    pass "$2"
  else
    fail "$2 (expected exit $1, got $STATUS)"
  fi
}

assert_out_has() {
  if grep -q -- "$1" "$OUT_FILE"; then
    pass "$2"
  else
    fail "$2 (stdout missing: $1)"
  fi
}

assert_out_empty() {
  if [ ! -s "$OUT_FILE" ]; then
    pass "$1"
  else
    fail "$1 (stdout not empty)"
  fi
}

assert_err_has() {
  if grep -q -- "$1" "$ERR_FILE"; then
    pass "$2"
  else
    fail "$2 (stderr missing: $1)"
  fi
}

# --- fixtures ---------------------------------------------------------------

FIX=$TMP_ROOT/transcripts
mkdir -p "$FIX" || exit 2
TINY=$FIX/tiny.jsonl
MID=$FIX/mid.jsonl
EXACT_WARN=$FIX/exact-warn.jsonl
EXACT_ACT=$FIX/exact-act.jsonl
printf '{"row":1}\n' >"$TINY"
head -c 1048577 /dev/zero | tr '\0' 'x' >"$MID"
head -c 8388608 /dev/zero | tr '\0' 'x' >"$EXACT_WARN"
head -c 16777216 /dev/zero | tr '\0' 'x' >"$EXACT_ACT"

# --- cases ------------------------------------------------------------------

if [ -x "$GUARD" ]; then
  pass 'guard is executable'
else
  fail 'guard is executable (chmod +x .claude/hooks/context-guard.sh)'
fi

# T1 under thresholds with defaults: silent success
run_guard s1 "$TINY"
assert_exit 0 'T1 under-default exits 0'
assert_out_empty 'T1 under-default stdout empty'

# T2 warn fires with additionalContext JSON when an override crosses the floor
run_guard s2 "$TINY" CLAUDART_GUARD_WARN_MB=0 CLAUDART_GUARD_ACT_MB=1073741823
assert_exit 0 'T2 warn exits 0'
assert_out_has 'hookSpecificOutput' 'T2 warn emits hookSpecificOutput'
assert_out_has '"hookEventName": *"PostToolUse"' 'T2 warn names the PostToolUse event'
assert_out_has 'additionalContext' 'T2 warn carries additionalContext'
assert_out_has 'CONTEXT-GUARD WARN' 'T2 warn message is warn level'

# T3 warn deduplicates per session: the second identical call is silent
run_guard s2 "$TINY" CLAUDART_GUARD_WARN_MB=0 CLAUDART_GUARD_ACT_MB=1073741823
assert_exit 0 'T3 warn dedup exits 0'
assert_out_empty 'T3 warn dedup is silent'

# T4 act level fires with the escalation message
run_guard s4 "$TINY" CLAUDART_GUARD_WARN_MB=0 CLAUDART_GUARD_ACT_MB=0
assert_exit 0 'T4 act exits 0'
assert_out_has 'CONTEXT-GUARD ACT' 'T4 act message is act level'
assert_out_has 'handoff' 'T4 act instructs handoff'

# T5 act still fires after warn fired for the same session (per-level markers)
run_guard s5 "$TINY" CLAUDART_GUARD_WARN_MB=0 CLAUDART_GUARD_ACT_MB=1073741823
run_guard s5 "$TINY" CLAUDART_GUARD_WARN_MB=0 CLAUDART_GUARD_ACT_MB=0
assert_out_has 'CONTEXT-GUARD ACT' 'T5 act fires after warn for the same session'

# T6 missing transcript_path: visible failure, exit 2
: >"$OUT_FILE"
: >"$ERR_FILE"
printf '{"session_id":"s6","hook_event_name":"PostToolUse"}\n' |
  env TMPDIR="$TMP_ROOT" "$GUARD" >"$OUT_FILE" 2>"$ERR_FILE"
STATUS=$?
assert_exit 2 'T6 missing transcript_path exits 2'
assert_err_has 'context-guard' 'T6 missing transcript_path names the guard'

# T7 invalid JSON stdin: visible failure, exit 2
run_stdin 'not json at all'
assert_exit 2 'T7 invalid json exits 2'
assert_err_has 'context-guard' 'T7 invalid json names the guard'

# T8 jq unavailable: visible failure, exit 2 (PATH sandbox without jq)
SANDBOX_BIN=$TMP_ROOT/sandbox-bin
mkdir -p "$SANDBOX_BIN" || exit 2
for tool in cat wc mkdir env head tr bash grep; do
  tool_path=$(command -v "$tool" 2>/dev/null) || continue
  ln -sf "$tool_path" "$SANDBOX_BIN/$tool"
done
run_guard s8 "$TINY" CLAUDART_GUARD_WARN_MB=0 CLAUDART_GUARD_ACT_MB=1073741823 \
  PATH="$SANDBOX_BIN"
assert_exit 2 'T8 jq missing exits 2'
assert_err_has 'jq' 'T8 jq missing names jq'

# T9 threshold override respected: the same fixture is silent by default
run_guard s9 "$TINY"
assert_out_empty 'T9 same fixture silent under defaults'
run_guard s9 "$TINY" CLAUDART_GUARD_WARN_MB=0 CLAUDART_GUARD_ACT_MB=1073741823
assert_out_has 'CONTEXT-GUARD WARN' 'T9 override fires on the same fixture'

# T10 a real 1MB+ transcript against default thresholds stays silent
run_guard s10 "$MID"
assert_exit 0 'T10 1MB transcript under defaults exits 0'
assert_out_empty 'T10 1MB transcript under defaults silent'

# T11 exactly at the warn boundary (8MB) fires WARN under defaults
run_guard s11 "$EXACT_WARN"
assert_out_has 'CONTEXT-GUARD WARN' 'T11 exactly-warn-boundary fires WARN'

# T12 exactly at the act boundary (16MB) fires ACT under defaults
run_guard s12 "$EXACT_ACT"
assert_out_has 'CONTEXT-GUARD ACT' 'T12 exactly-act-boundary fires ACT'

# T13 non-numeric threshold override: visible failure, exit 2
run_guard s13 "$TINY" CLAUDART_GUARD_WARN_MB=abc
assert_exit 2 'T13 non-numeric warn threshold exits 2'
assert_err_has 'CLAUDART_GUARD_WARN_MB' 'T13 non-numeric warn threshold names the var'

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
