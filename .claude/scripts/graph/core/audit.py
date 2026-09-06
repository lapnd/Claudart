"""graph.core.audit — PURE. Classify an extractor's violations into a refactor plan (D40).

HARD RULE (D15): nothing here performs I/O or imports an adapter. This module is fed the
already-extracted `Violation` rows (code/file/target/hint) and returns a plan description — a list
of `PlanItem`s. Rendering those items to disk is the adapter's job (`plan_writer`).

The plan is test-first by construction (D18): each forbidden-import cluster becomes a `test/*` node
that *proves* the fix and a behaviour node that *requires* that test. A tree with no violations
yields a single `gate/*` node pinning the clean state.
"""

from collections import namedtuple

# One row of the refactor plan: a graph node with its TDD edges. `requires` is a tuple of
# (dep_id, EDGE_TYPE); `proves` is a node id for test rows, else None; `paths` is a tuple of globs
# (empty for a gate, which writes nothing).
PlanItem = namedtuple("PlanItem", "task node kind title verify requires proves paths phase")

# Every node's verifier is the drift gate itself: it fails while the forbidden edge survives and
# passes once the count returns to the pinned budget. A real command (D30), never prose.
VERIFY = "bash .claude/scripts/claudart-graph.sh drift --root . --dir ."

# The offending "from" layer of a violation code -> the hexagonal behaviour kind that owns the fix.
# (`X_TO_Y` -> X.) Anything unrecognised is repaired as an adapter, the outermost behaviour layer.
_LAYER_KIND = {
    "domain": "domain",
    "usecase": "usecase",
    "port": "port",
    "adapter": "adapter",
    "composition": "composition",
}
BEHAVIOUR_FALLBACK = "adapter"


def _from_layer(code):
    return code.split("_TO_", 1)[0].lower()


def _locus_path(locus):
    """Strip a trailing `:line` from an extractor file locus, leaving the bare repo path."""
    head, sep, tail = locus.rpartition(":")
    if sep and head and tail.isdigit():
        return head
    return locus


def _dir_of(path):
    head, sep, _ = path.rpartition("/")
    return head if sep else path


def _slug(text):
    """A node-name-safe slug: alphanumerics and single hyphens only."""
    chars = [ch if (ch.isalnum() or ch == "-") else "-" for ch in text.lower()]
    slug = "".join(chars).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug or "x"


def classify(violations):
    """Cluster forbidden-import `violations` into a test-first refactor plan.

    One cluster per (offending behaviour kind, offending component directory): a `test/*` node that
    proves the fix, followed by the behaviour node that repairs the component and requires that test
    (red-first, D18). Clusters preserve the order violations arrive in (the extractor sorts them by
    file, so the plan reads top-to-bottom of the tree). No violations -> a single `gate/*` node.
    """
    clusters, index = [], {}
    for v in violations:
        kind = _LAYER_KIND.get(_from_layer(v.code), BEHAVIOUR_FALLBACK)
        path = _locus_path(v.file)
        comp = _dir_of(path)
        key = (kind, comp)
        if key not in index:
            index[key] = {"kind": kind, "comp": comp,
                          "name": _slug(comp.rpartition("/")[2] or comp),
                          "path": path, "codes": []}
            clusters.append(key)
        if v.code not in index[key]["codes"]:
            index[key]["codes"].append(v.code)

    if not clusters:
        return [PlanItem(
            task="P1.0", node="gate/architecture", kind="gate",
            title="Architecture gate - the tree already obeys every dependency rule",
            verify=VERIFY, requires=(), proves=None, paths=(), phase=1)]

    items = []
    for n, key in enumerate(clusters, 1):
        c = index[key]
        codes = ", ".join(c["codes"])
        beh_node = "%s/%s" % (c["kind"], c["name"])
        test_node = "test/%s-%s" % (c["kind"], c["name"])
        items.append(PlanItem(
            task="P1.%d" % (2 * n - 2), node=test_node, kind="test",
            title="Failing test pinning the correct dependency for %s [%s]" % (c["comp"], codes),
            verify=VERIFY, requires=(), proves=beh_node, paths=(c["path"],), phase=1))
        items.append(PlanItem(
            task="P1.%d" % (2 * n - 1), node=beh_node, kind=c["kind"],
            title="Remove %s from %s behind a port" % (codes, c["comp"]),
            verify=VERIFY, requires=((test_node, "TEST"),), proves=None,
            paths=(c["path"],), phase=1))
    return items
