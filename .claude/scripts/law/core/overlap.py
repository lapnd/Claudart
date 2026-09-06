"""law.core.overlap — the D3 overlap-declaration rule plus the level/layering rules.

Pure (D15): a mapping of law id -> parsed frontmatter goes in, `Finding` objects come out.
Nothing here touches the filesystem; "can these globs overlap" is decided by pattern
intersection, never by walking a real tree.

Codes emitted here (SCHEMA.md section 4):
    UNDECLARED-OVERLAP, OVERRIDES-CONSTITUTION, BAD-LAYER
"""

from law.core.schema import Finding

DECLARATION_KEYS = ("overrides", "supersedes_in_scope", "layers_on")


def check(records):
    """Return every overlap/level violation across a set of records; [] when all are legal."""
    return _level_findings(records) + _overlap_findings(records)


def _level_findings(records):
    """`overrides` may not target a constitution; a convention may only layers_on a law."""
    findings = []
    for law_id in sorted(records):
        record = records[law_id]
        overrides = _declared(record, "overrides")
        for target in overrides:
            if _level_of(records, target) == "constitution":
                findings.append(
                    Finding(
                        "OVERRIDES-CONSTITUTION",
                        law_id,
                        "`overrides` names %s, a level: constitution record" % target,
                    )
                )
        if record.get("level") != "convention":
            continue
        if overrides:
            findings.append(
                Finding("BAD-LAYER", law_id, "a level: convention record may not use `overrides`")
            )
        for target in _declared(record, "layers_on"):
            if _level_of(records, target) != "law":
                findings.append(
                    Finding(
                        "BAD-LAYER",
                        law_id,
                        "a level: convention record may only layers_on a level: law "
                        "record, and %s is not one" % target,
                    )
                )
    return findings


def _overlap_findings(records):
    """An overlap candidate pair needs a declaration in one direction; either one satisfies it."""
    findings = []
    law_ids = sorted(records)
    for index, first in enumerate(law_ids):
        for second in law_ids[index + 1:]:
            if not _is_overlap_candidate(records[first], records[second]):
                continue
            if _declares(records[first], second) or _declares(records[second], first):
                continue
            findings.append(
                Finding(
                    "UNDECLARED-OVERLAP",
                    "|".join(sorted([first, second])),
                    "paths can overlap and at least one tag is shared, but neither record "
                    "declares a relationship toward the other",
                )
            )
    return findings


def _declared(record, key):
    return list(record.get(key) or [])


def _declares(record, other_id):
    for key in DECLARATION_KEYS:
        if other_id in _declared(record, key):
            return True
    return False


def _level_of(records, law_id):
    return (records.get(law_id) or {}).get("level")


def _is_overlap_candidate(first, second):
    return _shares_tag(first, second) and _paths_can_overlap(first, second)


def _shares_tag(first, second):
    return bool(set(first.get("tags") or []) & set(second.get("tags") or []))


def _paths_can_overlap(first, second):
    for left in first.get("paths") or []:
        for right in second.get("paths") or []:
            if globs_can_overlap(left, right):
                return True
    return False


def globs_can_overlap(first, second):
    """True when some concrete path could match both globs (SCHEMA.md D3 condition 1)."""
    return _walk_segments(first.split("/"), 0, second.split("/"), 0)


def _walk_segments(left, i, right, j):
    """Segment-wise intersection; `**` spans zero or more whole segments on either side."""
    if i == len(left) and j == len(right):
        return True
    if i == len(left):
        return all(segment == "**" for segment in right[j:])
    if j == len(right):
        return all(segment == "**" for segment in left[i:])
    if left[i] == "**":
        return _walk_segments(left, i + 1, right, j) or _walk_segments(left, i, right, j + 1)
    if right[j] == "**":
        return _walk_segments(left, i, right, j + 1) or _walk_segments(left, i + 1, right, j)
    if _segments_intersect(left[i], right[j]):
        return _walk_segments(left, i + 1, right, j + 1)
    return False


def _segments_intersect(left, right):
    """Do two single-segment patterns (`*`, `?`, literals) share at least one concrete string?"""
    if "[" in left or "[" in right:
        return True  # character classes are not modelled; fail closed toward "they overlap"
    if left == "" and right == "":
        return True
    if left == "":
        return set(right) == {"*"}
    if right == "":
        return set(left) == {"*"}
    if left[0] == "*":
        return _segments_intersect(left[1:], right) or _segments_intersect(left, right[1:])
    if right[0] == "*":
        return _segments_intersect(left, right[1:]) or _segments_intersect(left[1:], right)
    if left[0] == "?" or right[0] == "?" or left[0] == right[0]:
        return _segments_intersect(left[1:], right[1:])
    return False
