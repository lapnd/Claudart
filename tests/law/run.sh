#!/usr/bin/env bash
# tests/law/run.sh — runner for every law-suite test script.
#
# This file is created once (P1.6a) and never edited again: it is the entry point `npm run
# test:law` calls, so its contract must stay stable while suites are added underneath it.
#
# Contract:
#   - Executes every tests/law/[a-z]*.sh EXCEPT ITSELF, in name (lexicographic) order.
#   - Fails on the first suite that exits nonzero, reporting which suite failed.
#   - Excludes mutate.sh explicitly (see below) — it is not a self-contained suite.
#   - Prints which suite it is about to run before each one, and a final summary.
#   - Resolves its own directory and the repo root the same way tests/constitution/run.sh does,
#     so it works from any working directory.
#
# Fail-closed shell: set -u, no `|| true`, no `2>/dev/null`, exit status captured on the command's
# own line — never read through a pipe (verification-mechanics.md §1).

set -u
LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2

SELF=$(basename -- "$0")

# mutate.sh is EXCLUDED on purpose: it is a parameterised tool, `mutate.sh <group>` (groups: core |
# fold), not a self-contained suite. Invoked bare — which is what a blind glob-and-run would do —
# it prints usage and exits 2. It is driven per-node by the graph engine with an explicit group
# argument, not by this runner. Excluding it here is what keeps this runner safe to wire up as the
# `npm run test:law` entry point without the graph engine's own invocations tripping it.
EXCLUDE_MUTATE='mutate.sh'

RUN_COUNT=0
FAIL_COUNT=0
FAILED_SUITE=''

for suite in "$TEST_DIR"/[a-z]*.sh; do
  [ -e "$suite" ] || continue
  name=$(basename -- "$suite")
  [ "$name" = "$SELF" ] && continue
  [ "$name" = "$EXCLUDE_MUTATE" ] && continue

  RUN_COUNT=$((RUN_COUNT + 1))
  printf '==> running %s\n' "$name"
  bash "$suite"
  STATUS=$?
  if [ "$STATUS" -ne 0 ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_SUITE=$name
    printf '==> FAILED: %s (exit %d)\n' "$name" "$STATUS"
    break
  fi
  printf '==> ok: %s\n' "$name"
done

printf '\n%d suite(s) run, %d failed\n' "$RUN_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  printf 'first failing suite: %s\n' "$FAILED_SUITE"
  exit 1
fi
exit 0
