"""law.adapters.claude_md_target — the `claude-md-target` adapter of the target-writer port (P2.6).

Implements the `TargetWriter` Protocol (`law.ports.target_writer`) against a real target file on
disk (e.g. `CLAUDE.md`): read the full file verbatim, `check` a candidate block against the text
currently between the markers without ever writing, and `replace_block` the between-markers text
in place while leaving everything else byte-for-byte untouched.

This adapter imports `_locate_markers` (the marker-matching algorithm) directly from
`law.ports.target_writer` (adapter -> port is the correct dependency direction) rather than
re-deriving it: the marker rule — begin matched by prefix, end matched as the rightmost exact
line, raising `ValueError` on any violation before a single byte is written — is the shared
contract's own frozen algorithm (see that module's and the contract test's docstrings), and a
second, independently-written copy is exactly the risk the shared contract test exists to catch.
Everything else here — file I/O, the diff, and the byte-preserving splice — is this adapter's own
implementation; none of it is copied from `InMemoryTargetWriter`, which is the port's own fake and
not a dependency of this adapter.
"""

import difflib
from pathlib import Path

from law.ports.target_writer import _locate_markers


class ClaudeMdTargetWriter:
    """Filesystem-backed `target-writer` adapter.

    Constructible with no arguments. Every method discovers its target purely from the `path`
    passed to that call — no state is held across calls beyond what is read or written on disk.
    """

    def read(self, path):
        return Path(path).read_text(encoding="utf-8", newline="")

    def check(self, path, block):
        text = self.read(path)
        lines = text.splitlines(keepends=True)
        begin_idx, end_idx = _locate_markers(lines)
        current = "".join(lines[begin_idx + 1 : end_idx])

        if current == block:
            return True, ""

        diff_lines = difflib.unified_diff(
            current.splitlines(keepends=True),
            block.splitlines(keepends=True),
            fromfile="current",
            tofile="block",
        )
        return False, "".join(diff_lines)

    def replace_block(self, path, block):
        text = self.read(path)
        lines = text.splitlines(keepends=True)
        begin_idx, end_idx = _locate_markers(lines)

        prefix = "".join(lines[: begin_idx + 1])
        suffix = "".join(lines[end_idx:])
        new_text = prefix + block + suffix

        Path(path).write_text(new_text, encoding="utf-8", newline="")
