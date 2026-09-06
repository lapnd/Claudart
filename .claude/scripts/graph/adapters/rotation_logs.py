"""graph.adapters.rotation_logs — read the cost/liveness record a rotation successor leaves behind.

`claudart-rotate.sh` launches each successor with `claude -p … --output-format json`, so every
`<spec>/artifacts/rotations/<ts>.log` is a single result-JSON object carrying `total_cost_usd`,
`usage.input_tokens`/`output_tokens`, `num_turns`, `duration_ms`, and error/limit signals. This
adapter reads those files; the pure summary lives in `core/retro.py`. A file that does not parse is
reported UNREADABLE, never guessed at (a truncated log means the successor was killed mid-write).
"""

import json
import os

Record = None  # records are plain dicts so core/retro stays import-free

# substrings that mark a run that ended because the account hit a usage/rate limit
_LIMIT_MARKERS = ("usage limit", "rate limit", "rate_limit", "usage_limit", "quota")


def _is_rate_limited(obj):
    if not isinstance(obj, dict):
        return False
    if obj.get("subtype") in ("error_usage_limit", "error_rate_limit"):
        return True
    blob = " ".join(str(obj.get(k, "")) for k in ("result", "error", "subtype")).lower()
    return bool(obj.get("is_error")) and any(m in blob for m in _LIMIT_MARKERS)


def read_rotation_logs(rotations_dir):
    """(records, unreadable): one record dict per parseable log, basenames of the rest.

    A record is {cost, tokens_in, tokens_out, turns, rate_limited, file}. Missing numeric fields
    read as 0 rather than raising — a valid result JSON with an absent cost is still a real run."""
    records, unreadable = [], []
    if not os.path.isdir(rotations_dir):
        return records, unreadable
    for name in sorted(os.listdir(rotations_dir)):
        if not name.endswith(".log"):
            continue
        path = os.path.join(rotations_dir, name)
        try:
            with open(path, encoding="utf-8") as fh:
                obj = json.loads(fh.read())
        except (ValueError, OSError):
            unreadable.append(name)
            continue
        if not isinstance(obj, dict):
            unreadable.append(name)
            continue
        usage = obj.get("usage") if isinstance(obj.get("usage"), dict) else {}
        records.append({
            "file": name,
            "cost": float(obj.get("total_cost_usd") or 0),
            "tokens_in": int(usage.get("input_tokens") or 0),
            "tokens_out": int(usage.get("output_tokens") or 0),
            "turns": int(obj.get("num_turns") or 0),
            "rate_limited": _is_rate_limited(obj),
        })
    return records, unreadable
