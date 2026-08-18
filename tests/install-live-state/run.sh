#!/bin/bash

# Regression test for install.sh's live-state exclusion.
#
# CLAUDART dogfoods itself: it uses CLAUDART to improve CLAUDART, so this
# repo's own checked-in tree always carries real CONTEXT/JOURNAL/tasks/specs/
# knowledge content for THIS repo's sessions. install.sh must never copy that
# content into someone else's project — on a fresh install, on --upgrade, or
# under --force — only template-owned files may travel.
#
# This test exercises the ACTUAL copy_tree/copy_file/is_live_state_path
# functions as shipped in install.sh (extracted by section marker, not
# reimplemented), against a synthetic fixture tree standing in for a
# downloaded tarball. It also proves the check can fail: the same fixture run
# against install.sh as it existed just before this fix landed must leak the
# live-state files — that historical pre-fix revision is the negative
# control. Pinned to a specific commit, not HEAD: once the fix itself is
# committed, HEAD stops being "the buggy version" and a HEAD-relative
# negative control would permanently fail from that point on.

set -u

LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2
INSTALL_SH="$REPO_ROOT/install.sh"

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

if /bin/bash -n "$TEST_DIR/run.sh"; then
  pass "Bash syntax is valid"
else
  fail "Bash syntax is valid"
fi

if [ ! -f "$INSTALL_SH" ]; then
  fail "install.sh exists"
  printf '1..%s\n' $((PASS_COUNT + FAIL_COUNT))
  exit 1
fi
pass "install.sh exists"

# Extracts the color helpers + is_template_path/is_live_state_path/copy_file/
# copy_file_from_src/copy_tree function bodies from a given install.sh
# revision (by section-comment markers, so it survives unrelated line drift)
# into a sourceable file. Never re-implements the logic under test.
extract_functions() {
  _src=$1
  _out=$2
  _helpers_start=$(grep -n '^# ── helpers ──' "$_src" | head -1 | cut -d: -f1)
  _helpers_end=$(grep -n '^# ── arg parsing ──' "$_src" | head -1 | cut -d: -f1)
  _copy_start=$(grep -n '^is_template_path() {' "$_src" | head -1 | cut -d: -f1)
  _copy_end=$(grep -n '^# ── install ──' "$_src" | head -1 | cut -d: -f1)
  if [ -z "$_helpers_start" ] || [ -z "$_helpers_end" ] || [ -z "$_copy_start" ] || [ -z "$_copy_end" ]; then
    return 1
  fi
  : > "$_out"
  sed -n "${_helpers_start},$((_helpers_end - 1))p" "$_src" >> "$_out"
  sed -n "${_copy_start},$((_copy_end - 1))p" "$_src" >> "$_out"
}

# Builds a fixture tree standing in for a downloaded tarball: one
# template-owned file and a representative live-state file per excluded
# category, under both the Claude and Codex layers.
build_fixture() {
  _root=$1
  mkdir -p "$_root/.claude/commands" "$_root/.claude/tasks" "$_root/.claude/specs" "$_root/.claude/knowledge"
  mkdir -p "$_root/.codex/guidelines" "$_root/.codex/tasks" "$_root/.codex/specs" "$_root/.codex/knowledge"

  echo "template command" > "$_root/.claude/commands/start.md"
  echo "dogfood context" > "$_root/.claude/CONTEXT.md"
  echo "dogfood journal" > "$_root/.claude/JOURNAL.md"
  echo "dogfood task" > "$_root/.claude/tasks/2026-08-14-001-evidence-gauntlet.md"
  echo "dogfood spec index" > "$_root/.claude/specs/INDEX.md"
  echo "dogfood knowledge" > "$_root/.claude/knowledge/codex-mirror-pattern.md"

  echo "template guideline" > "$_root/.codex/guidelines/ai-behavior.md"
  echo "dogfood context" > "$_root/.codex/CONTEXT.md"
  echo "dogfood task" > "$_root/.codex/tasks/index.md"
}

# Runs copy_tree ".claude" and copy_tree ".codex" from a sourced function set
# against a fresh fixture, as a genuine fresh install (FORCE=false,
# UPGRADE=false, empty destination). Prints the destination tree so a human
# can see exactly what would have landed in a user's project.
run_fresh_install() {
  _funcs=$1
  _tmpdir=$2
  _dest=$3

  # shellcheck disable=SC1090
  (
    TMPDIR="$_tmpdir"
    DEST="$_dest"
    FORCE=false
    UPGRADE=false
    SKIPPED=0
    COPIED=0
    UPGRADED=0
    UNCHANGED=0
    EXCLUDED=0
    . "$_funcs"
    copy_tree ".claude"
    copy_tree ".codex"
  ) >/dev/null 2>&1
}

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT

FUNCS_CURRENT="$WORK/funcs-current.sh"
FUNCS_PREFIX="$WORK/funcs-prefix.sh"
FIXTURE="$WORK/fixture"
DEST_CURRENT="$WORK/dest-current"
DEST_PREFIX="$WORK/dest-prefix"

build_fixture "$FIXTURE"

# ── negative control: the pre-fix script must leak live state ──────────────
# c2d623b is the "fix(install): never ship ... live state" commit; its parent
# is the last revision without is_live_state_path(). A fixed commit reference
# survives the fix itself being committed, unlike HEAD.
PREFIX_REV=c2d623b~1
if git -C "$REPO_ROOT" show "$PREFIX_REV:install.sh" > "$WORK/install-prefix.sh" 2>/dev/null; then
  if extract_functions "$WORK/install-prefix.sh" "$FUNCS_PREFIX"; then
    mkdir -p "$DEST_PREFIX"
    run_fresh_install "$FUNCS_PREFIX" "$FIXTURE" "$DEST_PREFIX"
    if [ -f "$DEST_PREFIX/.claude/CONTEXT.md" ]; then
      pass "negative control: pre-fix install.sh ($PREFIX_REV) leaks .claude/CONTEXT.md — the check can fail"
    else
      fail "negative control: pre-fix install.sh ($PREFIX_REV) leaks .claude/CONTEXT.md — the check can fail"
    fi
  else
    fail "negative control: could not extract functions from $PREFIX_REV:install.sh"
  fi
else
  fail "negative control: could not read $PREFIX_REV:install.sh (history rewritten or shallow clone?)"
fi

# ── current working tree: live state must never land in the destination ───
if extract_functions "$INSTALL_SH" "$FUNCS_CURRENT"; then
  pass "extracted copy_tree/copy_file/is_live_state_path from current install.sh"
else
  fail "extracted copy_tree/copy_file/is_live_state_path from current install.sh"
  printf '1..%s\n' $((PASS_COUNT + FAIL_COUNT))
  exit 1
fi

mkdir -p "$DEST_CURRENT"
run_fresh_install "$FUNCS_CURRENT" "$FIXTURE" "$DEST_CURRENT"

for live in \
  .claude/CONTEXT.md \
  .claude/JOURNAL.md \
  .claude/tasks/2026-08-14-001-evidence-gauntlet.md \
  .claude/specs/INDEX.md \
  .claude/knowledge/codex-mirror-pattern.md \
  .codex/CONTEXT.md \
  .codex/tasks/index.md \
; do
  if [ -f "$DEST_CURRENT/$live" ]; then
    fail "fresh install never copies $live"
  else
    pass "fresh install never copies $live"
  fi
done

for tmpl in .claude/commands/start.md .codex/guidelines/ai-behavior.md; do
  if [ -f "$DEST_CURRENT/$tmpl" ]; then
    pass "fresh install still copies template-owned $tmpl"
  else
    fail "fresh install still copies template-owned $tmpl"
  fi
done

printf '1..%s\n' $((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
