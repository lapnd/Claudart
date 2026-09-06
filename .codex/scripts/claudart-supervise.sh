#!/usr/bin/env bash
# claudart-supervise.sh — deterministic progress watchdog for an autonomous spec run (D43).
#
# Polls a mission's HEALTH line (from `claudart-graph progress`, which is file-derived and calls no
# model) and acts: a stalled chain is relaunched via claudart-rotate.sh; a rate-limited chain is
# backed off and re-polled until the limit lifts, then relaunched, so work resumes on its own after
# a limit clears instead of dying; a done/blocked mission ends the loop. The loop itself NEVER calls
# a model and NEVER adds a permission bypass — relaunch goes through claudart-rotate.sh, whose own
# 60-second and ceiling guards prevent a double or runaway launch. It is opt-in: nothing starts it.
#
# Usage:   claudart-supervise.sh <slug> [--dry-run]
#   --dry-run   print the health read and the single action that would be taken, then exit 0.
#
# Env:
#   CLAUDART_SPECS_ROOT          specs root (default <repo>/.claude/specs)
#   CLAUDART_SUPERVISE_INTERVAL  seconds between polls when running/stalled (default 300)
#   CLAUDART_SUPERVISE_MAX_BACKOFF  cap for the rate-limit backoff (default 3600)
#   CLAUDART_SUPERVISE_MAX_POLLS  stop after this many polls (default 0 = unbounded)
#
# Exit: 0 mission done / dry run, 1 a guard refused, 2 usage / spec not found.

set -u
PROGRAM=${0##*/}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
GRAPH="$HERE/claudart-graph.sh"
ROTATE="$HERE/claudart-rotate.sh"
SPECS=${CLAUDART_SPECS_ROOT:-$ROOT/.claude/specs}
INTERVAL=${CLAUDART_SUPERVISE_INTERVAL:-300}
MAX_BACKOFF=${CLAUDART_SUPERVISE_MAX_BACKOFF:-3600}
MAX_POLLS=${CLAUDART_SUPERVISE_MAX_POLLS:-0}

DRY_RUN=false
SLUG=
for a in "$@"; do
  case $a in
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) printf '%s: unknown option %s\n' "$PROGRAM" "$a" >&2; exit 2 ;;
    *) SLUG=$a ;;
  esac
done
[ -n "$SLUG" ] || { printf '%s: usage: %s <slug> [--dry-run]\n' "$PROGRAM" "$PROGRAM" >&2; exit 2; }

# Resolve the spec folder: exact dated-folder id, then a frontmatter slug match. Skip done/.
SPEC_DIR=
if [ -d "$SPECS/$SLUG" ]; then
  SPEC_DIR="$SPECS/$SLUG"
else
  for d in "$SPECS"/*/; do
    [ -f "${d}SPEC.md" ] || continue
    case $d in *"/done/"*) continue ;; esac
    if grep -qE "^slug: $SLUG\$" "${d}SPEC.md" 2>/dev/null; then SPEC_DIR="${d%/}"; break; fi
  done
fi
[ -n "$SPEC_DIR" ] && [ -d "$SPEC_DIR" ] || { printf '%s: no active spec for %s under %s\n' "$PROGRAM" "$SLUG" "$SPECS" >&2; exit 2; }

read_health() {
  # HEALTH line only; the engine computes it from files, so this costs no model call.
  HEALTH_LINE=$("$GRAPH" progress --dir "$SPEC_DIR" 2>/dev/null | grep -E '^HEALTH ' | head -1)
  STATE=$(printf '%s' "$HEALTH_LINE" | awk '{print $2}')
  [ -n "$STATE" ] || STATE=unknown
}

ledger() {
  # a supervisor action is auditable; append through the engine so the timestamp is the clock's.
  "$GRAPH" ledger supervisor "$SLUG" "$1" --dir "$SPEC_DIR" >/dev/null 2>&1 || true
}

decide() {
  # echo the single action for the current STATE. Backoff grows but is capped.
  case $STATE in
    done)         printf 'action: exit: done' ;;
    blocked)      printf 'action: exit: blocked' ;;
    rate-limited) printf 'action: back-off %ds' "$BACKOFF" ;;
    stalled)      printf 'action: relaunch' ;;
    running)      printf 'action: wait %ds' "$INTERVAL" ;;
    *)            printf 'action: wait %ds' "$INTERVAL" ;;
  esac
}

BACKOFF=$INTERVAL
read_health

if [ "$DRY_RUN" = true ]; then
  printf 'spec: %s\n' "$SPEC_DIR"
  printf 'health: %s\n' "$STATE"
  printf '%s\n' "$(decide)"
  exit 0
fi

POLLS=0
while :; do
  read_health
  POLLS=$((POLLS + 1))
  printf '[%s] health=%s %s\n' "$(date -u +%H:%M:%SZ)" "$STATE" "$(decide)"
  case $STATE in
    done)    ledger "watchdog: mission done, stopping"; exit 0 ;;
    blocked) ledger "watchdog: mission blocked, stopping"; exit 0 ;;
    stalled)
      ledger "watchdog: stalled, relaunching via claudart-rotate.sh"
      if [ -x "$ROTATE" ]; then "$ROTATE" "$SLUG" || true; fi
      BACKOFF=$INTERVAL
      SLEEP=$INTERVAL ;;
    rate-limited)
      ledger "watchdog: rate-limited, backing off ${BACKOFF}s then re-checking"
      SLEEP=$BACKOFF
      BACKOFF=$((BACKOFF * 2)); [ "$BACKOFF" -gt "$MAX_BACKOFF" ] && BACKOFF=$MAX_BACKOFF ;;
    *)
      BACKOFF=$INTERVAL
      SLEEP=$INTERVAL ;;
  esac
  [ "$MAX_POLLS" -gt 0 ] && [ "$POLLS" -ge "$MAX_POLLS" ] && { printf '%s: max polls reached\n' "$PROGRAM"; exit 0; }
  sleep "$SLEEP"
done
