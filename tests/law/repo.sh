#!/usr/bin/env bash
# tests/law/repo.sh — contract tests for THIS repository's rule files
#
# This suite asserts that the .claude/rules directory conforms to the law schema.
# The rule files have not been migrated yet, so every assertion is expected to FAIL
# (exit != 0). This is the deliverable: the RED baseline before migration begins.
# Do not weaken this suite to make it pass — missing fields and relationships must
# surface as failed assertions (verification.md §1, evidence-gauntlet.md §6).
#
# Style follows tests/law/schema.sh and tests/constitution/run.sh: TAP-ish
# `ok N - …` / `not ok - …` output, pass/fail counters, a `run()` helper that
# captures exit status on the command's OWN line (never through a pipe), `assert_*`
# helpers, mktemp + trap cleanup, and a final summary line with nonzero exit when
# anything failed.

set -u
LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2
LAW_CLI=$REPO_ROOT/.claude/scripts/claudart-law.sh
CHK=$REPO_ROOT/.claude/scripts/constitution-check.sh
RULES_DIR=$REPO_ROOT/.claude/rules
BUDGET=$REPO_ROOT/.claude/budget.yaml

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-law-repo-tests.XXXXXX") || exit 2

# shellcheck disable=SC2329
cleanup() { [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ] && rm -rf -- "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM

PASS_COUNT=0
FAIL_COUNT=0
OUT=$TMP_ROOT/last.out
STATUS=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'ok %s - %s\n' "$PASS_COUNT" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'not ok - %s\n' "$1" >&2; }

# run <arg ...> — invoke the CLI or command with the given args; capture merged
# output and exit status on the command's own line (never through a pipe).
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

# ===================================================================================================
# 1. validate --rules --budget exits 0
# ===================================================================================================
run bash "$LAW_CLI" validate --rules "$RULES_DIR" --budget "$BUDGET"
assert_status 0 'validate on real repo: exit 0'

# ===================================================================================================
# 2. constitution-check.sh exits 0
# ===================================================================================================
run bash "$CHK"
assert_status 0 'constitution-check.sh: exit 0'

# ===================================================================================================
# 3. Vendor files exist
# ===================================================================================================
VENDOR_1="$RULES_DIR/vendor/harness-coauthor-trailer.md"
VENDOR_2="$RULES_DIR/vendor/harness-delegation-default.md"

if [ -f "$VENDOR_1" ]; then
  pass "vendor file exists: harness-coauthor-trailer.md"
else
  fail "vendor file exists: harness-coauthor-trailer.md (not found at $VENDOR_1)"
fi

if [ -f "$VENDOR_2" ]; then
  pass "vendor file exists: harness-delegation-default.md"
else
  fail "vendor file exists: harness-delegation-default.md (not found at $VENDOR_2)"
fi

# ===================================================================================================
# 4. Every rule file carries stale_after: in frontmatter
# ===================================================================================================
MISSING_STALE_AFTER=()
STALE_AFTER_COUNT=0

# Check .claude/rules/*.md
for rule_file in "$RULES_DIR"/*.md; do
  [ -f "$rule_file" ] || continue
  if grep -q "^stale_after:" "$rule_file"; then
    STALE_AFTER_COUNT=$((STALE_AFTER_COUNT + 1))
  else
    MISSING_STALE_AFTER+=("$(basename "$rule_file")")
  fi
done

# Check .claude/rules/vendor/*.md (if directory exists)
if [ -d "$RULES_DIR/vendor" ]; then
  for vendor_file in "$RULES_DIR"/vendor/*.md; do
    [ -f "$vendor_file" ] || continue
    if grep -q "^stale_after:" "$vendor_file"; then
      STALE_AFTER_COUNT=$((STALE_AFTER_COUNT + 1))
    else
      MISSING_STALE_AFTER+=("vendor/$(basename "$vendor_file")")
    fi
  done
fi

if [ ${#MISSING_STALE_AFTER[@]} -eq 0 ]; then
  pass "stale_after field present: all ${STALE_AFTER_COUNT} rule files"
else
  fail "stale_after field present: ${#MISSING_STALE_AFTER[@]} files missing it: ${MISSING_STALE_AFTER[*]}"
fi

# ===================================================================================================
# 5. Six specific relationship declarations in frontmatter
# ===================================================================================================

# These are the 6 required relationships (file → must declare):
# 1. .claude/rules/git-commits.md — overrides: [vendor/harness-coauthor-trailer]
run grep -q "overrides:.*\[.*vendor/harness-coauthor-trailer.*\]" "$RULES_DIR/git-commits.md"
if [ $STATUS -eq 0 ]; then
  pass "git-commits.md declares: overrides [vendor/harness-coauthor-trailer]"
else
  fail "git-commits.md declares: overrides [vendor/harness-coauthor-trailer]"
fi

# 2. .claude/rules/spec-workflow.md — supersedes_in_scope: [task-management]
run grep -q "supersedes_in_scope:.*\[.*task-management.*\]" "$RULES_DIR/spec-workflow.md"
if [ $STATUS -eq 0 ]; then
  pass "spec-workflow.md declares: supersedes_in_scope [task-management]"
else
  fail "spec-workflow.md declares: supersedes_in_scope [task-management]"
fi

# 3. .claude/rules/agent-delegation.md — overrides: [vendor/harness-delegation-default]
run grep -q "overrides:.*\[.*vendor/harness-delegation-default.*\]" "$RULES_DIR/agent-delegation.md"
if [ $STATUS -eq 0 ]; then
  pass "agent-delegation.md declares: overrides [vendor/harness-delegation-default]"
else
  fail "agent-delegation.md declares: overrides [vendor/harness-delegation-default]"
fi

# 4. .claude/rules/code-quality.md — layers_on: [constitution]
run grep -q "layers_on:.*\[.*constitution.*\]" "$RULES_DIR/code-quality.md"
if [ $STATUS -eq 0 ]; then
  pass "code-quality.md declares: layers_on [constitution]"
else
  fail "code-quality.md declares: layers_on [constitution]"
fi

# 5. .claude/rules/stack-migration.md — supersedes_in_scope: [spec-workflow]
run grep -q "supersedes_in_scope:.*\[.*spec-workflow.*\]" "$RULES_DIR/stack-migration.md"
if [ $STATUS -eq 0 ]; then
  pass "stack-migration.md declares: supersedes_in_scope [spec-workflow]"
else
  fail "stack-migration.md declares: supersedes_in_scope [spec-workflow]"
fi

# 6. .claude/rules/delegation.md — layers_on: [constitution]
run grep -q "layers_on:.*\[.*constitution.*\]" "$RULES_DIR/delegation.md"
if [ $STATUS -eq 0 ]; then
  pass "delegation.md declares: layers_on [constitution]"
else
  fail "delegation.md declares: layers_on [constitution]"
fi

# --- summary ---------------------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
