"""law.core.tally — the fold side of the tally: lessons + laws + budget -> one report of intents.

Pure (D15): `today` is a parameter, nothing here reads a clock, and **nothing here writes**.
`fold` returns write *intents* — proposals to create, proposals to expire, laws to flip to
`draft` — which an adapter applies. It never mutates `lessons`, `laws`, `proposals` or `hours`.

Contracts implemented here: LESSONS.md sections 1, 3, 4 and 6 (de-duplication, the D8 threshold,
the monthly budget, proposal expiry, reviewer hours, the counter-tally) plus SCHEMA.md section 3's
lifecycle rule that an EXPIRED law's `status` is rewritten to `draft`.
"""

import statistics
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Dict, List, Optional

from law.core import retirement

SELF_FLAG = "self-flag"

MIN_LESSONS = 3
MIN_PROJECTS = 2

NO_SIGNAL_REASON = "blocked: no deterministic signal"
COUNT_REASON = "%d %s (needs ≥3), %d %s"
SPREAD_REASON = "%d %s, %d %s (needs ≥2)"
OVER_BUDGET_REASON = "over budget: max_proposals_per_month=%d reached"

PROPOSAL_ID = "proposals/%s.md"


@dataclass
class ProposalDecision:
    """One candidate law considered this run, and why it was or was not proposed."""

    candidate_law: str
    created: bool
    reason: Optional[str]
    lesson_count: int
    distinct_projects: int
    has_deterministic_signal: bool


@dataclass
class ProposalIntent:
    """A proposal the adapter should write. `id`'s slug drops a leading `law/` segment."""

    candidate_law: str
    id: str
    sources: List[str]
    created: date
    expires: date


@dataclass
class ExpireIntent:
    """An open proposal past `proposal_expires_days`, for the adapter to retire."""

    id: str
    candidate_law: str


@dataclass
class FoldReport:
    """Everything one `tally` run observed, plus the write intents it derived."""

    reviewer_hours_this_month: float
    decisions: List[ProposalDecision]
    creates: List[ProposalIntent]
    expires: List[ExpireIntent]
    flips: List[str]
    median_open_proposal_age_days: Optional[float]
    expired_this_run: int
    counter_tally: Dict[str, int]


def fold(lessons, laws, budget, proposals, hours, today):
    """Fold one run's inputs into a report of observations and write intents."""
    cap = budget["max_proposals_per_month"]
    expires_days = budget["proposal_expires_days"]
    decisions, creates = _consider(lessons, cap, expires_days, today, proposals)
    expires = [
        ExpireIntent(proposal["id"], proposal["candidate_law"])
        for proposal in proposals
        if _age_days(proposal, today) > expires_days
    ]
    ages = [_age_days(proposal, today) for proposal in proposals]
    return FoldReport(
        reviewer_hours_this_month=_reviewer_hours(hours, today),
        decisions=decisions,
        creates=creates,
        expires=expires,
        flips=[law_id for law_id in sorted(laws) if retirement.is_expired(laws[law_id], today)],
        median_open_proposal_age_days=statistics.median(ages) if ages else None,
        expired_this_run=len(expires),
        # LESSONS.md section 6 item 4: this mission has no enforcers, so every law's counter is 0.
        counter_tally={law_id: 0 for law_id in laws},
    )


def _consider(lessons, cap, expires_days, today, proposals):
    """One decision per candidate law, in sorted order, granting creates against the cap."""
    granted = _created_this_month(proposals, today)
    groups = _group(lessons)
    decisions = []
    creates = []
    for candidate_law in sorted(groups):
        entry = groups[candidate_law]
        reason = _threshold_reason(len(entry["sources"]), len(entry["projects"]))
        if reason is None and not entry["deterministic"]:
            reason = NO_SIGNAL_REASON
        if reason is None and granted + 1 > cap:
            reason = OVER_BUDGET_REASON % cap
        decisions.append(
            ProposalDecision(
                candidate_law=candidate_law,
                created=reason is None,
                reason=reason,
                lesson_count=len(entry["sources"]),
                distinct_projects=len(entry["projects"]),
                has_deterministic_signal=entry["deterministic"],
            )
        )
        if reason is None:
            creates.append(_intent(candidate_law, entry, expires_days, today))
            granted += 1
    return (decisions, creates)


def _group(lessons):
    """candidate_law -> distinct sources / projects and whether any signal is not `self-flag`.

    LESSONS.md section 3: records sharing a `source` count as ONE lesson, but the whole source
    group still contributes its `project` values and its `signal` values to the unions.
    """
    groups = {}
    for lesson in lessons:
        entry = groups.setdefault(
            lesson["candidate_law"], {"sources": [], "projects": [], "deterministic": False}
        )
        if lesson["source"] not in entry["sources"]:
            entry["sources"].append(lesson["source"])
        if lesson["project"] not in entry["projects"]:
            entry["projects"].append(lesson["project"])
        if lesson["signal"] != SELF_FLAG:
            entry["deterministic"] = True
    return groups


def _threshold_reason(lesson_count, project_count):
    """The D8 counting conditions: None when both hold, else the exact blocked-reason string."""
    if lesson_count < MIN_LESSONS:
        return COUNT_REASON % (
            lesson_count,
            _plural(lesson_count, "lesson"),
            project_count,
            _plural(project_count, "project"),
        )
    if project_count < MIN_PROJECTS:
        return SPREAD_REASON % (
            lesson_count,
            _plural(lesson_count, "lesson"),
            project_count,
            _plural(project_count, "project"),
        )
    return None


def _plural(count, word):
    return word if count == 1 else word + "s"


def _intent(candidate_law, entry, expires_days, today):
    slug = candidate_law.split("/", 1)[-1]
    return ProposalIntent(
        candidate_law=candidate_law,
        id=PROPOSAL_ID % slug,
        sources=list(entry["sources"]),
        created=today,
        expires=today + timedelta(days=expires_days),
    )


def _created_this_month(proposals, today):
    """How many of the open proposals were already created in `today`'s calendar month."""
    months = [_month(proposal["created"]) for proposal in proposals]
    return months.count(_month(today))


def _reviewer_hours(hours, today):
    """Sum of `minutes` logged in `today`'s calendar month, in hours (LESSONS.md section 2)."""
    minutes = 0
    for entry in hours:
        if _month(date.fromisoformat(entry["ts"][:10])) == _month(today):
            minutes += entry["minutes"]
    return minutes / 60.0


def _month(day):
    return (day.year, day.month)


def _age_days(proposal, today):
    return (today - proposal["created"]).days
