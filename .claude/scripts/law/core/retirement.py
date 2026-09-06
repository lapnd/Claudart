"""law.core.retirement — the D5 fail-soft retirement tiers (SCHEMA.md section 3).

Pure (D15): `today` is always a parameter. Nothing here reads a clock, so the same record and
the same date always produce the same answer.

Code emitted here: EXPIRED (a queue item; on its own it never fails `validate`).
"""

import calendar
from datetime import date

from law.core.schema import Finding

# Default stale_after offset from `since`, applied only when stale_after is derived.
DERIVED_OFFSET_MONTHS = {"core": 12, "standard": 12, "provisional": 6}

# Days past the effective stale_after before the compiled line is marked; None = never marked.
GRACE_DAYS = {"core": None, "standard": 30, "provisional": 0}

MARKING = "⚠ expired %s, re-verification pending — "


def derive_stale_after(record):
    """The record's effective stale_after as an absolute ISO instant. Explicit always wins."""
    explicit = record.get("stale_after")
    if explicit is not None:
        return explicit
    since = date.fromisoformat(record["since"])
    offset = DERIVED_OFFSET_MONTHS[record["authority"]]
    return _add_months(since, offset).isoformat() + "T00:00:00Z"


def is_expired(record, today):
    """True once `today` is strictly past the date the effective stale_after falls on."""
    return today > _effective_date(record)


def marking(record, today):
    """(should_mark, marking string) for the record's compiled CLAUDE.md line, tiered by authority."""
    grace = GRACE_DAYS[record["authority"]]
    expiry = _effective_date(record)
    if grace is not None and (today - expiry).days > grace:
        return (True, MARKING % expiry.isoformat())
    return (False, None)


def evaluate(records, today):
    """One EXPIRED finding per record whose effective stale_after has passed."""
    findings = []
    for law_id in sorted(records):
        record = records[law_id]
        if is_expired(record, today):
            findings.append(
                Finding("EXPIRED", law_id, "past stale_after %s" % derive_stale_after(record))
            )
    return findings


def _effective_date(record):
    return date.fromisoformat(derive_stale_after(record)[:10])


def _add_months(start, months):
    total = start.month - 1 + months
    year = start.year + total // 12
    month = total % 12 + 1
    return date(year, month, min(start.day, calendar.monthrange(year, month)[1]))
