#!/bin/bash

# Layer integrity checks.
#
# CLAUDART's four layers are forked from one another, so a phrase carried across
# a fork keeps its old layer's vocabulary and stays wrong until someone reads it
# closely. This suite makes the three decidable cross-layer invariants fail loudly
# instead. Each assertion here exists because a real defect got through prose
# review: a whole layer shipped with an invocation form its harness does not
# accept, three specialist files were never loaded by anything, and a rule moved
# to another tier left a knowledge relation pointing at nothing.

set -u

LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2
cd "$REPO_ROOT" || exit 2

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok - %s\n' "$1" >&2
  if [ -n "${2:-}" ]; then
    printf '%s\n' "$2" | sed 's/^/  /' >&2
  fi
}

# Files belonging to one layer: its own directory, plus its prefixed skills.
layer_files() {
  layer=$1
  dir=$2
  find "$dir" -name '*.md' -type f 2>/dev/null
  find ".agents/skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' \
    -path "*/$layer-*" -type f 2>/dev/null
}

# ── 1. Invocation form does not cross a layer boundary ────────────────────────
#
# Codex reads `$name` (TOOL_MENTION_SIGIL), dsh reads `/name`, Pi reads
# `/skill:name`. A form borrowed from a sibling layer names a command the
# harness will never resolve.

check_form() {
  layer=$1
  dir=$2
  foreign_label=$3
  foreign_pattern=$4

  hits=$(layer_files "$layer" "$dir" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -Fq -e "$foreign_pattern" "$f" 2>/dev/null; then
      printf '%s: %s\n' "$f" "$(grep -c -F -e "$foreign_pattern" "$f")"
    fi
  done)

  if [ -z "$hits" ]; then
    pass "$layer layer uses no $foreign_label invocation form"
  else
    fail "$layer layer uses no $foreign_label invocation form" "$hits"
  fi
}

check_form codex ".codex" deepseek '/deepseek-'
check_form codex ".codex" pi '/skill:pi-'
check_form deepseek ".deepseek" codex '$codex-'
check_form deepseek ".deepseek" pi '/skill:pi-'
check_form pi ".pi" codex '$codex-'
check_form pi ".pi" deepseek '/deepseek-'

# Each layer must actually use its own form somewhere, or the check above would
# pass vacuously on an empty layer.
check_own_form() {
  layer=$1
  dir=$2
  own=$3
  n=$(layer_files "$layer" "$dir" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -c -F -e "$own" "$f" 2>/dev/null
  done | awk '{s+=$1} END {print s+0}')
  if [ "$n" -gt 0 ]; then
    pass "$layer layer uses its own invocation form ($n occurrences)"
  else
    fail "$layer layer uses its own invocation form" "found none of: $own"
  fi
}

check_own_form codex ".codex" '$codex-'
check_own_form deepseek ".deepseek" '/deepseek-'
check_own_form pi ".pi" '/skill:pi-'

# ── 2. A layer's files reference only its own layer directory ─────────────────
#
# A fork that still points at the directory it came from sends the agent to
# another layer's state.

check_no_cross_dir() {
  layer=$1
  dir=$2
  shift 2
  hits=""
  for other in "$@"; do
    found=$(layer_files "$layer" "$dir" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      if grep -Fq -e "$other" "$f" 2>/dev/null; then
        printf '%s -> %s\n' "$f" "$other"
      fi
    done)
    [ -n "$found" ] && hits="$hits$found
"
  done
  if [ -z "$hits" ]; then
    pass "$layer layer references no sibling layer directory"
  else
    fail "$layer layer references no sibling layer directory" "$hits"
  fi
}

check_no_cross_dir codex ".codex" ".deepseek/" ".pi/"
check_no_cross_dir deepseek ".deepseek" ".codex/" ".pi/"
check_no_cross_dir pi ".pi" ".codex/" ".deepseek/"

# ── 3. Every skill a command tells you to load actually exists ────────────────
#
# The workflow contracts load on demand, so a command's "load the X skill" line
# is the only thing that pulls in a read-only lock before work starts. A typo
# there fails silently: the session simply proceeds without the contract.

# Two unambiguous phrasings name a skill, and nothing else counts. Deciding
# intent from the sentence — never from whether the target happens to exist —
# is what lets this check fail when the target is missing.
#   commands:   Load the `x` skill ...
#   CLAUDE.md:  Load `x` before ...
LOADS=$( {
  grep -rhoE '[Ll]oad the `[a-z][a-z-]*` skill' .claude/commands .claude/CLAUDE.md 2>/dev/null
  grep -rhoE '[Ll]oad `[a-z][a-z-]*` before' .claude/CLAUDE.md 2>/dev/null
} | grep -oE '`[a-z][a-z-]*`' | tr -d '`' | sort -u)

missing=$(printf '%s\n' "$LOADS" | while IFS= read -r s; do
  [ -n "$s" ] || continue
  [ -f ".claude/skills/$s/SKILL.md" ] || printf '  %s -> .claude/skills/%s/SKILL.md\n' "$s" "$s"
done)
named=$(printf '%s\n' "$LOADS" | grep -c '[a-z]')

if [ -z "$missing" ] && [ "$named" -gt 0 ]; then
  pass "every skill named in a load instruction exists ($named distinct)"
elif [ "$named" -eq 0 ]; then
  fail "every skill named in a load instruction exists" "no load instruction found at all"
else
  fail "every skill named in a load instruction exists" "$missing"
fi

# Reverse direction: a workflow skill nobody is told to load can never enforce
# anything, because nothing pulls it in before the work starts.
unnamed=$(for d in .claude/skills/*/; do
  s=$(basename "$d")
  printf '%s\n' "$LOADS" | grep -qx "$s" ||
    printf '  %s has no load instruction\n' "$s"
done)
if [ -z "$unnamed" ]; then
  pass "every workflow skill has at least one load instruction"
else
  fail "every workflow skill has at least one load instruction" "$unnamed"
fi

printf '1..%s\n' "$PASS_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf 'FAIL: %s assertion(s) failed\n' "$FAIL_COUNT" >&2
  exit 1
fi
printf 'PASS: %s assertions\n' "$PASS_COUNT"
