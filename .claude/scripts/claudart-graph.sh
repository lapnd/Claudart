#!/usr/bin/env bash
# claudart-graph.sh — entry point for the deterministic development-graph engine.
#
# Resolves the engine from ITS OWN location, never from the caller's cwd (a drifted cwd has
# merged the wrong repository before). Exit codes are the engine's: 0 clean, 1 findings,
# 2 usage/parse/runtime failure. Requires python3 (stdlib only); absent -> exit 2 with a message.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v python3 >/dev/null 2>&1; then
  printf 'claudart-graph: python3 is required (stdlib only, no packages) and was not found on PATH\n' >&2
  exit 2
fi

PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}" exec python3 "$HERE/graph/adapters/cli.py" "$@"
