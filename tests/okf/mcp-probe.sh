#!/usr/bin/env bash
# tests/okf/mcp-probe.sh — drive `okf mcp <bundle>` over stdio and print its tool list.
#
# Completes the MCP handshake (initialize -> notifications/initialized -> tools/list) against the
# resolved okf binary and prints one tool name per line on stdout. Exits 0 only when the handshake
# completed and at least one tool was returned; 1 on any protocol or resolution failure; 2 on usage.
#
# Fail-closed: no `|| true`, no `2>/dev/null`, and no exit status read through a pipe.

set -u
LC_ALL=C
export LC_ALL

PROGRAM=${0##*/}

if [ "$#" -ne 1 ]; then
  printf '%s: usage: %s <bundle-dir>\n' "$PROGRAM" "$PROGRAM" >&2
  exit 2
fi

BUNDLE=$1
if [ ! -d "$BUNDLE" ]; then
  printf '%s: not a directory: %s\n' "$PROGRAM" "$BUNDLE" >&2
  exit 2
fi

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." && pwd -P) || exit 2

OKF_BIN=$(bash "$REPO_ROOT/.claude/scripts/okf-resolve.sh")
RESOLVE_STATUS=$?
if [ "$RESOLVE_STATUS" -ne 0 ]; then
  printf '%s: okf binary required\n' "$PROGRAM" >&2
  exit 1
fi

python3 - "$OKF_BIN" "$BUNDLE" <<'PY'
import json
import subprocess
import sys

okf_bin, bundle = sys.argv[1], sys.argv[2]

proc = subprocess.Popen(
    [okf_bin, "mcp", bundle],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)


def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()


def read_result(want_id):
    """Read newline-delimited JSON until the response with `want_id` arrives."""
    while True:
        line = proc.stdout.readline()
        if line == "":
            return None
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("id") == want_id:
            return msg


def fail(message):
    proc.kill()
    proc.wait()
    sys.stderr.write("mcp-probe: %s\n" % message)
    sys.exit(1)


send({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "claudart-mcp-probe", "version": "1"},
    },
})
init = read_result(1)
if init is None or "result" not in init:
    fail("initialize did not return a result")

send({"jsonrpc": "2.0", "method": "notifications/initialized"})
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
listing = read_result(2)
if listing is None or "result" not in listing:
    fail("tools/list did not return a result")

tools = listing["result"].get("tools", [])
if not tools:
    fail("tools/list returned no tools")

server = init["result"].get("serverInfo", {}).get("name", "<unknown>")
print("serverInfo: %s" % server)
for tool in tools:
    print(tool.get("name", "<unnamed>"))

proc.stdin.close()
proc.terminate()
proc.wait()
PY
