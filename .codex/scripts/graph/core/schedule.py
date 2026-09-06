"""graph.core.schedule — waves, critical path, unblocking power, merge risk, shape, tier derivation.

Pure. Path resolution against a real tree happens in an adapter; this module accepts the resolved
sets (node -> set of files) and never touches the filesystem (D15, D25).
"""

from graph.core.graph import Node, TEST_KINDS
from graph.core import fold as F


def depth(g):
    memo = {}

    def go(nid):
        if nid in memo:
            return memo[nid]
        reqs = [d for d, _ in g.nodes[nid].requires if d in g.nodes]
        memo[nid] = 1 + max([go(d) for d in reqs], default=0)
        return memo[nid]
    return dict((nid, go(nid)) for nid in g.nodes)


def unblocking_power(g):
    p = dict((nid, 0) for nid in g.nodes)
    for n in g.nodes.values():
        for d, _ in n.requires:
            if d in p:
                p[d] += 1
    return p


def derive_tier(g, n):
    """D22: explicit `tier:` wins; otherwise derived from kind and edges."""
    if n.tier:
        return n.tier
    if n.kind in ("merge", "composition", "gate"):
        return "strong"
    if any(et == "RUNTIME" for _, et in n.requires):
        return "strong"
    if n.kind == "adapter":
        short = n.id.split("/", 1)[1]
        for a in g.manifest.get("adapters", []):
            if a.get("name") == short and a.get("datastore"):
                return "strong"
    if n.kind in ("mock", "contract"):
        return "fast"
    return "standard"


def project_waves(g):
    """Dry projection assuming every verify succeeds: tests enter the wave their inputs finish,
    implementations follow once their test is red, hypotheses when their inputs are satisfied."""
    state = dict((nid, "pending") for nid in g.nodes)
    power, dep = unblocking_power(g), depth(g)
    waves = []
    while True:
        tests = [nid for nid in g.nodes if F.test_ready(g, nid, state)]
        hyps = [nid for nid in g.nodes if F.hypothesis_ready(g, nid, state)]
        impls = F.ready_set(g, state)
        wave = sorted(set(tests) | set(hyps) | set(impls), key=lambda x: (-power[x], -dep[x], x))
        if not wave:
            break
        waves.append(wave)
        for nid in wave:
            k = g.nodes[nid].kind
            state[nid] = "red" if k in TEST_KINDS else ("confirmed" if k == "hypothesis" else "done")
            if k not in TEST_KINDS and k != "hypothesis":
                for t in g.nodes.values():
                    if t.kind in TEST_KINDS and t.proves == nid:
                        state[t.id] = "green"
    return waves


def shape(waves):
    """D27: wave widths, serial prefix (leading waves of width <= 2) and max width."""
    widths = [len(w) for w in waves]
    prefix = 0
    for w in widths:
        if w <= 2:
            prefix += 1
        else:
            break
    return {"widths": widths, "serial_prefix": prefix, "max_width": max(widths) if widths else 0}


def glob_prefix(p):
    return p.split("*", 1)[0].rstrip("/")


def merge_risk(g, wave, resolved=None):
    """Overlap between wave-mates. With `resolved` (node -> set of real files) the answer is a true
    intersection; without a tree it is a prefix heuristic and SAYS SO. Never removes a node (D10)."""
    pairs = []
    for i, a in enumerate(wave):
        for b in wave[i + 1:]:
            if a not in g.nodes or b not in g.nodes:
                continue
            if resolved is not None:
                common = sorted(resolved.get(a, set()) & resolved.get(b, set()))
                if common:
                    pairs.append((a, b, "%d shared file(s)" % len(common), common[0]))
                continue
            for pa in g.nodes[a].paths:
                for pb in g.nodes[b].paths:
                    x, y = glob_prefix(pa), glob_prefix(pb)
                    if x and y and (x.startswith(y) or y.startswith(x)):
                        pairs.append((a, b, "prefix heuristic (no tree)", "%s|%s" % (x, y)))
    return pairs


def empty_queries(g, resolved):
    """Lessons II.1: a query matching nothing is a wrong query far more often than an empty task."""
    from graph.core.graph import Finding
    return [Finding("EMPTY-PATH-QUERY", "%s: %s matched no file in the tree" % (nid, ", ".join(g.nodes[nid].paths)))
            for nid in sorted(resolved) if nid in g.nodes and g.nodes[nid].paths and not resolved[nid]]


def synthesize_merge_node(a, b, overlap):
    """D20: a conflict is a node, scheduled and evidenced like any other."""
    mid = "merge/%s+%s" % (a.split("/", 1)[1], b.split("/", 1)[1])
    return Node(id=mid, kind="merge", task="M", title="resolve %s vs %s at %s" % (a, b, overlap),
                verify="both %s and %s test suites green after merge" % (a, b),
                requires=[(a, "IMPLEMENTATION"), (b, "IMPLEMENTATION")],
                paths=[overlap], forbid=[], proves=None, tier="strong", phase=0, exclusive=False, early_ok=True)


def reverify_after_merge(g, merged, state, resolved, events):
    """D36: done nodes whose resolved files intersect the merged node's and whose latest evidence
    predates the merge event must be re-verified on the integrated tree."""
    if resolved is None or merged not in resolved:
        return []
    last = {}
    for e in events:
        last[e.node] = e.ts
    merged_ts = last.get(merged, 0)
    out = []
    for nid, s in state.items():
        if nid == merged or s not in ("done", "green"):
            continue
        if resolved.get(nid, set()) & resolved[merged] and last.get(nid, 0) < merged_ts:
            out.append(nid)
    return sorted(out)
