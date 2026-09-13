#!/bin/bash

# Pairwise file-overlap matrix for candidate parallel tasks.
#
# A dependency graph says two tasks have no edge between them. It does not say
# they can run at once: they may still write the same files. This measures that
# one question and nothing else.
#
# Read this before using the result:
#
#   Overlap is rule 1 of three. Rule 2 is output dependency — one task's result
#   changes what another should produce. Rule 3 is ordering, INCLUDING the plan's
#   own phase order. Neither is decidable here, and both have made finished work
#   unmergeable. A clean matrix is necessary, never sufficient.
#
# Both directions of the mistake cost real time on a downstream workspace in one
# day: two tasks declared serial from package-level reasoning turned out to touch
# 31 and 49 files with zero intersection, and two others run in parallel on a
# clean file measurement were both unmergeable because ordering was skipped.
#
# A task supplies a QUERY, never a file list. A list is today's answer and rots
# in silence; a pattern is resolved against the tree on every run. This is the
# same `paths:` a ROADMAP task already declares.
#
# Usage:
#   disjoint.sh <repo> <label>:<glob>[,<glob>...] <label>:<glob>[,...] ...
#   disjoint.sh --roadmap <ROADMAP.md> <repo> <taskid> <taskid> ...
#
# Exit: 0 every pair disjoint · 1 at least one pair overlaps · 2 cannot run

set -u

LC_ALL=C
export LC_ALL

PROGRAM=${0##*/}

die() {
  printf '%s: CANNOT RUN — %s\n' "$PROGRAM" "$1" >&2
  exit 2
}

usage() {
  sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
}

ROADMAP=
case "${1:-}" in
  --help | -h)
    usage
    exit 0
    ;;
  --roadmap)
    [ "$#" -ge 2 ] || die "--roadmap requires a ROADMAP.md path"
    ROADMAP=$2
    [ -f "$ROADMAP" ] || die "no roadmap at $ROADMAP"
    shift 2
    ;;
esac

[ "$#" -ge 3 ] || die "need a repo and at least two tasks to compare"
REPO=$1
shift
[ -d "$REPO" ] || die "no repo at $REPO"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudart-disjoint.XXXXXX") || die "cannot create a temporary directory"
# Invoked indirectly by trap.
# shellcheck disable=SC2329
cleanup() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"; }
trap cleanup EXIT

LABELS=""

# Resolve one comma-separated glob list against the tree. Language-agnostic by
# construction: it matches path names, so a `.sh`, `.ts`, `.vue` or `.yaml` file
# is as visible as any other. A content-grep restricted to one language was the
# recorded blind spot of the tool this replaces.
resolve() {
  label=$1
  queries=$2
  out=$TMP/$label.files
  : >"$out"
  # The trailing newline matters: without it `read` returns false on the final
  # field and the loop body never runs, which silently resolved every query to
  # the empty set and made every pair look disjoint.
  printf '%s\n' "$queries" | tr ',' '\n' | while IFS= read -r q || [ -n "$q" ]; do
    q=$(printf '%s' "$q" | sed 's/^[ \t]*//; s/[ \t]*$//')
    [ -n "$q" ] || continue
    (
      cd "$REPO" || exit 0
      find . -type f -path "./$q" 2>/dev/null
      find . -type f -path "./$q/*" 2>/dev/null
    )
  done | sed 's|^\./||' | LC_ALL=C sort -u >"$out"
}

for arg in "$@"; do
  if [ -n "$ROADMAP" ]; then
    label=$arg
    queries=$(awk -v want="$label" '
      /^-[ \t]+\[/ { id = $3; sub(/^~~/, "", id) }
      /^[ \t]+paths:/ && id == want {
        body = $0
        sub(/^[ \t]*paths:[ \t]*/, "", body)
        print body
        exit
      }
    ' "$ROADMAP")
    [ -n "$queries" ] || die "task '$label' declares no paths: in $ROADMAP"
  else
    case "$arg" in *:*) ;; *) die "argument '$arg' is not <label>:<glob>" ;; esac
    label=${arg%%:*}
    queries=${arg#*:}
    [ -n "$label" ] || die "empty label in '$arg'"
    [ -n "$queries" ] || die "empty query in '$arg'"
  fi

  resolve "$label" "$queries"
  n=$(wc -l <"$TMP/$label.files" | tr -d ' ')
  # Fail closed. An empty set means a wrong pattern far more often than a task
  # that touches nothing, and a silent empty set makes every pair look disjoint.
  [ "$n" -gt 0 ] || die "query for '$label' matched nothing: $queries"
  LABELS="$LABELS $label"
  printf '%-22s %5s files\n' "$label" "$n"
done

printf '\n'
overlap=0
set -- $LABELS
while [ "$#" -gt 1 ]; do
  a=$1
  shift
  for b in "$@"; do
    common=$(LC_ALL=C comm -12 "$TMP/$a.files" "$TMP/$b.files" | wc -l | tr -d ' ')
    if [ "$common" -gt 0 ]; then
      printf 'OVERLAP  %-20s %-20s %s file(s)\n' "$a" "$b" "$common"
      LC_ALL=C comm -12 "$TMP/$a.files" "$TMP/$b.files" | head -5 | sed 's/^/           /'
      overlap=1
    else
      printf 'disjoint %-20s %-20s\n' "$a" "$b"
    fi
  done
done

printf '\n'
if [ "$overlap" = 1 ]; then
  printf 'At least one pair shares files. Those two cannot run concurrently.\n'
else
  printf 'No pair shares a file. This clears rule 1 only — output dependency and\n'
  printf 'ordering, including the plan phase order, remain yours to decide.\n'
fi
exit "$overlap"
