#!/usr/bin/env bash
# tests/constitution/run.sh — contract tests for the Constitution enforcer
# (.claude/scripts/constitution-check.sh).
#
# For each of the enforcer's 5 checks this suite asserts BOTH directions (verification.md §1 /
# evidence-gauntlet.md §6 — "never trust a PASS until the check can FAIL"):
#   - a negative-control fixture fed through the matching CC_* override makes the check FAIL, and the
#     run names it with a `FAIL [<check>]` marker;
#   - the check PASSES on real repo inputs (and, where relevant, on a good fixture).
# A negative control overrides only its own CC_* var, so the other four checks run against the real
# repo (which complies) — the run's nonzero exit is therefore attributable to the one bad input.
#
# TAP-ish output; nonzero exit on any failed assertion. Same style as tests/context-guard/run.sh.

set -u
LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2
CHK=$REPO_ROOT/.claude/scripts/constitution-check.sh
FIX=$TEST_DIR/fixtures
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-constitution-tests.XXXXXX") || exit 2

# shellcheck disable=SC2329
cleanup() { [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ] && rm -rf -- "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM

PASS_COUNT=0
FAIL_COUNT=0
OUT=$TMP_ROOT/last.out
STATUS=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'ok %s - %s\n' "$PASS_COUNT" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'not ok - %s\n' "$1" >&2; }

# run <ENV=VALUE ...> — invoke the enforcer with overrides; capture merged output and exit status.
run() {
  : >"$OUT"
  env "$@" bash "$CHK" >"$OUT" 2>&1
  STATUS=$?
}

assert_status() {
  if [ "$STATUS" -eq "$1" ]; then pass "$2"; else fail "$2 (expected exit $1, got $STATUS)"; fi
}
assert_status_nonzero() {
  if [ "$STATUS" -ne 0 ]; then pass "$1"; else fail "$1 (expected nonzero exit, got 0)"; fi
}
assert_has() {
  if grep -q -- "$1" "$OUT"; then pass "$2"; else fail "$2 (output missing: $1)"; fi
}

if [ -f "$CHK" ]; then pass 'enforcer script exists'; else fail "enforcer script exists ($CHK)"; fi

# --- baseline: the enforcer passes on the real repo ------------------------------------------------
run
assert_status 0 'real repo: enforcer exits 0'
assert_has 'all checks passed' 'real repo: reports all checks passed'

# ===================================================================================================
# Check 1 — roadmap node/verify
# ===================================================================================================
# negative control: a task line missing both node: and (verify: …)
run CC_ROADMAP="$FIX/roadmap-bad.md"
assert_status_nonzero 'check1 negative: bad ROADMAP fails the run'
assert_has 'FAIL \[roadmap\]' 'check1 negative: names the roadmap check'
# positive: a good graph-format ROADMAP passes
run CC_ROADMAP="$FIX/roadmap-good.md"
assert_status 0 'check1 positive: good ROADMAP passes'
assert_has 'ok   \[roadmap\]' 'check1 positive: roadmap check reports ok'
# positive: no CC_ROADMAP -> skip (real repo, npm check has no active spec)
run
assert_has 'SKIP \[roadmap\]' 'check1 positive: unset CC_ROADMAP skips with a note'

# ===================================================================================================
# Check 2 — no verbatim duplication (>= 12 consecutive words from the constitution)
# ===================================================================================================
# negative control: a rule file copying 12+ consecutive words from the fixture constitution
run CC_CONSTITUTION="$FIX/dup/constitution.md" CC_RULES_DIR="$FIX/dup/rules-bad"
assert_status_nonzero 'check2 negative: 12-word copy fails the run'
assert_has 'FAIL \[duplication\]' 'check2 negative: names the duplication check'
# positive: a rules dir sharing only short fragments passes
run CC_CONSTITUTION="$FIX/dup/constitution.md" CC_RULES_DIR="$FIX/dup/rules-ok"
assert_status 0 'check2 positive: no long verbatim run passes'
assert_has 'ok   \[duplication\]' 'check2 positive: duplication check reports ok'

# ===================================================================================================
# Check 3 — auto-import budget
# ===================================================================================================
# negative control: CLAUDE.md importing two 200-line files (sum 400 > 200 budget; each > 150 cap).
# CC_IMPORT_BASE defaults to the .claude parent of CC_CLAUDE_MD, so the fixture layout resolves.
run CC_CLAUDE_MD="$FIX/import-over/.claude/CLAUDE.md"
assert_status_nonzero 'check3 negative: oversized imports fail the run'
assert_has 'FAIL \[import-budget\]' 'check3 negative: names the import-budget check'
# positive: the real repo's imports are within budget and each file <= 150 (covered by baseline run)
run
assert_has 'ok   \[import-budget\]' 'check3 positive: real repo imports within budget'

# ===================================================================================================
# Check 4 — core purity (D15)
# ===================================================================================================
# negative control: a core file with `import os`
run CC_CORE_DIR="$FIX/core-dirty"
assert_status_nonzero 'check4 negative: impure core file fails the run'
assert_has 'FAIL \[core-purity\]' 'check4 negative: names the core-purity check'
assert_has 'import os' 'check4 negative: reports the offending import'
# positive: the real graph/core is pure (covered by baseline run)
run
assert_has 'ok   \[core-purity\]' 'check4 positive: real graph/core is pure'

# ===================================================================================================
# Check 5 — rule->enforcer map (D29)
# ===================================================================================================
# negative control: a rules file with an untagged MUST bullet and an unknown enforcer ID
run CC_TAGGED_RULES="$FIX/enforcer/bad.md"
assert_status_nonzero 'check5 negative: untagged MUST / unknown ID fails the run'
assert_has 'FAIL \[enforcer-map\]' 'check5 negative: names the enforcer-map check'
assert_has 'NOT_A_REAL_ID' 'check5 negative: reports the unknown enforcer ID'
assert_has 'untagged MUST' 'check5 negative: reports the untagged MUST clause'
# positive: a fixture whose MUST bullets are all tagged with real IDs
run CC_TAGGED_RULES="$FIX/enforcer/good.md"
assert_status 0 'check5 positive: fully-tagged rules pass'
assert_has 'ok   \[enforcer-map\]' 'check5 positive: enforcer-map check reports ok'
# positive: the real repo's tagged rules pass (covered by baseline run)

# --- summary ---------------------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
