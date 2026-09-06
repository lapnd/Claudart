"""graph.core.graph — value objects, profiles, the enforcer registry, and lint.

HARD RULE (D15): nothing under graph/core performs I/O or imports an adapter. tests/graph/run.sh
enforces this with an `ast` walk (no open/print call; no os/sys/json/io/pathlib/subprocess import;
no graph.adapters import). Everything here is testable with an in-memory Graph.

Every node is a CLAIM + a VERIFIER + a STATE (D32). Which kinds exist is a profile; `hexagonal` is
the default because it is what this workspace builds, not because the engine assumes it.
"""

import re
from collections import namedtuple

GRAPH_FORMAT = 1
MANIFEST_VERSIONS = frozenset({1})

EDGE_TYPES = frozenset({
    "IMPLEMENTATION", "CONTRACT", "PORT", "DATA", "RUNTIME", "TEST", "DEPLOYMENT",
    "EVIDENCE",  # requires a CONFIRMED claim (debug profile, D31)
})

PROFILES = {
    "hexagonal": frozenset({"domain", "usecase", "port", "adapter", "contract", "mock", "composition",
                            "test", "merge", "gate", "spike"}),
    "debug": frozenset({"repro", "hypothesis", "fix", "test", "merge", "gate", "spike"}),
    "library": frozenset({"module", "api", "test", "merge", "gate", "spike"}),
}
KINDS = frozenset().union(*PROFILES.values())
BEHAVIOUR_KINDS = frozenset({"domain", "usecase", "port", "adapter", "composition", "mock", "fix", "module"})
WRITES_NOTHING = frozenset({"gate"})
TEST_KINDS = frozenset({"test", "repro"})

NODE_STATES = ("pending", "ready", "running", "done", "blocked", "reopened", "stale", "pruned")
TEST_STATES = ("pending", "red", "green")
HYPOTHESIS_STATES = ("open", "testing", "confirmed", "refuted")

Node = namedtuple("Node", "id kind task title verify requires paths forbid proves tier phase exclusive early_ok")
Event = namedtuple("Event", "ts node frm to cmd exit evidence agent worktree commit model tokens_in tokens_out duration_s mutation")
Finding = namedtuple("Finding", "category message")

# D29 — every deterministic check names the rule clause it makes checkable. `claudart-graph rules`
# prints this table; constitution-check fails a MUST clause that cites no registered enforcer.
ENFORCERS = {
    "BAD-ID": "graph-development §kinds: node ids are <kind>/<name>",
    "UNKNOWN-KIND": "graph-development §kinds: only profile roles are kinds",
    "UNKNOWN-PROFILE-KIND": "graph-development §profiles: a kind must belong to the manifest's profile",
    "GATE-WRITES": "graph-development §gate: a gate writes nothing",
    "DANGLING": "graph-development §edges: every requires/proves target exists",
    "BAD-EDGE": "graph-development §edges: registered edge types only",
    "CYCLE": "graph-development §dag: the graph is acyclic",
    "FORBIDDEN": "code-organization §3 + manifest rules.forbid: dependency direction",
    "NOT-COMPOSITION": "code-organization §4: only the composition root wires more than one adapter",
    "NO-TEST-FIRST": "graph-development §tdd: behaviour nodes require a TEST edge (red first)",
    "TEST-PROVES-NOTHING": "graph-development §tdd: a test names what it proves",
    "PORT-TEST-MISSING": "graph-development §seam: one shared contract test per outbound port",
    "ADAPTER-SKIPS-PORT-TEST": "graph-development §seam: every adapter passes the shared port test",
    "FIX-WITHOUT-CAUSE": "debug profile: a fix requires a CONFIRMED hypothesis (EVIDENCE) and a red repro",
    "UNANALYSED-TASK": "Lessons II.4: a roadmap task cannot exist without a scheduling decision",
    "PHASE-ORPHAN": "Lessons II.1: phase order is an ordering dependency unless early-ok is declared",
    "EMPTY-PATH-QUERY": "Lessons II.1: a path query matching nothing is a wrong query; fail closed",
    "FUTURE-TIMESTAMP": "Lessons VI.23: timestamps are read from the clock, never typed",
    "REFUSED-TRANSITION": "graph-development §tdd: done needs an observed red; red needs exit != 0",
    "CLAIMED-EXIT-REJECTED": "D30: the orchestrator runs verify itself; a worker's claimed exit is not evidence",
    "GATE-BUDGET": "Lessons IV.9: architecture debt is a ratchet matched exactly, both directions",
    "EVIDENCE-MISSING": "Lessons IV.13: an absent or empty evidence file means the job never ran",
    "STALE-RUNNING": "spec-workflow §crash-recovery: running past the budget with no terminal event",
    "MUTATION-MISSING": "evidence-gauntlet §5: a strong-tier implementation records a mutation score",
    "BRIEF-OVERSIZE": "GDSD §16 / Constitution §3: the brief has a byte budget",
    "MANIFEST-CHANGE-NEEDS-APPROVAL": "D33: adding/removing a port, contract or domain is a scope change",
    "UNEXPLAINED-DEBT-DROP": "Lessons IV.9/III.8: a debt drop with no port/move/merge is hiding, not fixing",
    "HIDDEN-DEPENDENCY": "GDSD §21: recurring merge conflicts reveal a missing port or contract",
    "UNSTABLE-CONTRACT": "GDSD §10.3: an adapter reopened after its port test went green has a weak contract test",
    "HIGH-RETRY": "agent-delegation §routing: escalate on evidence, one tier, once",
    "WRONG-TIER": "Constitution §2 / D34: a failed attempt at one tier followed by success one tier up cost both",
    "VERIFY-NOT-COMMAND": "D30: verify: is a shell command the orchestrator can execute, not prose about one",
}


class Graph(object):
    def __init__(self, nodes, manifest, unanalysed=None):
        self.nodes = dict((n.id, n) for n in nodes)
        self.manifest = manifest or {}
        self.unanalysed = list(unanalysed or [])

    def kind(self, nid):
        return nid.split("/", 1)[0]

    def profile(self):
        return self.manifest.get("profile", "hexagonal")

    def dependents(self, nid):
        return [n.id for n in self.nodes.values() if any(d == nid for d, _ in n.requires)]


def _adapters_by_port(manifest):
    out = {}
    for a in manifest.get("adapters", []):
        ports = a["port"] if isinstance(a.get("port"), list) else [a.get("port")]
        for pn in ports:
            out.setdefault("port/%s" % pn, []).append("adapter/%s" % a["name"])
    return out


def lint(g):
    out = []
    ids = set(g.nodes)
    allowed = PROFILES.get(g.profile(), KINDS)
    for n in g.nodes.values():
        if "/" not in n.id:
            out.append(Finding("BAD-ID", "%s has no <kind>/ prefix - kind cannot be derived" % n.id))
        if n.kind not in KINDS:
            out.append(Finding("UNKNOWN-KIND", "%s has kind %r" % (n.id, n.kind)))
        elif n.kind not in allowed:
            out.append(Finding("UNKNOWN-PROFILE-KIND", "%s: kind %s is not in profile %s" % (n.id, n.kind, g.profile())))
        if n.kind in WRITES_NOTHING and n.paths:
            out.append(Finding("GATE-WRITES", "%s is a gate but declares write paths" % n.id))
        for dep, et in n.requires:
            if dep not in ids:
                out.append(Finding("DANGLING", "%s requires unknown node %s" % (n.id, dep)))
            if et not in EDGE_TYPES:
                out.append(Finding("BAD-EDGE", "%s -> %s uses unknown edge type %s" % (n.id, dep, et)))
    # cycle (Kahn)
    indeg = dict((nid, 0) for nid in g.nodes)
    for n in g.nodes.values():
        for dep, _ in n.requires:
            if dep in indeg:
                indeg[n.id] += 1
    queue = [nid for nid, d in indeg.items() if d == 0]
    seen = 0
    while queue:
        cur = queue.pop()
        seen += 1
        for nid in g.dependents(cur):
            indeg[nid] -= 1
            if indeg[nid] == 0:
                queue.append(nid)
    if seen != len(g.nodes):
        out.append(Finding("CYCLE", "graph is not acyclic (%d/%d reachable)" % (seen, len(g.nodes))))
    # manifest forbid rules on kinds
    for r in g.manifest.get("rules", {}).get("forbid", []):
        for n in g.nodes.values():
            if n.kind != r.get("from"):
                continue
            for dep, _ in n.requires:
                if g.kind(dep) == r.get("to"):
                    out.append(Finding("FORBIDDEN", "%s -> %s violates %s->%s" % (n.id, dep, r["from"], r["to"])))
    # only the composition root may depend on more than one adapter — a rule about CODE that links,
    # so it binds behaviour-carrying kinds; docs, gates, tests and spikes may reference many adapters
    for n in g.nodes.values():
        adapters = [d for d, _ in n.requires if g.kind(d) == "adapter"]
        if len(adapters) > 1 and n.kind != "composition" and n.kind in BEHAVIOUR_KINDS:
            out.append(Finding("NOT-COMPOSITION", "%s depends on %d adapters but is not the composition root" % (n.id, len(adapters))))
    # TDD (D14/D18)
    for n in g.nodes.values():
        if n.kind in BEHAVIOUR_KINDS and not any(et == "TEST" for _, et in n.requires):
            out.append(Finding("NO-TEST-FIRST", "%s carries behaviour with no TEST edge" % n.id))
        if n.kind in TEST_KINDS and n.kind == "test":
            if not n.proves:
                out.append(Finding("TEST-PROVES-NOTHING", "%s has no proves: target" % n.id))
            elif n.proves not in ids:
                out.append(Finding("DANGLING", "%s proves unknown node %s" % (n.id, n.proves)))
    # debug profile (D31)
    for n in g.nodes.values():
        if n.kind == "fix":
            if not any(et == "EVIDENCE" and g.kind(d) == "hypothesis" for d, et in n.requires):
                out.append(Finding("FIX-WITHOUT-CAUSE", "%s has no EVIDENCE edge to a hypothesis" % n.id))
            if not any(et == "TEST" and g.kind(d) in TEST_KINDS for d, et in n.requires):
                out.append(Finding("FIX-WITHOUT-CAUSE", "%s has no TEST edge to a reproduction" % n.id))
    # verify must be executable by the orchestrator (D30)
    for n in g.nodes.values():
        v = n.verify or ""
        # prose, or a bare acceptance-scenario reference (`S39`, `S9, S35`) - a scenario names
        # what must hold, the command is how the orchestrator observes it (--run execs this line)
        if "`" in v or re.search(r"\b(exits?|expect|should|prints)\b", v) or re.match(r"\s*S\d+\b", v):
            out.append(Finding("VERIFY-NOT-COMMAND", "%s: verify is prose or a scenario id, not a command: %r" % (n.id, v[:60])))
    # completeness (D26)
    for tid, title in g.unanalysed:
        out.append(Finding("UNANALYSED-TASK", "%s %r has no node: metadata - decide where it sits" % (tid, title)))
    for n in g.nodes.values():
        if n.phase and n.phase > 1 and not n.early_ok and not n.requires:
            out.append(Finding("PHASE-ORPHAN", "%s is in phase %d with no requires - would run in wave 1; add an edge or early-ok: true" % (n.id, n.phase)))
    # shared outbound-port contract test (D17)
    port_tests = dict((n.proves, n.id) for n in g.nodes.values()
                      if n.kind == "test" and n.proves and g.kind(n.proves) == "port")
    for p in g.manifest.get("ports", []):
        pid = "port/%s" % p.get("name")
        if p.get("direction") == "out" and pid in g.nodes and pid not in port_tests:
            out.append(Finding("PORT-TEST-MISSING", "%s is an outbound port with no shared contract test" % pid))
    by_port = _adapters_by_port(g.manifest)
    for pid, tid in port_tests.items():
        for aid in by_port.get(pid, []):
            if aid in g.nodes and not any(d == tid and et == "TEST" for d, et in g.nodes[aid].requires):
                out.append(Finding("ADAPTER-SKIPS-PORT-TEST", "%s does not require shared %s" % (aid, tid)))
    return out
