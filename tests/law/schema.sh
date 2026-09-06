#!/usr/bin/env bash
# tests/law/schema.sh — contract tests for the law engine's `validate` command
# (.claude/scripts/claudart-law.sh validate), per .claude/scripts/law/SCHEMA.md.
#
# The CLI does not exist yet (P1.6a): this suite is expected to FAIL, and every assertion is
# expected to report a "not ok" line rather than the runner crashing. Do not weaken this suite to
# make it pass — a missing CLI must surface as a failed assertion (verification.md §1,
# evidence-gauntlet.md §6).
#
# Style follows tests/constitution/run.sh: TAP-ish `ok N - …` / `not ok - …` output, a `run()`
# helper that captures the exit status on the command's OWN line (never through a pipe — see
# verification-mechanics.md §1), `assert_status`/`assert_has`, mktemp + trap cleanup, and a final
# summary line with a nonzero exit when anything failed.
#
# Exit-code contract (SCHEMA.md §7): 0 clean, 1 findings, 2 usage/runtime error.

set -u
LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2
CLI=$REPO_ROOT/.claude/scripts/claudart-law.sh
FIX=$TEST_DIR/fixtures
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-law-schema-tests.XXXXXX") || exit 2

# shellcheck disable=SC2329
cleanup() { [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ] && rm -rf -- "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM

PASS_COUNT=0
FAIL_COUNT=0
OUT=$TMP_ROOT/last.out
STATUS=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'ok %s - %s\n' "$PASS_COUNT" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'not ok - %s\n' "$1" >&2; }

# run <arg ...> — invoke the CLI with the given args; capture merged output and exit status on
# the command's own line (never through a pipe).
run() {
  : >"$OUT"
  bash "$CLI" "$@" >"$OUT" 2>&1
  STATUS=$?
}

assert_status() {
  if [ "$STATUS" -eq "$1" ]; then pass "$2"; else fail "$2 (expected exit $1, got $STATUS)"; fi
}
assert_has() {
  if grep -q -- "$1" "$OUT"; then pass "$2"; else fail "$2 (output missing: $1)"; fi
}

# ===================================================================================================
# validate --rules rules-good -> exit 0
# ===================================================================================================
run validate --rules "$FIX/rules-good"
assert_status 0 'rules-good: validate exits 0'

# ===================================================================================================
# validate --rules rules-bad/<case> -> exit 1, expected finding code present
# ===================================================================================================
# case -> expected code, one pair per line: "<dir>|<code>"
BAD_CASES='
missing-stale-after|MISSING-FIELD
missing-enforcer|MISSING-FIELD
undeclared-overlap|UNDECLARED-OVERLAP
overrides-constitution|OVERRIDES-CONSTITUTION
approved-without-human|APPROVED-WITHOUT-HUMAN
convention-overrides-law|BAD-LAYER
'
IFS='
'
for pair in $BAD_CASES; do
  [ -n "$pair" ] || continue
  case_dir=${pair%%|*}
  code=${pair#*|}
  run validate --rules "$FIX/rules-bad/$case_dir"
  assert_status 1 "rules-bad/$case_dir: validate exits 1"
  assert_has "$code" "rules-bad/$case_dir: reports $code"
done
unset IFS

# ===================================================================================================
# validate --rules rules-good --budget budget.yaml --proposals proposals-stale -> exit 1, QUEUE-STALE
# ===================================================================================================
# NOTE: the fixture proposal is fixed at created: 2026-07-23 / expires: 2026-08-22, well past
# queue_max_age_days: 30 for any "today" from 2026-08-22 onward. The CLI has no documented
# --today-style override flag yet (none is specified in SCHEMA.md or the CLI brief), so this
# assertion depends on the wall clock staying past that date. If the CLI later grows a fixed-date
# override, prefer it here instead of relying on the current clock.
run validate --rules "$FIX/rules-good" --budget "$FIX/budget.yaml" --proposals "$FIX/proposals-stale"
assert_status 1 'proposals-stale: validate exits 1'
assert_has 'QUEUE-STALE' 'proposals-stale: reports QUEUE-STALE'

# ===================================================================================================
# missing --rules directory -> exit 2 (usage/runtime, not a finding)
# ===================================================================================================
run validate --rules "$FIX/does-not-exist"
assert_status 2 'missing --rules directory: validate exits 2'

# ===================================================================================================
# unknown flag -> exit 2 (usage error)
# ===================================================================================================
run validate --not-a-real-flag
assert_status 2 'unknown flag: validate exits 2'

# --- summary ---------------------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
