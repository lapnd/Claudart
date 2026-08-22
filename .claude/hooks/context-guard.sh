#!/bin/bash

# CLAUDART context guard — PostToolUse hook.
#
# Measures the session transcript's byte size after every tool call and injects
# a CONTEXT-GUARD warning into the conversation when growth approaches the
# ~32MB API request-body cap that kills sessions unrecoverably (token-based
# auto-compact cannot see base64 images or raw accumulated bytes).
#
# Contract:
#   stdin   — PostToolUse JSON (session_id, transcript_path, ...)
#   stdout  — on threshold: {"hookSpecificOutput":{"hookEventName":"PostToolUse",
#             "additionalContext":"CONTEXT-GUARD WARN|ACT: ..."}}
#   silence — under thresholds: exit 0, no output
#   exit 2  — when the guard cannot measure (fail-VISIBLE, never blocking a
#             tool that already ran; the stderr line is the documented warning
#             channel)
#
# Thresholds (MB): CLAUDART_GUARD_WARN_MB (default 8), CLAUDART_GUARD_ACT_MB
# (default 16). Fires once per session per level; state lives in
# ${TMPDIR:-/tmp}/claudart-context-guard.d and degrades OPEN — if markers are
# unwritable the guard re-fires rather than staying silent (Decision Log,
# task 2026-08-22-001).

set -u

LC_ALL=C
export LC_ALL

STATE_DIR=${TMPDIR:-/tmp}/claudart-context-guard.d
WARN_MB=${CLAUDART_GUARD_WARN_MB:-8}
ACT_MB=${CLAUDART_GUARD_ACT_MB:-16}

die() {
  printf 'context-guard: %s\n' "$1" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 ||
  die 'jq is required but not installed; context-size guard is NOT running'

input=$(cat)

printf '%s' "$input" | jq -e . >/dev/null 2>&1 ||
  die 'stdin was not valid JSON; cannot measure session context'

sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -n "$sid" ] || die 'payload has no session_id; cannot measure session context'

tpath=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
[ -n "$tpath" ] ||
  die 'payload has no transcript_path; cannot measure session context'

[ -f "$tpath" ] || die "transcript not found at $tpath; cannot measure session context"

case $WARN_MB in
'' | *[!0-9]*) die "CLAUDART_GUARD_WARN_MB='$WARN_MB' is not a non-negative integer" ;;
esac
case $ACT_MB in
'' | *[!0-9]*) die "CLAUDART_GUARD_ACT_MB='$ACT_MB' is not a non-negative integer" ;;
esac

bytes=$(wc -c <"$tpath") || die "could not stat $tpath; cannot measure session context"
bytes=${bytes//[[:space:]]/}
mb=$((bytes / 1024 / 1024))

if [ "$bytes" -ge $((ACT_MB * 1024 * 1024)) ]; then
  level=ACT
elif [ "$bytes" -ge $((WARN_MB * 1024 * 1024)) ]; then
  level=WARN
else
  # Under thresholds — stay silent; exit 0 plain stdout is invisible by design.
  exit 0
fi

# Fire-once-per-session-per-level. Deliberate degrade-open: if the marker
# cannot be written we still fire (a repeated warning beats a silent guard),
# so the only suppressed outcome is the healthy duplicate-fire case.
safe_sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_')
marker=$STATE_DIR/$safe_sid-$level
if [ -e "$marker" ]; then
  exit 0
fi
mkdir -p -- "$STATE_DIR" 2>/dev/null
: >"$marker" 2>/dev/null

if [ "$level" = ACT ]; then
  message="CONTEXT-GUARD ACT: session transcript is ${mb}MB and closing on the 32MB API request-body limit where this session becomes unrecoverable. Do not start new work. Run /handoff NOW, then have the user open a fresh session and run /start."
else
  message="CONTEXT-GUARD WARN: session transcript reached ${mb}MB (warn ${WARN_MB}MB / act ${ACT_MB}MB; hard failure near 32MB). Avoid streaming large command output or base64 images into context; finish the current unit, then run /handoff and rotate to a fresh session."
fi

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
  "$message"
exit 0
