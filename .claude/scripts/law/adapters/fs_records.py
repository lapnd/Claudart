"""law.adapters.fs_records — the `fs-records` adapter of the record-store port (P1.5).

Implements the `RecordStore` Protocol (`law.ports.record_store`) against real files on disk: law/
rule Markdown files with YAML-lite frontmatter under a rules directory (including a nested
`vendor/` subtree), a `budget.yaml`, a `proposals/` directory of open/expired proposal files, and
JSONL lesson/hours logs.

This adapter imports `parse_yaml_lite`, `PERMITTED_LESSON_KEYS`, and the port's dataclasses/
Protocol from `law.ports.record_store` (adapter -> port is the correct dependency direction). The
frontmatter grammar (flow lists, block lists, one-key-mapping-per-list-item — SCHEMA.md section 8)
is genuinely the shared contract's own parsing algorithm, identical for every adapter that ever
touches frontmatter — copy-pasting it here would just be an unsynchronized second copy of the same
rules, so it is reused by import instead. Everything else — directory walking, frontmatter/body
splitting, the in-place `status:` rewrite, the proposal lifecycle, and the lesson/hours JSONL
round-trip and validation — is this adapter's own independent implementation; none of it is copied
from `InMemoryRecordStore`, which is the port's own fake and not a dependency of this adapter.
"""

import json
import re
from pathlib import Path

from law.ports.record_store import (
    PERMITTED_LESSON_KEYS,
    LawRecord,
    Proposal,
    parse_yaml_lite,
)

_FRONTMATTER_DELIM = "---"
_STATUS_LINE = re.compile(r"^(\s*status\s*:\s*)(\S+)(.*)$")


class FsRecordStore:
    """Filesystem-backed `record-store` adapter.

    Constructible with no arguments. Every method discovers its target purely from the path(s)
    passed to that call — no state is held across calls beyond what is read or written on disk.
    """

    # -- laws -----------------------------------------------------------------

    def load_laws(self, rules_dir):
        base = Path(rules_dir)
        records = []
        if not base.is_dir():
            return records
        for file_path in sorted(base.rglob("*.md")):
            if not file_path.is_file():
                continue
            rel = file_path.relative_to(base)
            law_id = "/".join(rel.with_suffix("").parts)
            text = file_path.read_text(encoding="utf-8")
            frontmatter, body = self._split_frontmatter(text)
            records.append(
                LawRecord(id=law_id, path=str(file_path), frontmatter=frontmatter, body=body)
            )
        return records

    def load_budget(self, path):
        text = Path(path).read_text(encoding="utf-8")
        return parse_yaml_lite(text)

    # -- proposals --------------------------------------------------------------

    def list_proposals(self, proposals_dir):
        base = Path(proposals_dir)
        if not base.is_dir():
            return []
        proposals = []
        for file_path in sorted(base.iterdir()):
            name = file_path.name
            if not file_path.is_file() or not name.endswith(".md") or name.endswith(".expired.md"):
                continue
            proposal_id = name[: -len(".md")]
            text = file_path.read_text(encoding="utf-8")
            proposals.append(Proposal(id=proposal_id, path=str(file_path), text=text))
        return proposals

    def write_proposal(self, proposals_dir, proposal_id, text):
        base = Path(proposals_dir)
        base.mkdir(parents=True, exist_ok=True)
        (base / (proposal_id + ".md")).write_text(text, encoding="utf-8")

    def expire_proposal(self, proposals_dir, proposal_id):
        base = Path(proposals_dir)
        src = base / (proposal_id + ".md")
        dst = base / (proposal_id + ".expired.md")
        src.rename(dst)

    # -- status -------------------------------------------------------------------

    def set_status(self, law_path, status):
        path = Path(law_path)
        text = path.read_text(encoding="utf-8", newline="")
        new_text = self._rewrite_status(text, status)
        path.write_text(new_text, encoding="utf-8", newline="")

    # -- lessons / hours ------------------------------------------------------------

    def append_lesson(self, path, obj):
        unknown = set(obj) - PERMITTED_LESSON_KEYS
        if unknown:
            raise ValueError(
                "lesson carries unknown key(s) outside the permitted set: %s"
                % ", ".join(sorted(unknown))
            )
        if "signal" not in obj:
            raise ValueError("lesson is missing the required key 'signal'")
        self._append_jsonl(path, obj)

    def iter_lessons(self, path):
        return self._iter_jsonl(path)

    def append_hours(self, path, obj):
        self._append_jsonl(path, obj)

    def iter_hours(self, path):
        return self._iter_jsonl(path)

    # -- internals --------------------------------------------------------------------

    @staticmethod
    def _split_frontmatter(text):
        """Split `---\\n<frontmatter>\\n---\\n<body>` into (parsed dict, verbatim body)."""
        lines = text.split("\n")
        if not lines or lines[0].strip() != _FRONTMATTER_DELIM:
            return {}, text
        end = None
        for idx in range(1, len(lines)):
            if lines[idx].strip() == _FRONTMATTER_DELIM:
                end = idx
                break
        if end is None:
            return {}, text
        frontmatter = parse_yaml_lite("\n".join(lines[1:end]))
        body = "\n".join(lines[end + 1 :])
        return frontmatter, body

    @staticmethod
    def _rewrite_status(text, status):
        """Rewrite only the frontmatter `status:` line's value; every other byte survives."""
        lines = text.split("\n")
        end = len(lines)
        if lines and lines[0].strip() == _FRONTMATTER_DELIM:
            for idx in range(1, len(lines)):
                if lines[idx].strip() == _FRONTMATTER_DELIM:
                    end = idx
                    break
        for idx in range(end):
            match = _STATUS_LINE.match(lines[idx])
            if match:
                lines[idx] = match.group(1) + status + match.group(3)
                break
        return "\n".join(lines)

    @staticmethod
    def _append_jsonl(path, obj):
        file_path = Path(path)
        file_path.parent.mkdir(parents=True, exist_ok=True)
        with file_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(obj) + "\n")

    @staticmethod
    def _iter_jsonl(path):
        file_path = Path(path)
        if not file_path.exists():
            return
        with file_path.open("r", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line:
                    yield json.loads(line)
