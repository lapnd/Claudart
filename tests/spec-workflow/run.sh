#!/bin/bash

set -u

LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok - %s\n' "$1" >&2
}

assert_contains() {
  file=$1
  pattern=$2
  label=$3
  if grep -Fq -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label (missing '$pattern' in ${file#"$REPO_ROOT/"})"
  fi
}

assert_not_contains() {
  file=$1
  pattern=$2
  label=$3
  if grep -Fq -- "$pattern" "$file"; then
    fail "$label (found legacy '$pattern' in ${file#"$REPO_ROOT/"})"
  else
    pass "$label"
  fi
}

CODEX_RULE=$REPO_ROOT/.codex/guidelines/spec-workflow.md
CLAUDE_RULE=$REPO_ROOT/.claude/rules/spec-workflow.md
CODEX_RUNNER=$REPO_ROOT/.agents/skills/codex-spec-run/SKILL.md
CLAUDE_RUNNER=$REPO_ROOT/.claude/commands/spec-run.md
CODEX_AUTHOR=$REPO_ROOT/.agents/skills/codex-spec/SKILL.md
CLAUDE_AUTHOR=$REPO_ROOT/.claude/commands/spec.md

if /bin/bash -n "$TEST_DIR/run.sh"; then
  pass "Bash syntax is valid"
else
  fail "Bash syntax is valid"
fi

for rule in "$CODEX_RULE" "$CLAUDE_RULE"; do
  assert_contains "$rule" "full-baseline" \
    "rule defines a full final-gate baseline"
  assert_contains "$rule" "scoped-review" \
    "rule defines scoped review revalidation"
  assert_contains "$rule" "smallest non-redundant" \
    "rule requires non-redundant verification"
  assert_contains "$rule" "bounded review patch" \
    "rule keeps explicit review patches bounded"
  assert_contains "$rule" "actual changed surface" \
    "rule derives review impact from actual changes"
  assert_contains "$rule" "resulting revision or bounded worktree fingerprint" \
    "rule identifies the state proved by every successful gate"
  assert_not_contains "$rule" "user reports a problem within approved intent" \
    "rule requires an exact review anchor"
  assert_not_contains "$rule" "last full baseline" \
    "rule does not skip evidence from earlier scoped reviews"
  assert_contains "$rule" "decisive output lines" \
    "rule specifies the evidence entry anatomy"
  assert_contains "$rule" "No evidence line, no tick" \
    "rule refuses ticks without evidence"
  assert_contains "$rule" "re-verify rather than re-do" \
    "rule classifies crash recovery before redoing work"
  assert_contains "$rule" "executor-tier" \
    "rule records the recommended executor tier in SPEC frontmatter"
done

assert_contains "$CODEX_RULE" \
  "when the mission has no successful full-baseline" \
  "Codex first mission gate establishes a full baseline"
assert_contains "$CLAUDE_RULE" \
  "required for the mission's first final gate" \
  "Claude first mission gate establishes a full baseline"
assert_contains "$CODEX_RULE" \
  'latest successful `final-gate` cumulative evidence state' \
  "Codex chains repeated scoped reviews from the latest gate"
assert_contains "$CLAUDE_RULE" \
  'latest successful `final-gate` cumulative evidence state' \
  "Claude chains repeated scoped reviews from the latest gate"
assert_contains "$CODEX_RULE" \
  "effects that remain inside a defensible local boundary" \
  "Codex bounded patches require a defensible impact boundary"
assert_contains "$CLAUDE_RULE" \
  "effects that escape a defensible local boundary" \
  "Claude bounded patches require a defensible impact boundary"

for runner in "$CODEX_RUNNER" "$CLAUDE_RUNNER"; do
  assert_contains "$runner" "full-baseline" \
    "runner can establish or refresh a full baseline"
  assert_contains "$runner" "scoped-review" \
    "runner uses scoped review gates"
  assert_contains "$runner" "bounded review patch" \
    "runner recognizes bounded review patches"
  assert_contains "$runner" "actual changed surface" \
    "runner computes impact after implementation"
  assert_contains "$runner" "resulting revision or bounded worktree fingerprint" \
    "runner records the state proved by each gate"
  assert_not_contains "$runner" "re-run every Acceptance Scenario fresh" \
    "runner does not mandate unconditional full replay"
  assert_not_contains "$runner" "last full baseline" \
    "runner does not skip evidence from earlier scoped reviews"
  assert_not_contains "$runner" "changed verifier, or cross-cutting change" \
    "runner does not treat every local verifier edit as cross-cutting"
  assert_contains "$runner" "executor-tier" \
    "runner surfaces the recommended executor tier"
  assert_contains "$runner" "escalation signal" \
    "runner escalates after repeated failed validation below the strong tier"
done

assert_contains "$CODEX_RUNNER" \
  'latest successful cumulative `final-gate` evidence state' \
  "Codex runner chains cumulative scoped-review evidence"
assert_contains "$CLAUDE_RUNNER" \
  'latest successful `final-gate` baseline' \
  "Claude runner chains cumulative scoped-review evidence"
assert_contains "$CODEX_RUNNER" \
  "semantically changed shared verifier/harness" \
  "Codex runner falls back only for shared semantic verifier impact"
assert_contains "$CLAUDE_RUNNER" \
  "semantic change to a shared verifier/harness" \
  "Claude runner falls back only for shared semantic verifier impact"

for author in "$CODEX_AUTHOR" "$CLAUDE_AUTHOR"; do
  assert_contains "$author" "smallest non-redundant" \
    "spec authoring exposes a non-redundant final verification set"
  assert_contains "$author" "composite" \
    "spec authoring records composite coverage"
  assert_contains "$author" "None in scope" \
    "refactor missions keep empty contract categories explicit"
  assert_contains "$author" "never the refactored code" \
    "refactor contract is reconstructed from the baseline"
  assert_contains "$author" "Tier-annotate tasks" \
    "spec authoring annotates task tiers for model routing"
done

printf '1..%s\n' $((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
