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

assert_file() {
  file=$1
  label=$2
  if [ -f "$file" ]; then
    pass "$label"
  else
    fail "$label (missing file ${file#"$REPO_ROOT/"})"
  fi
}

assert_contains() {
  file=$1
  pattern=$2
  label=$3
  if [ ! -f "$file" ]; then
    fail "$label (missing file ${file#"$REPO_ROOT/"})"
    return
  fi
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
  if [ ! -f "$file" ]; then
    fail "$label (missing file ${file#"$REPO_ROOT/"})"
    return
  fi
  if grep -Fq -- "$pattern" "$file"; then
    fail "$label (found '$pattern' in ${file#"$REPO_ROOT/"})"
  else
    pass "$label"
  fi
}

CLAUDE_RULE=$REPO_ROOT/.claude/rules/evidence-gauntlet.md
CODEX_RULE=$REPO_ROOT/.codex/guidelines/evidence-gauntlet.md
CLAUDE_CMD=$REPO_ROOT/.claude/commands/prove.md
CODEX_CMD=$REPO_ROOT/.agents/skills/codex-prove/SKILL.md

SPEC_RULE_CLAUDE=$REPO_ROOT/.claude/rules/spec-workflow.md
SPEC_RULE_CODEX=$REPO_ROOT/.codex/guidelines/spec-workflow.md
QUALITY_RULE=$REPO_ROOT/.claude/rules/code-quality.md
CLAUDE_MEMORY=$REPO_ROOT/.claude/CLAUDE.md
DOCTOR_CMD=$REPO_ROOT/.claude/commands/doctor.md

if /bin/bash -n "$TEST_DIR/run.sh"; then
  pass "Bash syntax is valid"
else
  fail "Bash syntax is valid"
fi

assert_file "$CLAUDE_RULE" "Claude layer carries the evidence-gauntlet rule"
assert_file "$CODEX_RULE" "Codex layer carries the evidence-gauntlet guideline"
assert_file "$CLAUDE_CMD" "Claude layer carries the /prove command"
assert_file "$CODEX_CMD" "Codex layer carries the codex-prove skill"

# --- The contract, asserted identically across both layers -------------------

for rule in "$CLAUDE_RULE" "$CODEX_RULE"; do
  assert_contains "$rule" "Tier 1" \
    "rule calibrates effort at tier 1"
  assert_contains "$rule" "Tier 2" \
    "rule calibrates effort at tier 2"
  assert_contains "$rule" "Tier 3" \
    "rule calibrates effort at tier 3"
  assert_contains "$rule" "blast radius" \
    "rule selects a tier by blast radius"

  assert_contains "$rule" "A test you never saw fail proves nothing" \
    "rule requires an observed red before green"
  assert_contains "$rule" "red-verified" \
    "rule names the red-verified evidence event"
  assert_contains "$rule" "throwaway mutant" \
    "rule proves an immediately-passing test rather than asserting it"

  assert_contains "$rule" "changed-line coverage" \
    "rule gates on changed-line coverage"
  assert_contains "$rule" "exit nonzero" \
    "rule requires the coverage layer to be a gate, not a report"
  assert_contains "$rule" "equivalent mutant" \
    "rule classifies unkillable mutants instead of gaming them"

  assert_contains "$rule" "fail closed" \
    "rule requires home-grown checkers to fail closed"
  assert_contains "$rule" "negative control" \
    "rule proves a checker can fail before trusting its pass"
  assert_contains "$rule" "gauntlet entry point" \
    "rule persists one rerunnable entry point"

  assert_contains "$rule" "Never weaken a test to make it pass" \
    "rule forbids weakening a test"
  assert_contains "$rule" "Never report a layer you didn't run" \
    "rule forbids inventing a layer result"
  assert_contains "$rule" "Coverage is a detector" \
    "rule forbids chasing the coverage number"

  # Conflict accommodations with the rules that already exist.
  assert_contains "$rule" "never injected at final review" \
    "rule keeps tier selection out of bounded review patches"
  assert_contains "$rule" "Independent Review Dispatch" \
    "rule reuses the existing independent-review contract"
  assert_contains "$rule" "not performed" \
    "rule keeps the four verification states"
  assert_contains "$rule" "commits:" \
    "rule routes commit cadence through the existing grant"

  assert_not_contains "$rule" "clean-code-reviewer" \
    "rule does not auto-dispatch an explicit-request-only review agent"
  assert_not_contains "$rule" "security-auditor" \
    "rule does not auto-dispatch the security auditor"
done

# --- The driver, asserted identically across both layers ---------------------

for cmd in "$CLAUDE_CMD" "$CODEX_CMD"; do
  assert_contains "$cmd" "evidence-gauntlet" \
    "command reads the evidence-gauntlet contract"
  assert_contains "$cmd" "Tier" \
    "command declares a tier"
  assert_contains "$cmd" "red-verified" \
    "command records the red-verified transition"
  assert_contains "$cmd" "Evidence" \
    "command ends in an evidence report"
  assert_contains "$cmd" "mission scale" \
    "command states its scope boundary against the spec layer"

  assert_not_contains "$cmd" "Tier 1 — trivial" \
    "command drives the rule instead of duplicating its tier table"
done

# --- The wiring: the new contract is reachable from the existing layers ------

for spec_rule in "$SPEC_RULE_CLAUDE" "$SPEC_RULE_CODEX"; do
  assert_contains "$spec_rule" "red-verified" \
    "spec workflow accepts the red-verified ledger event"
done

assert_contains "$QUALITY_RULE" "changed-line coverage" \
  "code quality gates on changed lines, not only the global percentage"
assert_contains "$QUALITY_RULE" "mutation" \
  "code quality defends its coverage bar with mutation testing"

assert_contains "$CLAUDE_MEMORY" "evidence-gauntlet" \
  "project memory registers the evidence-gauntlet rule trigger"
assert_contains "$CLAUDE_MEMORY" "/prove" \
  "project memory registers the /prove command"
assert_contains "$DOCTOR_CMD" "prove.md" \
  "doctor requires the /prove command file"

printf '1..%s\n' $((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
