"""graph.core.retro — deterministic signals from the event log (D21, D28, D34). The engine flags;
`/learn` and a human decide. Nothing here writes a rule."""

from graph.core import schedule as S

TIER_RANK = {"fast": 0, "standard": 1, "strong": 2, "frontier": 3}
# agent-delegation.md → Model & Effort Routing. Events may carry either a tier or a model name.
MODEL_TIER = {"haiku": "fast", "sonnet": "standard", "opus": "strong", "fable": "frontier"}


def rank(model_or_tier):
    m = (model_or_tier or "").lower()
    for k, t in MODEL_TIER.items():
        if k in m:
            return TIER_RANK[t]
    return TIER_RANK.get(m, 9)


def retro(g, events):
    verify_runs, reopens, red_since, red_time, retries = {}, {}, {}, {}, {}
    cost_node, cost_tier, attempts = {}, {}, {}
    merges, debt = [], []
    for e in events:
        if e.node == "_arch" and e.to == "measured":
            debt.append((e.ts, e.exit))
            continue
        if e.cmd:
            verify_runs[e.node] = verify_runs.get(e.node, 0) + 1
        if e.to == "reopened":
            reopens[e.node] = reopens.get(e.node, 0) + 1
        if e.to == "red":
            red_since[e.node] = e.ts
        if e.to == "green" and e.node in red_since:
            red_time[e.node] = e.ts - red_since.pop(e.node)
        if e.node.startswith("merge/"):
            merges.append(e.node)
        if e.exit not in (None, 0) and e.to != "red":
            retries[e.node] = retries.get(e.node, 0) + 1
        tok = (e.tokens_in or 0) + (e.tokens_out or 0)
        if tok or e.duration_s:
            cost_node[e.node] = cost_node.get(e.node, 0) + tok
            if e.model:
                cost_tier[e.model] = cost_tier.get(e.model, 0) + tok
        if e.model and e.to in ("done", "green", "validation-failed", "confirmed", "refuted"):
            attempts.setdefault(e.node, []).append((e.model, e.to, tok))
    flags = []
    for (t0, c0), (t1, c1) in zip(debt, debt[1:]):
        if c1 < c0:
            explained = any(t0 <= e.ts <= t1 and e.to == "done" and
                            (e.node.startswith("port/") or e.node.startswith("merge/") or e.node.startswith("usecase/"))
                            for e in events)
            if not explained:
                flags.append("UNEXPLAINED-DEBT-DROP %d -> %d with no port/merge/usecase completed in between - a dependency may have gone underground" % (c0, c1))
    for m in sorted(set(merges)):
        if merges.count(m) >= 2:
            flags.append("HIDDEN-DEPENDENCY %s recurred %dx -> propose a port/contract between the pair" % (m, merges.count(m)))
    for nid, c in reopens.items():
        if c >= 2 and nid.startswith("adapter/"):
            flags.append("UNSTABLE-CONTRACT %s reopened %dx -> strengthen its port contract test" % (nid, c))
    for nid, c in retries.items():
        if c >= 3:
            tier = S.derive_tier(g, g.nodes[nid]) if nid in g.nodes else "?"
            flags.append("HIGH-RETRY %s failed verify %dx -> check tier (%s) or split the node" % (nid, c, tier))
    for nid, seq in attempts.items():
        failed = [(m, t) for m, s, t in seq if s == "validation-failed"]
        ok = [(m, t) for m, s, t in seq if s in ("done", "green", "confirmed")]
        if failed and ok and rank(ok[-1][0]) > rank(failed[0][0]) and rank(failed[0][0]) < 9:
            flags.append("WRONG-TIER %s: failed at %s then passed at %s - both attempts cost %d tokens" % (
                nid, failed[0][0], ok[-1][0], sum(t for _, t in failed) + sum(t for _, t in ok)))
    return {"verify_runs": verify_runs, "reopens": reopens, "red_time": red_time, "retries": retries,
            "merges": len(merges), "cost_node": cost_node, "cost_tier": cost_tier, "flags": flags}


def summarize_rotations(records):
    """Pure fold over rotation records (dicts from adapters.rotation_logs). Returns totals; the
    adapter reads the files, this only adds them, so it stays testable without a filesystem."""
    total = {"n": len(records), "cost": 0.0, "tokens_in": 0, "tokens_out": 0, "turns": 0,
             "rate_limited": 0}
    for r in records:
        total["cost"] += r.get("cost", 0) or 0
        total["tokens_in"] += r.get("tokens_in", 0) or 0
        total["tokens_out"] += r.get("tokens_out", 0) or 0
        total["turns"] += r.get("turns", 0) or 0
        if r.get("rate_limited"):
            total["rate_limited"] += 1
    return total
