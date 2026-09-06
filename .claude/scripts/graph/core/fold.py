"""graph.core.fold — current state is a FOLD over the append-only event log (D19). Nothing else is
authoritative: not a state file, not a session's memory, not a worker's report.

Node states       pending ready running done blocked reopened stale pruned
Test states       pending red green            (repro behaves as a test)
Hypothesis states open testing confirmed refuted

Rules the fold enforces (D18/D31):
  * an implementation `done` flips every test that `proves` it from red -> green
  * a `reopened` node marks every transitive dependent (and its proving tests) that was done/green
    as `stale`
  * a `refuted` hypothesis prunes every transitive dependent that had not started
  * readiness: TEST edges need red|green; EVIDENCE edges need confirmed; everything else needs done
"""

from graph.core.graph import TEST_KINDS


def dependents_and_provers(g, nid):
    out = list(g.dependents(nid))
    out += [n.id for n in g.nodes.values() if n.kind in TEST_KINDS and n.proves == nid]
    return out


def transitive_dependents(g, root):
    seen, frontier = set(), [root]
    while frontier:
        cur = frontier.pop()
        for d in dependents_and_provers(g, cur):
            if d not in seen:
                seen.add(d)
                frontier.append(d)
    return seen


def fold(g, events, ticked=()):
    """`ticked` = node ids whose ROADMAP checkbox is [x] (spec-workflow's mechanical state, backed
    by a LEDGER evidence line). They seed done/green; any event for the node overrides the seed."""
    state = dict((nid, "pending") for nid in g.nodes)
    for nid in ticked:
        if nid in g.nodes:
            state[nid] = "green" if g.nodes[nid].kind in TEST_KINDS else "done"
    for e in events:
        if e.node not in state and not e.node.startswith("_"):
            state[e.node] = e.to   # a synthesised node (merge/...) may appear before the roadmap lists it
            continue
        if e.node.startswith("_"):
            continue               # measurements (_arch) are not node transitions
        state[e.node] = e.to
        if e.to == "done" and g.nodes[e.node].kind not in TEST_KINDS:
            for t in g.nodes.values():
                if t.kind in TEST_KINDS and t.proves == e.node and state.get(t.id) in ("red", "pending"):
                    state[t.id] = "green"
        if e.to == "reopened":
            for d in transitive_dependents(g, e.node):
                if state.get(d) in ("done", "green", "confirmed"):
                    state[d] = "stale"
        if e.to == "refuted":
            for d in transitive_dependents(g, e.node):
                if state.get(d) in ("pending", "open", "ready"):
                    state[d] = "pruned"
    return state


def _dep_satisfied(g, state, dep, etype):
    s = state.get(dep)
    if etype == "TEST":
        return s in ("red", "green")
    if etype == "EVIDENCE":
        return s == "confirmed"
    if dep in g.nodes and g.nodes[dep].kind in TEST_KINDS:
        return s in ("red", "green")   # a test harness "exists" once it has been observed at all
    return s == "done"


def is_ready(g, nid, state):
    n = g.nodes[nid]
    if state.get(nid) not in ("pending", "reopened", "stale"):
        return False
    return all(_dep_satisfied(g, state, d, et) for d, et in n.requires)


def ready_set(g, state):
    """Implementations whose inputs are satisfied. Tests and hypotheses have their own readiness."""
    return sorted(nid for nid in g.nodes
                  if g.nodes[nid].kind not in TEST_KINDS and g.nodes[nid].kind != "hypothesis"
                  and is_ready(g, nid, state))


def test_ready(g, nid, state):
    """A test can be WRITTEN (and observed red) once its non-TEST inputs are satisfied."""
    n = g.nodes[nid]
    return n.kind in TEST_KINDS and state.get(nid) in ("pending", "stale") and all(
        _dep_satisfied(g, state, d, et) for d, et in n.requires if et != "TEST")


def hypothesis_ready(g, nid, state):
    n = g.nodes[nid]
    return n.kind == "hypothesis" and state.get(nid) in ("pending", "open") and all(
        _dep_satisfied(g, state, d, et) for d, et in n.requires)


def blocked_reasons(g, nid, state):
    n = g.nodes[nid]
    return ["%s (%s, is %s)" % (d, et, state.get(d)) for d, et in n.requires if not _dep_satisfied(g, state, d, et)]
