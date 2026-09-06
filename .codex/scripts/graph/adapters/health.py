"""graph.adapters.health — gather the scalars core/health_rule needs from a spec folder (D43).

Reads only files (ROADMAP ticks, the LEDGER tail timestamp, the rotation logs); the decision itself
is the pure function in core. This is what makes `progress`'s HEALTH line, and the watchdog that
polls it, deterministic and free of any model call."""

import os
import re
import time

from graph.adapters import rotation_logs
from graph.core import health_rule

DEFAULT_STALL_SECONDS = 1800

_TASK = re.compile(r"^- \[( |x)\] ", re.M)
_LEDGER_HEAD = re.compile(r"^### (\d{4}-\d{2}-\d{2}) (\d{2}):(\d{2})Z ", re.M)


def _roadmap_path(spec_dir):
    for name in ("ROADMAP.md", "ROADMAP.sample.md"):
        p = os.path.join(spec_dir, name)
        if os.path.isfile(p):
            return p
    return None


def _tasks(spec_dir):
    """(ticked, total) from the ROADMAP checkboxes."""
    p = _roadmap_path(spec_dir)
    if not p:
        return 0, 0
    with open(p, encoding="utf-8") as fh:
        boxes = _TASK.findall(fh.read())
    return sum(1 for b in boxes if b == "x"), len(boxes)


def _ledger_age_s(spec_dir, now):
    """Seconds since the last `### <ts> —` header in the LEDGER, or None."""
    p = os.path.join(spec_dir, "LEDGER.md")
    if not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8") as fh:
        heads = _LEDGER_HEAD.findall(fh.read())
    if not heads:
        return None
    day, hh, mm = heads[-1]
    try:
        t = time.strptime(day + " " + hh + ":" + mm, "%Y-%m-%d %H:%M")
    except ValueError:
        return None
    age = now - _to_epoch_utc(t)
    return age if age >= 0 else None


def _to_epoch_utc(t):
    import calendar
    return calendar.timegm(t)


def assess(spec_dir, stall_threshold_s=DEFAULT_STALL_SECONDS, now=None):
    """(state, detail) for a spec folder — detail carries the facts the state was decided from."""
    now = time.time() if now is None else now
    ticked, total = _tasks(spec_dir)
    all_done = total > 0 and ticked == total
    has_runnable = total > 0 and ticked < total
    recs, _ = rotation_logs.read_rotation_logs(os.path.join(spec_dir, "artifacts", "rotations"))
    rate_limited = bool(recs) and recs[-1].get("rate_limited", False)
    age = _ledger_age_s(spec_dir, now)
    has_blocked = _has_blocked(spec_dir)
    state = health_rule.health_state(all_done, rate_limited, has_blocked, has_runnable,
                                     age, stall_threshold_s)
    detail = {"ticked": ticked, "total": total, "ledger_age_s": age,
              "rate_limited": rate_limited, "blocked": has_blocked}
    return state, detail


def _has_blocked(spec_dir):
    p = _roadmap_path(spec_dir)
    if not p:
        return False
    with open(p, encoding="utf-8") as fh:
        return "⚠ blocked" in fh.read()
