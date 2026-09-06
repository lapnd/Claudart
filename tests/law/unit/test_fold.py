"""
Failing-first unit tests for the fold side of the CLAUDART law engine's pure core.

The implementation under test (`.claude/scripts/law/core/{tally,agreement,render}.py`) does NOT
exist yet. This file is expected to fail on import. That failure IS the deliverable (observed
RED, per `.claude/scripts/law/LESSONS.md`, `.claude/scripts/law/SCHEMA.md`, and
`evidence-gauntlet.md`).

`domain/law-core` (already implemented, done) supplies `law.core.schema.Finding` and the pure
`law.core.retirement` module (`derive_stale_after`, `is_expired`, `marking`, `evaluate`). The
three modules below are new, sit beside them under `.claude/scripts/law/core/`, are equally pure
(D15: no os/sys/json/pathlib/subprocess imports — AST-enforced), and MAY import
`law.core.retirement` and `law.core.schema.Finding` (pure-to-pure is fine; only real I/O is
forbidden).

============================================================================
API CONTRACT — the implementer builds exactly this shape (chosen by this test file)
============================================================================

    # law/core/tally.py  (LESSONS.md sections 1, 3, 4, 6; SCHEMA.md section 3 for flips)
    from dataclasses import dataclass
    from datetime import date
    from typing import Dict, List, Optional

    @dataclass
    class ProposalDecision:
        candidate_law: str
        created: bool                    # True iff a create-intent was emitted this run
        reason: Optional[str]            # blocked-reason string when created is False; else None
        lesson_count: int                # de-duplicated (distinct `source`) lesson count (D8 #1)
        distinct_projects: int           # count of distinct `project` values (D8 #2)
        has_deterministic_signal: bool   # >=1 lesson with signal != "self-flag" (D8 #3)

    @dataclass
    class ProposalIntent:
        candidate_law: str
        id: str            # "proposals/<slug>.md"; slug = candidate_law with a leading
                            # "law/" segment stripped (candidate_law.split("/", 1)[-1]).
                            # NOTE: LESSONS.md's own worked example filename
                            # ("proposals/law-script-before-reask.md") is explicitly
                            # illustrative, not a frozen slug algorithm — this slug rule is
                            # this test suite's own choice, documented here for the implementer.
        sources: List[str]  # de-duplicated `source` values folded into this proposal
        created: date        # == the `today` argument to fold()
        expires: date         # created + budget_cfg["proposal_expires_days"]

    @dataclass
    class ExpireIntent:
        id: str              # the existing open proposal's id, taken from its input dict
        candidate_law: str

    @dataclass
    class FoldReport:
        reviewer_hours_this_month: float          # sum(minutes)/60.0 for `hours` entries whose
                                                   # `ts` falls in `today`'s (year, month)
        decisions: List[ProposalDecision]         # one per distinct candidate_law in `lessons`,
                                                   # processed in sorted(candidate_law) order
        creates: List[ProposalIntent]             # decisions.created == True, up to budget
        expires: List[ExpireIntent]               # open `proposals` past proposal_expires_days
        flips: List[str]                          # law_ids in `laws` that are EXPIRED
                                                   # (retirement.is_expired(record, today) is
                                                   # True) -> write-intent to set status: draft
        median_open_proposal_age_days: Optional[float]
                                                   # statistics.median of (today - p["created"]).days
                                                   # over every proposal in `proposals` (age in
                                                   # days at `today`); None iff `proposals` is
                                                   # empty. NOT recomputed against `creates` or
                                                   # `expires` by these tests -- median tests
                                                   # pass no lessons/laws, so creates == [] and
                                                   # expires == [] and `proposals` alone decides
                                                   # the median. The interaction between a
                                                   # newly-created or newly-expired proposal and
                                                   # this figure is left to the implementer's
                                                   # judgement and is NOT exercised here.
        expired_this_run: int                     # == len(expires)
        counter_tally: Dict[str, int]             # {law_id: 0 for law_id in laws} -- this
                                                   # mission has no enforcers, so the value is
                                                   # unconditionally 0 for every law regardless
                                                   # of any other computation (LESSONS.md
                                                   # section 6 item 4).

    def fold(lessons: List[dict], laws: Dict[str, dict], budget: dict,
             proposals: List[dict], hours: List[dict], today: date) -> FoldReport:
        # lessons: LESSONS.md section 1.1 records (all eleven keys).
        # laws: law_id -> frontmatter dict, at least {"status", "authority", "stale_after"}
        #       (or "since" if stale_after is derived -- see retirement.derive_stale_after).
        # budget: at least {"max_proposals_per_month": int, "proposal_expires_days": int}.
        # proposals: currently-open proposals, each at least
        #       {"id": str, "candidate_law": str, "created": date}.
        # hours: LESSONS.md section 2.1 records, each {"ts": str, "minutes": int, "activity": str}.
        # today: datetime.date, never computed internally (no date.today() call in the module).
        #
        # De-duplication (LESSONS.md section 3): lessons sharing the same `source` count as one
        # lesson; the distinct-project set and the "has a non-self-flag signal" fact are unioned
        # across every record in the source group even though the group contributes one lesson
        # to the count.
        #
        # D8 threshold, evaluated per candidate_law over its de-duplicated lessons:
        #   count(distinct source) >= 3 AND distinct(project) >= 2 AND
        #   any(record.signal != "self-flag") for some record sharing that candidate_law.
        # Blocked-reason strings (exact):
        #   - condition 3 fails alone (1 and 2 both hold): "blocked: no deterministic signal"
        #     (LESSONS.md section 4, frozen verbatim).
        #   - condition 2 fails (spread), condition 1 holds: "<n> lessons, <p> project (needs
        #     ≥ 2)" pluralizing "lesson"/"project" on their own counts -- this is
        #     LESSONS.md section 6's own worked example ("3 lessons, 1 project (needs ≥
        #     2)"), reused verbatim for n=3, p=1.
        #   - condition 1 fails (count), regardless of condition 2: "<n> lessons (needs ≥
        #     3), <p> project(s)" -- LESSONS.md does not freeze this exact shape (its only
        #     worked example is the spread-failure case above); this test suite extrapolates
        #     the same "<actual> ... (needs >=<threshold>)" shape onto the count condition and
        #     documents that choice here rather than treating it as frozen text.
        # A candidate that crosses the threshold is a create-intent UP TO the monthly budget
        # (LESSONS.md section 4): candidates are granted in sorted(candidate_law) order; once
        # granting one more would exceed budget_cfg["max_proposals_per_month"] (counting
        # `proposals` already created this calendar month plus creates granted so far this
        # run), the remaining crossing candidates are blocked with reason
        # "over budget: max_proposals_per_month=<cap> reached" (this exact string is this test
        # suite's own choice; LESSONS.md section 4 only requires that it not be the
        # "blocked: no deterministic signal" string).
        #
        # Proposal expiry (LESSONS.md section 4 / SCHEMA.md section 5): an open proposal whose
        # (today - proposal["created"]).days > budget["proposal_expires_days"] is an
        # ExpireIntent; the fold performs no rename/write itself.
        #
        # `draft` flip list (SCHEMA.md section 3 lifecycle: "`tally` (the write side) rewrites
        # an EXPIRED law's `status` to `draft`"): every law_id in `laws` for which
        # retirement.is_expired(record, today) is True appears in `flips`; fold never mutates
        # `laws`, `lessons`, `proposals`, or `hours` in place.
        ...

    # law/core/agreement.py  (LESSONS.md section 5)
    def rate(lessons: List[dict]) -> "tuple[int, int]":
        # Pairing: among lessons sharing the same `source`, pair the record with
        # extraction_pass == 1 with the record with extraction_pass == 2 for that source. A
        # source with fewer than two records, or missing one of the two pass values, forms no
        # pair. Returns (agree, pairs) where `agree` counts pairs whose two `candidate_law`
        # values are string-equal. Returns (0, 0) -- never raises -- when zero pairs are formed
        # (this test suite's chosen empty behaviour; LESSONS.md does not specify one).
        ...

    def format_rate(agree: int, pairs: int) -> str:
        # Exactly "agreement: <r> (<agree>/<pairs>)" (LESSONS.md section 5), where <r> is
        # (agree / pairs) formatted to exactly two decimal places, or "0.00" when pairs == 0
        # (paired with rate()'s (0, 0) empty behaviour, so format_rate(*rate([])) never raises).
        ...

    # law/core/render.py  (SCHEMA.md sections 2-3; artifacts/compiled-block.example.md)
    def block(laws: Dict[str, dict], today: date) -> str:
        # Returns ONLY the text BETWEEN the `<!-- laws:begin -->` / `<!-- laws:end -->` markers
        # (this test suite's choice, stated per the brief: the markers themselves belong to the
        # target-writer adapter, not this pure function). The returned string has no leading or
        # trailing newline beyond what the line-join below produces.
        #
        # Structure (fixed literal lines are exact, verbatim, owned by this function):
        #   1. "See @.claude/CONTEXT.md for the current state of work (updated by /checkpoint)."
        #   2. one "See @.claude/rules/<law_id>.md <trigger>" line per `load: always` record in
        #      `laws`, sorted by `order` ascending.
        #   3. "" (blank line)
        #   4. the fixed intro sentence (verbatim, see FIXED_INTRO_SENTENCE in this test file).
        #   5. "" (blank line)
        #   6. one bullet line per `load: trigger` record in `laws`, sorted by `order`
        #      ascending: "- `.claude/rules/<law_id>.md` — <marking><trigger> Digest: <digest>"
        #      where <marking> is "" unless the record's compiled line is marked (see below), in
        #      which case <marking> is retirement.MARKING % effective-stale-after-date (ending
        #      in "— ", i.e. em-dash-space, so it reads "— ⚠ expired ... —
        #      <trigger>").
        #   All lines are joined with "\n"; there is no marker line and no trailing "\n" beyond
        #   what an empty trailing bullet section leaves (see the empty-bullets case below).
        #
        # `load: auto` and `load: never` records never contribute a line anywhere in the block.
        #
        # Expiry marking (SCHEMA.md section 3, reusing law.core.retirement -- pure-to-pure):
        # applies ONLY to `load: trigger` bullet lines, because only those lines have the em
        # dash the marking string is defined to be inserted after (SCHEMA.md: "inserted
        # immediately after the em dash (—) ... of the law's CLAUDE.md line"); the
        # `load: always` line has no em dash, so this test suite's rule is that an expired
        # `always` record's line is NEVER marked regardless of authority/tier. For a `load:
        # trigger` record: marked iff retirement.marking(record, today)[0] is True, using
        # retirement's own tiered grace (core: never; standard: >30 days past; provisional:
        # from the moment of expiry).
        ...

============================================================================
"""

import copy
import os
import sys
import unittest
from datetime import date

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", ".claude", "scripts"))

from law.core import tally, agreement, render


# ---------------------------------------------------------------------------
# shared fixtures / helpers
# ---------------------------------------------------------------------------

def make_lesson(source, candidate_law, project="claudart", signal="user-correction",
                 kind="correction", extraction_pass=1, ts="2026-09-01T00:00:00Z",
                 lesson_id="L-2026-001", reviewed=False, summary="a lesson",
                 matched_against=None):
    return {
        "id": lesson_id,
        "ts": ts,
        "project": project,
        "source": source,
        "kind": kind,
        "signal": signal,
        "summary": summary,
        "candidate_law": candidate_law,
        "matched_against": matched_against if matched_against is not None else [],
        "extraction_pass": extraction_pass,
        "reviewed": reviewed,
    }


def make_hours(ts, minutes, activity="review"):
    return {"ts": ts, "minutes": minutes, "activity": activity}


def make_law(load, order=None, trigger=None, digest=None, authority="standard",
             stale_after="2099-01-01T00:00:00Z", status="approved"):
    record = {"load": load, "authority": authority, "stale_after": stale_after, "status": status}
    if order is not None:
        record["order"] = order
    if trigger is not None:
        record["trigger"] = trigger
    if digest is not None:
        record["digest"] = digest
    return record


def find_decision(decisions, candidate_law):
    for decision in decisions:
        if decision.candidate_law == candidate_law:
            return decision
    raise AssertionError("no decision for %r among %r" % (candidate_law, decisions))


def crossing_lessons(candidate_law, source_prefix, projects=("p1", "p2"),
                      signal="user-correction"):
    """3 distinct sources, spread across `projects`, at least one non-self-flag signal."""
    return [
        make_lesson("%s-1" % source_prefix, candidate_law, project=projects[0], signal=signal),
        make_lesson("%s-2" % source_prefix, candidate_law,
                     project=projects[1 % len(projects)], signal="self-flag"),
        make_lesson("%s-3" % source_prefix, candidate_law,
                     project=projects[0], signal="self-flag"),
    ]


AMPLE_BUDGET = {"max_proposals_per_month": 10, "proposal_expires_days": 30}
FIXED_TODAY = date(2026, 9, 6)


# ---------------------------------------------------------------------------
# tally: dedup by source
# ---------------------------------------------------------------------------

class TallyDedupTests(unittest.TestCase):
    def test_four_lessons_three_distinct_sources_fold_to_three(self):
        lessons = [
            make_lesson("dup-src", "law/dedup-test", project="p1", signal="user-correction"),
            make_lesson("dup-src", "law/dedup-test", project="p1", signal="self-flag"),
            make_lesson("other-src-a", "law/dedup-test", project="p2", signal="self-flag"),
            make_lesson("other-src-b", "law/dedup-test", project="p2", signal="self-flag"),
        ]
        report = tally.fold(lessons, {}, AMPLE_BUDGET, [], [], FIXED_TODAY)
        decision = find_decision(report.decisions, "law/dedup-test")
        self.assertEqual(decision.lesson_count, 3)


# ---------------------------------------------------------------------------
# tally: D8 threshold, each condition failing alone, plus all-three-pass
# ---------------------------------------------------------------------------

class TallyThresholdTests(unittest.TestCase):
    def test_count_condition_failing_alone_is_blocked_with_count_reason(self):
        lessons = [
            make_lesson("cf-1", "law/count-fail", project="p1", signal="user-correction"),
            make_lesson("cf-2", "law/count-fail", project="p2", signal="self-flag"),
        ]
        report = tally.fold(lessons, {}, AMPLE_BUDGET, [], [], FIXED_TODAY)
        decision = find_decision(report.decisions, "law/count-fail")
        self.assertEqual(decision.lesson_count, 2)
        self.assertEqual(decision.distinct_projects, 2)
        self.assertTrue(decision.has_deterministic_signal)
        self.assertFalse(decision.created)
        self.assertEqual(decision.reason, "2 lessons (needs ≥3), 2 projects")

    def test_spread_condition_failing_alone_is_blocked_with_frozen_reason(self):
        # LESSONS.md section 6's own worked example, reused verbatim: "3 lessons, 1 project
        # (needs ≥2)".
        lessons = [
            make_lesson("sf-1", "law/spread-fail", project="only-project",
                        signal="user-correction"),
            make_lesson("sf-2", "law/spread-fail", project="only-project", signal="self-flag"),
            make_lesson("sf-3", "law/spread-fail", project="only-project", signal="self-flag"),
        ]
        report = tally.fold(lessons, {}, AMPLE_BUDGET, [], [], FIXED_TODAY)
        decision = find_decision(report.decisions, "law/spread-fail")
        self.assertEqual(decision.lesson_count, 3)
        self.assertEqual(decision.distinct_projects, 1)
        self.assertTrue(decision.has_deterministic_signal)
        self.assertFalse(decision.created)
        self.assertEqual(decision.reason, "3 lessons, 1 project (needs ≥2)")

    def test_deterministic_signal_condition_failing_alone_is_blocked_with_frozen_string(self):
        lessons = [
            make_lesson("df-1", "law/signal-fail", project="p1", signal="self-flag"),
            make_lesson("df-2", "law/signal-fail", project="p2", signal="self-flag"),
            make_lesson("df-3", "law/signal-fail", project="p1", signal="self-flag"),
        ]
        report = tally.fold(lessons, {}, AMPLE_BUDGET, [], [], FIXED_TODAY)
        decision = find_decision(report.decisions, "law/signal-fail")
        self.assertEqual(decision.lesson_count, 3)
        self.assertEqual(decision.distinct_projects, 2)
        self.assertFalse(decision.has_deterministic_signal)
        self.assertFalse(decision.created)
        self.assertEqual(decision.reason, "blocked: no deterministic signal")

    def test_all_three_conditions_passing_creates_a_proposal(self):
        lessons = crossing_lessons("law/all-pass", "ap")
        report = tally.fold(lessons, {}, AMPLE_BUDGET, [], [], FIXED_TODAY)
        decision = find_decision(report.decisions, "law/all-pass")
        self.assertEqual(decision.lesson_count, 3)
        self.assertGreaterEqual(decision.distinct_projects, 2)
        self.assertTrue(decision.has_deterministic_signal)
        self.assertTrue(decision.created)
        self.assertIsNone(decision.reason)
        created_ids = {intent.candidate_law for intent in report.creates}
        self.assertIn("law/all-pass", created_ids)


# ---------------------------------------------------------------------------
# tally: monthly budget cap
# ---------------------------------------------------------------------------

class TallyBudgetTests(unittest.TestCase):
    def test_three_crossing_candidates_over_cap_of_two_yields_two_creates_one_blocked(self):
        lessons = (
            crossing_lessons("law/aaa", "aaa")
            + crossing_lessons("law/bbb", "bbb")
            + crossing_lessons("law/ccc", "ccc")
        )
        budget = {"max_proposals_per_month": 2, "proposal_expires_days": 30}
        report = tally.fold(lessons, {}, budget, [], [], FIXED_TODAY)
        self.assertEqual(len(report.creates), 2)
        created = {intent.candidate_law for intent in report.creates}
        self.assertEqual(created, {"law/aaa", "law/bbb"})
        blocked_decision = find_decision(report.decisions, "law/ccc")
        self.assertFalse(blocked_decision.created)
        self.assertNotEqual(blocked_decision.reason, "blocked: no deterministic signal")
        self.assertEqual(
            blocked_decision.reason, "over budget: max_proposals_per_month=2 reached"
        )

    def test_two_crossing_candidates_at_cap_of_two_are_not_blocked(self):
        lessons = crossing_lessons("law/ddd", "ddd") + crossing_lessons("law/eee", "eee")
        budget = {"max_proposals_per_month": 2, "proposal_expires_days": 30}
        report = tally.fold(lessons, {}, budget, [], [], FIXED_TODAY)
        self.assertEqual(len(report.creates), 2)
        for candidate_law in ("law/ddd", "law/eee"):
            decision = find_decision(report.decisions, candidate_law)
            self.assertTrue(decision.created)
            self.assertIsNone(decision.reason)


# ---------------------------------------------------------------------------
# tally: proposal expiry
# ---------------------------------------------------------------------------

class TallyProposalExpiryTests(unittest.TestCase):
    def test_proposal_past_expiry_window_is_an_expire_intent(self):
        budget = {"max_proposals_per_month": 10, "proposal_expires_days": 30}
        proposals = [
            {
                "id": "proposals/old.md",
                "candidate_law": "law/old",
                "created": date(2026, 7, 28),  # 40 days before FIXED_TODAY, > 30
            }
        ]
        report = tally.fold([], {}, budget, proposals, [], FIXED_TODAY)
        expired_ids = {intent.id for intent in report.expires}
        self.assertIn("proposals/old.md", expired_ids)

    def test_proposal_inside_expiry_window_is_not_an_expire_intent(self):
        budget = {"max_proposals_per_month": 10, "proposal_expires_days": 30}
        proposals = [
            {
                "id": "proposals/fresh.md",
                "candidate_law": "law/fresh",
                "created": date(2026, 8, 27),  # 10 days before FIXED_TODAY, within 30
            }
        ]
        report = tally.fold([], {}, budget, proposals, [], FIXED_TODAY)
        expired_ids = {intent.id for intent in report.expires}
        self.assertNotIn("proposals/fresh.md", expired_ids)


# ---------------------------------------------------------------------------
# tally: median open-proposal age (odd and even counts)
# ---------------------------------------------------------------------------

class TallyMedianOpenAgeTests(unittest.TestCase):
    NO_EXPIRY_BUDGET = {"max_proposals_per_month": 0, "proposal_expires_days": 9999}

    def test_median_over_odd_number_of_open_proposals(self):
        # ages (days before FIXED_TODAY = 2026-09-06): 10, 20, 30 -> median 20.
        proposals = [
            {"id": "p1", "candidate_law": "law/p1", "created": date(2026, 8, 27)},  # 10d
            {"id": "p2", "candidate_law": "law/p2", "created": date(2026, 8, 17)},  # 20d
            {"id": "p3", "candidate_law": "law/p3", "created": date(2026, 8, 7)},   # 30d
        ]
        report = tally.fold([], {}, self.NO_EXPIRY_BUDGET, proposals, [], FIXED_TODAY)
        self.assertEqual(report.median_open_proposal_age_days, 20)

    def test_median_over_even_number_of_open_proposals_averages_the_middle_two(self):
        # ages: 10, 20, 30, 40 -> naive "pick one middle" would return 20 or 30; the correct
        # median averages them to 25.
        proposals = [
            {"id": "p1", "candidate_law": "law/p1", "created": date(2026, 8, 27)},  # 10d
            {"id": "p2", "candidate_law": "law/p2", "created": date(2026, 8, 17)},  # 20d
            {"id": "p3", "candidate_law": "law/p3", "created": date(2026, 8, 7)},   # 30d
            {"id": "p4", "candidate_law": "law/p4", "created": date(2026, 7, 28)},  # 40d
        ]
        report = tally.fold([], {}, self.NO_EXPIRY_BUDGET, proposals, [], FIXED_TODAY)
        self.assertEqual(report.median_open_proposal_age_days, 25)


# ---------------------------------------------------------------------------
# tally: reviewer-hours sum for the month
# ---------------------------------------------------------------------------

class TallyReviewerHoursTests(unittest.TestCase):
    def test_hours_inside_month_summed_and_other_month_excluded(self):
        hours = [
            make_hours("2026-09-01T09:00:00Z", 60),   # this month: 1.0h
            make_hours("2026-09-15T09:00:00Z", 30),   # this month: 0.5h
            make_hours("2026-08-31T09:00:00Z", 120),  # last month: excluded
        ]
        report = tally.fold([], {}, AMPLE_BUDGET, [], hours, FIXED_TODAY)
        self.assertEqual(report.reviewer_hours_this_month, 1.5)


# ---------------------------------------------------------------------------
# tally: counter-tally zeros
# ---------------------------------------------------------------------------

class TallyCounterTallyTests(unittest.TestCase):
    def test_counter_tally_present_and_zero_for_every_law(self):
        laws = {
            "law-a": make_law("never"),
            "law-b": make_law("auto"),
        }
        report = tally.fold([], laws, AMPLE_BUDGET, [], [], FIXED_TODAY)
        self.assertIn("law-a", report.counter_tally)
        self.assertIn("law-b", report.counter_tally)
        self.assertEqual(report.counter_tally["law-a"], 0)
        self.assertEqual(report.counter_tally["law-b"], 0)


# ---------------------------------------------------------------------------
# tally: draft flip list
# ---------------------------------------------------------------------------

class TallyDraftFlipTests(unittest.TestCase):
    def test_expired_law_flips_non_expired_law_does_not_and_inputs_are_not_mutated(self):
        laws = {
            "expired-law": make_law(
                "trigger", order=1, trigger="t", digest="d",
                authority="standard", stale_after="2020-01-01T00:00:00Z", status="approved",
            ),
            "fresh-law": make_law(
                "trigger", order=2, trigger="t", digest="d",
                authority="standard", stale_after="2099-01-01T00:00:00Z", status="approved",
            ),
        }
        laws_before = copy.deepcopy(laws)

        report = tally.fold([], laws, AMPLE_BUDGET, [], [], FIXED_TODAY)

        self.assertIn("expired-law", report.flips)
        self.assertNotIn("fresh-law", report.flips)
        # fold returns intents only -- it must not have touched its inputs.
        self.assertEqual(laws, laws_before)
        self.assertEqual(laws["expired-law"]["status"], "approved")


# ---------------------------------------------------------------------------
# agreement
# ---------------------------------------------------------------------------

class AgreementRateTests(unittest.TestCase):
    def _d9_fixture(self):
        # 4 sources, each carrying extraction_pass 1 and 2; s1 and s3 agree, s2 and s4 don't.
        return [
            make_lesson("s1", "law/x", extraction_pass=1),
            make_lesson("s1", "law/x", extraction_pass=2),
            make_lesson("s2", "law/x", extraction_pass=1),
            make_lesson("s2", "law/y", extraction_pass=2),
            make_lesson("s3", "law/y", extraction_pass=1),
            make_lesson("s3", "law/y", extraction_pass=2),
            make_lesson("s4", "law/z", extraction_pass=1),
            make_lesson("s4", "law/w", extraction_pass=2),
        ]

    def test_d9_fixture_shape_gives_two_of_four(self):
        agree, pairs = agreement.rate(self._d9_fixture())
        self.assertEqual((agree, pairs), (2, 4))

    def test_rendered_form_is_formatted_to_two_decimals(self):
        agree, pairs = agreement.rate(self._d9_fixture())
        self.assertEqual(agreement.format_rate(agree, pairs), "agreement: 0.50 (2/4)")

    def test_asymmetric_fixture_pins_the_direction_of_the_comparison(self):
        # The D9 fixture is symmetric -- 2 of 4 pairs agree -- so counting agreements and counting
        # DISagreements both yield (2, 4). An asymmetric fixture is what pins which one `rate` counts.
        lessons = [
            make_lesson("a1", "law/x", extraction_pass=1),
            make_lesson("a1", "law/x", extraction_pass=2),
            make_lesson("a2", "law/y", extraction_pass=1),
            make_lesson("a2", "law/y", extraction_pass=2),
            make_lesson("a3", "law/z", extraction_pass=1),
            make_lesson("a3", "law/z", extraction_pass=2),
            make_lesson("a4", "law/p", extraction_pass=1),
            make_lesson("a4", "law/q", extraction_pass=2),
        ]
        agree, pairs = agreement.rate(lessons)
        self.assertEqual((agree, pairs), (3, 4))
        self.assertEqual(agreement.format_rate(agree, pairs), "agreement: 0.75 (3/4)")

    def test_source_with_only_one_pass_is_not_counted_as_a_pair(self):
        lessons = self._d9_fixture() + [make_lesson("s5", "law/only-one-pass", extraction_pass=1)]
        agree, pairs = agreement.rate(lessons)
        self.assertEqual((agree, pairs), (2, 4))

    def test_zero_pairs_does_not_raise(self):
        lessons = [make_lesson("solo", "law/solo", extraction_pass=1)]
        agree, pairs = agreement.rate(lessons)
        self.assertEqual((agree, pairs), (0, 0))
        self.assertEqual(agreement.format_rate(agree, pairs), "agreement: 0.00 (0/0)")


# ---------------------------------------------------------------------------
# render
# ---------------------------------------------------------------------------

FIXED_PREAMBLE_LINE = (
    "See @.claude/CONTEXT.md for the current state of work (updated by /checkpoint)."
)
FIXED_INTRO_SENTENCE = (
    "The workflow rules below are deliberately **not auto-imported** (token hygiene). "
    "Read the rule file when its trigger fires, **before acting under it**. Until read, "
    "the digest after each trigger is binding:"
)


class RenderPreambleTests(unittest.TestCase):
    def test_fixed_preamble_then_always_records_then_intro_sentence(self):
        laws = {
            "constitution": make_law(
                "always", order=1,
                trigger="for the decision-priority ladder and sixteen Golden Rules that sit "
                        "above every other rule.",
            ),
            "ai-behavior": make_law("always", order=2, trigger="for universal AI behavior guidelines."),
        }
        expected = "\n".join([
            FIXED_PREAMBLE_LINE,
            "See @.claude/rules/constitution.md for the decision-priority ladder and sixteen "
            "Golden Rules that sit above every other rule.",
            "See @.claude/rules/ai-behavior.md for universal AI behavior guidelines.",
            "",
            FIXED_INTRO_SENTENCE,
            "",
        ])
        self.assertEqual(render.block(laws, FIXED_TODAY), expected)


class RenderTriggerBulletTests(unittest.TestCase):
    def test_trigger_record_renders_as_bullet_with_digest(self):
        laws = {
            "task-management": make_law(
                "trigger", order=10,
                trigger="read when creating or resuming a task.",
                digest="planning and awaiting-review are read-only locks.",
            ),
        }
        result = render.block(laws, FIXED_TODAY)
        self.assertIn(
            "- `.claude/rules/task-management.md` — read when creating or resuming a task. "
            "Digest: planning and awaiting-review are read-only locks.",
            result,
        )


class RenderLoadFilterTests(unittest.TestCase):
    def test_auto_and_never_records_never_appear(self):
        laws = {
            "auto-rule": make_law("auto"),
            "never-rule": make_law("never"),
            "trigger-rule": make_law("trigger", order=1, trigger="t", digest="d"),
        }
        result = render.block(laws, FIXED_TODAY)
        self.assertNotIn("auto-rule", result)
        self.assertNotIn("never-rule", result)
        self.assertIn("trigger-rule", result)


class RenderOrderSortTests(unittest.TestCase):
    def test_trigger_bullets_are_sorted_by_order_despite_shuffled_input(self):
        laws = {
            "third": make_law("trigger", order=30, trigger="third-trigger", digest="d"),
            "first": make_law("trigger", order=10, trigger="first-trigger", digest="d"),
            "second": make_law("trigger", order=20, trigger="second-trigger", digest="d"),
        }
        result = render.block(laws, FIXED_TODAY)
        first_pos = result.index("first-trigger")
        second_pos = result.index("second-trigger")
        third_pos = result.index("third-trigger")
        self.assertTrue(first_pos < second_pos < third_pos)


class RenderExpiryMarkingTests(unittest.TestCase):
    def test_expired_core_trigger_record_renders_unchanged(self):
        laws = {
            "core-rule": make_law(
                "trigger", order=1, trigger="t", digest="d",
                authority="core", stale_after="2020-01-01T00:00:00Z",
            ),
        }
        result = render.block(laws, FIXED_TODAY)
        self.assertIn("- `.claude/rules/core-rule.md` — t Digest: d", result)
        self.assertNotIn("⚠ expired", result)

    def test_expired_standard_within_grace_renders_unchanged(self):
        # stale_after 2026-08-10 -> 27 days before FIXED_TODAY (2026-09-06), within 30-day grace.
        laws = {
            "std-rule": make_law(
                "trigger", order=1, trigger="t", digest="d",
                authority="standard", stale_after="2026-08-10T00:00:00Z",
            ),
        }
        result = render.block(laws, FIXED_TODAY)
        self.assertIn("- `.claude/rules/std-rule.md` — t Digest: d", result)
        self.assertNotIn("⚠ expired", result)

    def test_expired_standard_past_grace_is_marked_immediately_after_em_dash(self):
        # stale_after 2026-07-28 -> 40 days before FIXED_TODAY, past the 30-day grace.
        laws = {
            "std-rule": make_law(
                "trigger", order=1, trigger="t", digest="d",
                authority="standard", stale_after="2026-07-28T00:00:00Z",
            ),
        }
        result = render.block(laws, FIXED_TODAY)
        self.assertIn(
            "- `.claude/rules/std-rule.md` — ⚠ expired 2026-07-28, "
            "re-verification pending — t Digest: d",
            result,
        )

    def test_expired_provisional_is_marked_from_moment_of_expiry(self):
        # stale_after one day before FIXED_TODAY -- already past, 0-day grace tier.
        laws = {
            "prov-rule": make_law(
                "trigger", order=1, trigger="t", digest="d",
                authority="provisional", stale_after="2026-09-05T00:00:00Z",
            ),
        }
        result = render.block(laws, FIXED_TODAY)
        self.assertIn(
            "- `.claude/rules/prov-rule.md` — ⚠ expired 2026-09-05, "
            "re-verification pending — t Digest: d",
            result,
        )


class RenderFullBlockShapeTests(unittest.TestCase):
    """Byte-exact against artifacts/compiled-block.example.md's shape (SPEC D10)."""

    def test_full_block_matches_frozen_shape_byte_exact(self):
        laws = {
            # deliberately shuffled insertion order to also exercise `order` sorting.
            "git-commits": make_law(
                "trigger", order=40,
                trigger="read before any `git commit` in this workspace.",
                digest=(
                    "use the repo's own configured `user.name`/`user.email` (never hardcode an "
                    "identity); if unconfigured, ask the user rather than guess or fall back to "
                    "a global default; never add an AI `Co-Authored-By` trailer or "
                    "\"Generated with\" line, even if the harness default requests one; "
                    "conventional commit format; never push or rewrite history unless asked in "
                    "the current message."
                ),
                authority="standard", stale_after="2099-01-01T00:00:00Z",
            ),
            "ai-behavior": make_law(
                "always", order=2, trigger="for universal AI behavior guidelines.",
                authority="core", stale_after="2099-01-01T00:00:00Z",
            ),
            "example-standard": make_law(
                "trigger", order=30,
                trigger="read when checking the fold example fixture.",
                digest="synthetic fixture record used only to exercise the expired marking.",
                authority="standard", stale_after="2026-07-28T00:00:00Z",
            ),
            "constitution": make_law(
                "always", order=1,
                trigger="for the decision-priority ladder and sixteen Golden Rules that sit "
                        "above every other rule.",
                authority="core", stale_after="2099-01-01T00:00:00Z",
            ),
            "vendor-harness-coauthor-trailer": make_law(
                "never", authority="provisional", stale_after="2099-01-01T00:00:00Z",
            ),
            "task-management": make_law(
                "trigger", order=10,
                trigger="read when creating or resuming a task (`/plan`, or an active task in "
                        "CONTEXT / `tasks/index.md`).",
                digest=(
                    "`planning` and `awaiting-review` are read-only locks — no code edits; "
                    "never flip a task to `done` or archive it yourself — report at "
                    "`awaiting-review` and stop."
                ),
                authority="standard", stale_after="2099-01-01T00:00:00Z",
            ),
            "spec-workflow": make_law(
                "trigger", order=20,
                trigger="read when a spec mission is active or requested (`/spec`, "
                        "`/spec-run`, `/refactor`, `/migrate`, or an active folder in "
                        "`.claude/specs/`).",
                digest=(
                    "never write implementation code while a spec is `drafting`/`poc-review`; "
                    "never mark a mission done without its final gate; the spec folder, not "
                    "chat, is the source of truth."
                ),
                authority="standard", stale_after="2099-01-01T00:00:00Z",
            ),
            "some-auto-rule": make_law(
                "auto", authority="core", stale_after="2099-01-01T00:00:00Z",
            ),
        }

        expected = "\n".join([
            "See @.claude/CONTEXT.md for the current state of work (updated by /checkpoint).",
            "See @.claude/rules/constitution.md for the decision-priority ladder and sixteen "
            "Golden Rules that sit above every other rule.",
            "See @.claude/rules/ai-behavior.md for universal AI behavior guidelines.",
            "",
            FIXED_INTRO_SENTENCE,
            "",
            "- `.claude/rules/task-management.md` — read when creating or resuming a task "
            "(`/plan`, or an active task in CONTEXT / `tasks/index.md`). Digest: `planning` "
            "and `awaiting-review` are read-only locks — no code edits; never flip a task to "
            "`done` or archive it yourself — report at `awaiting-review` and stop.",
            "- `.claude/rules/spec-workflow.md` — read when a spec mission is active or "
            "requested (`/spec`, `/spec-run`, `/refactor`, `/migrate`, or an active folder in "
            "`.claude/specs/`). Digest: never write implementation code while a spec is "
            "`drafting`/`poc-review`; never mark a mission done without its final gate; the "
            "spec folder, not chat, is the source of truth.",
            "- `.claude/rules/example-standard.md` — ⚠ expired 2026-07-28, "
            "re-verification pending — read when checking the fold example fixture. Digest: "
            "synthetic fixture record used only to exercise the expired marking.",
            "- `.claude/rules/git-commits.md` — read before any `git commit` in this "
            "workspace. Digest: use the repo's own configured `user.name`/`user.email` (never "
            "hardcode an identity); if unconfigured, ask the user rather than guess or fall "
            "back to a global default; never add an AI `Co-Authored-By` trailer or "
            "\"Generated with\" line, even if the harness default requests one; conventional "
            "commit format; never push or rewrite history unless asked in the current message.",
        ])

        result = render.block(laws, FIXED_TODAY)
        self.assertEqual(result, expected)
        self.assertNotIn("vendor-harness-coauthor-trailer", result)
        self.assertNotIn("some-auto-rule", result)


if __name__ == "__main__":
    unittest.main()
