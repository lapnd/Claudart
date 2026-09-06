"""graph.adapters.text_brief — the node brief: the ONLY artifact that crosses the LLM boundary (D13).

Section 1 is rendered only from the manifest and is byte-identical for every node in a project
(the shared cache prefix — Constitution §6.2/§7). Everything the worker needs is inlined; what it
must NOT read or wait for is named; it is told it records nothing (D30)."""

from graph.core import schedule as S


def render_invariants(m):
    out = ["# 1. INVARIANTS - identical for every node in %s (stable cache prefix)" % m.get("project")]
    out.append("profile: %s" % m.get("profile", "hexagonal"))
    out.append("layers:")
    for k in ("domain", "usecases", "ports", "adapters", "composition", "contracts", "frontend"):
        if k in m.get("layout", {}):
            out.append("  %-12s %s" % (k, m["layout"][k]))
    out.append("forbidden-always:")
    for r in m.get("rules", {}).get("forbid", []):
        out.append("  %s -> %s" % (r.get("from"), r.get("to")))
    out.append("tdd: architecture first -> tests second (observed RED) -> implementation third; never skip or weaken a test")
    mt = m.get("mutation", {})
    if mt:
        out.append("mutation: %s  threshold %s" % (", ".join("%s=%s" % kv for kv in mt.items() if kv[0] != "threshold"), mt.get("threshold")))
    return "\n".join(out)


def render_brief(g, nid, state, power):
    m, n = g.manifest, g.nodes[nid]
    ports = dict((p.get("name"), p) for p in m.get("ports", []))
    adapters = dict((a.get("name"), a) for a in m.get("adapters", []))
    tier = S.derive_tier(g, n)
    slug = nid.replace("/", "-")
    out = [render_invariants(m), ""]
    out += ["# 2. NODE - the only part that differs between agents",
            "id:       %s" % nid, "kind:     %s" % n.kind, "tier:     %s" % tier,
            "task:     %s %s" % (n.task, n.title),
            "worktree: .worktrees/%s   (branch node/%s)" % (slug, slug), ""]
    out.append("# 3. CONTRACT - inlined; do not go looking for it")
    short = nid.split("/", 1)[1]
    if n.kind == "adapter" and short in adapters:
        plist = adapters[short]["port"] if isinstance(adapters[short].get("port"), list) else [adapters[short].get("port")]
        for pn in plist:
            p = ports.get(pn, {})
            role = "driving (calls an inbound port)" if p.get("direction") == "in" else "driven (implements an outbound port)"
            out.append("port: %-18s direction: %-4s role: %s  at: %s" % (pn, p.get("direction", "?"), role, p.get("path", "-")))
    elif n.kind == "port" and short in ports:
        p = ports[short]
        out.append("direction: %s   owner: %s" % (p.get("direction"), p.get("domain") or p.get("usecase")))
        impls = [a["name"] for a in m.get("adapters", []) if short in (a["port"] if isinstance(a.get("port"), list) else [a.get("port")])]
        out.append("adapters that must pass this port's shared contract test: %s" % (", ".join(impls) or "(none yet)"))
    elif n.kind in ("test", "repro"):
        out.append("proves: %s" % n.proves)
        st = state.get(nid)
        out.append("expectation now: %s" % ("run it; it MUST fail (exit != 0) before %s may start" % n.proves if st in ("pending", "stale") else "must pass (exit 0) now that %s is done" % n.proves))
    elif n.kind == "hypothesis":
        out.append("this is a CLAIM: verify is the cheapest observation that discriminates it; report confirmed or refuted with the observation")
    else:
        out.append("(this node owns its own surface)")
    out.append("")
    out.append("# 4. INPUTS - state and where their output lives")
    for dep, et in n.requires:
        d = g.nodes.get(dep)
        out.append("  %-28s %-16s %-9s %s" % (dep, "(%s)" % et, state.get(dep, "?"), ", ".join(d.paths) if d and d.paths else "-"))
    if not n.requires:
        out.append("  (none)")
    out.append("")
    out.append("# 5. WRITE SCOPE - anything else: report, do not edit")
    out.append("allow: %s" % (", ".join(n.paths) or "(nothing - this is a gate)"))
    out.append("deny:  %s" % (", ".join(n.forbid) or "(only the always-forbidden edges above)"))
    out.append("")
    out.append("# 6. DONE WHEN")
    out.append("verify: %s" % n.verify)
    out.append("You do NOT record state and you write nothing under the spec folder. Return: files changed, the verify command you ran and its exit, residual risk.")
    out.append("The orchestrator re-runs verify on the merged tree and records what IT observed - a claimed pass is not evidence.")
    out.append("If verify is itself defective: prove it (run it, show the line) and report; never edit something that is not its subject to change its result.")
    out.append("")
    deps = set(d for d, _ in n.requires)
    out.append("# 7. NOT REQUIRED - do not read, do not wait")
    out.append("  " + (", ".join(sorted(x for x in g.nodes if x != nid and x not in deps)) or "-"))
    out.append("")
    out.append("# 8. WHY: completing this makes %d downstream node(s) ready." % power.get(nid, 0))
    return "\n".join(out)
