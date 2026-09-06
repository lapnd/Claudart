"""graph.adapters.fs_extract — derive an architecture manifest from a real tree and measure the
architectural drift in it (D8/D35/D40).

Language-agnostic by construction: a file's LAYER comes from the manifest `layout:` — which
directory tree the file sits in — never from its language, and its import edges come from a
per-extension pattern table plus a per-language resolver, both owned by `lang_imports`. Adding a
language means one row in each of its tables; nothing else in the engine learns a new word.

Only imports that LOOK in-repo are ever judged. An in-repo-looking import that resolves to nothing
on disk is reported (UNRESOLVED-IMPORT) rather than dropped, because a dropped edge is an invisible
architecture violation; anything that does not look in-repo (stdlib, third party) is ignored in
silence.
"""

import os
import posixpath
from collections import namedtuple

from graph.adapters import lang_imports
from graph.core.graph import Finding

Violation = namedtuple("Violation", "code file target hint")


SKIP_DIRS = frozenset((
    ".git", "node_modules", "vendor", "dist", "build", "out", "target",
    "__pycache__", ".venv", "venv", ".tox", ".mypy_cache", ".pytest_cache",
))

# layout key -> layer name used by rules{forbid:{from,to}}
LAYER_OF = {
    "domain": "domain",
    "usecases": "usecase",
    "ports": "port",
    "adapters": "adapter",
    "composition": "composition",
    "contracts": "contract",
    "frontend": "frontend",
}
LAYOUT_ORDER = ("domain", "usecases", "ports", "adapters", "composition", "contracts", "frontend")

DEFAULT_LAYOUT = {
    "domain": "internal/domain",
    "usecases": "internal/app",
    "ports": "internal/ports",
    "adapters": "internal/adapters",
    "composition": "cmd",
}

DEFAULT_FORBID = (
    {"from": "adapter", "to": "adapter"},
    {"from": "domain", "to": "adapter"},
    {"from": "domain", "to": "port"},
    {"from": "usecase", "to": "adapter"},
)

# Lessons III.6 — a violation without a remediation is a complaint, not a finding. Each hint must
# open with one of: repoint | inject | extract | move.
HINT_ADAPTER_TO_ADAPTER = (
    "repoint to the port the symbols belong to; if it is a constructor, inject it at the "
    "composition root; if shared logic, extract a package named for the concept; if a misfiled "
    "pure computation, move it to the domain"
)
HINT_FROM_DOMAIN = "move the infrastructure call behind a port owned by the domain"
HINT_USECASE_TO_ADAPTER = "inject the port; the use case must see interfaces only"


class ExtractResult(object):
    """What one walk of a tree produced: a canonical manifest, forbidden edges, and findings."""

    def __init__(self, manifest_text, violations, findings):
        self.manifest_text = manifest_text
        self.violations = violations
        self.findings = findings


# ------------------------------------------------------------------------------- tree
def _rel(root, path):
    r = os.path.relpath(path, root).replace(os.sep, "/")
    return "" if r == "." else r


def _scan(root):
    """(sorted source files, every directory) as repo-relative posix paths."""
    files, dirs = [], set()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not d.startswith("."))
        here = _rel(root, dirpath)
        if here:
            dirs.add(here)
        for fn in filenames:
            if fn.startswith("."):
                continue
            files.append(posixpath.join(here, fn) if here else fn)
    return sorted(files), dirs


def _layer_trees(layout):
    """[(tree, layer)] longest-first, so a nested tree wins over its parent."""
    trees = []
    for key, layer in LAYER_OF.items():
        val = layout.get(key)
        for tree in (val if isinstance(val, list) else [val]):
            if isinstance(tree, str) and tree.strip():
                trees.append((tree.strip().strip("/"), layer))
    return sorted(trees, key=lambda t: -len(t[0]))


def _under(path, tree):
    return path == tree or path.startswith(tree + "/")


def _locate(path, trees):
    """(layer, tree) for a repo path, or (None, None) when it is outside every layer tree."""
    for tree, layer in trees:
        if _under(path, tree):
            return layer, tree
    return None, None


def _component(path, tree):
    """The directory directly under `tree` that owns `path` (an adapter, a port, a domain)."""
    rest = path[len(tree):].lstrip("/")
    head = rest.split("/", 1)[0] if rest else ""
    return posixpath.join(tree, head) if head else tree


TEST_DIR_NAMES = frozenset(("test", "tests", "__tests__", "testdata", "spec"))


def is_test_file(path):
    base = posixpath.basename(path)
    if set(path.split("/")[:-1]) & TEST_DIR_NAMES:
        return True
    if base.endswith("_test.go") or base.endswith("_test.py") or base.startswith("test_"):
        return True
    stem = base.rsplit(".", 1)[0]
    return stem.endswith(".test") or stem.endswith(".spec")


# ----------------------------------------------------------------------------- edges
Edge = namedtuple("Edge", "file line imp target from_layer to_layer from_tree to_tree test")


def _line_of(text, imp):
    """1-based line of the first occurrence of the import string (0 when the pattern normalised it away)."""
    for i, line in enumerate(text.split("\n"), 1):
        if imp in line:
            return i
    return 0


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def _edges(root, tree, files, trees):
    """(edges, unresolved) for every source file that sits inside a layer tree."""
    edges, unresolved = [], []
    for rel_file in files:
        ext = posixpath.splitext(rel_file)[1]
        if ext not in lang_imports.IMPORT_PATTERNS:
            continue
        from_layer, from_tree = _locate(rel_file, trees)
        if from_layer is None:
            continue
        text = _read(os.path.join(root, rel_file.replace("/", os.sep)))
        seen = []
        for imp in lang_imports.IMPORT_PATTERNS[ext](text):
            if imp not in seen:
                seen.append(imp)
        for imp in seen:
            target, looks_in_repo = lang_imports.RESOLVERS[ext](tree, rel_file, imp)
            if target is None:
                if looks_in_repo:
                    unresolved.append((rel_file, imp))
                continue
            to_layer, to_tree = _locate(target, trees)
            edges.append(Edge(rel_file, _line_of(text, imp), imp, target, from_layer, to_layer,
                              from_tree, to_tree, is_test_file(rel_file)))
    return edges, unresolved


def _forbidden(manifest):
    rules = (manifest.get("rules") or {}).get("forbid")
    pairs = []
    for rule in (rules if isinstance(rules, list) else list(DEFAULT_FORBID)):
        if isinstance(rule, dict) and rule.get("from") and rule.get("to"):
            pair = (str(rule["from"]), str(rule["to"]))
            if pair not in pairs:
                pairs.append(pair)
    return pairs or [(r["from"], r["to"]) for r in DEFAULT_FORBID]


def _hint(from_layer, to_layer):
    if from_layer == "adapter" and to_layer == "adapter":
        return HINT_ADAPTER_TO_ADAPTER
    if from_layer == "domain":
        return HINT_FROM_DOMAIN
    if from_layer == "usecase" and to_layer == "adapter":
        return HINT_USECASE_TO_ADAPTER
    return "move the dependency behind a port so the %s layer stops depending on the %s layer" % (
        from_layer, to_layer)


def _violation(edge):
    code = "%s_TO_%s" % (edge.from_layer.upper(), edge.to_layer.upper())
    locus = "%s:%d" % (edge.file, edge.line) if edge.line else edge.file
    return Violation(code, locus, edge.target,
                     _hint(edge.from_layer, edge.to_layer))


def _finding(category, locus, rest):
    return Finding(category, "%s %s" % (locus, rest))


# ------------------------------------------------------------------------ divergence
def _declared(manifest, key):
    """{path: name} of the manifest's declared `key` (ports / adapters) entries."""
    out = {}
    for item in manifest.get(key) or []:
        if isinstance(item, dict) and item.get("path"):
            out[str(item["path"]).strip("/")] = str(item.get("name") or posixpath.basename(item["path"]))
    return out


def _divergence(manifest, trees, edges, files):
    """Where the manifest and the tree disagree about ports and adapters. Findings only: the budget
    counts forbidden imports, and a stale manifest is fixed by re-extracting, not by refactoring."""
    out = []
    ports, adapters = _declared(manifest, "ports"), _declared(manifest, "adapters")
    if ports:
        implemented = set()
        for e in edges:
            if not e.test and e.from_layer == "adapter" and e.to_layer == "port" and e.to_tree:
                implemented.add(_component(e.target, e.to_tree))
        for path in sorted(ports):
            if path not in implemented:
                out.append(_finding("PORT-WITHOUT-ADAPTER", ports[path],
                                    "declared at %s but no adapter in the tree imports it - write the adapter, or drop the port from the manifest" % path))
    if adapters:
        for comp in sorted(_components(trees, "adapter", files)):
            if comp not in adapters:
                out.append(_finding("ADAPTER-NOT-IN-MANIFEST", comp,
                                    "exists in the tree but the manifest does not list it - re-extract (executor-level change per D23)"))
    return out


# -------------------------------------------------------------------------- manifest
def _components(trees, layer, files):
    """{component path: name} for every directory directly under `layer`'s tree holding sources."""
    out = {}
    for tree, tree_layer in trees:
        if tree_layer != layer:
            continue
        for rel_file in files:
            if posixpath.splitext(rel_file)[1] not in lang_imports.SOURCE_EXTS or not _under(rel_file, tree):
                continue
            comp = _component(rel_file, tree)
            if comp != tree:
                out[comp] = posixpath.basename(comp)
    return out


def _imported(edges, comp, to_layer, targets):
    """Names of `to_layer` components imported by non-test files of component `comp`."""
    names = set()
    for e in edges:
        if e.test or e.to_layer != to_layer or e.to_tree is None:
            continue
        if _under(e.file, comp) and _component(e.target, e.to_tree) in targets:
            names.add(targets[_component(e.target, e.to_tree)])
    return sorted(names)


def _importers_of(edges, comp, from_layer):
    return any(not e.test and e.from_layer == from_layer and e.to_tree is not None
               and _under(e.target, comp) for e in edges)


def _q(value):
    """Quote a scalar only when the YAML subset would otherwise re-read it as another type."""
    text = str(value)
    if text == "" or text != text.strip() or text[0] in "-[\"'#" or ":" in text:
        return '"%s"' % text.replace('"', '\\"')
    return text


def _manifest_text(root, layout, trees, edges, files, budget, forbid):
    domains = _components(trees, "domain", files)
    usecases = _components(trees, "usecase", files)
    ports = _components(trees, "port", files)
    adapters = _components(trees, "adapter", files)

    out = ["# architecture.yaml - extracted by `claudart-graph extract`; the tree is the source, this file is the",
           "# pinned reading of it. `architecture.budget` is a ratchet: `drift` fails when the measured count",
           "# differs from it in either direction. A merge conflict on the budget is resolved by re-measuring the",
           "# merged tree (`claudart-graph drift --root .`), never by picking a side.",
           "version: 1",
           "project: %s" % _q(posixpath.basename(os.path.abspath(root).replace(os.sep, "/"))),
           "profile: hexagonal",
           "layout:"]
    for key in LAYOUT_ORDER:
        if layout.get(key):
            out.append("  %s: %s" % (key, _q(layout[key])))

    if domains:
        out.append("domains:")
        for comp in sorted(domains):
            out.append("  - name: %s" % _q(domains[comp]))
            out.append("    path: %s" % _q(comp))

    if usecases:
        out.append("usecases:")
        for comp in sorted(usecases):
            out.append("  - name: %s" % _q(usecases[comp]))
            out.append("    path: %s" % _q(comp))
            owned = _imported(edges, comp, "domain", domains)
            if len(owned) == 1:
                out.append("    domain: %s" % _q(owned[0]))

    if ports:
        out.append("ports:")
        for comp in sorted(ports):
            out.append("  - name: %s" % _q(ports[comp]))
            # A driven (out) port is the one an adapter implements; a driving (in) port is one the
            # use cases own and only the composition root reaches. Undeterminable -> out.
            if _importers_of(edges, comp, "adapter"):
                direction = "out"
            elif _importers_of(edges, comp, "usecase") and _importers_of(edges, comp, "composition"):
                direction = "in"
            else:
                direction = "out"
            out.append("    direction: %s" % direction)
            owned = _imported(edges, comp, "domain", domains)
            if len(owned) == 1:
                out.append("    domain: %s" % _q(owned[0]))
            out.append("    path: %s" % _q(comp))

    if adapters:
        out.append("adapters:")
        for comp in sorted(adapters):
            out.append("  - name: %s" % _q(adapters[comp]))
            wired = _imported(edges, comp, "port", ports)
            if len(wired) == 1:
                out.append("    port: %s" % _q(wired[0]))
            elif wired:
                out.append("    port: [%s]" % ", ".join(_q(p) for p in wired))
            out.append("    path: %s" % _q(comp))

    out.append("architecture:")
    out.append("  budget: %d" % budget)
    out.append("rules:")
    out.append("  forbid:")
    for frm, to in forbid:
        out.append("    - from: %s" % _q(frm))
        out.append("      to: %s" % _q(to))
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------- extract
def extract(root, manifest):
    """Walk `root` and report what its architecture IS, measured against `manifest`'s rules."""
    manifest = manifest if isinstance(manifest, dict) else {}
    layout = manifest.get("layout")
    layout = dict(layout) if isinstance(layout, dict) and layout else dict(DEFAULT_LAYOUT)
    trees = _layer_trees(layout)
    forbid = _forbidden(manifest)

    files, dirs = _scan(root)
    tree = lang_imports.Tree(root, files, dirs)
    edges, unresolved = _edges(root, tree, files, trees)

    violations, findings = [], []
    for e in sorted(edges, key=lambda x: (x.file, x.target, x.imp)):
        if e.to_layer is None:
            continue
        same_component = (e.from_tree == e.to_tree
                          and _component(e.file, e.from_tree) == _component(e.target, e.to_tree))
        if e.test:
            # The arch gate ignores test files (Lessons IV.11): a test reaching infrastructure is
            # reported, never counted, so the budget stays a statement about production code.
            if e.from_layer in ("domain", "usecase") and e.to_layer == "adapter":
                findings.append(_finding("TEST-REACHES-INFRA", e.file, "imports %s" % e.target))
            continue
        if same_component:
            continue
        if (e.from_layer, e.to_layer) in forbid:
            violations.append(_violation(e))

    for rel_file, imp in sorted(unresolved):
        findings.append(_finding("UNRESOLVED-IMPORT", rel_file,
                                 "imports %s which resolves to nothing under %s" % (imp, root)))
    findings.extend(_divergence(manifest, trees, edges, files))

    findings.sort(key=lambda f: str.__str__(f.category) + "\x00" + str.__str__(f.message))
    text = _manifest_text(root, layout, trees, edges, files, len(violations), forbid)
    return ExtractResult(text, violations, findings)
