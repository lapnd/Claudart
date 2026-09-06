"""law.ports.record_store — the outbound record-store port (SPEC D15 / P1.4).

Defines the `RecordStore` Protocol every persistence adapter implements (`FsRecordStore`,
`JsonlLessonStore`, per the shared contract in `tests/law/unit/test_port_record_store.py`), the
typed records it returns, and `InMemoryRecordStore` — the port's own fake, shipped so downstream
consumers and the shared contract suite can proceed before any adapter exists
(`graph-development.md` section 4).

Ports are not the pure domain (`law.core`): stdlib modules the domain forbids (`os`, `json`, `re`)
are fine here. Frontmatter is a hand-rolled parser — no PyYAML — per this project's
stdlib-only constraint; it accepts exactly the shapes SCHEMA.md section 8 documents (flow lists,
block lists, one-key-mapping-per-list-item blocks).
"""

import json
import os
import re
from dataclasses import dataclass
from typing import Iterator, Protocol

# The eleven permitted lesson keys (LESSONS.md section 1.1). `confidence` is the canonical
# rejected example; any key outside this closed set is rejected.
PERMITTED_LESSON_KEYS = frozenset(
    (
        "id",
        "ts",
        "project",
        "source",
        "kind",
        "signal",
        "summary",
        "candidate_law",
        "matched_against",
        "extraction_pass",
        "reviewed",
    )
)

_KEY_VALUE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")


@dataclass
class LawRecord:
    """One parsed law/rule Markdown file.

    `id` is the file's path under the rules dir, without ".md", "/"-separated — a file under
    "vendor/x.md" gets id "vendor/x".
    """

    id: str
    path: str
    frontmatter: dict
    body: str


@dataclass
class Proposal:
    """One proposal file: its id (filename stem), path, and full raw content."""

    id: str
    path: str
    text: str


class RecordStore(Protocol):
    """The outbound record-store port. An interface declaration only — no behaviour here."""

    def load_laws(self, rules_dir: str) -> list:
        ...

    def load_budget(self, path: str) -> dict:
        ...

    def list_proposals(self, proposals_dir: str) -> list:
        ...

    def write_proposal(self, proposals_dir: str, proposal_id: str, text: str) -> None:
        ...

    def expire_proposal(self, proposals_dir: str, proposal_id: str) -> None:
        ...

    def set_status(self, law_path: str, status: str) -> None:
        ...

    def append_lesson(self, path: str, obj: dict) -> None:
        ...

    def iter_lessons(self, path: str) -> Iterator[dict]:
        ...

    def append_hours(self, path: str, obj: dict) -> None:
        ...

    def iter_hours(self, path: str) -> Iterator[dict]:
        ...


# ---------------------------------------------------------------------------
# hand-rolled frontmatter/YAML-lite parsing (SCHEMA.md section 8)
# ---------------------------------------------------------------------------


def _parse_scalar(text):
    """One YAML-lite scalar: quoted string, bool, int, or bare string."""
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in ("'", '"'):
        return text[1:-1]
    if text == "true":
        return True
    if text == "false":
        return False
    if re.match(r"^-?\d+$", text):
        return int(text)
    return text


def _parse_flow_list(text):
    """`[a, b]` -> ["a", "b"]; `[]` -> []."""
    inner = text.strip()
    if inner.startswith("["):
        inner = inner[1:]
    if inner.endswith("]"):
        inner = inner[:-1]
    inner = inner.strip()
    if inner == "":
        return []
    return [_parse_scalar(part) for part in inner.split(",")]


def _line_indent(line):
    return len(line) - len(line.lstrip(" "))


def _parse_block_list(lines, i):
    """Block-style list starting at `lines[i]`: scalar items or one-mapping-per-item dicts."""
    items = []
    n = len(lines)
    if i >= n:
        return items, i
    first_stripped = lines[i].lstrip(" ")
    if not first_stripped.startswith("- "):
        return items, i
    item_indent = _line_indent(lines[i])
    content_indent = item_indent + 2
    while i < n:
        line = lines[i]
        if line.strip() == "":
            break
        stripped = line.lstrip(" ")
        if _line_indent(line) != item_indent or not stripped.startswith("- "):
            break
        content = stripped[2:]
        i += 1
        match = _KEY_VALUE.match(content)
        if not match:
            items.append(_parse_scalar(content))
            continue
        entry = {match.group(1): _parse_scalar(match.group(2))}
        while i < n:
            cont = lines[i]
            if cont.strip() == "" or _line_indent(cont) != content_indent:
                break
            cont_match = _KEY_VALUE.match(cont.lstrip(" "))
            if not cont_match:
                break
            entry[cont_match.group(1)] = _parse_scalar(cont_match.group(2))
            i += 1
        items.append(entry)
    return items, i


def parse_yaml_lite(text):
    """Parse a flat YAML-lite document (frontmatter body, or a whole `budget.yaml`) to a dict."""
    lines = text.split("\n")
    result = {}
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.strip() == "" or _line_indent(line) != 0:
            i += 1
            continue
        match = _KEY_VALUE.match(line)
        if not match:
            i += 1
            continue
        key, rest = match.group(1), match.group(2).rstrip()
        if rest == "":
            items, i = _parse_block_list(lines, i + 1)
            result[key] = items
        elif rest.startswith("["):
            result[key] = _parse_flow_list(rest)
            i += 1
        else:
            result[key] = _parse_scalar(rest)
            i += 1
    return result


def _split_frontmatter(text):
    """Split `---\\n<frontmatter>\\n---\\n<body>` into (parsed frontmatter dict, verbatim body)."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        return {}, text
    frontmatter = parse_yaml_lite("\n".join(lines[1:end]))
    body = "\n".join(lines[end + 1 :])
    return frontmatter, body


def _rewrite_status(text, status):
    """Rewrite only the frontmatter `status:` line's value, byte-exact elsewhere."""
    lines = text.split("\n")
    end = len(lines)
    if lines and lines[0].strip() == "---":
        for idx in range(1, len(lines)):
            if lines[idx].strip() == "---":
                end = idx
                break
    pattern = re.compile(r"^(status:\s*)(\S+)(.*)$")
    for idx in range(0, end):
        match = pattern.match(lines[idx])
        if match:
            lines[idx] = match.group(1) + status + match.group(3)
            break
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# InMemoryRecordStore — the port's own fake (P1.4)
# ---------------------------------------------------------------------------


class InMemoryRecordStore:
    """The record-store port's own fake, constructible with no arguments.

    Every method discovers its target purely from the path(s) it is handed, per the shared
    contract's docstring. The contract's own assertions read results back through direct
    filesystem checks (`os.path.exists`, raw byte reads) rather than through this store, so the
    only implementation that can satisfy it genuinely is one that performs the real filesystem
    operations the contract describes — this class holds no additional in-process state beyond
    what each call reads or writes at the given path.
    """

    def load_laws(self, rules_dir):
        records = []
        for dirpath, _dirnames, filenames in os.walk(rules_dir):
            for filename in filenames:
                if not filename.endswith(".md"):
                    continue
                full_path = os.path.join(dirpath, filename)
                rel = os.path.relpath(full_path, rules_dir)
                law_id = rel[: -len(".md")].replace(os.sep, "/")
                with open(full_path, "r", encoding="utf-8") as handle:
                    text = handle.read()
                frontmatter, body = _split_frontmatter(text)
                records.append(LawRecord(id=law_id, path=full_path, frontmatter=frontmatter, body=body))
        return records

    def load_budget(self, path):
        with open(path, "r", encoding="utf-8") as handle:
            return parse_yaml_lite(handle.read())

    def list_proposals(self, proposals_dir):
        proposals = []
        if not os.path.isdir(proposals_dir):
            return proposals
        for filename in os.listdir(proposals_dir):
            if not filename.endswith(".md") or filename.endswith(".expired.md"):
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

    def set_status(self, law_path, status):
        with open(law_path, "r", encoding="utf-8", newline="") as handle:
            text = handle.read()
        new_text = _rewrite_status(text, status)
        with open(law_path, "w", encoding="utf-8", newline="") as handle:
            handle.write(new_text)

    def append_lesson(self, path, obj):
        unknown = set(obj) - PERMITTED_LESSON_KEYS
        if unknown:
            raise ValueError("lesson carries forbidden key(s): %s" % ", ".join(sorted(unknown)))
        if "signal" not in obj:
            raise ValueError("lesson is missing required key `signal`")
        self._append_jsonl(path, obj)

    def iter_lessons(self, path):
        return self._iter_jsonl(path)

    def append_hours(self, path, obj):
        self._append_jsonl(path, obj)

    def iter_hours(self, path):
        return self._iter_jsonl(path)

    @staticmethod
    def _append_jsonl(path, obj):
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(obj) + "\n")

    @staticmethod
    def _iter_jsonl(path):
        if not os.path.exists(path):
            return
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line:
                    yield json.loads(line)
