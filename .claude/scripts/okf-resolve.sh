#!/usr/bin/env bash
# okf-resolve.sh — prints the resolved path to the `okf` binary (okf-agent-memory CLI), per D13.
#
# Resolution order (first hit wins): $CLAUDART_OKF_BIN -> <repo>/.claude/scripts/bin/okf -> `okf`
# on PATH. Prints exactly one line (the absolute path) and exits 0 on success; on failure prints
# "okf binary required" to stderr and exits 1. Never prints a path and exits nonzero, and never
# exits 0 without printing a path.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ -n "${CLAUDART_OKF_BIN:-}" ] && [ -x "${CLAUDART_OKF_BIN}" ]; then
  printf '%s\n' "${CLAUDART_OKF_BIN}"
  exit 0
fi

VENDORED="${HERE}/bin/okf"
if [ -x "${VENDORED}" ]; then
  printf '%s\n' "${VENDORED}"
  exit 0
fi

if command -v okf >/dev/null 2>&1; then
  command -v okf
  exit 0
fi

printf 'okf binary required\n' >&2
exit 1
