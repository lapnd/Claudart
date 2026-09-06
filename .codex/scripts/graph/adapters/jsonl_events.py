"""graph.adapters.jsonl_events — the append-only event log, `<spec>/graph/events.jsonl`.

One JSON object per line, keys sorted. Written ONLY by the orchestrator in the main tree (D30): a
git worktree cannot see the gitignored spec folder, and concurrent appends longer than PIPE_BUF
(512 bytes on macOS) can interleave. Workers return structured output; they never call this.
"""

import json
import os
import time

from graph.core.graph import Event

FIELDS = ("ts", "node", "from", "to", "cmd", "exit", "evidence", "agent", "worktree", "commit",
          "model", "tokens_in", "tokens_out", "duration_s", "mutation")


class EventLogError(ValueError):
    pass


def read_events(path):
    out = []
    if not os.path.isfile(path):
        return out
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            if not line.strip():
                continue
            try:
                d = json.loads(line)
            except ValueError as exc:
                raise EventLogError("%s:%d: malformed event line (%s)" % (path, lineno, exc))
            if "node" not in d or "to" not in d or "ts" not in d:
                raise EventLogError("%s:%d: event missing ts/node/to" % (path, lineno))
            out.append(Event(d["ts"], d["node"], d.get("from"), d["to"], d.get("cmd"), d.get("exit"),
                             d.get("evidence"), d.get("agent"), d.get("worktree"), d.get("commit"),
                             d.get("model"), d.get("tokens_in"), d.get("tokens_out"),
                             d.get("duration_s"), d.get("mutation")))
    return out


def append_event(path, node, frm, to, cmd=None, exit_code=None, evidence=None, agent=None,
                 worktree=None, commit=None, model=None, tokens_in=None, tokens_out=None,
                 duration_s=None, mutation=None, ts=None):
    rec = {"ts": int(time.time()) if ts is None else ts, "node": node, "from": frm, "to": to,
           "cmd": cmd, "exit": exit_code, "evidence": evidence, "agent": agent, "worktree": worktree,
           "commit": commit, "model": model, "tokens_in": tokens_in, "tokens_out": tokens_out,
           "duration_s": duration_s, "mutation": mutation}
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, sort_keys=True) + "\n")
    return rec
