"""
Failing-first unit tests for the pure core of the CLAUDART law engine.

The implementation under test (`.claude/scripts/law/core/{schema,overlap,retirement,budget}.py`)
does NOT exist yet. This file is expected to fail on import. That failure IS the deliverable
(observed RED, per `.claude/scripts/law/SCHEMA.md` and `evidence-gauntlet.md`).

============================================================================
API CONTRACT — the implementer builds exactly this shape (chosen by this test file)
============================================================================

Package layout: `.claude/scripts/law/core/__init__.py`, `schema.py`, `overlap.py`,
`retirement.py`, `budget.py`. No I/O in any of the four modules (no os/sys/json/pathlib/
subprocess imports) — every function takes plain Python data and returns plain Python data.

    # law/core/schema.py (or re-exported from law/core/__init__.py)
    @dataclass
    class Finding:
        code: str       # one of the eleven codes in SCHEMA.md section 6
        law_id: str     # the record/pair/proposal identifier the finding is about
        message: str    # human-readable detail; NEVER asserted on by these tests

    def validate(record: dict, law_id: str) -> list[Finding]:
        # Validate one parsed frontmatter dict against the SCHEMA.md field table and the
        # `load` conditional matrix. Returns [] when the record is fully conformant. Every
        # Finding.law_id in the result equals the `law_id` argument.
        ...

    # law/core/overlap.py
    def check(records: dict[str, dict]) -> list[Finding]:
        # records maps law_id -> parsed frontmatter dict (must carry at least `paths`,
        # `tags`, `level`, and optionally `overrides`/`supersedes_in_scope`/`layers_on`).
        #
        # Emits, per SCHEMA.md section 4:
        #   - UNDECLARED-OVERLAP: for each unordered pair of overlap candidates (paths can
        #     overlap AND share >=1 tag) where neither side declares a relationship toward the
        #     other. Finding.law_id for this code is the pair's two ids sorted and joined with
        #     "|" (e.g. "record-a|record-b") since the violation belongs to the pair, not either
        #     single record.
        #   - OVERRIDES-CONSTITUTION: Finding.law_id is the id of the record whose `overrides`
        #     illegally names a `level: constitution` record.
        #   - BAD-LAYER: Finding.law_id is the id of the offending `level: convention` record
        #     (one that uses `overrides` at all, or whose `layers_on` targets a non-`law`
        #     record).
        # Returns [] when a pair is legally declared or not an overlap candidate at all.
        ...

    # law/core/retirement.py
    def derive_stale_after(record: dict) -> str:
        # Returns the record's effective `stale_after` as an absolute ISO instant string
        # ("YYYY-MM-DDTHH:MM:SSZ"). If `record["stale_after"]` is present, it is returned
        # UNCHANGED (explicit always wins). Otherwise it is derived from `record["since"]`
        # ("YYYY-MM-DD") plus an offset by `record["authority"]`: core/standard -> +12 months,
        # provisional -> +6 months. Time-of-day on a derived value is always "00:00:00Z".
        ...

    def is_expired(record: dict, today: datetime.date) -> bool:
        # True iff `today` is strictly past the date portion of the record's effective
        # `stale_after` (explicit or derived via derive_stale_after).
        ...

    def marking(record: dict, today: datetime.date) -> tuple[bool, str | None]:
        # Decides whether the record's compiled CLAUDE.md line should carry the marking
        # string, tiered by `record["authority"]` per SCHEMA.md section 3:
        #   - core: never marked -> always (False, None), regardless of how expired.
        #   - standard: marked only once >30 days past effective stale_after; within the
        #     30-day grace (including exactly at expiry) -> (False, None).
        #   - provisional: marked from the moment effective stale_after passes (0-day grace).
        # When should_mark is True, the string is EXACTLY:
        #     "⚠ expired <YYYY-MM-DD>, re-verification pending — "
        # (note the trailing space), where <YYYY-MM-DD> is the effective stale_after's date.
        ...

    def evaluate(records: dict[str, dict], today: datetime.date) -> list[Finding]:
        # Returns one EXPIRED Finding per record (keyed by law_id) whose is_expired(record,
        # today) is True. Never raises for a record that is not expired; contributes nothing
        # for it.
        ...

    # law/core/budget.py
    def check_queue(proposals: list[dict], expired_laws: list[dict], budget_cfg: dict,
                     today: datetime.date) -> list[Finding]:
        # proposals: [{"id": str, "expires": datetime.date}, ...] (an open reviewer-queue
        # proposal's expiry date). expired_laws: [{"id": str, "stale_after": datetime.date}, ...]
        # (an EXPIRED law's effective expiry date). budget_cfg carries at least
        # "queue_max_age_days" (int). Emits QUEUE-STALE (Finding.law_id = the item's "id") for
        # any proposal or expired law whose (today - expiry_date).days > queue_max_age_days.
        # Items within the window contribute nothing.
        ...

    def check_new_proposal(existing_count_this_month: int, budget_cfg: dict,
                            today: datetime.date) -> list[Finding]:
        # budget_cfg carries at least "max_proposals_per_month" (int). Emits one OVER-BUDGET
        # Finding (Finding.law_id = "<current-month>", e.g. "2026-09") when creating one more
        # proposal this calendar month (existing_count_this_month + 1) would exceed
        # max_proposals_per_month. Returns [] when creating it would stay at or under the cap.
        ...

    def is_blocking(findings: list[Finding]) -> bool:
        # Severity classification, NOT a process exit call (the core never exits): True iff
        # `findings` contains at least one Finding whose code is anything other than "EXPIRED".
        # An EXPIRED-only (or empty) list classifies as non-blocking, matching SCHEMA.md's rule
        # that EXPIRED alone never fails `validate` while QUEUE-STALE (and every other code)
        # does.
        ...

============================================================================
"""

import os
import sys
import unittest
from datetime import date

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", ".claude", "scripts"))

from law.core import schema, overlap, retirement, budget
from law.core.schema import Finding


def codes_for(findings, law_id=None):
    """Set of finding codes, optionally filtered to one law_id."""
    return {f.code for f in findings if law_id is None or f.law_id == law_id}


# ---------------------------------------------------------------------------
# schema
# ---------------------------------------------------------------------------

def conformant_trigger_record():
    """A fully conformant `load: trigger` record (mirrors SCHEMA.md's worked example)."""
    return {
        "paths": ["**/*"],
        "description": "Commit authorship and message rules for this workspace.",
        "when_to_use": "Before any git commit in this workspace.",
        "tags": ["git", "commits", "authorship"],
        "level": "law",
        "authority": "standard",
        "status": "approved",
        "since": "2026-08-30",
        "stale_after": "2027-08-30T00:00:00Z",
        "verified": [{"by": "human:lapnd", "at": "2026-08-30T00:00:00Z"}],
        "enforcer": "judgement",
        "load": "trigger",
        "order": 90,
        "trigger": "read before any git commit in this workspace.",
        "digest": "use the repo's own configured identity; ...",
    }


def conformant_always_record():
    r = conformant_trigger_record()
    r["load"] = "always"
    r["order"] = 10
    r["trigger"] = "for the fixture decision ladder."
    del r["digest"]
    return r


def conformant_auto_record():
    r = conformant_trigger_record()
    r["load"] = "auto"
    del r["order"]
    del r["trigger"]
    del r["digest"]
    return r


def conformant_never_record():
    r = conformant_auto_record()
    r["load"] = "never"
    return r


REQUIRED_FIELDS = [
    "level",
    "authority",
    "status",
    "since",
    "stale_after",
    "verified",
    "enforcer",
    "load",
]


class SchemaMissingFieldTests(unittest.TestCase):
    """Each required field absent -> MISSING-FIELD."""

    def _assert_missing(self, field):
        record = conformant_trigger_record()
        del record[field]
        findings = schema.validate(record, "law-under-test")
        self.assertIn("MISSING-FIELD", codes_for(findings))
        for f in findings:
            self.assertEqual(f.law_id, "law-under-test")

    def test_missing_level(self):
        self._assert_missing("level")

    def test_missing_authority(self):
        self._assert_missing("authority")

    def test_missing_status(self):
        self._assert_missing("status")

    def test_missing_since(self):
        self._assert_missing("since")

    def test_missing_stale_after(self):
        self._assert_missing("stale_after")

    def test_missing_verified(self):
        self._assert_missing("verified")

    def test_missing_enforcer(self):
        self._assert_missing("enforcer")

    def test_missing_load(self):
        self._assert_missing("load")


class SchemaBadVocabTests(unittest.TestCase):
    """Each enumerated field given an out-of-vocabulary value -> BAD-VOCAB."""

    def _assert_bad_vocab(self, field, bad_value):
        record = conformant_trigger_record()
        record[field] = bad_value
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-VOCAB", codes_for(findings))

    def test_bad_level(self):
        self._assert_bad_vocab("level", "not-a-real-level")

    def test_bad_authority(self):
        self._assert_bad_vocab("authority", "not-a-real-authority")

    def test_bad_status(self):
        self._assert_bad_vocab("status", "not-a-real-status")

    def test_bad_load(self):
        self._assert_bad_vocab("load", "not-a-real-load")


class SchemaStaleAfterTests(unittest.TestCase):
    """`stale_after` present but not an absolute ISO instant -> BAD-STALE-AFTER."""

    def test_bare_date_is_bad_stale_after(self):
        record = conformant_trigger_record()
        record["stale_after"] = "2027-08-30"
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-STALE-AFTER", codes_for(findings))

    def test_relative_expression_is_bad_stale_after(self):
        record = conformant_trigger_record()
        record["stale_after"] = "+30d"
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-STALE-AFTER", codes_for(findings))


class SchemaEnforcerTests(unittest.TestCase):
    def test_blank_enforcer_is_missing_field(self):
        record = conformant_trigger_record()
        record["enforcer"] = ""
        findings = schema.validate(record, "law-under-test")
        self.assertIn("MISSING-FIELD", codes_for(findings))

    def test_check_with_empty_path_is_missing_field(self):
        record = conformant_trigger_record()
        record["enforcer"] = "check:"
        findings = schema.validate(record, "law-under-test")
        self.assertIn("MISSING-FIELD", codes_for(findings))

    def test_malformed_enforcer_shape_is_bad_vocab(self):
        record = conformant_trigger_record()
        record["enforcer"] = "banana:something"
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-VOCAB", codes_for(findings))


class SchemaApprovedWithoutHumanTests(unittest.TestCase):
    def test_approved_with_only_agent_verifier_is_flagged(self):
        record = conformant_trigger_record()
        record["status"] = "approved"
        record["verified"] = [{"by": "agent:claude", "at": "2026-08-30T00:00:00Z"}]
        findings = schema.validate(record, "law-under-test")
        self.assertIn("APPROVED-WITHOUT-HUMAN", codes_for(findings))

    def test_approved_with_human_verifier_added_has_no_finding(self):
        record = conformant_trigger_record()
        record["status"] = "approved"
        record["verified"] = [
            {"by": "agent:claude", "at": "2026-08-30T00:00:00Z"},
            {"by": "human:lapnd", "at": "2026-08-30T00:00:00Z"},
        ]
        findings = schema.validate(record, "law-under-test")
        self.assertEqual(findings, [])


class SchemaLoadMatrixTests(unittest.TestCase):
    """The `load` conditional matrix for order/trigger/digest, per SCHEMA.md section 2."""

    # load: always -> order required, trigger required, digest forbidden
    def test_always_missing_order_is_missing_field(self):
        record = conformant_always_record()
        del record["order"]
        findings = schema.validate(record, "law-under-test")
        self.assertIn("MISSING-FIELD", codes_for(findings))

    def test_always_missing_trigger_is_missing_field(self):
        record = conformant_always_record()
        del record["trigger"]
        findings = schema.validate(record, "law-under-test")
        self.assertIn("MISSING-FIELD", codes_for(findings))

    def test_always_with_digest_is_bad_vocab(self):
        record = conformant_always_record()
        record["digest"] = "should not be here"
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-VOCAB", codes_for(findings))

    # load: trigger -> order required, trigger required, digest required
    def test_trigger_missing_order_is_missing_field(self):
        record = conformant_trigger_record()
        del record["order"]
        findings = schema.validate(record, "law-under-test")
        self.assertIn("MISSING-FIELD", codes_for(findings))

    def test_trigger_missing_trigger_is_missing_field(self):
        record = conformant_trigger_record()
        del record["trigger"]
        findings = schema.validate(record, "law-under-test")
        self.assertIn("MISSING-FIELD", codes_for(findings))

    def test_trigger_missing_digest_is_missing_field(self):
        record = conformant_trigger_record()
        del record["digest"]
        findings = schema.validate(record, "law-under-test")
        self.assertIn("MISSING-FIELD", codes_for(findings))

    # load: auto -> order/trigger/digest all forbidden
    def test_auto_with_order_is_bad_vocab(self):
        record = conformant_auto_record()
        record["order"] = 1
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-VOCAB", codes_for(findings))

    def test_auto_with_trigger_is_bad_vocab(self):
        record = conformant_auto_record()
        record["trigger"] = "should not be here"
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-VOCAB", codes_for(findings))

    def test_auto_with_digest_is_bad_vocab(self):
        record = conformant_auto_record()
        record["digest"] = "should not be here"
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-VOCAB", codes_for(findings))

    # load: never -> order/trigger/digest all forbidden
    def test_never_with_order_is_bad_vocab(self):
        record = conformant_never_record()
        record["order"] = 1
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-VOCAB", codes_for(findings))

    def test_never_with_trigger_is_bad_vocab(self):
        record = conformant_never_record()
        record["trigger"] = "should not be here"
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-VOCAB", codes_for(findings))

    def test_never_with_digest_is_bad_vocab(self):
        record = conformant_never_record()
        record["digest"] = "should not be here"
        findings = schema.validate(record, "law-under-test")
        self.assertIn("BAD-VOCAB", codes_for(findings))


class SchemaPositiveControlTests(unittest.TestCase):
    """A fully conformant record, one per `load` value, returns zero findings."""

    def test_conformant_trigger_record_has_no_findings(self):
        self.assertEqual(schema.validate(conformant_trigger_record(), "law-under-test"), [])

    def test_conformant_always_record_has_no_findings(self):
        self.assertEqual(schema.validate(conformant_always_record(), "law-under-test"), [])

    def test_conformant_auto_record_has_no_findings(self):
        self.assertEqual(schema.validate(conformant_auto_record(), "law-under-test"), [])

    def test_conformant_never_record_has_no_findings(self):
        self.assertEqual(schema.validate(conformant_never_record(), "law-under-test"), [])


# ---------------------------------------------------------------------------
# overlap
# ---------------------------------------------------------------------------

def pair_key(a, b):
    return "|".join(sorted([a, b]))


OVERLAPPING_GLOB = ["src/**/*.go"]
DISJOINT_GLOB = ["docs/**/*.md"]


class OverlapUndeclaredTests(unittest.TestCase):
    def test_overlap_candidates_with_no_declaration_is_undeclared_overlap(self):
        records = {
            "record-a": {"paths": OVERLAPPING_GLOB, "tags": ["shared-tag"], "level": "law"},
            "record-b": {"paths": OVERLAPPING_GLOB, "tags": ["shared-tag"], "level": "law"},
        }
        findings = overlap.check(records)
        self.assertIn("UNDECLARED-OVERLAP", codes_for(findings))
        self.assertIn(pair_key("record-a", "record-b"), {f.law_id for f in findings})

    def test_declared_overrides_in_direction_a_to_b_has_no_finding(self):
        records = {
            "record-a": {
                "paths": OVERLAPPING_GLOB,
                "tags": ["shared-tag"],
                "level": "law",
                "overrides": ["record-b"],
            },
            "record-b": {"paths": OVERLAPPING_GLOB, "tags": ["shared-tag"], "level": "law"},
        }
        findings = overlap.check(records)
        self.assertEqual(findings, [])

    def test_declared_overrides_in_direction_b_to_a_has_no_finding(self):
        records = {
            "record-a": {"paths": OVERLAPPING_GLOB, "tags": ["shared-tag"], "level": "law"},
            "record-b": {
                "paths": OVERLAPPING_GLOB,
                "tags": ["shared-tag"],
                "level": "law",
                "overrides": ["record-a"],
            },
        }
        findings = overlap.check(records)
        self.assertEqual(findings, [])

    def test_overlapping_globs_disjoint_tags_has_no_finding(self):
        records = {
            "record-a": {"paths": OVERLAPPING_GLOB, "tags": ["tag-a"], "level": "law"},
            "record-b": {"paths": OVERLAPPING_GLOB, "tags": ["tag-b"], "level": "law"},
        }
        findings = overlap.check(records)
        self.assertEqual(findings, [])

    def test_shared_tag_disjoint_globs_has_no_finding(self):
        records = {
            "record-a": {"paths": OVERLAPPING_GLOB, "tags": ["shared-tag"], "level": "law"},
            "record-b": {"paths": DISJOINT_GLOB, "tags": ["shared-tag"], "level": "law"},
        }
        findings = overlap.check(records)
        self.assertEqual(findings, [])


class OverlapLevelRuleTests(unittest.TestCase):
    def test_overrides_naming_a_constitution_record_is_flagged(self):
        records = {
            "law-x": {
                "paths": ["a/**"],
                "tags": ["tag-x"],
                "level": "law",
                "overrides": ["const-x"],
            },
            "const-x": {"paths": ["b/**"], "tags": ["tag-y"], "level": "constitution"},
        }
        findings = overlap.check(records)
        self.assertIn("OVERRIDES-CONSTITUTION", codes_for(findings, "law-x"))

    def test_convention_using_overrides_is_bad_layer(self):
        records = {
            "conv-x": {
                "paths": ["a/**"],
                "tags": ["tag-x"],
                "level": "convention",
                "overrides": ["law-y"],
            },
            "law-y": {"paths": ["b/**"], "tags": ["tag-y"], "level": "law"},
        }
        findings = overlap.check(records)
        self.assertIn("BAD-LAYER", codes_for(findings, "conv-x"))

    def test_convention_layers_on_non_law_is_bad_layer(self):
        records = {
            "conv-y": {
                "paths": ["a/**"],
                "tags": ["tag-x"],
                "level": "convention",
                "layers_on": ["vendor-z"],
            },
            "vendor-z": {"paths": ["b/**"], "tags": ["tag-y"], "level": "vendor-default"},
        }
        findings = overlap.check(records)
        self.assertIn("BAD-LAYER", codes_for(findings, "conv-y"))

    def test_convention_layers_on_law_has_no_finding(self):
        records = {
            "conv-z": {
                "paths": ["a/**"],
                "tags": ["tag-x"],
                "level": "convention",
                "layers_on": ["law-w"],
            },
            "law-w": {"paths": ["b/**"], "tags": ["tag-y"], "level": "law"},
        }
        findings = overlap.check(records)
        self.assertEqual(findings, [])


# ---------------------------------------------------------------------------
# retirement
# ---------------------------------------------------------------------------

FIXED_TODAY = date(2026, 6, 15)


class RetirementExpiryTests(unittest.TestCase):
    def test_past_stale_after_is_expired(self):
        record = {"authority": "standard", "stale_after": "2026-01-01T00:00:00Z"}
        findings = retirement.evaluate({"law-x": record}, FIXED_TODAY)
        self.assertIn("EXPIRED", codes_for(findings, "law-x"))

    def test_not_yet_past_stale_after_has_no_finding(self):
        record = {"authority": "standard", "stale_after": "2030-01-01T00:00:00Z"}
        findings = retirement.evaluate({"law-x": record}, FIXED_TODAY)
        self.assertEqual(findings, [])


class RetirementTierBehaviorTests(unittest.TestCase):
    def test_core_past_expiry_is_queued_and_never_marked(self):
        record = {"authority": "core", "stale_after": "2026-01-01T00:00:00Z"}
        findings = retirement.evaluate({"core-law": record}, FIXED_TODAY)
        self.assertIn("EXPIRED", codes_for(findings, "core-law"))
        self.assertEqual(retirement.marking(record, FIXED_TODAY), (False, None))

    def test_standard_within_30_day_grace_is_queued_and_not_marked(self):
        # stale_after 2026-06-01, today 2026-06-15 -> 14 days past, within the 30-day grace.
        record = {"authority": "standard", "stale_after": "2026-06-01T00:00:00Z"}
        findings = retirement.evaluate({"std-law": record}, FIXED_TODAY)
        self.assertIn("EXPIRED", codes_for(findings, "std-law"))
        self.assertEqual(retirement.marking(record, FIXED_TODAY), (False, None))

    def test_standard_past_30_day_grace_is_marked(self):
        # stale_after 2026-01-01, today 2026-06-15 -> ~165 days past, well past the 30-day grace.
        record = {"authority": "standard", "stale_after": "2026-01-01T00:00:00Z"}
        should_mark, line = retirement.marking(record, FIXED_TODAY)
        self.assertTrue(should_mark)
        self.assertEqual(line, "⚠ expired 2026-01-01, re-verification pending — ")

    def test_provisional_is_marked_from_moment_of_expiry(self):
        # stale_after one day before today -> already past, 0-day grace tier.
        record = {"authority": "provisional", "stale_after": "2026-06-14T00:00:00Z"}
        should_mark, line = retirement.marking(record, FIXED_TODAY)
        self.assertTrue(should_mark)
        self.assertEqual(line, "⚠ expired 2026-06-14, re-verification pending — ")


class RetirementDerivedStaleAfterTests(unittest.TestCase):
    def test_core_default_offset_is_12_months(self):
        record = {"authority": "core", "since": "2026-01-01"}
        self.assertEqual(retirement.derive_stale_after(record), "2027-01-01T00:00:00Z")

    def test_standard_default_offset_is_12_months(self):
        record = {"authority": "standard", "since": "2026-01-01"}
        self.assertEqual(retirement.derive_stale_after(record), "2027-01-01T00:00:00Z")

    def test_provisional_default_offset_is_6_months(self):
        record = {"authority": "provisional", "since": "2026-01-01"}
        self.assertEqual(retirement.derive_stale_after(record), "2026-07-01T00:00:00Z")

    def test_explicit_stale_after_wins_over_derived(self):
        record = {
            "authority": "provisional",
            "since": "2020-01-01",
            "stale_after": "2099-01-01T00:00:00Z",
        }
        self.assertEqual(retirement.derive_stale_after(record), "2099-01-01T00:00:00Z")


# ---------------------------------------------------------------------------
# budget
# ---------------------------------------------------------------------------

BUDGET_TODAY = date(2026, 9, 6)
BUDGET_CFG = {
    "queue_max_age_days": 30,
    "max_proposals_per_month": 4,
}


class BudgetQueueStaleTests(unittest.TestCase):
    def test_open_proposal_older_than_max_age_is_queue_stale(self):
        # expires 2026-08-01 -> 36 days before BUDGET_TODAY, > 30-day window.
        proposals = [{"id": "prop-old", "expires": date(2026, 8, 1)}]
        findings = budget.check_queue(proposals, [], BUDGET_CFG, BUDGET_TODAY)
        self.assertIn("QUEUE-STALE", codes_for(findings, "prop-old"))

    def test_expired_law_older_than_max_age_is_queue_stale(self):
        expired_laws = [{"id": "law-old", "stale_after": date(2026, 8, 1)}]
        findings = budget.check_queue([], expired_laws, BUDGET_CFG, BUDGET_TODAY)
        self.assertIn("QUEUE-STALE", codes_for(findings, "law-old"))

    def test_proposal_within_window_has_no_finding(self):
        # expires 2026-08-20 -> 17 days before BUDGET_TODAY, within the 30-day window.
        proposals = [{"id": "prop-fresh", "expires": date(2026, 8, 20)}]
        findings = budget.check_queue(proposals, [], BUDGET_CFG, BUDGET_TODAY)
        self.assertEqual(findings, [])


class BudgetOverBudgetTests(unittest.TestCase):
    def test_creating_beyond_cap_is_over_budget(self):
        # 4 already exist this month; creating a 5th exceeds max_proposals_per_month=4.
        findings = budget.check_new_proposal(4, BUDGET_CFG, BUDGET_TODAY)
        self.assertIn("OVER-BUDGET", codes_for(findings))

    def test_creating_at_cap_has_no_finding(self):
        # 3 already exist this month; creating a 4th reaches exactly the cap.
        findings = budget.check_new_proposal(3, BUDGET_CFG, BUDGET_TODAY)
        self.assertEqual(findings, [])


class BudgetSeverityClassificationTests(unittest.TestCase):
    def test_expired_alone_is_not_blocking(self):
        findings = [Finding(code="EXPIRED", law_id="law-x", message="expired")]
        self.assertFalse(budget.is_blocking(findings))

    def test_queue_stale_is_blocking(self):
        findings = [Finding(code="QUEUE-STALE", law_id="prop-old", message="stale")]
        self.assertTrue(budget.is_blocking(findings))

    def test_expired_plus_queue_stale_is_blocking(self):
        findings = [
            Finding(code="EXPIRED", law_id="law-x", message="expired"),
            Finding(code="QUEUE-STALE", law_id="prop-old", message="stale"),
        ]
        self.assertTrue(budget.is_blocking(findings))


if __name__ == "__main__":
    unittest.main()
