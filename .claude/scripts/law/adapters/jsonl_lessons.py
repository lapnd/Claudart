"""law.adapters.jsonl_lessons — the `jsonl-lessons` adapter of the record-store port (P2.5).

Implements the full `RecordStore` Protocol (`law.ports.record_store`). Its specialty is the
lesson/hours JSONL round-trip (LESSONS.md sections 1-2): append-only newline-delimited JSON,
rejecting a lesson that carries a key outside the closed eleven-key set or is missing `signal`,
with a rejected write leaving the target file byte-unchanged.

Adapter -> port is the only import direction used here (dataclasses, the closed lesson key set,
and the project's hand-rolled YAML-lite/frontmatter helpers are reused from `law.ports` rather than
re-implemented, per LESSONS.md's stdlib-only constraint). This module never imports another
adapter and never imports `law.core`.
"""

import json
import os

from law.ports.record_store import (
    PERMITTED_LESSON_KEYS,
    LawRecord,
    Proposal,
    _rewrite_status,
    _split_frontmatter,
    parse_yaml_lite,
)


class JsonlLessonStore:
    """The `jsonl-lessons` adapter: JSONL-backed lesson/hours logs, plus the rest of the port.

    Constructible with no arguments; every method discovers its target purely from the path(s)
    passed to it, matching the port's zero-arg-constructor contract.
    """

    # -- law records -----------------------------------------------------

    def load_laws(self, rules_dir):
        records = []
        for dirpath, _dirnames, filenames in os.walk(rules_dir):
            for filename in sorted(filenames):
                if not filename.endswith(".md"):
                    continue
                full_path = os.path.join(dirpath, filename)
                rel = os.path.relpath(full_path, rules_dir)
                law_id = rel[: -len(".md")].replace(os.sep, "/")
                with open(full_path, "r", encoding="utf-8") as handle:
                    text = handle.read()
                frontmatter, body = _split_frontmatter(text)
                records.append(
                    LawRecord(id=law_id, path=full_path, frontmatter=frontmatter, body=body)
                )
        return records

    def load_budget(self, path):
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
        return parse_yaml_lite(text)

    # -- proposals ---------------------------------------------------------

    def list_proposals(self, proposals_dir):
        if not os.path.isdir(proposals_dir):
            return []
        proposals = []
        for filename in sorted(os.listdir(proposals_dir)):
            if filename.endswith(".expired.md") or not filename.endswith(".md"):
                continue
            proposal_id = filename[: -len(".md")]
            full_path = os.path.join(proposals_dir, filename)
            with open(full_path, "r", encoding="utf-8") as handle:
                text = handle.read()
            proposals.append(Proposal(id=proposal_id, path=full_path, text=text))
        return proposals

    def write_proposal(self, proposals_dir, proposal_id, text):
        os.makedirs(proposals_dir, exist_ok=True)
        full_path = os.path.join(proposals_dir, proposal_id + ".md")
        with open(full_path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def expire_proposal(self, proposals_dir, proposal_id):
        src = os.path.join(proposals_dir, proposal_id + ".md")
        dst = os.path.join(proposals_dir, proposal_id + ".expired.md")
        os.rename(src, dst)

    # -- law status ----------------------------------------------------------

    def set_status(self, law_path, status):
        with open(law_path, "r", encoding="utf-8", newline="") as handle:
            original = handle.read()
        rewritten = _rewrite_status(original, status)
        with open(law_path, "w", encoding="utf-8", newline="") as handle:
            handle.write(rewritten)

    # -- lessons (specialty) -----------------------------------------------

    def append_lesson(self, path, obj):
        """Validate against the closed key set + required `signal`, then append one JSON line.

        Validation happens entirely before any file is opened for writing, so a rejected `obj`
        leaves the target byte-for-byte as it was (including staying absent if it never existed).
        """
        unknown_keys = set(obj.keys()) - PERMITTED_LESSON_KEYS
        if unknown_keys:
            raise ValueError(
                "lesson object carries key(s) outside the permitted set: %s"
                % ", ".join(sorted(unknown_keys))
            )
        if "signal" not in obj:
            raise ValueError("lesson object is missing the required `signal` key")
        self._append_json_line(path, obj)

    def iter_lessons(self, path):
        return self._iter_json_lines(path)

    # -- hours ---------------------------------------------------------------

    def append_hours(self, path, obj):
        self._append_json_line(path, obj)

    def iter_hours(self, path):
        return self._iter_json_lines(path)

    # -- shared JSONL mechanics ------------------------------------------

    @staticmethod
    def _append_json_line(path, obj):
        parent_dir = os.path.dirname(path)
        if parent_dir:
            os.makedirs(parent_dir, exist_ok=True)
        line = json.dumps(obj)
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(line)
            handle.write("\n")

    @staticmethod
    def _iter_json_lines(path):
        if not os.path.exists(path):
            return
        with open(path, "r", encoding="utf-8") as handle:
            for raw_line in handle:
                stripped = raw_line.strip()
                if not stripped:
                    continue
                yield json.loads(stripped)
