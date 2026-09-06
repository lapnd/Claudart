"""law.core.schema — validate one parsed law record against the frozen SCHEMA.md contract.

Pure (D15): a plain frontmatter dict goes in, `Finding` objects come out. No filesystem, no
environment, no clock — parsing the Markdown and its YAML belongs to an adapter, not here.

Codes emitted here (SCHEMA.md section 6):
    MISSING-FIELD, BAD-VOCAB, BAD-STALE-AFTER, APPROVED-WITHOUT-HUMAN
"""

import re
from dataclasses import dataclass


@dataclass
class Finding:
    """One violation: its SCHEMA.md section-6 code, what it is about, and readable detail.

    `law_id` is the record id for a per-record code, and the two ids sorted and joined with "|"
    for `UNDECLARED-OVERLAP`, whose violation belongs to the pair rather than to either side.
    """

    code: str
    law_id: str
    message: str


REQUIRED_FIELDS = (
    "level",
    "authority",
    "status",
    "since",
    "stale_after",
    "verified",
    "enforcer",
    "load",
)

VOCABULARIES = {
    "level": ("constitution", "law", "convention", "vendor-default"),
    "authority": ("core", "standard", "provisional"),
    "status": ("proposed", "approved", "draft", "deprecated", "superseded"),
    "load": ("always", "trigger", "auto", "never"),
}

# SCHEMA.md section 2 — load value -> (fields it requires, fields it forbids).
LOAD_MATRIX = {
    "always": (("order", "trigger"), ("digest",)),
    "trigger": (("order", "trigger", "digest"), ()),
    "auto": ((), ("order", "trigger", "digest")),
    "never": ((), ("order", "trigger", "digest")),
}

ENFORCER_PREFIXES = ("check", "hook")
HUMAN_ACTOR = "human:"

DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
INSTANT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def validate(record, law_id):
    """Return every SCHEMA.md violation in one parsed frontmatter dict; [] when conformant."""
    findings = []

    def add(code, message):
        findings.append(Finding(code, law_id, message))

    for field in REQUIRED_FIELDS:
        if field not in record:
            add("MISSING-FIELD", "required field `%s` is absent" % field)

    for field in sorted(VOCABULARIES):
        if field in record and record[field] not in VOCABULARIES[field]:
            add(
                "BAD-VOCAB",
                "`%s` is %r, not one of %s"
                % (field, record[field], " | ".join(VOCABULARIES[field])),
            )

    if "since" in record and not _matches(DATE, record["since"]):
        add("BAD-VOCAB", "`since` is %r, not a YYYY-MM-DD date" % (record["since"],))

    if "stale_after" in record and not _matches(INSTANT, record["stale_after"]):
        add(
            "BAD-STALE-AFTER",
            "`stale_after` is %r, not an absolute ISO instant" % (record["stale_after"],),
        )

    _check_enforcer(record, add)
    _check_human_verification(record, add)
    _check_load_matrix(record, add)
    return findings


def _matches(pattern, value):
    return isinstance(value, str) and pattern.match(value) is not None


def _check_enforcer(record, add):
    """`judgement` verbatim, or check:/hook: with a non-empty path; blank counts as absent."""
    if "enforcer" not in record:
        return
    value = record["enforcer"]
    text = value.strip() if isinstance(value, str) else ""
    if text == "":
        add("MISSING-FIELD", "`enforcer` is present but blank")
        return
    if text == "judgement":
        return
    prefix, separator, path = text.partition(":")
    if separator and prefix in ENFORCER_PREFIXES:
        if path.strip() == "":
            add("MISSING-FIELD", "`enforcer` %r names an empty path" % text)
        return
    add("BAD-VOCAB", "`enforcer` %r is not judgement, check:<path> or hook:<path>" % text)


def _check_human_verification(record, add):
    """An approved record needs at least one `verified` entry whose `by` is a human actor."""
    if record.get("status") != "approved":
        return
    for entry in record.get("verified") or []:
        actor = entry.get("by", "") if isinstance(entry, dict) else ""
        if isinstance(actor, str) and actor.startswith(HUMAN_ACTOR):
            return
    add("APPROVED-WITHOUT-HUMAN", "status is approved but no `verified` entry names a human actor")


def _check_load_matrix(record, add):
    """order/trigger/digest are required or forbidden by the record's `load` value."""
    load = record.get("load")
    if load not in LOAD_MATRIX:
        return
    required, forbidden = LOAD_MATRIX[load]
    for name in required:
        if name not in record:
            add("MISSING-FIELD", "`%s` is required when load is %s" % (name, load))
    for name in forbidden:
        if name in record:
            add("BAD-VOCAB", "`%s` is forbidden when load is %s" % (name, load))
    if "order" in record and not isinstance(record["order"], int):
        add("BAD-VOCAB", "`order` is %r, not an integer" % (record["order"],))
