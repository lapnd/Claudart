#!/bin/bash

# claudart-rotate.sh -- launch the successor session of an autonomous spec run.
#
#   bash .claude/scripts/claudart-rotate.sh <slug-or-dated-id> [--dry-run]
#
# This script is the only place in CLAUDART that starts an unattended Claude
# session, so every guard here is a safety property, not a convenience:
#
#   * Rotation ceiling. An unattended chain rotates itself; without a hard cap a
#     mission that never reaches its final gate keeps launching successors
#     forever. The count of rotation logs already written IS the number of
#     rotations so far, so the ceiling is derived from durable evidence on disk
#     rather than from a counter a crashed session could forget to bump.
#   * Status gate. A spec that is not `ready` or `running` (drafting, poc-review,
#     blocked, done) must never be re-launched: the successor would either work
#     against an unapproved plan or redo finished work.
#   * Double-launch guard. A rotation log younger than 60 s means a successor was
#     just started -- almost certainly this same launcher firing twice (a retried
#     hook, a double keypress, two parallel loops). Two sessions editing one spec
#     folder corrupt each other's LEDGER and ROADMAP, so the second one refuses.
#
# Permission posture: the successor runs with --permission-mode acceptEdits by
# default. This script NEVER adds a permission bypass on its own; a bypass can
# only appear via CLAUDART_ROTATE_EXTRA_ARGS, which is the user's explicit act.
#
# Why --allowedTools exists here (measured 2026-09-06, Lessons IV): a headless
# `claude -p` session cannot show a permission prompt, so anything that would
# prompt is denied. acceptEdits auto-accepts file edits only; a Bash call such
# as `bash .claude/scripts/claudart-graph.sh …` is DENIED and the successor
# stalls on its first engine call. A compound command is allowed only when
# every segment matches a pattern, so the default list below is a narrow prefix
# toolkit: the engine wraps every arbitrary `verify:` behind a single allowed
# prefix (`claudart-graph.sh event … --run`). Nothing destructive or networked
# (rm, curl, sudo, git push, git reset) is in the default; extend it via
# CLAUDART_ROTATE_ALLOWED_TOOLS when a mission's verify lines need more.
#
# Environment:
#   CLAUDART_SPECS_ROOT             specs root (default <repo>/.claude/specs)
#   CLAUDART_MAX_ROTATIONS          rotation ceiling (default 12; 0 always refuses)
#   CLAUDART_ROTATE_PERMISSION_MODE successor --permission-mode (default acceptEdits)
#   CLAUDART_ROTATE_EXTRA_ARGS      extra argv appended verbatim to the successor
#   CLAUDART_ROTATE_ALLOWED_TOOLS   comma-separated --allowedTools patterns for the
#                                   successor (default: the deterministic loop toolkit
#                                   listed in DEFAULT_ALLOWED_TOOLS below)
#
# Exit codes: 0 launched (or dry run), 1 refused by a guard, 2 not found / no `claude`.

set -u

PROGRAM=${0##*/}

# The repo root comes from this script's own location, never from cwd: rotation
# is triggered from wherever the previous session happened to be standing.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SPECS=${CLAUDART_SPECS_ROOT:-$ROOT/.claude/specs}
MAX_ROTATIONS=${CLAUDART_MAX_ROTATIONS:-12}
PERM=${CLAUDART_ROTATE_PERMISSION_MODE:-acceptEdits}
EXTRA=${CLAUDART_ROTATE_EXTRA_ARGS:-}

# The successor's Bash toolkit, one comma-joined --allowedTools argument (patterns
# contain spaces, so a space-separated list would be split into garbage). Prefix
# patterns only; each is a single command shape the spec loop is built on. Deliberately absent: rm, curl/wget, sudo,
# git push, git reset, git rebase.
DEFAULT_ALLOWED_TOOLS="Bash(bash .claude/scripts/*),Bash(bash tests/*),Bash(bash -n *),Bash(npm run *),Bash(npm test*),Bash(npx *),Bash(python3 *),Bash(pytest*),Bash(go *),Bash(make *),Bash(git status*),Bash(git diff*),Bash(git log*),Bash(git show*),Bash(git branch *),Bash(git worktree *),Bash(git merge *),Bash(git add *),Bash(git commit *),Bash(git checkout *),Bash(grep *),Bash(rg *),Bash(ls *),Bash(cat *),Bash(head *),Bash(tail *),Bash(wc *),Bash(sed -n *),Bash(find *),Bash(test *),Bash(mkdir *),Bash(cp *),Bash(mv *),Bash(date *),Bash(chmod +x *),Bash(echo *),Bash(printf *)"
ALLOWED=${CLAUDART_ROTATE_ALLOWED_TOOLS:-$DEFAULT_ALLOWED_TOOLS}

DRY_RUN=false
TARGET=

usage() {
  printf 'usage: %s <slug-or-dated-id> [--dry-run]\n' "$PROGRAM"
}

# Refusals are operator-facing output, so they go to stdout (the caller may be a
# log-capturing hook) and always carry a nonzero exit.
refuse() {
  printf 'refusing: %s\n' "$1"
  exit 1
}

die() {
  printf '%s: %s\n' "$PROGRAM" "$1"
  exit 2
}

while [ $# -gt 0 ]; do
  case $1 in
    --dry-run | -n)
      DRY_RUN=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      usage
      die "unknown option: $1"
      ;;
    *)
      if [ -n "$TARGET" ]; then
        usage
        die "unexpected extra argument: $1"
      fi
      TARGET=$1
      ;;
  esac
  shift
done

[ -n "$TARGET" ] || {
  usage
  die "no spec slug or dated id given"
}
[ -d "$SPECS" ] || die "specs root not found: $SPECS"

# Read one frontmatter key from a SPEC.md: only the leading `---` block is
# scanned, so a later body line cannot forge a status.
frontmatter_value() {
  awk -v key="$2" '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    {
      k = $0
      sub(/:.*/, "", k)
      if (k == key) {
        v = $0
        sub(/^[^:]*:[[:space:]]*/, "", v)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$1"
}

# 1) exact dated folder id, 2) frontmatter slug match. `done/` is an archive, not
# a candidate: a finished mission must never be resurrected by a stale rotation.
SPEC_DIR=
if [ "$TARGET" != "done" ] && [ -f "$SPECS/$TARGET/SPEC.md" ]; then
  SPEC_DIR="$SPECS/$TARGET"
else
  for candidate in "$SPECS"/*/; do
    [ -f "${candidate}SPEC.md" ] || continue
    case ${candidate%/} in
      "$SPECS/done") continue ;;
    esac
    if [ "$(frontmatter_value "${candidate}SPEC.md" slug)" = "$TARGET" ]; then
      SPEC_DIR=${candidate%/}
      break
    fi
  done
fi

[ -n "$SPEC_DIR" ] || die "no spec folder for '$TARGET' under $SPECS"

SPEC_FILE="$SPEC_DIR/SPEC.md"
SLUG=$(frontmatter_value "$SPEC_FILE" slug)
[ -n "$SLUG" ] || SLUG=$TARGET
STATUS=$(frontmatter_value "$SPEC_FILE" status)

case $STATUS in
  ready | running) ;;
  *) refuse "spec status is ${STATUS:-<unset>}, not ready/running" ;;
esac

ROTATIONS_DIR="$SPEC_DIR/artifacts/rotations"

# The logs on disk are the rotation counter.
ROTATION_COUNT=0
if [ -d "$ROTATIONS_DIR" ]; then
  ROTATION_COUNT=$(find "$ROTATIONS_DIR" -type f -name '*.log' 2>/dev/null | wc -l | tr -d '[:space:]')
  [ -n "$ROTATION_COUNT" ] || ROTATION_COUNT=0
fi

if [ "$ROTATION_COUNT" -ge "$MAX_ROTATIONS" ]; then
  refuse "rotation ceiling reached ($ROTATION_COUNT/$MAX_ROTATIONS)"
fi

# -mmin -1 is the portable spelling of "younger than 60 seconds" (BSD and GNU
# find both have it; -newermt does not exist everywhere).
if [ -d "$ROTATIONS_DIR" ]; then
  RECENT=$(find "$ROTATIONS_DIR" -type f -mmin -1 2>/dev/null | head -1)
  if [ -n "$RECENT" ]; then
    refuse "double launch — a rotation log is younger than 60 s"
  fi
fi

LOG="$ROTATIONS_DIR/$(date -u +%Y%m%dT%H%M%SZ).log"
PROMPT="/start then run /spec-run $SLUG"
COMMAND="claude -p \"$PROMPT\" --permission-mode $PERM --output-format json --allowedTools \"$ALLOWED\"${EXTRA:+ $EXTRA}"

if [ "$DRY_RUN" = true ]; then
  # Print only. No directory is created and no log file is written, so a dry run
  # can never itself trip the ceiling or the double-launch guard.
  printf 'dry-run: would launch successor for %s (%s)\n' "$SLUG" "$SPEC_DIR"
  printf 'command: %s\n' "$COMMAND"
  printf 'log: %s\n' "$LOG"
  exit 0
fi

command -v claude >/dev/null 2>&1 || die "\`claude\` not found on PATH; cannot launch a successor"

mkdir -p "$ROTATIONS_DIR" || die "cannot create $ROTATIONS_DIR"

# shellcheck disable=SC2086 # EXTRA is user-supplied argv and must word-split.
nohup claude -p "$PROMPT" --permission-mode "$PERM" --output-format json --allowedTools "$ALLOWED" $EXTRA </dev/null >"$LOG" 2>&1 &
PID=$!

# The clock, never a hardcoded stamp: the LEDGER is the mission's audit trail.
NOW=$(date -u +"%Y-%m-%d %H:%MZ")
{
  printf '\n### %s — rotation-checkpoint (auto)\n' "$NOW"
  printf -- '- log: %s\n' "$LOG"
  printf -- '- successor prompt: %s\n' "$PROMPT"
} >>"$SPEC_DIR/LEDGER.md"

printf 'launched successor: pid %s, log %s\n' "$PID" "$LOG"
exit 0
