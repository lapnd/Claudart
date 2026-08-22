#!/bin/bash

# Scripted mutation pass for the context guard (evidence-gauntlet §5: persist
# the procedure, never hand-edit restores). Applies one mutant at a time to
# .claude/hooks/context-guard.sh, runs the behavior suite, and requires the
# suite to FAIL under every mutant (a surviving mutant = missing assertion).
# The guard is restored from a pristine in-script copy and verified by byte
# comparison — the file is untracked, so `git diff` cannot see it; cmp is the
# stronger check here.

set -u

LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2
GUARD=$REPO_ROOT/.claude/hooks/context-guard.sh
SUITE=$TEST_DIR/run.sh
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-guard-mutants.XXXXXX") || exit 2
PRISTINE=$TMP_ROOT/context-guard.pristine

# Invoked indirectly by trap.
# shellcheck disable=SC2329
cleanup() {
  if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf -- "$TMP_ROOT"
  fi
}
trap cleanup EXIT HUP INT TERM

cp -- "$GUARD" "$PRISTINE" || exit 2
KILLED=0
SURVIVED=0

restore() {
  cp -- "$PRISTINE" "$GUARD" || {
    printf 'FATAL: could not restore guard from pristine copy\n' >&2
    exit 3
  }
  if ! cmp -s -- "$GUARD" "$PRISTINE"; then
    printf 'FATAL: guard restore verification failed (cmp mismatch)\n' >&2
    exit 3
  fi
}

# run_mutant <name> <perl-substitution>
run_mutant() {
  restore
  if ! perl -pi -e "$2" -- "$GUARD"; then
    printf 'ERROR: mutant %s could not be applied\n' "$1" >&2
    exit 3
  fi
  if cmp -s -- "$GUARD" "$PRISTINE"; then
    printf 'ERROR: mutant %s changed nothing (bad substitution)\n' "$1" >&2
    exit 3
  fi
  if bash "$SUITE" >/dev/null 2>&1; then
    printf 'SURVIVED: %s\n' "$1"
    SURVIVED=$((SURVIVED + 1))
  else
    printf 'killed: %s\n' "$1"
    KILLED=$((KILLED + 1))
  fi
}

# M1 — flip the warn boundary comparison (-ge -> -gt): killed by T11.
run_mutant 'M1 warn-boundary -ge -> -gt' \
  's/-ge \$\(\(WARN_MB/-gt \$\(\(WARN_MB/'

# M2 — flip the act boundary comparison (-ge -> -gt): killed by T12.
run_mutant 'M2 act-boundary -ge -> -gt' \
  's/-ge \$\(\(ACT_MB/-gt \$\(\(ACT_MB/'

# M3 — invert the unhealthy branch (die exits 0): killed by T6/T7/T8/T13.
run_mutant 'M3 die exits 0 instead of 2' \
  's/^  exit 2$/  exit 0/'

# M4 — disable dedup (marker check never suppresses): killed by T3.
run_mutant 'M4 dedup disabled' \
  's/if \[ -e "\$marker" \]; then/if false; then/'

# M5 — swap warn/act escalation messages: killed by T2/T4/T5.
run_mutant 'M5 warn/act messages swapped' \
  's/if \[ "\$level" = ACT \]/if [ "\$level" = WARN ]/'

# M6 — neutralize threshold validation: killed by T13.
run_mutant 'M6 threshold validation removed' \
  "s/'' \\| \\*\\[!0-9\\]\\*\\)/__never__)/g"

restore

printf '\n%d killed, %d survived\n' "$KILLED" "$SURVIVED"
if [ "$SURVIVED" -eq 0 ]; then
  exit 0
fi
exit 1
