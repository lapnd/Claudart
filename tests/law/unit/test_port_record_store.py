"""
Failing-first SHARED CONTRACT test for the outbound `record-store` port of the CLAUDART law
engine (SPEC D15 / P1.4). Neither the port module nor any adapter exists yet — this file is
expected to fail on IMPORT (ImportError), and that failure IS the deliverable (observed RED, per
`.claude/scripts/law/SCHEMA.md`, `.claude/scripts/law/LESSONS.md`, `graph-development.md` §4-5,
and `evidence-gauntlet.md`).

============================================================================
API CONTRACT — the implementer builds exactly this shape (chosen by this test file)
============================================================================

Package layout: `.claude/scripts/law/ports/record_store.py` (the Protocol + the dataclasses
below) and one module per adapter, e.g. `.claude/scripts/law/adapters/fs_records.py` (class
`FsRecordStore`, node `adapter/fs-records`, P1.5) and
`.claude/scripts/law/adapters/jsonl_lessons.py` (class `JsonlLessonStore`, node
`adapter/jsonl-lessons`, P2.5). The port's methods are INSTANCE methods (not free functions) so
that an adapter is a constructible object with no required constructor arguments — `FsRecordStore()`
and `JsonlLessonStore()` must both work with zero args, discovering paths purely from the
arguments passed to each call. Both adapter classes implement the FULL Protocol below (the single
shared contract in this file exercises every method against whichever adapter `make_store()`
returns) — how each adapter internally satisfies the lesson/hours methods versus the law/budget/
proposal methods is an implementation decision for P1.5/P2.5, not this contract's concern.

    # law/ports/record_store.py
    from dataclasses import dataclass
    from typing import Protocol, Iterator

    @dataclass
    class LawRecord:
        id: str            # law id = the file's path under the rules dir, without ".md",
                            # using "/" separators (e.g. "git-commits" or "vendor/harness-x").
        path: str           # filesystem path to the .md file, as passed to/derived from load_laws.
        frontmatter: dict   # parsed YAML frontmatter (delimited by "---" lines) as a plain dict.
                            # Flow-style and block-style lists parse to the same Python list;
                            # a `verified` entry (or any one-key-mapping-per-list-item field)
                            # parses to a list of plain dicts, flow or block, per SCHEMA.md §8.
        body: str           # the prose after the closing "---" delimiter, verbatim.

    @dataclass
    class Proposal:
        id: str    # proposal id (filename stem, without ".md" / ".expired.md")
        path: str  # filesystem path to the proposal file
        text: str  # full raw file content (frontmatter + body) as written by write_proposal

    class RecordStore(Protocol):
        def load_laws(self, rules_dir: str) -> list[LawRecord]:
            # Recursively loads every "*.md" file under rules_dir, INCLUDING any nested under a
            # "vendor/" subdirectory. A record under "<rules_dir>/vendor/x.md" gets id
            # "vendor/x". Order is not part of the contract (tests compare by id, not position).
            ...

        def load_budget(self, path: str) -> dict:
            # Parses the YAML file at `path` and returns it as a plain dict carrying at least
            # the five D6 keys: "project" (str), "hours_per_month", "max_proposals_per_month",
            # "proposal_expires_days", "queue_max_age_days" (numeric).
            ...

        def list_proposals(self, proposals_dir: str) -> list[Proposal]:
            # Returns every OPEN proposal under proposals_dir — i.e. every "<id>.md" file, never
            # a "<id>.expired.md" one. Order is not part of the contract.
            ...

        def write_proposal(self, proposals_dir: str, proposal_id: str, text: str) -> None:
            # Writes "<proposals_dir>/<proposal_id>.md" with content exactly `text` (creating
            # proposals_dir if it does not exist).
            ...

        def expire_proposal(self, proposals_dir: str, proposal_id: str) -> None:
            # Renames "<proposals_dir>/<proposal_id>.md" to
            # "<proposals_dir>/<proposal_id>.expired.md". After this call the proposal no longer
            # appears in list_proposals's result.
            ...

        def set_status(self, law_path: str, status: str) -> None:
            # Rewrites ONLY the frontmatter "status:" line's value in the file at `law_path` to
            # `status`, in place. Every other byte of the file — other frontmatter fields, their
            # order, the body, blank lines, and the trailing newline (or lack of one) — is
            # preserved exactly. Works regardless of whether "status:" is the first frontmatter
            # field or sits mid-frontmatter.
            ...

        def append_lesson(self, path: str, obj: dict) -> None:
            # Appends `obj` as one JSON line to the JSONL file at `path` (creating parent
            # directories and the file as needed). The permitted key set is CLOSED — exactly the
            # eleven keys from LESSONS.md §1.1: id, ts, project, source, kind, signal, summary,
            # candidate_law, matched_against, extraction_pass, reviewed. Raises ValueError, and
            # appends NOTHING to the file (a rejected write leaves no trace — the file is left
            # byte-identical to its state before the call, including staying absent if it did
            # not exist), when `obj` carries any key outside that set (e.g. the specifically
            # forbidden `confidence`) or is missing the required `signal` key. This contract
            # exercises only those two rejection cases; the full validation surface (enum checks
            # on kind/signal, type checks, etc.) belongs to LESSONS.md §7 and a future node.
            ...

        def iter_lessons(self, path: str) -> Iterator[dict]:
            # Yields each line of the JSONL file at `path`, parsed to a dict, in append order.
            # A `path` that does not exist yields nothing (an empty iterator) — it never raises.
            ...

        def append_hours(self, path: str, obj: dict) -> None:
            # Appends `obj` (shape: {"ts": str, "minutes": int, "activity": str}) as one JSON
            # line to the JSONL file at `path` (creating parent directories/file as needed).
            ...

        def iter_hours(self, path: str) -> Iterator[dict]:
            # Same contract as iter_lessons: append order, empty iterator for an absent file.
            ...

============================================================================
EXTENDING THIS CONTRACT — the one-edit instruction for the next adapter
============================================================================

`RecordStoreContract` below holds every assertion and is NOT itself a `unittest.TestCase`
subclass (so bare `unittest discover` never collects or runs it directly — only its
`*ContractTests` subclasses are collected). To add a new adapter's node to this shared contract,
add ONE small subclass, e.g.:

    class NewAdapterContractTests(RecordStoreContract, unittest.TestCase):
        def make_store(self):
            return NewAdapterClass()

That subclass inherits every assertion in `RecordStoreContract` unchanged — no test body is ever
copied. `FsRecordsContractTests` (adapter/fs-records, P1.5) and `JsonlLessonsContractTests`
(adapter/jsonl-lessons, P2.5) below are exactly this shape, targeting their respective
not-yet-implemented adapter modules.
============================================================================
"""

import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", ".claude", "scripts"))

from law.ports.record_store import (  # noqa: F401
    InMemoryRecordStore,
    LawRecord,
    Proposal,
    RecordStore,
)


# ---------------------------------------------------------------------------
# fixtures (built inline — never read from tests/law/fixtures/)
# ---------------------------------------------------------------------------

def valid_lesson():
    """A fully conformant lesson object carrying exactly the eleven permitted keys."""
    return {
        "id": "L-2026-001",
        "ts": "2026-09-12T10:00:00Z",
        "project": "claudart",
        "source": "ledger:tests/law/unit/test_port_record_store.py#L1",
        "kind": "correction",
        "signal": "user-correction",
        "summary": "Agent used the record-store contract instead of ad-hoc file writes.",
        "candidate_law": "law/example-candidate",
        "matched_against": [],
        "extraction_pass": 1,
        "reviewed": False,
    }


def valid_hours_entry():
    return {"ts": "2026-09-15T14:30:00Z", "minutes": 90, "activity": "proposal review"}


RECORD_TEMPLATE = """---
level: law
authority: standard
status: approved
since: 2026-01-01
tags: [a, b]
---
Body prose for {name}.
"""


# ---------------------------------------------------------------------------
# the shared contract — a mixin, deliberately NOT a unittest.TestCase subclass
# ---------------------------------------------------------------------------

class RecordStoreContract:
    """Every assertion the record-store port must satisfy, for ANY adapter `make_store()` returns.

    Subclasses must also inherit `unittest.TestCase` and implement `make_store(self)`.
    """

    def make_store(self):
        raise NotImplementedError("subclass must return an adapter instance")

    def setUp(self):
        self.store = self.make_store()
        self.tmp = tempfile.mkdtemp(prefix="record-store-contract-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write(self, path, content):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(content.encode("utf-8"))

    def _read_bytes(self, path):
        with open(path, "rb") as f:
            return f.read()

    # -- 1. load_laws including vendor/ ------------------------------------

    def test_load_laws_includes_vendor_subdirectory(self):
        rules_dir = os.path.join(self.tmp, "rules")
        self._write(os.path.join(rules_dir, "top-a.md"), RECORD_TEMPLATE.format(name="top-a"))
        self._write(os.path.join(rules_dir, "top-b.md"), RECORD_TEMPLATE.format(name="top-b"))
        self._write(
            os.path.join(rules_dir, "vendor", "vendor-x.md"),
            RECORD_TEMPLATE.format(name="vendor-x"),
        )

        records = self.store.load_laws(rules_dir)

        self.assertEqual(len(records), 3)
        ids = {r.id for r in records}
        self.assertEqual(ids, {"top-a", "top-b", "vendor/vendor-x"})
        by_id = {r.id: r for r in records}
        self.assertEqual(by_id["vendor/vendor-x"].frontmatter["status"], "approved")
        self.assertEqual(by_id["top-a"].frontmatter["level"], "law")

    # -- 2. load_budget ------------------------------------------------------

    def test_load_budget_reads_the_five_d6_keys(self):
        budget_path = os.path.join(self.tmp, "budget.yaml")
        self._write(
            budget_path,
            "project: claudart\n"
            "hours_per_month: 4\n"
            "max_proposals_per_month: 4\n"
            "proposal_expires_days: 30\n"
            "queue_max_age_days: 30\n",
        )

        budget = self.store.load_budget(budget_path)

        self.assertEqual(budget["project"], "claudart")
        self.assertIsInstance(budget["project"], str)
        self.assertEqual(budget["hours_per_month"], 4)
        self.assertEqual(budget["max_proposals_per_month"], 4)
        self.assertEqual(budget["proposal_expires_days"], 30)
        self.assertEqual(budget["queue_max_age_days"], 30)

    # -- 3. flow vs block list styles -----------------------------------------

    def test_flow_and_block_tags_parse_identically(self):
        rules_dir = os.path.join(self.tmp, "rules-styles")
        self._write(
            os.path.join(rules_dir, "flow-tags.md"),
            "---\n"
            "level: law\n"
            "authority: standard\n"
            "status: approved\n"
            "since: 2026-01-01\n"
            "tags: [a, b]\n"
            "---\n"
            "Body.\n",
        )
        self._write(
            os.path.join(rules_dir, "block-tags.md"),
            "---\n"
            "level: law\n"
            "authority: standard\n"
            "status: approved\n"
            "since: 2026-01-01\n"
            "tags:\n"
            "  - a\n"
            "  - b\n"
            "---\n"
            "Body.\n",
        )

        records = {r.id: r for r in self.store.load_laws(rules_dir)}

        self.assertEqual(records["flow-tags"].frontmatter["tags"], ["a", "b"])
        self.assertEqual(records["block-tags"].frontmatter["tags"], ["a", "b"])
        self.assertEqual(
            records["flow-tags"].frontmatter["tags"], records["block-tags"].frontmatter["tags"]
        )

    def test_verified_block_list_of_mappings_parses_to_dicts(self):
        rules_dir = os.path.join(self.tmp, "rules-verified")
        self._write(
            os.path.join(rules_dir, "verified-block.md"),
            "---\n"
            "level: law\n"
            "authority: standard\n"
            "status: approved\n"
            "since: 2026-01-01\n"
            "verified:\n"
            "  - by: human:x\n"
            "    at: 2026-08-30T00:00:00Z\n"
            "---\n"
            "Body.\n",
        )

        records = {r.id: r for r in self.store.load_laws(rules_dir)}

        self.assertEqual(
            records["verified-block"].frontmatter["verified"],
            [{"by": "human:x", "at": "2026-08-30T00:00:00Z"}],
        )

    # -- 4. list_proposals / write_proposal / expire_proposal -----------------

    def test_write_list_and_expire_proposal(self):
        proposals_dir = os.path.join(self.tmp, "proposals")

        self.store.write_proposal(proposals_dir, "prop-1", "# Proposal One\n\nBody one.\n")
        self.store.write_proposal(proposals_dir, "prop-2", "# Proposal Two\n\nBody two.\n")

        proposals = self.store.list_proposals(proposals_dir)
        self.assertEqual({p.id for p in proposals}, {"prop-1", "prop-2"})

        self.store.expire_proposal(proposals_dir, "prop-1")

        self.assertTrue(os.path.exists(os.path.join(proposals_dir, "prop-1.expired.md")))
        self.assertFalse(os.path.exists(os.path.join(proposals_dir, "prop-1.md")))

        remaining = self.store.list_proposals(proposals_dir)
        self.assertEqual({p.id for p in remaining}, {"prop-2"})

    # -- 5. set_status rewrites in place, byte-exact elsewhere -----------------

    def test_set_status_rewrites_in_place_status_first_field(self):
        path = os.path.join(self.tmp, "status-first.md")
        original = (
            "---\n"
            "status: approved\n"
            "level: law\n"
            "authority: standard\n"
            "since: 2026-01-01\n"
            "tags: [a, b]\n"
            "---\n"
            "\n"
            "Body prose line one.\n"
            "\n"
            "Body prose line two.\n"
        )
        self.assertEqual(original.count("status: approved"), 1)
        self._write(path, original)
        original_bytes = self._read_bytes(path)

        self.store.set_status(path, "draft")

        new_bytes = self._read_bytes(path)
        expected_bytes = original.replace("status: approved", "status: draft", 1).encode("utf-8")
        self.assertEqual(new_bytes, expected_bytes)
        self.assertNotEqual(new_bytes, original_bytes)

    def test_set_status_rewrites_in_place_status_mid_frontmatter_no_trailing_newline(self):
        path = os.path.join(self.tmp, "status-mid.md")
        original = (
            "---\n"
            "level: law\n"
            "authority: standard\n"
            "status: approved\n"
            "since: 2026-01-01\n"
            "---\n"
            "Body without a trailing newline."
        )
        self.assertEqual(original.count("status: approved"), 1)
        self._write(path, original)

        self.store.set_status(path, "draft")

        new_bytes = self._read_bytes(path)
        expected_bytes = original.replace("status: approved", "status: draft", 1).encode("utf-8")
        self.assertEqual(new_bytes, expected_bytes)

    # -- 6. lessons round-trip -------------------------------------------------

    def test_lessons_round_trip_preserves_order(self):
        path = os.path.join(self.tmp, "lessons", "2026.jsonl")
        first = valid_lesson()
        second = valid_lesson()
        second["id"] = "L-2026-002"
        second["source"] = "ledger:other#L2"

        self.store.append_lesson(path, first)
        self.store.append_lesson(path, second)

        result = list(self.store.iter_lessons(path))
        self.assertEqual(result, [first, second])

        with open(path, "r", encoding="utf-8") as f:
            lines = [line for line in f.read().splitlines() if line]
        self.assertEqual(len(lines), 2)
        for line in lines:
            json.loads(line)  # each line is valid standalone JSON

    def test_iter_lessons_on_absent_file_yields_nothing(self):
        path = os.path.join(self.tmp, "lessons", "does-not-exist.jsonl")
        self.assertEqual(list(self.store.iter_lessons(path)), [])

    # -- 7. hours round-trip -----------------------------------------------

    def test_hours_round_trip_preserves_order(self):
        path = os.path.join(self.tmp, "reviewer-hours.jsonl")
        first = valid_hours_entry()
        second = {"ts": "2026-09-16T09:00:00Z", "minutes": 30, "activity": "lesson triage"}

        self.store.append_hours(path, first)
        self.store.append_hours(path, second)

        result = list(self.store.iter_hours(path))
        self.assertEqual(result, [first, second])

    def test_iter_hours_on_absent_file_yields_nothing(self):
        path = os.path.join(self.tmp, "does-not-exist-hours.jsonl")
        self.assertEqual(list(self.store.iter_hours(path)), [])

    # -- 8. lesson rejection — negative controls -----------------------------

    def test_append_lesson_rejects_unknown_key_and_leaves_no_trace(self):
        path = os.path.join(self.tmp, "lessons-bad", "unknown-key.jsonl")
        bad = valid_lesson()
        bad["confidence"] = 0.9  # the specifically forbidden key

        with self.assertRaises(ValueError):
            self.store.append_lesson(path, bad)

        self.assertFalse(os.path.exists(path))

    def test_append_lesson_rejects_missing_signal_and_leaves_no_trace(self):
        path = os.path.join(self.tmp, "lessons-bad", "missing-signal.jsonl")
        bad = valid_lesson()
        del bad["signal"]

        with self.assertRaises(ValueError):
            self.store.append_lesson(path, bad)

        self.assertFalse(os.path.exists(path))

    def test_append_lesson_rejection_does_not_corrupt_existing_file(self):
        path = os.path.join(self.tmp, "lessons-bad", "preexisting.jsonl")
        good = valid_lesson()
        self.store.append_lesson(path, good)
        size_before = os.path.getsize(path)

        bad = valid_lesson()
        bad["id"] = "L-2026-999"
        bad["confidence"] = 0.5
        with self.assertRaises(ValueError):
            self.store.append_lesson(path, bad)

        self.assertEqual(os.path.getsize(path), size_before)
        self.assertEqual(list(self.store.iter_lessons(path)), [good])


# ---------------------------------------------------------------------------
# per-adapter subclasses — the only place a future node needs to touch
# ---------------------------------------------------------------------------

class InMemoryContractTests(RecordStoreContract, unittest.TestCase):
    """The port's own fake, shipped with port/record-store (P1.4).

    graph-development.md §4: "the port task ships its own fake so consumers can proceed."
    It is what lets this suite be green at the port node, before any adapter exists, without
    the fail-open of collecting zero tests.
    """

    def make_store(self):
        return InMemoryRecordStore()


# Each adapter node adds ITS OWN subclass here when it lands -- one small edit, no assertion
# changes, inheriting all of RecordStoreContract unchanged. Do not add a subclass for an adapter
# that does not exist yet: its import would fail the whole module and take the port down with it.
#
from law.adapters.fs_records import FsRecordStore  # noqa: E402


class FsRecordsContractTests(RecordStoreContract, unittest.TestCase):
    """adapter/fs-records (P1.5): markdown frontmatter records, budget.yaml, proposals/."""

    def make_store(self):
        return FsRecordStore()


#   adapter/fs-records   (P1.5):
#       from law.adapters.fs_records import FsRecordStore
#       class FsRecordsContractTests(RecordStoreContract, unittest.TestCase):
#           def make_store(self): return FsRecordStore()
#
from law.adapters.jsonl_lessons import JsonlLessonStore  # noqa: E402


class JsonlLessonsContractTests(RecordStoreContract, unittest.TestCase):
    """adapter/jsonl-lessons (P2.5): lessons/<year>.jsonl and reviewer-hours.jsonl."""

    def make_store(self):
        return JsonlLessonStore()


#   adapter/jsonl-lessons (P2.5):
#       from law.adapters.jsonl_lessons import JsonlLessonStore
#       class JsonlLessonsContractTests(RecordStoreContract, unittest.TestCase):
#           def make_store(self): return JsonlLessonStore()


if __name__ == "__main__":
    unittest.main()
