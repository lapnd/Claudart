"""law.core.budget — the D6 queue/budget rules and finding severity (SCHEMA.md sections 5-6).

Pure (D15): `today`, the already-parsed budget config, and plain item dicts go in; `Finding`
objects come out. Reading `.claude/budget.yaml` belongs to an adapter, not here.

Codes emitted here: QUEUE-STALE, OVER-BUDGET.
"""

from law.core.schema import Finding

# The one code that is a queue item rather than a failure: EXPIRED alone never blocks.
NON_BLOCKING_CODE = "EXPIRED"


def check_queue(proposals, expired_laws, budget_cfg, today):
    """QUEUE-STALE for every open proposal or EXPIRED law past `queue_max_age_days`."""
    max_age = budget_cfg["queue_max_age_days"]
    items = [(item["id"], item["expires"]) for item in proposals]
    items += [(item["id"], item["stale_after"]) for item in expired_laws]
    findings = []
    for item_id, expiry in items:
        if (today - expiry).days > max_age:
            findings.append(
                Finding(
                    "QUEUE-STALE",
                    item_id,
                    "expired %s, more than %d days before %s"
                    % (expiry.isoformat(), max_age, today.isoformat()),
                )
            )
    return findings


def check_new_proposal(existing_count_this_month, budget_cfg, today):
    """OVER-BUDGET when one more proposal this calendar month would exceed the monthly cap."""
    cap = budget_cfg["max_proposals_per_month"]
    month = "%04d-%02d" % (today.year, today.month)
    if existing_count_this_month + 1 > cap:
        return [
            Finding(
                "OVER-BUDGET",
                month,
                "proposal %d in %s exceeds max_proposals_per_month=%d"
                % (existing_count_this_month + 1, month, cap),
            )
        ]
    return []


def is_blocking(findings):
    """Severity only — the core never exits. True iff some finding is not a bare queue item."""
    for finding in findings:
        if finding.code != NON_BLOCKING_CODE:
            return True
    return False
