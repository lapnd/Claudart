"""graph.adapters.cli — the driving adapter. The exit-code contract lives HERE, once:

    0  clean / gate open / accepted
    1  findings / gate closed / refused transition / needs approval
    2  usage, parse, or runtime failure

The engine never executes a verify on its own initiative; `event … --run` does so at the
orchestrator's request and records only what it observed (D30). State is a fold over
`<dir>/graph/events.jsonl`, the one file the engine writes (D19).
"""

import argparse
import os
import sys
import time

from graph.core import graph as core
from graph.core import fold as F
from graph.core import schedule as S
from graph.core import retro as RT
from graph.adapters import yaml_manifest, md_roadmap, jsonl_events, runner, fs_paths, text_brief, bookkeeping

EXIT_CLEAN, EXIT_FINDINGS, EXIT_USAGE = 0, 1, 2
MANIFEST = "architecture.yaml"
ROADMAP_CANDIDATES = ("ROADMAP.md", "ROADMAP.sample.md")
DEFAULT_RUNNING_BUDGET_S = 4 * 3600


# ------------------------------------------------------------------------------ loading
def _paths(where):
    return (os.path.join(where, MANIFEST),
            next((os.path.join(where, c) for c in ROADMAP_CANDIDATES if os.path.isfile(os.path.join(where, c))), None),
            os.path.join(where, "graph", "events.jsonl"),
            os.path.join(where, "graph", "evidence"))


def load_manifest(where):
    """The manifest alone. `drift`/`extract` compare a manifest with a tree and need no ROADMAP —
    a brownfield audit runs before any mission exists."""
    mpath = _paths(where)[0]
    if not os.path.isfile(mpath):
        print("error: no %s in %s" % (MANIFEST, where)); sys.exit(EXIT_USAGE)
    try:
        with open(mpath, encoding="utf-8") as fh:
            return yaml_manifest.parse(fh.read())
    except ValueError as exc:
        print("MANIFEST REJECTED: %s" % exc); sys.exit(EXIT_USAGE)


def load(where):
    _, rpath, epath, _ = _paths(where)
    manifest = load_manifest(where)
    if rpath is None:
        print("error: no ROADMAP.md (or ROADMAP.sample.md) in %s" % where); sys.exit(EXIT_USAGE)
    try:
        with open(rpath, encoding="utf-8") as fh:
            nodes, errors, unanalysed, ticked = md_roadmap.parse_with_ticks(fh.read())
    except ValueError as exc:
        print("ROADMAP REJECTED: %s" % exc); sys.exit(EXIT_USAGE)
    try:
        events = jsonl_events.read_events(epath)
    except ValueError as exc:
        print("EVENT LOG REJECTED: %s" % exc); sys.exit(EXIT_USAGE)
    g = core.Graph(nodes, manifest, unanalysed)
    g.ticked = ticked
    return g, errors, events


def _resolved(args, g):
    root = getattr(args, "root", None)
    return fs_paths.resolve_paths(root, g) if root else None


# ----------------------------------------------------------------------------- commands
def cmd_lint(args):
    g, errors, _ = load(args.dir)
    findings = core.lint(g)
    for e in errors:
        print("%-24s %s" % ("PARSE", e))
    for f in findings:
        print("%-24s %s" % f)
    if findings or errors:
        print("LINT FAILED - %d finding(s), %d parse error(s)" % (len(findings), len(errors)))
        return EXIT_FINDINGS
    print("clean - %d nodes, profile %s, no cycle, no dangling ref, no forbidden edge, TDD edges complete" % (len(g.nodes), g.profile()))
    return EXIT_CLEAN


def cmd_rules(args):
    print("%-30s %s" % ("ENFORCER", "rule clause it makes checkable"))
    for k, v in core.ENFORCERS.items():
        print("%-30s %s" % (k, v))
    return EXIT_CLEAN


def cmd_schedule(args):
    g, _, _ = load(args.dir)
    power, dep = S.unblocking_power(g), S.depth(g)
    resolved = _resolved(args, g)
    rc = EXIT_CLEAN
    if resolved is not None:
        for f in S.empty_queries(g, resolved):
            print("%-24s %s" % f); rc = EXIT_FINDINGS
    waves = S.project_waves(g)
    for i, w in enumerate(waves, 1):
        print("WAVE %d - %d node(s)" % (i, len(w)))
        for nid in w:
            n = g.nodes[nid]
            print("  %-30s %-12s tier=%-8s unblocks=%d" % (nid, n.kind, S.derive_tier(g, n), power[nid]))
        for a, b, how, where_ in S.merge_risk(g, w, resolved):
            print("  MERGE RISK %s <-> %s  [%s: %s]  -> worktrees; a conflict becomes %s" % (a, b, how, where_, S.synthesize_merge_node(a, b, where_).id))
        excl = [n for n in w if g.nodes[n].exclusive]
        if excl:
            print("  EXCLUSIVE %s needs a quiet tree: run alone at the first quiet moment" % ", ".join(excl))
    sh = S.shape(waves)
    print("critical path length: %d | wave widths: %s | serial prefix: %d wave(s) | max width: %d" % (
        max(dep.values()) if dep else 0, sh["widths"], sh["serial_prefix"], sh["max_width"]))
    return rc


def cmd_next(args):
    g, _, ev = load(args.dir)
    state = F.fold(g, ev, getattr(g, 'ticked', ()))
    tests = sorted(n for n in g.nodes if F.test_ready(g, n, state))
    hyps = sorted(n for n in g.nodes if F.hypothesis_ready(g, n, state))
    impls = F.ready_set(g, state)
    print("READY tests to write (will be RED): %s" % (", ".join(tests) or "-"))
    if hyps:
        print("READY hypotheses to test: %s" % ", ".join(hyps))
    print("READY implementations (their test is RED): %s" % (", ".join(impls) or "-"))
    resolved = _resolved(args, g)
    for a, b, how, where_ in S.merge_risk(g, tests + hyps + impls, resolved):
        print("MERGE RISK %s <-> %s [%s: %s]" % (a, b, how, where_))
    shown = 0
    for n in sorted(g.nodes):
        if state.get(n) == "pending" and n not in tests and n not in impls and n not in hyps and shown < 8:
            print("BLOCKED %-30s <- %s" % (n, "; ".join(F.blocked_reasons(g, n, state)))); shown += 1
    return EXIT_CLEAN


def cmd_brief(args):
    g, _, ev = load(args.dir)
    if args.node not in g.nodes:
        print("unknown node %s" % args.node); return EXIT_USAGE
    text = text_brief.render_brief(g, args.node, F.fold(g, ev, getattr(g, 'ticked', ())), S.unblocking_power(g))
    budget = g.manifest.get("brief", {}).get("max_bytes")
    print(text)
    if budget and len(text.encode("utf-8")) > int(budget):
        print("BRIEF-OVERSIZE: %d bytes > brief.max_bytes %s" % (len(text.encode("utf-8")), budget)); return EXIT_FINDINGS
    return EXIT_CLEAN


def cmd_event(args):
    g, _, ev = load(args.dir)
    _, _, epath, evdir = _paths(args.dir)
    state = F.fold(g, ev, getattr(g, 'ticked', ()))
    nid, to = args.node, args.to
    if nid not in g.nodes and not nid.startswith("merge/"):
        print("unknown node %s" % nid); return EXIT_USAGE
    cmd, code = args.cmd, args.exit
    evidence = None
    if args.run:
        if nid not in g.nodes:
            print("cannot --run a node the roadmap does not list"); return EXIT_USAGE
        root = args.root or args.dir
        ev_abs = os.path.join(evdir, nid.replace("/", "-") + ".log")
        observed = runner.run_verify(g.nodes[nid].verify, root, ev_abs, args.timeout)
        evidence = os.path.relpath(ev_abs, args.dir)
        if code is not None and code != observed:
            print("CLAIMED-EXIT-REJECTED: worker claimed exit %d, orchestrator observed %d (%s)" % (code, observed, evidence))
        cmd, code = g.nodes[nid].verify, observed
        if to in ("done", "green", "confirmed") and observed != 0:
            jsonl_events.append_event(epath, nid, state.get(nid), "validation-failed", cmd, code, evidence, args.agent, args.worktree, args.commit, args.model, args.tokens_in, args.tokens_out, args.duration)
            print("REFUSED: verify exited %d - recorded validation-failed, not %s" % (observed, to)); return EXIT_FINDINGS
    if to == "green" and nid in g.nodes and g.nodes[nid].kind in core.TEST_KINDS and state.get(nid) not in ("red", "stale"):
        print("REFUSED-TRANSITION: %s cannot be green from %s - a test is green only after it was observed red (D18)" % (nid, state.get(nid))); return EXIT_FINDINGS
    if to == "red" and (code is None or code == 0):
        print("REFUSED-TRANSITION: a test reaches red only with an observed nonzero exit (D18)"); return EXIT_FINDINGS
    if to in ("done", "confirmed") and nid in g.nodes and g.nodes[nid].kind not in core.TEST_KINDS:
        for d, et in g.nodes[nid].requires:
            if et == "TEST" and state.get(d) not in ("red", "green"):
                print("REFUSED-TRANSITION: %s cannot be %s - its test %s was never observed red" % (nid, to, d)); return EXIT_FINDINGS
    if evidence is None and cmd:
        evidence = "graph/evidence/%s.log" % nid.replace("/", "-")
    jsonl_events.append_event(epath, nid, state.get(nid), to, cmd, code, evidence, args.agent, args.worktree, args.commit, args.model, args.tokens_in, args.tokens_out, args.duration, args.mutation)
    print("event: %s %s -> %s%s" % (nid, state.get(nid), to, "  [orchestrator-observed exit %d]" % code if args.run else ""))
    if to == "done" and nid in g.nodes and g.nodes[nid].kind not in core.TEST_KINDS:
        for t in g.nodes.values():
            if t.kind in core.TEST_KINDS and t.proves == nid and state.get(t.id) == "red":
                jsonl_events.append_event(epath, t.id, "red", "green", cmd, code, evidence)
                print("event: %s red -> green (proved by %s)" % (t.id, nid))
    if to == "done":
        resolved = _resolved(args, g)
        if resolved is not None:
            rv = S.reverify_after_merge(g, nid, F.fold(g, jsonl_events.read_events(epath), getattr(g, 'ticked', ())), resolved, jsonl_events.read_events(epath))
            if rv:
                print("RE-VERIFY on the integrated tree (files overlap, evidence predates this merge): %s" % ", ".join(rv))
    return EXIT_CLEAN


def cmd_reopen(args):
    g, _, ev = load(args.dir)
    _, _, epath, _ = _paths(args.dir)
    state = F.fold(g, ev, getattr(g, 'ticked', ()))
    jsonl_events.append_event(epath, args.node, state.get(args.node), "reopened")
    st = F.fold(g, jsonl_events.read_events(epath), getattr(g, 'ticked', ()))
    stale = sorted(k for k, v in st.items() if v == "stale")
    print("reopened: %s\nstale   : %s" % (args.node, ", ".join(stale) or "none"))
    return EXIT_FINDINGS if stale else EXIT_CLEAN


def cmd_progress(args):
    g, _, ev = load(args.dir)
    state = F.fold(g, ev, getattr(g, 'ticked', ()))
    tests = [n for n in g.nodes.values() if n.kind in core.TEST_KINDS]
    green = [t.id for t in tests if state.get(t.id) == "green"]
    red = [t.id for t in tests if state.get(t.id) == "red"]
    pend = [t.id for t in tests if state.get(t.id) in ("pending", "stale")]
    print("green %d/%d | red %d | not yet written %d" % (len(green), len(tests), len(red), len(pend)))
    print("red: %s" % (", ".join(sorted(red)) or "-"))
    # HEALTH: a machine-readable liveness line the watchdog polls (D43). File-derived, no model call.
    from graph.adapters import health as _health
    hstate, hd = _health.assess(args.dir, getattr(args, "stall_seconds", None) or _health.DEFAULT_STALL_SECONDS)
    age = hd["ledger_age_s"]
    print("HEALTH %s | tasks %d/%d | ledger-age %s | rate-limited %s" % (
        hstate, hd["ticked"], hd["total"],
        ("%ds" % int(age)) if age is not None else "-", "yes" if hd["rate_limited"] else "no"))
    if args.fail_on_regression:
        regressed = sorted(set(e.node for e in ev if e.to == "red" and any(p.node == e.node and p.to == "green" and p.ts <= e.ts and p is not e for p in ev)))
        if regressed:
            print("REGRESSION: %s" % ", ".join(regressed)); return EXIT_FINDINGS
    return EXIT_CLEAN


def cmd_measure(args):
    g, _, _ = load(args.dir)
    _, _, epath, _ = _paths(args.dir)
    jsonl_events.append_event(epath, "_arch", None, "measured", "claudart-graph drift", args.count)
    print("measured: %d violation(s) (budget %s)" % (args.count, g.manifest.get("architecture", {}).get("budget", 0)))
    return EXIT_CLEAN


def cmd_gate(args):
    g, _, ev = load(args.dir)
    state = F.fold(g, ev, getattr(g, 'ticked', ()))
    now = int(time.time())
    missing = []
    for n in g.nodes.values():
        s = state.get(n.id)
        if s == "pruned":
            continue
        if n.kind in core.TEST_KINDS:
            if s != "green":
                missing.append("test not green: %s (%s)" % (n.id, s))
        elif n.kind == "hypothesis":
            if s not in ("confirmed", "refuted"):
                missing.append("hypothesis undecided: %s (%s)" % (n.id, s))
        elif s != "done":
            missing.append("node not done: %s (%s)" % (n.id, s))
    budget = g.manifest.get("architecture", {}).get("budget", 0)
    if args.violations is None:
        missing.append("GATE-BUDGET: drift was not measured")
    elif args.violations != budget:
        missing.append("GATE-BUDGET: measured %d violation(s), budget pinned at %d (%s)" % (
            args.violations, budget, "new debt" if args.violations > budget else "unrecorded gain - lower the budget in this change"))
    thr = g.manifest.get("mutation", {}).get("threshold")
    if thr is not None and (args.mutation is None or args.mutation < float(thr)):
        missing.append("mutation score %s below threshold %s" % (args.mutation, thr))
    for n in g.nodes.values():
        if S.derive_tier(g, n) == "strong" and n.kind in core.BEHAVIOUR_KINDS and state.get(n.id) == "done":
            if not any(e.node == n.id and e.to == "done" and e.mutation is not None for e in ev):
                missing.append("MUTATION-MISSING: %s is strong-tier and done with no recorded mutation score" % n.id)
    if args.check_evidence:
        for e in ev:
            if e.to in ("done", "green", "red", "confirmed", "refuted") and e.evidence and not runner.evidence_ok(e.evidence, args.dir):
                missing.append("EVIDENCE-MISSING: %s -> %s cites %s which is absent or empty" % (e.node, e.to, e.evidence))
    for e in ev:
        if e.ts > now + 60:
            missing.append("FUTURE-TIMESTAMP: %s event at %d is after now (%d)" % (e.node, e.ts, now)); break
    last = {}
    for e in ev:
        last[e.node] = e.ts
    for n, s in state.items():
        if s == "running" and now - last.get(n, now) > args.running_budget:
            missing.append("STALE-RUNNING: %s running for %ds with no terminal event" % (n, now - last[n]))
    if missing:
        print("GATE CLOSED - %d item(s) missing:" % len(missing))
        for m in missing:
            print("  " + m)
        return EXIT_FINDINGS
    print("GATE OPEN - every node done, every test green, debt == budget (%d), mutation %s" % (budget, args.mutation))
    return EXIT_CLEAN


def cmd_status(args):
    g, _, ev = load(args.dir)
    state = F.fold(g, ev, getattr(g, 'ticked', ()))
    tests = [n for n in g.nodes.values() if n.kind in core.TEST_KINDS]
    green = sum(1 for t in tests if state.get(t.id) == "green")
    done = sum(1 for n in g.nodes.values() if state.get(n.id) in ("done", "confirmed", "refuted"))
    pick = lambda st: ", ".join(sorted(k for k, v in state.items() if v == st)) or "-"
    print("profile %s | nodes %d done %d | tests green %d/%d | running %s | stale %s | pruned %s" % (
        g.profile(), len(g.nodes), done, green, len(tests), pick("running"), pick("stale"), pick("pruned")))
    f = core.lint(g)
    print("lint %s | budget %s | next: %s" % ("clean" if not f else "%d finding(s)" % len(f),
          g.manifest.get("architecture", {}).get("budget", 0), ", ".join(F.ready_set(g, state)[:4]) or "-"))
    return EXIT_CLEAN


def cmd_retro(args):
    from graph.adapters import rotation_logs
    g, _, ev = load(args.dir)
    r = RT.retro(g, ev)
    print("verify runs : %s" % r["verify_runs"]); print("reopens     : %s" % r["reopens"])
    print("red time    : %s" % r["red_time"]); print("retries     : %s" % r["retries"]); print("merge nodes : %d" % r["merges"])
    print("cost/node   : %s" % r["cost_node"]); print("cost/model  : %s" % r["cost_tier"])
    # Rotation cost (D42): summed from the successors' own result-JSON logs — no model call here.
    recs, unreadable = rotation_logs.read_rotation_logs(os.path.join(args.dir, "artifacts", "rotations"))
    rt = RT.summarize_rotations(recs)
    print("rotations   : %d \u00b7 $%.4f \u00b7 in %d / out %d \u00b7 turns %d%s" % (
        rt["n"], rt["cost"], rt["tokens_in"], rt["tokens_out"], rt["turns"],
        (" \u00b7 rate-limited %d" % rt["rate_limited"]) if rt["rate_limited"] else ""))
    for name in unreadable:
        print("ROTATION-LOG-UNREADABLE %s" % name)
    print("FLAGS for /learn:")
    for fl in r["flags"] or ["  none"]:
        print("  " + fl if not fl.startswith("  ") else fl)
    return EXIT_CLEAN


def cmd_manifest_diff(args):
    g, _, _ = load(args.dir)
    try:
        with open(args.old, encoding="utf-8") as fh:
            old = yaml_manifest.parse(fh.read())
    except (OSError, ValueError) as exc:
        print("old manifest unreadable: %s" % exc); return EXIT_USAGE
    needs, exec_level = fs_paths.manifest_change_class(old, g.manifest)
    for x in needs:
        print("MANIFEST-CHANGE-NEEDS-APPROVAL %s" % x)
    for x in exec_level:
        print("executor-level %s" % x)
    return EXIT_FINDINGS if needs else EXIT_CLEAN


def cmd_extract(args):
    from graph.adapters import fs_extract
    mpath = os.path.join(args.dir, MANIFEST) if args.dir else os.path.join(args.root, MANIFEST)
    manifest = {}
    if os.path.isfile(mpath):
        with open(mpath, encoding="utf-8") as fh:
            manifest = yaml_manifest.parse(fh.read())
    result = fs_extract.extract(args.root, manifest)
    sys.stdout.write(result.manifest_text)
    return EXIT_CLEAN


def cmd_audit(args):
    """Scan a brownfield tree for architecture violations and emit a refactor plan (D40).

    extract (adapter) -> classify (core) -> write (adapter). Prints each violation with the same
    line `drift` uses, writes the plan under `--out`, and NEVER writes anywhere else. Exit 1 when
    the tree carries any violation, else 0.
    """
    from graph.adapters import fs_extract, plan_writer
    from graph.core import audit as A
    if args.profile != "hexagonal":
        print("audit currently scans for the hexagonal profile only (got %r)" % args.profile)
        return EXIT_USAGE
    mpath = os.path.join(args.root, MANIFEST)
    manifest = {}
    if os.path.isfile(mpath):
        with open(mpath, encoding="utf-8") as fh:
            manifest = yaml_manifest.parse(fh.read())
    result = fs_extract.extract(args.root, manifest)
    for v in result.violations:
        print("%s %s -> %s  → %s" % (v.code, v.file, v.target, v.hint))
    for f in result.findings:
        print("%s %s" % (f.category, f.message))
    n = len(result.violations)
    items = A.classify(result.violations)
    project = os.path.basename(os.path.abspath(args.root.rstrip("/"))) or "project"
    _, ppath = plan_writer.write_plan(args.out, result.manifest_text, n, items, project)
    print("%d violation(s); wrote %s and %s" % (n, os.path.join(args.out, MANIFEST), ppath))
    return EXIT_FINDINGS if n > 0 else EXIT_CLEAN


def cmd_drift(args):
    """Measure architecture violations in the real tree and compare with the pinned budget (D24)."""
    from graph.adapters import fs_extract
    manifest = load_manifest(args.dir)
    result = fs_extract.extract(args.root, manifest)
    for v in result.violations:
        print("%s %s -> %s  → %s" % (v.code, v.file, v.target, v.hint))
    for f in result.findings:
        print("%s %s" % (f.category, f.message))
    budget = manifest.get("architecture", {}).get("budget", 0)
    n = len(result.violations)
    hard = [f for f in result.findings if f.category in ("UNRESOLVED-IMPORT",)]
    print("%d violation(s); budget %d" % (n, budget))
    if getattr(args, "record", False):
        # the only write drift ever makes, and only on request: a `measured` event the gate reads
        epath = _paths(args.dir)[2]
        os.makedirs(os.path.dirname(epath), exist_ok=True)
        jsonl_events.append_event(epath, "_arch", None, "measured", "claudart-graph drift", n)
        print("recorded: measured %d" % n)
    if hard:
        print("DRIFT FAILED - %d unresolved import(s): fail closed" % len(hard)); return EXIT_FINDINGS
    if n != budget:
        print("GATE-BUDGET: measured %d, budget pinned at %d (%s)" % (n, budget, "new debt" if n > budget else "unrecorded gain - lower the budget in this change"))
        return EXIT_FINDINGS
    if any(f.category == "TEST-REACHES-INFRA" for f in result.findings):
        return EXIT_FINDINGS
    return EXIT_CLEAN


# ----------------------------------------------------------------- bookkeeping (D41)
def _spec_files(where):
    r = next((os.path.join(where, c) for c in ROADMAP_CANDIDATES if os.path.isfile(os.path.join(where, c))), None)
    return r, os.path.join(where, "LEDGER.md"), os.path.join(where, "SPEC.md")


def cmd_tick(args):
    g, _, ev = load(args.dir)
    rpath, lpath, spath = _spec_files(args.dir)
    node = next((n.id for n in g.nodes.values() if n.task == args.task), None)
    if node is None:
        print("no node for task %s" % args.task); return EXIT_USAGE
    e = bookkeeping.latest_terminal_event(ev, node)
    if e is None:
        print("REFUSED: %s (%s) has no done event — record `event %s done --run` first" % (args.task, node, node)); return EXIT_FINDINGS
    if not bookkeeping.tick_task(rpath, args.task):
        print("REFUSED: could not find exactly one pending line for %s" % args.task); return EXIT_FINDINGS
    body = ["Evidence: `%s` → exit %s · evidence `%s` · agent %s · observed by the orchestrator (event `%s`)" % (
        e.cmd, e.exit, e.evidence, e.agent or "-", e.to)]
    if e.model:
        body.append("Cost: model %s · tokens in/out %s/%s · %ss" % (e.model, e.tokens_in, e.tokens_out, e.duration_s))
    stamp = bookkeeping.append_ledger(lpath, "task-completed", args.task, body)
    if os.path.isfile(spath):
        bookkeeping.bump_updated(spath)
    print("ticked %s (%s) · LEDGER %s · SPEC updated bumped" % (args.task, node, stamp)); return EXIT_CLEAN


def cmd_ledger(args):
    _, lpath, _ = _spec_files(args.dir)
    try:
        stamp = bookkeeping.append_ledger(lpath, args.event, args.scope, [args.text], ts=args.ts)
    except ValueError as exc:
        print(str(exc)); return EXIT_FINDINGS
    print("LEDGER: %s — %s %s" % (stamp, args.event, args.scope)); return EXIT_CLEAN


def _repo_specs_root():
    """<repo>/.claude/specs, resolved from THIS file's location so it is correct in any project
    that installs CLAUDART and from any cwd (D43 hardening: a bare `sync-index` must never write
    outside the repo — the old `dirname(cwd)` default wrote to $HOME from the repo root)."""
    d = os.path.abspath(__file__)
    for _ in range(5):  # adapters -> graph -> scripts -> .claude -> <repo>
        d = os.path.dirname(d)
    return os.path.join(d, ".claude", "specs")


def cmd_sync_index(args):
    # sync-index scans ALL specs under one root, so the root never depends on --dir. Explicit
    # --specs-root wins (tests, non-standard layouts); otherwise the repo's own .claude/specs.
    root = args.specs_root or _repo_specs_root()
    a, d = bookkeeping.sync_index(root)
    print("INDEX synced: %d active, %d done (%s)" % (a, d, os.path.join(root, "INDEX.md"))); return EXIT_CLEAN


def cmd_phase_check(args):
    g, _, ev = load(args.dir)
    rpath, _, _ = _spec_files(args.dir)
    state = F.fold(g, ev, getattr(g, "ticked", ()))
    nodes = [n for n in g.nodes.values() if n.phase == args.phase]
    done = [n for n in nodes if state.get(n.id) in ("done", "green", "confirmed", "refuted", "pruned")]
    with open(rpath, encoding="utf-8") as fh:
        pv = bookkeeping.phase_validation_command(fh.read(), args.phase)
    print("phase %d: %d/%d complete%s" % (args.phase, len(done), len(nodes), " — phase %d complete" % args.phase if nodes and len(done) == len(nodes) else ""))
    print("validation: %s" % (pv or "(none declared)"))
    left = [n.id for n in nodes if n not in done]
    if left:
        print("remaining: %s" % ", ".join(left))
    print("rotation: %s" % ("due at this boundary (rotation: auto → claudart-rotate.sh)" if nodes and len(done) == len(nodes) else "not yet"))
    return EXIT_CLEAN if nodes and len(done) == len(nodes) else EXIT_FINDINGS


INIT_DEBUG_MANIFEST = "version: 1\nproject: %s\nprofile: debug\narchitecture:\n  budget: 0\n"
INIT_DEBUG_ROADMAP = """# ROADMAP — %s (debug profile)

graph-format: 1

## Phase 1 — Reproduce before anything

- [ ] P1.0 Deterministic reproduction of the bug (verify: %s)
      node: repro/bug | kind: repro
      paths: test/repro/**

## Phase 2 — Hypotheses, cheapest discriminator first

- [ ] P2.0 H1: <first hypothesis> (verify: <cheapest observation that discriminates it>)
      node: hypothesis/h1 | kind: hypothesis
      requires: repro/bug (TEST)
      paths: scripts/check-h1.sh
- [ ] P2.1 H2: <second hypothesis> (verify: <observation>)
      node: hypothesis/h2 | kind: hypothesis
      requires: repro/bug (TEST)
      paths: scripts/check-h2.sh

## Phase 3 — Fix only what was proven

- [ ] P3.0 Regression test for the confirmed cause (verify: <test command>)
      node: test/regression | kind: test
      proves: fix/cause
      requires: hypothesis/h1 (EVIDENCE)
      paths: test/regression/**
- [ ] P3.1 Fix the confirmed cause (verify: <test command> && %s)
      node: fix/cause | kind: fix
      requires: hypothesis/h1 (EVIDENCE), test/regression (TEST), repro/bug (TEST)
      paths: <files>
- [ ] P3.2 Gate (verify: bash .claude/scripts/claudart-graph.sh gate --dir .)
      node: gate/resolved | kind: gate
      requires: fix/cause (IMPLEMENTATION)
"""


def cmd_init(args):
    if args.profile != "debug":
        print("init currently seeds the debug profile only; hexagonal missions are seeded by /spec"); return EXIT_USAGE
    os.makedirs(args.dir, exist_ok=True)
    mp, rp = os.path.join(args.dir, MANIFEST), os.path.join(args.dir, "ROADMAP.md")
    if os.path.exists(mp) or os.path.exists(rp):
        print("refusing to overwrite an existing manifest/ROADMAP in %s" % args.dir); return EXIT_FINDINGS
    repro = args.repro or "sh scripts/repro.sh"
    with open(mp, "w", encoding="utf-8") as fh:
        fh.write(INIT_DEBUG_MANIFEST % args.project)
    with open(rp, "w", encoding="utf-8") as fh:
        fh.write(INIT_DEBUG_ROADMAP % (args.title or "Bug investigation", repro, repro))
    print("seeded %s and %s (edit the hypotheses, then: claudart-graph lint --dir %s)" % (mp, rp, args.dir))
    return EXIT_CLEAN


# ------------------------------------------------------------------------------- parser
def build_parser():
    p = argparse.ArgumentParser(prog="claudart-graph",
        description="Deterministic development-graph engine.\nExit codes: 0 clean/open/accepted, 1 findings/closed/refused, 2 usage/parse failure.",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", metavar="<command>")

    def add(name, fn, help_, root=False, **extra):
        sp = sub.add_parser(name, help=help_)
        sp.add_argument("--dir", default=".", help="spec folder (or /plan task companion) holding architecture.yaml + ROADMAP.md")
        if root:
            sp.add_argument("--root", help="repository tree to resolve path queries against (enables real-file merge risk)")
        sp.set_defaults(fn=fn)
        return sp

    add("lint", cmd_lint, "parse and report every finding")
    sub.add_parser("rules", help="print the enforcer registry").set_defaults(fn=cmd_rules)
    add("schedule", cmd_schedule, "project every wave, merge risk, shape metrics", root=True)
    add("next", cmd_next, "what is ready right now, and why the rest is blocked", root=True)
    b = add("brief", cmd_brief, "render the node brief - the only LLM-facing artifact"); b.add_argument("node")
    e = add("event", cmd_event, "record a transition (orchestrator only); --run executes verify and records the observed exit", root=True)
    e.add_argument("node"); e.add_argument("to", choices=["running", "red", "green", "done", "blocked", "reopened", "confirmed", "refuted", "validation-failed", "open", "testing"])
    e.add_argument("cmd", nargs="?"); e.add_argument("exit", nargs="?", type=int)
    e.add_argument("--run", action="store_true"); e.add_argument("--timeout", type=int, default=600)
    for opt in ("agent", "worktree", "commit", "model"):
        e.add_argument("--" + opt)
    e.add_argument("--tokens-in", dest="tokens_in", type=int); e.add_argument("--tokens-out", dest="tokens_out", type=int)
    e.add_argument("--duration", type=int); e.add_argument("--mutation", type=float)
    r = add("reopen", cmd_reopen, "reopen a node; transitive dependents become stale"); r.add_argument("node")
    pg = add("progress", cmd_progress, "Red -> Green progress + HEALTH line"); pg.add_argument("--fail-on-regression", action="store_true"); pg.add_argument("--stall-seconds", type=int)
    m = add("measure", cmd_measure, "record an architecture-debt measurement"); m.add_argument("count", type=int)
    gt = add("gate", cmd_gate, "is the mission done? lists exactly what is missing")
    gt.add_argument("--violations", type=int); gt.add_argument("--mutation", type=float)
    gt.add_argument("--check-evidence", action="store_true"); gt.add_argument("--running-budget", type=int, default=DEFAULT_RUNNING_BUDGET_S)
    add("status", cmd_status, "one-screen dashboard")
    add("retro", cmd_retro, "deterministic retrospective signals for /learn")
    md = add("manifest-diff", cmd_manifest_diff, "classify a manifest change: scope (needs approval) vs executor-level"); md.add_argument("old")
    ex = sub.add_parser("extract", help="derive the architecture manifest from a real tree (D8/D35)"); ex.add_argument("--root", required=True); ex.add_argument("--dir", default=None, help="folder whose architecture.yaml supplies layout/rules (default: --root)"); ex.set_defaults(fn=cmd_extract)
    dr = add("drift", cmd_drift, "measure violations in the tree against the manifest's rules and budget", root=True); dr.add_argument("--record", action="store_true", help="append a measured event to <dir>/graph/events.jsonl (the only write drift makes)")
    au = sub.add_parser("audit", help="scan a brownfield tree for architecture violations and emit a refactor plan (D40)")
    au.add_argument("--root", required=True, help="the project tree to scan (never modified)")
    au.add_argument("--out", required=True, help="output dir for architecture.yaml + refactor-plan.md")
    au.add_argument("--profile", default="hexagonal", help="architecture profile to scan for")
    au.set_defaults(fn=cmd_audit)
    tk = add("tick", cmd_tick, "flip a ROADMAP checkbox and write its LEDGER entry from the node's done event"); tk.add_argument("task")
    lg = add("ledger", cmd_ledger, "append a clock-stamped LEDGER entry"); lg.add_argument("event"); lg.add_argument("scope"); lg.add_argument("text"); lg.add_argument("--ts", type=int)
    si = add("sync-index", cmd_sync_index, "rewrite specs/INDEX.md from SPEC frontmatter"); si.add_argument("--specs-root")
    pc = add("phase-check", cmd_phase_check, "is phase N complete? prints its validation command"); pc.add_argument("phase", type=int)
    it = add("init", cmd_init, "seed a manifest + ROADMAP for a profile"); it.add_argument("--profile", default="debug"); it.add_argument("--project", default="project"); it.add_argument("--title"); it.add_argument("--repro")
    return p


def main(argv=None):
    p = build_parser()
    args = p.parse_args(argv)
    if not getattr(args, "fn", None):
        p.print_help(); return EXIT_USAGE
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
