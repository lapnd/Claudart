#!/bin/bash

# spec-check.sh tests.
#
# Every assertion is a mutation: build a healthy mission, confirm the checker is
# silent, inject exactly one defect, confirm the matching code fires. A code that
# cannot be made to fire is a dead assertion, and this suite exists because a
# sibling suite passed 14 of 14 while two of its assertions were dead.

set -u

LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2
CHECKER=$REPO_ROOT/.claude/scripts/spec-check.sh
DISJOINT=$REPO_ROOT/.claude/scripts/disjoint.sh
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-spec-engine.XXXXXX") || exit 2

# Invoked indirectly by trap.
# shellcheck disable=SC2329
cleanup() { [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ] && rm -rf -- "$TMP_ROOT"; }
trap cleanup EXIT HUP INT TERM

PASS_COUNT=0
FAIL_COUNT=0
pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$1"
}
fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok - %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  /' >&2
}

# A healthy two-phase mission with a declared graph. Everything the checker is
# entitled to complain about is correct here, so any finding is the mutation's.
build() {
  d=$1
  rm -rf "$d"
  mkdir -p "$d/.claude/specs/2026-01-02-sample-mission" "$d/.claude/specs/done"
  m=$d/.claude/specs/2026-01-02-sample-mission
  cat >"$m/SPEC.md" <<'EOF'
---
slug: sample-mission
status: running
created: 2026-01-02
updated: 2026-01-02
agent: claude
commits: user
---

# Sample Mission
EOF
  cat >"$m/ROADMAP.md" <<'EOF'
# ROADMAP — Sample Mission

## Phase 1 — seam

- [x] P1.1 Write the contract test RED (verify: run the contract test)
      node: test/contract | kind: test
      paths: src/contract/**
- [ ] P1.2 Implement against the frozen contract (verify: run the contract test)
      node: impl/contract | kind: usecase
      requires: test/contract (TEST)
      paths: src/impl/**

## Phase 2 — widen

- [ ] P2.1 Second adapter (verify: run the adapter test)
      node: adapter/second | kind: adapter
      requires: impl/contract (IMPLEMENTATION)
      paths: src/second/**
EOF
  printf '# NOTES — Sample Mission\n\n## Orientation\n\n- nothing yet\n' >"$m/NOTES.md"
  cat >"$m/LEDGER.md" <<'EOF'
# LEDGER — Sample Mission

### 2026-01-02 09:00Z — run-started sample-mission

- Evidence: started

### 2026-01-02 10:00Z — task-completed P1.1

- Evidence: contract test observed red then green
EOF
  printf '<!-- index -->\n\n## Active\n\n- [sample-mission](2026-01-02-sample-mission/SPEC.md) — running — updated 2026-01-02 — sample\n\n## Done\n\n- _(none)_\n' \
    >"$d/.claude/specs/INDEX.md"
}

run_checker() { /bin/bash "$CHECKER" --root "$1" --layer claude 2>&1; }

# assert_code <label> <expected code|-> <mutation command...>
assert_code() {
  label=$1
  code=$2
  shift 2
  d=$TMP_ROOT/case
  build "$d"
  m=$d/.claude/specs/2026-01-02-sample-mission
  export d m
  if [ "$#" -gt 0 ]; then
    if ! ( eval "$*" ) 2>/dev/null; then
      fail "$label" "mutation command failed"
      return
    fi
  fi
  out=$(run_checker "$d")
  if [ "$code" = "-" ]; then
    if [ -z "$out" ]; then pass "$label"; else fail "$label" "$out"; fi
  else
    if printf '%s\n' "$out" | grep -q "|$code|"; then
      pass "$label"
    else
      fail "$label" "expected $code, got:${out:-(silence)}"
    fi
  fi
}

if /bin/bash -n "$CHECKER" "$DISJOINT" "$TEST_DIR/run.sh"; then
  pass "Bash syntax is valid"
else
  fail "Bash syntax is valid"
fi

# The healthy baseline must be silent, or every mutation below proves nothing.
assert_code "healthy mission produces no finding" -

assert_code "S001 missing core file"        S001 'rm "$m/NOTES.md"'
assert_code "S002 folder name mismatch"     S002 'sed -i "s/^slug: sample-mission/slug: other/" "$m/SPEC.md"'
assert_code "S003 NOTES over ceiling"       S003 'for i in $(seq 1 160); do echo "line $i" >> "$m/NOTES.md"; done'
assert_code "S110 missing frontmatter key"  S110 'sed -i "/^agent:/d" "$m/SPEC.md"'
assert_code "S111 status not in enum"       S111 'sed -i "s/^status: running/status: galloping/" "$m/SPEC.md"'
assert_code "S112 commits not in enum"      S112 'sed -i "s/^commits: user/commits: whenever/" "$m/SPEC.md"'
assert_code "S113 archived but not terminal" S113 'mkdir -p "$d/.claude/specs/done" && mv "$m" "$d/.claude/specs/done/"'
assert_code "S114 terminal but not archived"  S114 'sed -i "s/^status: running/status: done/" "$m/SPEC.md" && sed -i "s/^- \[ \]/- [x]/g" "$m/ROADMAP.md"'
assert_code "S301 dependency cycle"           S301 'sed -i "s|requires: test/contract (TEST)|requires: adapter/second (TEST)|" "$m/ROADMAP.md"'
assert_code "S200 unticked struck row"      S200 'sed -i "s/^- \[ \] P2.1/- [ ] ~~P2.1~~/" "$m/ROADMAP.md"'
assert_code "S201 superseded without name"  S201 'sed -i "s/^- \[x\] P1.1/- [x] ~~P1.1~~/" "$m/ROADMAP.md"'
assert_code "S202 blocked without unlock"   S202 'sed -i "s|^- \[ \] P2.1 Second adapter|- [ ] P2.1 Second adapter — ⚠ blocked: waiting on a decision|" "$m/ROADMAP.md"'
assert_code "S203 task without verify"      S203 'sed -i "s/ (verify: run the adapter test)//" "$m/ROADMAP.md"'
assert_code "S204 complete status, open row" S204 'sed -i "s/^status: running/status: awaiting-final-review/" "$m/SPEC.md"'
assert_code "S205 running with nothing open" S205 'sed -i "s/^- \[ \]/- [x]/g" "$m/ROADMAP.md"'
assert_code "S206 blocked with no blocked row" S206 'sed -i "s/^status: running/status: blocked/" "$m/SPEC.md"'
assert_code "S300 requires an unsupplied node" S300 'sed -i "s|requires: test/contract (TEST)|requires: test/absent (TEST)|" "$m/ROADMAP.md"'
assert_code "S303 unregistered edge type"   S303 'sed -i "s|(TEST)|(VIBES)|" "$m/ROADMAP.md"'
assert_code "S310 open task with no node"   S310 'printf -- "- [ ] P2.9 Unscheduled work (verify: something)\\n" >> "$m/ROADMAP.md"'
assert_code "S402 final gate without mode"  S402 'printf "\\n### 2026-01-02 12:00Z — final-gate sample\\n\\n- Evidence: all green\\n" >> "$m/LEDGER.md"'
assert_code "S402 silent when mode given"   -    'printf "\\n### 2026-01-02 12:00Z — final-gate, full-baseline — 3 of 3\\n\\n- Evidence: all green\\n" >> "$m/LEDGER.md"'
assert_code "S404 wave-selected names no exclusion" S404 \
  'printf "\\n### 2026-01-02 11:00Z — wave-selected 1 of 2 runnable\\n\\n- Selected: P1.2\\n" >> "$m/LEDGER.md"'
assert_code "S404 wave-selected names no rule" S404 \
  'printf "\\n### 2026-01-02 11:00Z — wave-selected 1 of 2 runnable\\n\\n- Selected: P1.2\\n- Excluded: P2.1\\n" >> "$m/LEDGER.md"'
assert_code "S404 silent on a complete record" - \
  'printf "\\n### 2026-01-02 11:00Z — wave-selected 1 of 2 runnable\\n\\n- Selected: P1.2\\n- Excluded: P2.1 (rule 3 — ordering, phase gate not reached)\\n" >> "$m/LEDGER.md"'
assert_code "S401 unmatched task-started"   S401 'printf "\\n### 2026-01-02 11:30Z — task-started P1.2\\n\\n- Evidence: begun\\n" >> "$m/LEDGER.md"'
# `delegated` closes a task and is the corpus's second most common event. Listing
# closers by name reported every delegated task as an unclosed crash.
assert_code "S401 silent when delegated closes" - \
  'printf "\\n### 2026-01-02 11:30Z — task-started P1.2\\n\\n- Evidence: begun\\n\\n### 2026-01-02 11:40Z — delegated P1.2\\n\\n- Evidence: handed to a worker\\n" >> "$m/LEDGER.md"'

# ── next: the distinction that caused a 3x over-report ────────────────────────
d=$TMP_ROOT/nextcase
build "$d"
out=$(/bin/bash "$CHECKER" next --root "$d" --layer claude 2>&1)
# The header reports the mission's own status. It printed the last task's row
# state for a while, because disposition_for reused the caller's `st` variable.
if printf '%s\n' "$out" | grep -q 'sample-mission \[running\]'; then
  pass "next header reports the mission status, not a task row state"
else
  fail "next header reports the mission status, not a task row state" "$out"
fi
if printf '%s\n' "$out" | grep -q 'runnable P1.2'; then
  pass "next reports a task whose only dependency is satisfied"
else
  fail "next reports a task whose only dependency is satisfied" "$out"
fi
if printf '%s\n' "$out" | grep -q 'waiting P2.1 impl/contract'; then
  pass "next names the unmet node rather than omitting the task"
else
  fail "next names the unmet node rather than omitting the task" "$out"
fi
# The obligation to record a narrower selection is stated where the selection is
# made. With one runnable task there is no choice to justify, so it must be
# absent — an obligation printed unconditionally is noise and gets tuned out.
if printf '%s\n' "$out" | grep -q 'requires a `wave-selected` LEDGER entry'; then
  fail "next states no obligation when only one task is runnable" "$out"
else
  pass "next states no obligation when only one task is runnable"
fi
sed -i 's|requires: impl/contract (IMPLEMENTATION)|requires: test/contract (TEST)|' \
  "$d/.claude/specs/2026-01-02-sample-mission/ROADMAP.md"
out=$(/bin/bash "$CHECKER" next --root "$d" --layer claude 2>&1)
if printf '%s\n' "$out" | grep -q 'Selecting fewer than 2 requires a `wave-selected`'; then
  pass "next states the obligation once a choice exists"
else
  fail "next states the obligation once a choice exists" "$out"
fi

printf -- '- [ ] P9.9 Appended without a node (verify: x)\n' >>"$d/.claude/specs/2026-01-02-sample-mission/ROADMAP.md"
out=$(/bin/bash "$CHECKER" next --root "$d" --layer claude 2>&1)
if printf '%s\n' "$out" | grep -q 'unmodelled P9.9'; then
  pass "next separates an unscheduled task from a runnable one"
else
  fail "next separates an unscheduled task from a runnable one" "$out"
fi

# ── disjoint.sh ───────────────────────────────────────────────────────────────
w=$TMP_ROOT/tree/src
mkdir -p "$w"
for ext in sh ts vue yaml go; do
  printf 'x\n' >"$w/shared.$ext"
  printf 'y\n' >"$w/only.$ext"
done
for ext in sh ts vue yaml go; do
  /bin/bash "$DISJOINT" "$TMP_ROOT/tree" "A:src/shared.$ext" "B:src/shared.$ext" >/dev/null 2>&1
  if [ "$?" = 1 ]; then
    pass "disjoint sees an overlap in .$ext"
  else
    fail "disjoint sees an overlap in .$ext"
  fi
done
/bin/bash "$DISJOINT" "$TMP_ROOT/tree" 'A:src/only.ts' 'B:src/only.vue' >/dev/null 2>&1
[ "$?" = 0 ] && pass "disjoint clears a genuinely separate pair" ||
  fail "disjoint clears a genuinely separate pair"
/bin/bash "$DISJOINT" "$TMP_ROOT/tree" 'A:absent/**' 'B:src/only.ts' >/dev/null 2>&1
[ "$?" = 2 ] && pass "disjoint fails closed when a query matches nothing" ||
  fail "disjoint fails closed when a query matches nothing"

printf '1..%s\n' "$PASS_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf 'FAIL: %s assertion(s) failed\n' "$FAIL_COUNT" >&2
  exit 1
fi
printf 'PASS: %s assertions\n' "$PASS_COUNT"
