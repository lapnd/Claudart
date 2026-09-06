"""law.adapters.cli — the composition root for the CLAUDART law engine.

This is the ONLY place in the system that wires an adapter (`FsRecordStore`) to the pure
`law.core` checks. Nothing here re-derives a SCHEMA.md rule: every finding code comes straight
out of `law.core.schema.validate`, `law.core.overlap.check`, `law.core.retirement.evaluate`, or
`law.core.budget.check_queue` (see the per-code table in the module docstring of `cmd_validate`
below). `cli.py` only loads records, hands them to the core, and formats what comes back.

Exit codes (SCHEMA.md section 7), owned here once:
    0  clean (or only a bare EXPIRED queue item — never a failure on its own)
    1  one or more findings
    2  usage or runtime error (bad invocation, missing/unreadable file)
"""

import argparse
import json
import sys
from datetime import date
from pathlib import Path

from law.adapters.fs_records import FsRecordStore
from law.core import budget, overlap, retirement, schema
from law.ports.record_store import parse_yaml_lite

EXIT_CLEAN, EXIT_FINDINGS, EXIT_USAGE = 0, 1, 2

# Defaults point at the real repo locations; the test suite always passes explicit paths, so
# these only matter for a bare invocation from the repo root.
DEFAULT_RULES = ".claude/rules"
DEFAULT_BUDGET = ".claude/budget.yaml"
DEFAULT_PROPOSALS = ".claude/proposals"

_FRONTMATTER_DELIM = "---"


# --------------------------------------------------------------------------- proposal frontmatter
def _parse_frontmatter(text):
    """Parse a `---`-delimited frontmatter block (SCHEMA.md section 8 grammar) via the shared
    `parse_yaml_lite` grammar the ports module already owns; {} when the file carries none.
    This is plumbing (splitting a Markdown file at its two `---` lines), not a rule."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != _FRONTMATTER_DELIM:
        return {}
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == _FRONTMATTER_DELIM:
            end = idx
            break
    if end is None:
        return {}
    return parse_yaml_lite("\n".join(lines[1:end]))


def _parse_date(value):
    if not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


# --------------------------------------------------------------------------------- loading -> core
def _load_records(store, rules_dir):
    """All law records under `rules_dir`, as (list of LawRecord, {id: frontmatter}).

    `FsRecordStore.load_laws` itself tolerates a missing directory by returning [] — the CLI is
    the one that must turn a missing --rules directory into a usage error (SPEC), so the caller
    checks `Path(rules_dir).is_dir()` before ever calling this.
    """
    law_records = store.load_laws(str(rules_dir))
    records = {lr.id: lr.frontmatter for lr in law_records}
    return law_records, records


def _load_proposal_items(store, proposals_dir):
    """Open proposals as `{"id": ..., "expires": date}` for `budget.check_queue`.

    `queue_max_age_days` (SCHEMA.md D6) is the maximum age a queue item may sit unresolved since
    it *entered* the queue. A proposal enters the reviewer queue at `created`, not at its own
    `expires` field (that field is `tally`'s own housekeeping date for when it renames the file
    to `<id>.expired.md` — `proposal_expires_days` days after `created`). `check_queue` compares
    whatever date is placed under its `"expires"` key against `today`, so `created` is what is
    passed there; the tuple key name is the core's own parameter name, not a claim about which
    frontmatter field feeds it.
    """
    items = []
    for proposal in store.list_proposals(str(proposals_dir)):
        fields = _parse_frontmatter(proposal.text)
        created = _parse_date(fields.get("created"))
        if created is None:
            continue
        items.append({"id": proposal.id, "expires": created})
    return items


def _load_expired_items(records, today):
    """Every EXPIRED law as `{"id": ..., "stale_after": date}` for `budget.check_queue`."""
    items = []
    for law_id in sorted(records):
        record = records[law_id]
        if not retirement.is_expired(record, today):
            continue
        effective = date.fromisoformat(retirement.derive_stale_after(record)[:10])
        items.append({"id": law_id, "stale_after": effective})
    return items


def _build_queue(records, today):
    """One (law_id, authority, marked, marking-text) tuple per EXPIRED law, for the `queue:`
    section. `retirement.is_expired`/`retirement.marking` supply the decision; this just shapes
    it for printing."""
    queue = []
    for law_id in sorted(records):
        record = records[law_id]
        if not retirement.is_expired(record, today):
            continue
        marked, marking_text = retirement.marking(record, today)
        queue.append((law_id, record.get("authority"), marked, marking_text))
    return queue


# ------------------------------------------------------------------------------------- formatting
def _fmt_finding(finding):
    return "%s %s: %s" % (finding.code, finding.law_id, finding.message)


def _print_text(findings, queue_items):
    for finding in findings:
        print(_fmt_finding(finding))
    print("queue:")
    if not queue_items:
        print("  (none)")
        return
    for law_id, authority, marked, marking_text in queue_items:
        if marked:
            print("  %s (authority: %s) - marked: %s" % (law_id, authority, marking_text))
        else:
            print("  %s (authority: %s) - queued (text unchanged)" % (law_id, authority))


def _print_json(findings, queue_items):
    payload = {
        "findings": [
            {"code": f.code, "law_id": f.law_id, "message": f.message} for f in findings
        ],
        "queue": [
            {
                "law_id": law_id,
                "authority": authority,
                "marked": marked,
                "marking": marking_text,
            }
            for law_id, authority, marked, marking_text in queue_items
        ],
    }
    print(json.dumps(payload, indent=2, sort_keys=True))


# ------------------------------------------------------------------------------------- commands
def cmd_validate(args):
    """`validate` — read-only. Never writes; that is `tally`'s job alone.

    Finding-code provenance (no code here re-derives a rule the core already owns):
        MISSING-FIELD, BAD-VOCAB, BAD-STALE-AFTER, APPROVED-WITHOUT-HUMAN
            -> law.core.schema.validate
        UNDECLARED-OVERLAP, OVERRIDES-CONSTITUTION, BAD-LAYER
            -> law.core.overlap.check
        EXPIRED
            -> law.core.retirement.evaluate
        QUEUE-STALE
            -> law.core.budget.check_queue
    Exit-code severity (EXPIRED alone keeps exit 0; everything else makes it 1) comes from
    law.core.budget.is_blocking — never re-derived here.
    """
    store = FsRecordStore()

    rules_dir = Path(args.rules)
    if not rules_dir.is_dir():
        print("claudart-law: --rules directory not found: %s" % args.rules, file=sys.stderr)
        return EXIT_USAGE

    law_records, records = _load_records(store, rules_dir)

    findings = []
    for law_record in law_records:
        findings.extend(schema.validate(law_record.frontmatter, law_record.id))
    findings.extend(overlap.check(records))

    today = date.today()
    findings.extend(retirement.evaluate(records, today))

    budget_explicit = args.budget is not None
    budget_path = Path(args.budget) if budget_explicit else Path(DEFAULT_BUDGET)
    if budget_path.is_file():
        budget_cfg = store.load_budget(str(budget_path))
        proposals_dir = Path(args.proposals) if args.proposals is not None else Path(DEFAULT_PROPOSALS)
        proposal_items = _load_proposal_items(store, proposals_dir)
        expired_items = _load_expired_items(records, today)
        findings.extend(budget.check_queue(proposal_items, expired_items, budget_cfg, today))
    elif budget_explicit:
        print("claudart-law: --budget file not found: %s" % args.budget, file=sys.stderr)
        return EXIT_USAGE
    # else: no budget configured (default missing) -- queue-staleness is simply not checked;
    # the retirement queue below is independent of budget.yaml.

    queue_items = _build_queue(records, today)

    if args.json:
        _print_json(findings, queue_items)
    else:
        _print_text(findings, queue_items)

    return EXIT_FINDINGS if budget.is_blocking(findings) else EXIT_CLEAN


# --------------------------------------------------------------------------------------- parser
def build_parser():
    parser = argparse.ArgumentParser(
        prog="claudart-law",
        description="CLAUDART law engine.\nExit codes: 0 clean, 1 findings, 2 usage/runtime error.",
    )
    sub = parser.add_subparsers(dest="cmd", metavar="<command>")

    v = sub.add_parser(
        "validate",
        help="read-only: report every SCHEMA.md violation plus the retirement queue",
    )
    v.add_argument("--rules", default=DEFAULT_RULES, help="rules directory (default: %s)" % DEFAULT_RULES)
    v.add_argument("--budget", default=None, help="budget.yaml path (default: %s if present)" % DEFAULT_BUDGET)
    v.add_argument("--proposals", default=None, help="open-proposals directory (default: %s)" % DEFAULT_PROPOSALS)
    v.add_argument("--json", action="store_true", help="emit machine-readable JSON instead of text")
    v.set_defaults(fn=cmd_validate)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "fn", None):
        parser.print_help()
        return EXIT_USAGE
    try:
        return args.fn(args)
    except Exception as exc:  # a traceback escaping to the user is a defect (brief requirement)
        print("claudart-law: unexpected error: %s" % exc, file=sys.stderr)
        return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main())
