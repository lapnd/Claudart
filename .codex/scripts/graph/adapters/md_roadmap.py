"""graph.adapters.md_roadmap — ROADMAP.md task/node parser.

The checkbox line is exactly `spec-workflow.md`'s: `- [ ] P1.2 <title> (verify: <cmd>)`, and the
existing states `[x]`, `~~superseded~~`, `⚠ blocked` stay untouched and parseable. Node metadata is
strictly ADDITIVE: six-space-indented continuation lines under the checkbox.

    - [ ] P2.1 PostgreSQL adapter (verify: go test ./internal/adapters/postgres/...)
          node: adapter/postgres-user | kind: adapter | tier: strong
          requires: port/user-repository (PORT), test/port-user-repository (TEST)
          paths: internal/adapters/postgres/**
          forbid: internal/adapters/smtp/**
          proves: <node-id>          # test nodes only
          exclusive: true            # needs a quiet tree
          early-ok: true             # deliberately independent of earlier phases

`## Phase N` headings give every node its phase. A pending task with no `node:` is returned in
`unanalysed` (D26) so lint can refuse to forget it. An optional header line `graph-format: N` is
checked against the supported format.
"""

import re

from graph.core.graph import Node, EDGE_TYPES, GRAPH_FORMAT

TASK_RE = re.compile(r"^- \[(?P<box> |x)\] (?P<strike>~~)?(?P<tid>P\d+\.\d+[a-z]?) (?P<rest>.*)$")
META_RE = re.compile(r"^ {6}(?P<key>node|kind|tier|requires|paths|forbid|proves|exclusive|early-ok): (?P<val>.*)$")
REQ_RE = re.compile(r"^(?P<dep>[^()]+?) \((?P<etype>[A-Z]+)\)$")
PHASE_RE = re.compile(r"^## Phase (?P<n>\d+)")
FORMAT_RE = re.compile(r"^graph-format: (?P<n>\d+)")
BLOCKED = "⚠ blocked"


class RoadmapError(ValueError):
    pass


TIER_TAIL_RE = re.compile(r"\s*\(tier: (?P<tier>[a-z]+)\)\s*$")
MARKER_TAIL_RE = re.compile(r"\s*(?:~~)?\s*— (?:⚠ blocked|superseded).*$")


def split_task_rest(rest):
    """title, verify, tier from everything after the task id. verify runs from the LAST
    `(verify: ` to the final `)`, so shell commands containing parentheses/subshells survive."""
    rest = MARKER_TAIL_RE.sub("", rest.rstrip())
    rest = rest.rstrip("~").rstrip()
    tier = None
    tm = TIER_TAIL_RE.search(rest)
    if tm:
        tier = tm.group("tier")
        rest = rest[:tm.start()].rstrip()
    verify = None
    i = rest.rfind("(verify: ")
    if i >= 0 and rest.endswith(")"):
        verify = rest[i + len("(verify: "):-1]
        rest = rest[:i].rstrip()
    return rest.strip(), verify, tier


MD_ESCAPE_RE = re.compile(r"\\([\\`*_{}\[\]()#+\-.!|<>~])")


def unescape_md(value):
    r"""Prettier (and humans) backslash-escape `*`, `_`, `#`, ... inside markdown text, so a path
    query `internal/**` is stored on disk as `internal/\*\*`. Both spellings must resolve to the same
    query, or a formatter run silently changes the schedule. Applied to every metadata value and
    to `verify:`."""
    return MD_ESCAPE_RE.sub(r"\1", value) if value else value


def parse(text):
    """Return (nodes, errors, unanalysed). Errors are strings; they never stop parsing.
    `parse_with_ticks` additionally returns the set of node ids whose checkbox is `[x]`."""
    return parse_with_ticks(text)[:3]


def parse_with_ticks(text):
    nodes, errors, unanalysed, ticked = [], [], [], set()
    cur = None
    phase = 0

    def flush():
        if cur is None:
            return
        if cur.get("node"):
            if cur["done"]:
                ticked.add(cur["node"])
            if "/" not in cur["node"]:
                errors.append("%s: node %r has no <kind>/ prefix" % (cur["tid"], cur["node"]))
            nodes.append(Node(
                id=cur["node"], kind=cur.get("kind") or cur["node"].split("/", 1)[0],
                task=cur["tid"], title=cur["title"], verify=cur["verify"],
                requires=cur["requires"], paths=cur["paths"], forbid=cur["forbid"],
                proves=cur["proves"], tier=cur.get("tier"), phase=cur["phase"],
                exclusive=cur["exclusive"], early_ok=cur["early_ok"]))
        elif not cur["done"] and not cur["struck"] and not cur["blocked"]:
            unanalysed.append((cur["tid"], cur["title"]))

    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        fm = FORMAT_RE.match(line)
        if fm and int(fm.group("n")) != GRAPH_FORMAT:
            raise RoadmapError("line %d: graph-format %s is not supported (this engine reads %d)" % (lineno, fm.group("n"), GRAPH_FORMAT))
        pm = PHASE_RE.match(line)
        if pm:
            phase = int(pm.group("n"))
        m = TASK_RE.match(line)
        if m:
            flush()
            title, verify, tier = split_task_rest(m.group("rest"))
            cur = {"tid": m.group("tid"), "title": title, "verify": unescape_md(verify),
                   "requires": [], "paths": [], "forbid": [], "proves": None, "phase": phase,
                   "exclusive": False, "early_ok": False, "done": m.group("box") == "x", "tier": tier,
                   "struck": bool(m.group("strike")), "blocked": BLOCKED in line}
            if not cur["verify"] and not cur["struck"]:
                errors.append("%s: task has no verify:" % cur["tid"])
            continue
        mm = META_RE.match(line)
        if not mm:
            if line.strip() and not line.startswith(" "):
                flush()
                cur = None
            continue
        if cur is None:
            errors.append("line %d: node metadata with no owning task" % lineno)
            continue
        key, val = mm.group("key"), unescape_md(mm.group("val").strip())
        if key in ("node", "kind", "tier"):
            for part in val.split("|"):
                part = part.strip()
                if ":" in part:
                    k, _, v = part.partition(":")
                    cur[k.strip()] = v.strip()
                else:
                    cur[key] = part
        elif key == "proves":
            cur["proves"] = val
        elif key in ("exclusive", "early-ok"):
            cur[key.replace("-", "_")] = val.lower() == "true"
        elif key == "requires":
            for part in [p.strip() for p in val.split(",") if p.strip()]:
                rm = REQ_RE.match(part)
                if not rm:
                    errors.append("%s: malformed requires %r" % (cur["tid"], part))
                elif rm.group("etype") not in EDGE_TYPES:
                    errors.append("%s: unknown edge type %s" % (cur["tid"], rm.group("etype")))
                else:
                    cur["requires"].append((rm.group("dep").strip(), rm.group("etype")))
        else:
            cur[key] = [p.strip() for p in val.split(",") if p.strip()]
    flush()
    return nodes, errors, unanalysed, ticked
