"""graph.adapters.bookkeeping — the executor's repetitive edits as deterministic commands (D41).

Everything here used to be a hand-written edit per task: flip a checkbox, write a LEDGER entry from
the event that proved the task, bump SPEC `updated:`, rewrite the specs INDEX from frontmatter.
Same bytes, produced by code, with timestamps read from the clock.
"""

import os
import re
import time

FRONT_RE = re.compile(r"^---\n(.*?)\n---", re.S)


def utc_now(ts=None):
    return time.strftime("%Y-%m-%d %H:%MZ", time.gmtime(time.time() if ts is None else ts))


def read_frontmatter(spec_md):
    with open(spec_md, encoding="utf-8") as fh:
        text = fh.read()
    m = FRONT_RE.match(text)
    fm = {}
    if m:
        for line in m.group(1).splitlines():
            if ":" in line:
                k, _, v = line.partition(":")
                fm[k.strip()] = v.split("#", 1)[0].strip()
    return fm, text


def bump_updated(spec_md, day=None):
    fm, text = read_frontmatter(spec_md)
    day = day or time.strftime("%Y-%m-%d", time.gmtime())
    new = re.sub(r"^updated: .*$", "updated: %s" % day, text, count=1, flags=re.M)
    with open(spec_md, "w", encoding="utf-8") as fh:
        fh.write(new)
    return day


def append_ledger(ledger_md, event, scope, body_lines, ts=None):
    """Append one entry in spec-workflow.md's anatomy. `ts` may be given (tests); it must not be in
    the future — a typed timestamp that runs ahead of the clock is refused (Lessons VI.23)."""
    now = int(time.time())
    if ts is not None and ts > now + 60:
        raise ValueError("FUTURE-TIMESTAMP: %d is after now (%d) — timestamps are read, not typed" % (ts, now))
    stamp = utc_now(ts)
    with open(ledger_md, "a", encoding="utf-8") as fh:
        fh.write("\n### %s — %s %s\n\n" % (stamp, event, scope))
        for line in body_lines:
            fh.write("- %s\n" % line)
    return stamp


def tick_task(roadmap_md, task_id):
    """Flip `- [ ] <task_id> ` to `- [x]`. Returns True if exactly one line changed."""
    with open(roadmap_md, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    hits = [i for i, l in enumerate(lines) if l.startswith("- [ ] %s " % task_id)]
    if len(hits) != 1:
        return False
    lines[hits[0]] = "- [x]" + lines[hits[0]][5:]
    with open(roadmap_md, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    return True


def latest_terminal_event(events, node):
    for e in reversed(events):
        if e.node == node and e.to in ("done", "green", "confirmed", "refuted"):
            return e
    return None


def sync_index(specs_root):
    """Rewrite <specs_root>/INDEX.md from every SPEC.md frontmatter (spec-workflow.md format)."""
    active, done = [], []
    for name in sorted(os.listdir(specs_root)):
        p = os.path.join(specs_root, name, "SPEC.md")
        if name == "done" or not os.path.isfile(p):
            continue
        fm, _ = read_frontmatter(p)
        st = fm.get("status", "?")
        mark = " ⏳ awaiting your review" if st in ("poc-review", "awaiting-final-review") else ""
        active.append("- [%s](%s/SPEC.md) — %s — updated %s%s" % (fm.get("slug", name), name, st, fm.get("updated", "?"), mark))
    dd = os.path.join(specs_root, "done")
    if os.path.isdir(dd):
        for name in sorted(os.listdir(dd)):
            p = os.path.join(dd, name, "SPEC.md")
            if os.path.isfile(p):
                fm, _ = read_frontmatter(p)
                done.append("- [%s](done/%s/SPEC.md) — %s %s" % (fm.get("slug", name), name, fm.get("status", "?"), fm.get("updated", "?")))
    text = ("<!-- .claude/specs/INDEX.md — registry of spec missions. Maintained by /spec, /spec-run, /checkpoint.\n"
            "     SPEC.md frontmatter is the source of truth; this index is a convenience cache. -->\n\n"
            "## Active\n\n%s\n\n## Done\n\n%s\n") % ("\n".join(active) or "- _(no specs — run `/spec <mission description>` to create one)_",
                                                    "\n".join(done) or "- _(none)_")
    with open(os.path.join(specs_root, "INDEX.md"), "w", encoding="utf-8") as fh:
        fh.write(text)
    return len(active), len(done)


def phase_validation_command(roadmap_text, phase):
    m = re.search(r"^## Phase %d\b.*?(?=^## Phase |\Z)" % phase, roadmap_text, re.S | re.M)
    if not m:
        return None
    pv = re.search(r"\*\*Phase validation\*\*: (.*)$", m.group(0), re.M)
    return pv.group(1).strip() if pv else None
