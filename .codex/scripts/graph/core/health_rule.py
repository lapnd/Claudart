"""graph.core.health_rule — the pure decision for a mission's health state (D43).

Kept pure and free of I/O so it is testable without a clock or a filesystem: the adapter
(`adapters/health.py`) gathers the scalars, this decides the state. Precedence is deliberate —
done wins over everything (nothing to supervise), a usage limit outranks staleness (a limited run
looks stalled but the cure is waiting, not relaunching), an explicit block outranks staleness, and
staleness is the last non-running verdict.
"""

STATES = ("running", "stalled", "rate-limited", "done", "blocked")


def health_state(all_done, rate_limited, has_blocked, has_runnable,
                 ledger_age_s, stall_threshold_s):
    """Return one of STATES from already-gathered facts.

    all_done: every roadmap task ticked. rate_limited: the latest rotation log is a usage-limit
    error. has_blocked: a task is marked blocked. has_runnable: some task could run now.
    ledger_age_s: seconds since the last LEDGER entry (None if unknown). stall_threshold_s: the age
    past which, with no live successor, a chain is presumed hung."""
    if all_done:
        return "done"
    if rate_limited:
        return "rate-limited"
    if has_blocked and not has_runnable:
        return "blocked"
    if ledger_age_s is not None and ledger_age_s > stall_threshold_s:
        return "stalled"
    return "running"
