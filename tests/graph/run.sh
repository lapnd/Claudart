#!/usr/bin/env bash
# tests/graph/run.sh — contract tests for the development-graph engine.
#
# Every fixture asserts BOTH the exit code and a marker string (verification.md §1: a check that
# has never been seen failing has not been shown to work). The core-purity test walks the AST of
# graph/core and has its own negative control. TAP-ish output; nonzero exit on any failure.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENGINE="$ROOT/.claude/scripts/claudart-graph.sh"
FIX="$ROOT/tests/graph/fixtures"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/claudart-graph-test.XXXXXX")
PASS_COUNT=0
FAIL_COUNT=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'ok %s - %s\n' "$PASS_COUNT" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'not ok - %s\n' "$1" >&2; }

# assert_fixture <name> <expected-exit> <marker>
# Output goes to a file and the exit code is read on the command's own line — never through a pipe
# (verification-mechanics.md §1).
assert_fixture() {
  local name=$1 want=$2 marker=$3 out="$TMP/$1.out" rc
  bash "$ENGINE" lint --dir "$FIX/$name" >"$out" 2>&1
  rc=$?
  if [ "$rc" -eq "$want" ]; then pass "$name: exit $want"; else fail "$name: expected exit $want, got $rc ($(head -1 "$out"))"; fi
  if grep -q -- "$marker" "$out"; then pass "$name: reports $marker"; else fail "$name: missing marker $marker ($(head -1 "$out"))"; fi
}

[ -x "$ENGINE" ] || fail "engine not executable at $ENGINE"

# --- every fixture: exit code + marker -------------------------------------------------------------
assert_fixture healthy                  0 "clean"
assert_fixture forbidden-edge           1 "FORBIDDEN"
assert_fixture cycle                    1 "CYCLE"
assert_fixture out-of-subset            2 "MANIFEST REJECTED"
assert_fixture no-test-first            1 "NO-TEST-FIRST"
assert_fixture test-proves-nothing      1 "TEST-PROVES-NOTHING"
assert_fixture adapter-skips-port-test  1 "ADAPTER-SKIPS-PORT-TEST"
assert_fixture not-composition          1 "NOT-COMPOSITION"
assert_fixture gate-writes              1 "GATE-WRITES"
assert_fixture unanalysed-task          1 "UNANALYSED-TASK"
assert_fixture phase-orphan             1 "PHASE-ORPHAN"
assert_fixture debug                    0 "profile debug"
assert_fixture debug-fix-without-cause  1 "FIX-WITHOUT-CAUSE"
assert_fixture verify-prose             1 "VERIFY-NOT-COMMAND"
# both bad lines fire (prose, and a bare scenario id like `S39`); the real command does not
[ "$(grep -c VERIFY-NOT-COMMAND "$TMP/verify-prose.out")" -eq 2 ] && pass "verify-prose: exactly the two non-command verifies are flagged" || fail "verify-prose: expected 2 VERIFY-NOT-COMMAND findings, got $(grep -c VERIFY-NOT-COMMAND "$TMP/verify-prose.out")"

# healthy must name exactly the expected node count (a parser that silently drops nodes still says "clean")
if grep -q "clean - 23 nodes" "$TMP/healthy.out"; then pass "healthy: parses exactly 23 nodes"; else fail "healthy: node count drifted ($(head -1 "$TMP/healthy.out"))"; fi

# early-ok clears PHASE-ORPHAN on the same fixture
cp -R "$FIX/phase-orphan" "$TMP/phase-orphan-ok"
printf '      early-ok: true\n' >>"$TMP/phase-orphan-ok/ROADMAP.sample.md"
bash "$ENGINE" lint --dir "$TMP/phase-orphan-ok" >"$TMP/po.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then pass "phase-orphan: early-ok: true is accepted"; else fail "phase-orphan: early-ok not honoured ($(head -1 "$TMP/po.out"))"; fi

# --- prettier-escaped metadata parses to the same query (formatter must not change the schedule) --
mkdir -p "$TMP/escaped"; cp "$FIX/healthy/architecture.yaml" "$TMP/escaped/"
printf '## Phase 1\n- [ ] P1.0 t (verify: go test ./internal/domain/user/... -run Test\\_Foo)\n      node: test/x | kind: test\n      proves: domain/x\n      paths: internal/domain/\\*\\*\n- [ ] P1.1 d (verify: true)\n      node: domain/x | kind: domain\n      requires: test/x (TEST)\n      paths: internal/domain/\\*\\*\n' >"$TMP/escaped/ROADMAP.sample.md"
if PYTHONPATH="$ROOT/.claude/scripts" python3 -c "
from graph.adapters import md_roadmap as R
n,e,u=R.parse(open('$TMP/escaped/ROADMAP.sample.md').read())
assert n[0].paths==['internal/domain/**'], n[0].paths
assert n[0].verify=='go test ./internal/domain/user/... -run Test_Foo', n[0].verify
"; then pass "markdown escapes (\\* \\_) are unescaped in paths and verify"; else fail "markdown escapes not unescaped"; fi

# --- a trailing (tier: …) annotation must not leak into verify (found by dogfooding this mission) ---
if PYTHONPATH="$ROOT/.claude/scripts" python3 -c "
from graph.adapters import md_roadmap as R
n,e,u=R.parse('## Phase 1\n- [ ] P1.0 t (verify: go test ./a/... -run X) (tier: strong)\n      node: test/t | kind: test\n      proves: domain/x\n')
assert n[0].verify=='go test ./a/... -run X', repr(n[0].verify)
assert n[0].tier=='strong', n[0].tier
"; then pass "trailing (tier: …) is parsed as tier, not swallowed into verify"; else fail "tier suffix leaks into verify"; fi

# --- verify may contain parentheses / subshells (found by dogfooding this mission) ---
if PYTHONPATH="$ROOT/.claude/scripts" python3 -c "
from graph.adapters import md_roadmap as R
n,e,u=R.parse('## Phase 1\n- [ ] P1.0 t (verify: test \"\$(grep -c x f)\" -ge 1 && (cd a && make)) (tier: fast)\n      node: test/t | kind: test\n      proves: domain/x\n')
assert n[0].verify=='test \"\$(grep -c x f)\" -ge 1 && (cd a && make)', repr(n[0].verify)
assert n[0].tier=='fast' and n[0].title=='t', (n[0].tier, n[0].title)
"; then pass "verify with subshells and nested parens parses whole"; else fail "verify with parens truncated"; fi

# --- CLI contract -----------------------------------------------------------------------------------
bash "$ENGINE" --help >"$TMP/help.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q "lint" "$TMP/help.out"; then pass "--help exits 0 and lists lint"; else fail "--help contract (rc=$rc)"; fi
bash "$ENGINE" >"$TMP/noarg.out" 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then pass "no subcommand exits 2"; else fail "no subcommand should exit 2, got $rc"; fi
bash "$ENGINE" rules >"$TMP/rules.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q "NO-TEST-FIRST" "$TMP/rules.out"; then pass "rules prints the enforcer registry"; else fail "rules registry (rc=$rc)"; fi
mkdir -p "$TMP/empty"
bash "$ENGINE" lint --dir "$TMP/empty" >"$TMP/empty.out" 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then pass "missing manifest exits 2"; else fail "missing manifest should exit 2, got $rc"; fi
# python3 absent -> exit 2 with a message (simulate with an empty PATH but a real bash)
PATH=/nonexistent /bin/bash "$ENGINE" lint >"$TMP/nopy.out" 2>&1; rc=$?
if [ "$rc" -eq 2 ] && grep -q "python3 is required" "$TMP/nopy.out"; then pass "missing python3 exits 2 with a message"; else fail "missing python3 handling (rc=$rc)"; fi

# --- core purity (D15): AST walk, plus a negative control that must FAIL --------------------------
purity() {
  # $1 = directory to walk. Prints violations; exits 1 if any.
  python3 - "$1" <<'PY'
import ast, os, sys
root = sys.argv[1]
banned_modules = {"os", "sys", "json", "io", "pathlib", "subprocess", "shutil", "socket", "tempfile"}
banned_calls = {"open", "print", "input", "exec", "eval"}
bad = []
for dirpath, _, files in os.walk(root):
    for f in files:
        if not f.endswith(".py"):
            continue
        p = os.path.join(dirpath, f)
        tree = ast.parse(open(p, encoding="utf-8").read(), filename=p)
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for a in node.names:
                    top = a.name.split(".")[0]
                    if top in banned_modules or a.name.startswith("graph.adapters"):
                        bad.append("%s:%d import %s" % (p, node.lineno, a.name))
            elif isinstance(node, ast.ImportFrom):
                mod = node.module or ""
                if mod.split(".")[0] in banned_modules or mod.startswith("graph.adapters"):
                    bad.append("%s:%d from %s import" % (p, node.lineno, mod))
            elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in banned_calls:
                bad.append("%s:%d call %s()" % (p, node.lineno, node.func.id))
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
}
purity "$ROOT/.claude/scripts/graph/core" >"$TMP/purity.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then pass "core purity: no I/O, no adapter import under graph/core"; else fail "core purity violated: $(head -3 "$TMP/purity.out" | tr '\n' ';')"; fi
# negative control: inject `import os` into a copy and expect the purity test to fail
cp -R "$ROOT/.claude/scripts/graph/core" "$TMP/core-dirty"
printf '\nimport os\n' >>"$TMP/core-dirty/graph.py"
purity "$TMP/core-dirty" >"$TMP/purity-neg.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q "import os" "$TMP/purity-neg.out"; then pass "core purity negative control: injected import os is caught"; else fail "core purity negative control did not fire (rc=$rc)"; fi

# =====================================================================================================
# Phase 2 — scheduling, state, the LLM boundary, the gate (S5–S8, S15, S16, S20–S23, S25–S29, S31–S34, S36, S37)
# =====================================================================================================
run() { local out=$1; shift; bash "$ENGINE" "$@" >"$out" 2>&1; RC=$?; }   # status read on its own line, never via a pipe

# S5 / S28
run "$TMP/sched.out" schedule --dir "$FIX/healthy"
W=$(awk '/^WAVE/{w=$2} /adapter\/postgres-user |adapter\/memory-user |adapter\/smtp-notify /{print w}' "$TMP/sched.out" | sort -u | wc -l | tr -d ' ')
if [ "$RC" -eq 0 ] && [ "$W" = "1" ]; then pass "S5: the three driven adapters share one wave"; else fail "S5: adapters split across $W wave(s) (rc=$RC)"; fi
if grep -q "wave widths: \[" "$TMP/sched.out" && grep -q "serial prefix:" "$TMP/sched.out" && grep -q "max width:" "$TMP/sched.out"; then pass "S28: shape metrics printed"; else fail "S28: shape metrics missing"; fi
FW=$(awk '/^WAVE/{w=$2} /adapter\/frontend-users /{print w; exit}' "$TMP/sched.out"); CW=$(awk '/^WAVE/{w=$2} /composition\/user-service /{print w; exit}' "$TMP/sched.out")
if [ -n "$FW" ] && [ -n "$CW" ] && [ "$FW" -le "$CW" ]; then pass "S5: frontend adapter scheduled no later than the composition root"; else fail "S5: frontend wave $FW vs composition wave $CW"; fi

# S6 / S22 / S26
run "$TMP/mr.out" schedule --dir "$FIX/merge-risk"
if grep -q "MERGE RISK adapter/postgres-user <-> adapter/memory-user" "$TMP/mr.out" && grep -q "merge/postgres-user+memory-user" "$TMP/mr.out"; then pass "S6/S22: MERGE RISK reported with synthesised merge node"; else fail "S6: merge risk not reported"; fi
MW=$(awk '/^WAVE/{w=$2} /adapter\/postgres-user |adapter\/memory-user /{print w}' "$TMP/mr.out" | sort -u | wc -l | tr -d ' ')
if [ "$MW" = "1" ]; then pass "S6: both overlapping nodes stay in the same wave (D10)"; else fail "S6: overlap split the wave"; fi
if grep -q "prefix heuristic (no tree)" "$TMP/mr.out"; then pass "S26: without --root the heuristic labels itself"; else fail "S26: heuristic label missing"; fi
run "$TMP/mr0.out" schedule --dir "$FIX/healthy"
if ! grep -q "MERGE RISK" "$TMP/mr0.out"; then pass "S6 negative control: healthy has no MERGE RISK"; else fail "S6: false positive on healthy"; fi
run "$TMP/ts.out" schedule --dir "$FIX/merge-risk" --root "$FIX/tree-shared"
if grep -q "1 shared file(s): internal/adapters/postgres/repo.go" "$TMP/ts.out"; then pass "S26: real intersection reported (tree-shared)"; else fail "S26: tree-shared intersection missing"; fi
run "$TMP/td.out" schedule --dir "$FIX/merge-risk" --root "$FIX/tree-disjoint"
if ! grep -q "MERGE RISK adapter/postgres-user <-> adapter/memory-user" "$TMP/td.out"; then pass "S26: same globs, disjoint on disk -> no risk"; else fail "S26: false overlap on tree-disjoint"; fi
if grep -qE "EMPTY-PATH-QUERY +adapter/postgres-user" "$TMP/td.out"; then pass "S26: a glob matching nothing fails closed"; else fail "S26: EMPTY-PATH-QUERY missing"; fi

# S7 / S22
run "$TMP/b1.out" brief adapter/http --dir "$FIX/healthy"; run "$TMP/b2.out" brief adapter/postgres-user --dir "$FIX/healthy"
sed -n '/# 1\./,/# 2\./p' "$TMP/b1.out" | sed '$d' >"$TMP/b1.inv"; sed -n '/# 1\./,/# 2\./p' "$TMP/b2.out" | sed '$d' >"$TMP/b2.inv"
if cmp -s "$TMP/b1.inv" "$TMP/b2.inv" && [ -s "$TMP/b1.inv" ]; then pass "S7: section 1 byte-identical across nodes"; else fail "S7: invariant prefix differs"; fi
if grep -q "driving" "$TMP/b1.out" && grep -q "driven" "$TMP/b2.out" && grep -q "tier:     strong" "$TMP/b2.out"; then pass "S22: brief states role and derived tier"; else fail "S22: role/tier missing"; fi
if grep -q "You do NOT record state" "$TMP/b2.out"; then pass "S7: brief tells the worker it records nothing (D30)"; else fail "S7: D30 sentence missing"; fi

# S15
cat >"$TMP/s15.py" <<'PYEOF'
import sys, io
from graph.core.graph import Graph
from graph.core import schedule as S
from graph.adapters import yaml_manifest as Y, md_roadmap as R
d = sys.argv[1]
m = Y.parse(io.open(d + "/architecture.yaml").read()); n, e, u = R.parse(io.open(d + "/ROADMAP.sample.md").read())
g = Graph(n, m, u); waves = S.project_waves(g); idx = {}
for i, w in enumerate(waves):
    for nid in w: idx[nid] = i
bad = [(t.id, t.proves) for t in g.nodes.values() if t.kind == "test" and t.proves in idx and not idx[t.id] < idx[t.proves]]
print("violations:", bad); sys.exit(1 if bad else 0)
PYEOF
if PYTHONPATH="$ROOT/.claude/scripts" python3 "$TMP/s15.py" "$FIX/healthy" >"$TMP/s15.out" 2>&1; then pass "S15: every test lands strictly before the node it proves"; else fail "S15: $(cat "$TMP/s15.out")"; fi

# S20 / S8 / S16 / S21 / S23 — live flow from an empty log
rm -rf "$TMP/live"; cp -R "$FIX/healthy" "$TMP/live"
run "$TMP/l1.out" event domain/user done "go test" 0 --dir "$TMP/live"; [ "$RC" -eq 1 ] && grep -q "REFUSED-TRANSITION" "$TMP/l1.out" && pass "S20: done before red is refused" || fail "S20: done-before-red accepted (rc=$RC)"
run "$TMP/l2.out" event test/domain-user red "go test" 0 --dir "$TMP/live"; [ "$RC" -eq 1 ] && grep -q "nonzero exit" "$TMP/l2.out" && pass "S20: red with exit 0 is refused" || fail "S20: red with exit 0 accepted"
run "$TMP/lg.out" event test/domain-user green "go test" 0 --dir "$TMP/live"; [ "$RC" -eq 1 ] && grep -q "green only after it was observed red" "$TMP/lg.out" && pass "S20: green without a prior red is refused" || fail "S20: green from pending accepted"
run "$TMP/l3.out" event test/domain-user red "go test" 1 --dir "$TMP/live"; [ "$RC" -eq 0 ] && pass "S20: red with exit 1 accepted" || fail "S20: red refused"
run "$TMP/l4.out" event domain/user done "go test" 0 --dir "$TMP/live"; [ "$RC" -eq 0 ] && grep -q "test/domain-user red -> green" "$TMP/l4.out" && grep -q '"to": "green"' "$TMP/live/graph/events.jsonl" && pass "S20: done writes an explicit red -> green event" || fail "S20: green not explicit"
run "$TMP/p.out" progress --dir "$TMP/live"; grep -q "green 1/9" "$TMP/p.out" && pass "S16: progress reports green 1/9" || fail "S16: $(head -1 "$TMP/p.out")"
run "$TMP/g.out" gate --violations 0 --mutation 0.9 --dir "$TMP/live"; [ "$RC" -eq 1 ] && grep -q "GATE CLOSED" "$TMP/g.out" && grep -q "test not green: test/port-user-repository" "$TMP/g.out" && pass "S21: gate closed lists what is missing" || fail "S21: gate (rc=$RC)"
run "$TMP/r.out" reopen domain/user --dir "$TMP/live"; [ "$RC" -eq 1 ] && grep -q "stale   : test/domain-user" "$TMP/r.out" && pass "S8: reopen marks the proving test stale, exits nonzero" || fail "S8: reopen"
rm -rf "$TMP/fresh"; cp -R "$FIX/healthy" "$TMP/fresh"
run "$TMP/p0.out" progress --fail-on-regression --dir "$TMP/fresh"; [ "$RC" -eq 0 ] && grep -q "green 0/9" "$TMP/p0.out" && pass "S16/S23: a fully red suite is the designed start (exit 0)" || fail "S16: fresh rc=$RC"
rm -rf "$TMP/reg"; cp -R "$FIX/healthy" "$TMP/reg"
bash "$ENGINE" event test/domain-user red x 1 --dir "$TMP/reg" >/dev/null 2>&1; bash "$ENGINE" event domain/user done x 0 --dir "$TMP/reg" >/dev/null 2>&1; sleep 1; bash "$ENGINE" event test/domain-user red x 1 --dir "$TMP/reg" >/dev/null 2>&1
run "$TMP/reg.out" progress --fail-on-regression --dir "$TMP/reg"; [ "$RC" -eq 1 ] && grep -q "REGRESSION: test/domain-user" "$TMP/reg.out" && pass "S23: green -> red is a regression (exit 1)" || fail "S23: regression not detected (rc=$RC)"

# S27 — budget ratchet
rm -rf "$TMP/bud"; cp -R "$FIX/healthy" "$TMP/bud"; sed -i.bak 's/  budget: 0/  budget: 5/' "$TMP/bud/architecture.yaml"
run "$TMP/b7.out" gate --violations 7 --dir "$TMP/bud"; grep -q "GATE-BUDGET: measured 7.*new debt" "$TMP/b7.out" && pass "S27: over budget = new debt" || fail "S27: over budget not flagged"
run "$TMP/b3.out" gate --violations 3 --dir "$TMP/bud"; grep -q "GATE-BUDGET: measured 3.*unrecorded gain" "$TMP/b3.out" && pass "S27: under budget also fails" || fail "S27: under budget not flagged"
run "$TMP/b5.out" gate --violations 5 --dir "$TMP/bud"; if ! grep -q "GATE-BUDGET" "$TMP/b5.out"; then pass "S27: exact budget -> no budget finding"; else fail "S27: exact budget flagged"; fi
run "$TMP/bn.out" gate --dir "$TMP/bud"; grep -q "drift was not measured" "$TMP/bn.out" && pass "S27: unmeasured drift fails" || fail "S27: unmeasured passed"

# S29 — retro flags, FUTURE-TIMESTAMP
rm -rf "$TMP/dd"; cp -R "$FIX/healthy" "$TMP/dd"; bash "$ENGINE" measure 12 --dir "$TMP/dd" >/dev/null; bash "$ENGINE" measure 9 --dir "$TMP/dd" >/dev/null
run "$TMP/dd.out" retro --dir "$TMP/dd"; grep -q "UNEXPLAINED-DEBT-DROP 12 -> 9" "$TMP/dd.out" && pass "S29: unexplained debt drop flagged" || fail "S29: not flagged"
rm -rf "$TMP/de"; cp -R "$FIX/healthy" "$TMP/de"; bash "$ENGINE" measure 12 --dir "$TMP/de" >/dev/null; bash "$ENGINE" event test/port-notification red x 1 --dir "$TMP/de" >/dev/null; bash "$ENGINE" event port/notification done x 0 --dir "$TMP/de" >/dev/null; bash "$ENGINE" measure 9 --dir "$TMP/de" >/dev/null
run "$TMP/de.out" retro --dir "$TMP/de"; if ! grep -q "UNEXPLAINED-DEBT-DROP" "$TMP/de.out"; then pass "S29: drop explained by a port is not flagged"; else fail "S29: explained drop flagged"; fi
rm -rf "$TMP/ft"; cp -R "$FIX/healthy" "$TMP/ft"; mkdir -p "$TMP/ft/graph"
python3 -c "import json,time; print(json.dumps({'ts':int(time.time())+7200,'node':'test/domain-user','from':'pending','to':'red','cmd':'x','exit':1}))" >"$TMP/ft/graph/events.jsonl"
run "$TMP/ft.out" gate --violations 0 --dir "$TMP/ft"; grep -q "FUTURE-TIMESTAMP" "$TMP/ft.out" && pass "S29: a future timestamp closes the gate" || fail "S29: future timestamp accepted"

# S31 — orchestrator runs verify (D30); S36 — evidence/stale/mutation/oversize/format
rm -rf "$TMP/rv"; cp -R "$FIX/run-verify" "$TMP/rv"
run "$TMP/rv1.out" event test/domain-user red claimed 1 --run --dir "$TMP/rv" --root "$TMP/rv"; [ "$RC" -eq 0 ] && grep -q "orchestrator-observed exit 1" "$TMP/rv1.out" && pass "S31: red accepted from an observed nonzero exit" || fail "S31: red via --run (rc=$RC)"
run "$TMP/rv2.out" event domain/user done claimed 0 --run --dir "$TMP/rv" --root "$TMP/rv"; [ "$RC" -eq 1 ] && grep -q "CLAIMED-EXIT-REJECTED" "$TMP/rv2.out" && grep -q '"to": "validation-failed"' "$TMP/rv/graph/events.jsonl" && pass "S31: claimed pass rejected, recorded validation-failed" || fail "S31: claimed pass accepted (rc=$RC)"
touch "$TMP/rv/tree/domain_test_passes"
run "$TMP/rv3.out" event domain/user done claimed 0 --run --dir "$TMP/rv" --root "$TMP/rv"; [ "$RC" -eq 0 ] && grep -q "orchestrator-observed exit 0" "$TMP/rv3.out" && pass "S31: done accepted once the artifact exists" || fail "S31: real pass refused"
if [ -s "$TMP/rv/graph/evidence/domain-user.log" ] && head -1 "$TMP/rv/graph/evidence/domain-user.log" | grep -q '^\$ test -f tree/domain_test_passes'; then pass "S31: evidence file non-empty, begins with the command"; else fail "S31: evidence file wrong"; fi
rm "$TMP/rv/graph/evidence/test-domain-user.log"
run "$TMP/em.out" gate --violations 0 --check-evidence --dir "$TMP/rv"; grep -q "EVIDENCE-MISSING: test/domain-user" "$TMP/em.out" && pass "S36: deleted evidence is caught" || fail "S36: EVIDENCE-MISSING not raised"
bash "$ENGINE" event port/notification running --dir "$TMP/rv" >/dev/null; sleep 2
run "$TMP/sr.out" gate --violations 0 --running-budget 1 --dir "$TMP/rv"; grep -q "STALE-RUNNING: port/notification" "$TMP/sr.out" && pass "S36: stale running detected" || fail "S36: STALE-RUNNING not raised"
rm -rf "$TMP/mm"; cp -R "$FIX/healthy" "$TMP/mm"
bash "$ENGINE" event test/port-user-repository red x 1 --dir "$TMP/mm" >/dev/null; bash "$ENGINE" event adapter/postgres-user done x 0 --dir "$TMP/mm" >/dev/null 2>&1
run "$TMP/mm.out" gate --violations 0 --dir "$TMP/mm"; grep -q "MUTATION-MISSING: adapter/postgres-user" "$TMP/mm.out" && pass "S36: strong-tier done without mutation score flagged" || fail "S36: MUTATION-MISSING not raised"
rm -rf "$TMP/bo"; cp -R "$FIX/healthy" "$TMP/bo"; printf '\nbrief:\n  max_bytes: 200\n' >>"$TMP/bo/architecture.yaml"
run "$TMP/bo.out" brief adapter/http --dir "$TMP/bo"; [ "$RC" -eq 1 ] && grep -q "BRIEF-OVERSIZE" "$TMP/bo.out" && pass "S36: brief over budget flagged" || fail "S36: BRIEF-OVERSIZE not raised"
rm -rf "$TMP/fv"; cp -R "$FIX/healthy" "$TMP/fv"; printf 'graph-format: 99\n' | cat - "$TMP/fv/ROADMAP.sample.md" >"$TMP/fv/R2" && mv "$TMP/fv/R2" "$TMP/fv/ROADMAP.sample.md"
run "$TMP/fv.out" lint --dir "$TMP/fv"; [ "$RC" -eq 2 ] && pass "S36: unknown graph-format exits 2" || fail "S36: graph-format 99 accepted (rc=$RC)"

# S32 — debug profile
rm -rf "$TMP/dbg"; cp -R "$FIX/debug" "$TMP/dbg"
run "$TMP/ds.out" schedule --dir "$TMP/dbg"
RW=$(awk '/^WAVE/{w=$2} /repro\/users-500/{print w; exit}' "$TMP/ds.out"); FXW=$(awk '/^WAVE/{w=$2} /fix\/close-on-error/{print w; exit}' "$TMP/ds.out"); HW=$(awk '/^WAVE/{w=$2} /hypothesis\//{print w}' "$TMP/ds.out" | sort -n | tail -1)
if [ "$RW" = "1" ] && [ -n "$FXW" ] && [ "$HW" -lt "$FXW" ]; then pass "S32: repro wave 1, every hypothesis before the fix"; else fail "S32: ordering (repro $RW, last hyp $HW, fix $FXW)"; fi
bash "$ENGINE" event repro/users-500 red x 1 --dir "$TMP/dbg" >/dev/null; bash "$ENGINE" event hypothesis/pool-exhausted refuted x 0 --dir "$TMP/dbg" >/dev/null
run "$TMP/dst.out" status --dir "$TMP/dbg"
if grep -q "pruned.*hypothesis/conn-leak" "$TMP/dst.out" && grep -q "pruned.*fix/close-on-error" "$TMP/dst.out" && ! grep "pruned" "$TMP/dst.out" | grep -q "hypothesis/timeout"; then pass "S32: refutation prunes the subtree, spares the sibling"; else fail "S32: pruning: $(head -1 "$TMP/dst.out")"; fi

# S33 — manifest-diff
rm -rf "$TMP/md"; cp -R "$FIX/healthy" "$TMP/md"; cp "$FIX/healthy/architecture.yaml" "$TMP/old.yaml"
python3 - "$TMP/md/architecture.yaml" <<'PYEOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("ports:\n","ports:\n  - name: audit-log\n    direction: out\n    domain: user\n    path: internal/ports/audit\n",1).replace("adapters:\n","adapters:\n  - name: ses-notify\n    port: notification\n    path: internal/adapters/ses\n",1); open(p,'w').write(s)
PYEOF
run "$TMP/md.out" manifest-diff "$TMP/old.yaml" --dir "$TMP/md"; [ "$RC" -eq 1 ] && grep -q "MANIFEST-CHANGE-NEEDS-APPROVAL ports +audit-log" "$TMP/md.out" && grep -q "executor-level adapters +ses-notify" "$TMP/md.out" && pass "S33: port add needs approval, adapter add is executor-level" || fail "S33: manifest-diff (rc=$RC)"

# S34 — cost + WRONG-TIER
rm -rf "$TMP/ct"; cp -R "$FIX/healthy" "$TMP/ct"
bash "$ENGINE" event test/domain-user red x 1 --dir "$TMP/ct" --model haiku --tokens-in 100 --tokens-out 50 >/dev/null
bash "$ENGINE" event domain/user validation-failed x 1 --dir "$TMP/ct" --model haiku --tokens-in 500 --tokens-out 100 >/dev/null
bash "$ENGINE" event domain/user done x 0 --dir "$TMP/ct" --model sonnet --tokens-in 700 --tokens-out 200 >/dev/null
run "$TMP/ct.out" retro --dir "$TMP/ct"; grep -q "WRONG-TIER domain/user: failed at haiku then passed at sonnet" "$TMP/ct.out" && grep -q "cost/model" "$TMP/ct.out" && pass "S34: cost per model and WRONG-TIER reported" || fail "S34: cost/WRONG-TIER missing"

# S37 — status + init
run "$TMP/st.out" status --dir "$FIX/healthy"; grep -q "profile hexagonal | nodes 23 done" "$TMP/st.out" && grep -q "lint clean | budget 0 | next:" "$TMP/st.out" && pass "S37: status is a one-screen dashboard" || fail "S37: status format"
rm -rf "$TMP/init"; run "$TMP/init.out" init --profile debug --dir "$TMP/init" --project x --title "bug" --repro "sh repro.sh"
run "$TMP/initl.out" lint --dir "$TMP/init"; [ "$RC" -eq 0 ] && grep -q "repro/bug" "$TMP/init/ROADMAP.md" && pass "S37: init --profile debug seeds a lint-clean graph" || fail "S37: init does not lint (rc=$RC)"
run "$TMP/init2.out" init --profile debug --dir "$TMP/init"; [ "$RC" -eq 1 ] && pass "S37: init refuses to overwrite" || fail "S37: init overwrote"

# =====================================================================================================
# RED-FIRST blocks (written before their implementations existed; each was observed failing)
# =====================================================================================================
# --- S39 rotate script (P2.10a → P2.11a) ---
ROT="$ROOT/.claude/scripts/claudart-rotate.sh"
rm -rf "$TMP/specs"; mkdir -p "$TMP/specs"; cp -R "$FIX/spec-copy" "$TMP/specs/2026-09-06-spec-copy"
if [ -f "$ROT" ]; then
  CLAUDART_SPECS_ROOT="$TMP/specs" bash "$ROT" --dry-run spec-copy >"$TMP/rot1.out" 2>&1; RC=$?
  [ "$RC" -eq 0 ] && grep -q "claude -p" "$TMP/rot1.out" && grep -q -- "--permission-mode acceptEdits" "$TMP/rot1.out" && grep -q "artifacts/rotations/" "$TMP/rot1.out" && pass "S39: --dry-run prints the claude -p command and log path" || fail "S39: dry-run (rc=$RC): $(head -2 "$TMP/rot1.out" | tr '\n' ' ')"
  CLAUDART_SPECS_ROOT="$TMP/specs" CLAUDART_MAX_ROTATIONS=0 bash "$ROT" --dry-run spec-copy >"$TMP/rot2.out" 2>&1; RC=$?
  [ "$RC" -eq 1 ] && grep -q "rotation ceiling reached" "$TMP/rot2.out" && pass "S39: rotation ceiling refuses" || fail "S39: ceiling not enforced (rc=$RC)"
  mkdir -p "$TMP/specs/2026-09-06-spec-copy/artifacts/rotations"; touch "$TMP/specs/2026-09-06-spec-copy/artifacts/rotations/$(date -u +%Y%m%dT%H%M%SZ).log"
  CLAUDART_SPECS_ROOT="$TMP/specs" bash "$ROT" --dry-run spec-copy >"$TMP/rot3.out" 2>&1; RC=$?
  [ "$RC" -eq 1 ] && grep -q "double launch" "$TMP/rot3.out" && pass "S39: a rotation log younger than 60 s refuses (double launch)" || fail "S39: double launch not detected (rc=$RC)"
  rm -rf "$TMP/specs/2026-09-06-spec-copy/artifacts/rotations"
  sed -i.bak 's/^status: running/status: poc-review/' "$TMP/specs/2026-09-06-spec-copy/SPEC.md"
  CLAUDART_SPECS_ROOT="$TMP/specs" bash "$ROT" --dry-run spec-copy >"$TMP/rot4.out" 2>&1; RC=$?
  [ "$RC" -eq 1 ] && grep -qi "not ready/running\|status" "$TMP/rot4.out" && pass "S39: refuses when the spec is not ready/running" || fail "S39: launched for a non-running spec (rc=$RC)"
  sed -i.bak 's/^status: poc-review/status: running/' "$TMP/specs/2026-09-06-spec-copy/SPEC.md"
  if ! grep -q -- "--dangerously-skip-permissions" "$TMP/rot1.out"; then pass "S39: never adds --dangerously-skip-permissions by itself"; else fail "S39: permission bypass present by default"; fi
  # D39 measured: headless -p denies any Bash call that would prompt, so the successor
  # must carry a scoped --allowedTools; the default toolkit must never include rm/push/sudo.
  if grep -q -- "--allowedTools \"Bash(bash .claude/scripts/\*)," "$TMP/rot1.out" && ! grep -qE "Bash\((rm|sudo|curl|wget|git push|git reset)" "$TMP/rot1.out"; then pass "S39: successor carries a scoped --allowedTools without rm/push/sudo"; else fail "S39: allowedTools default missing or too broad"; fi
else
  fail "S39: rotate script missing ($ROT)"; fail "S39: rotation ceiling"; fail "S39: double launch"; fail "S39: not-running refusal"; fail "S39: no permission bypass"; fail "S39: allowedTools"
fi

# --- S41 bookkeeping (P2.12a → P2.12) ---
rm -rf "$TMP/bk"; cp -R "$FIX/spec-copy" "$TMP/bk"
bash "$ENGINE" event test/domain-user red "go test ./internal/domain/user/..." 1 --dir "$TMP/bk" >/dev/null 2>&1
bash "$ENGINE" event domain/user done "go test ./internal/domain/user/..." 0 --dir "$TMP/bk" --agent sonnet >/dev/null 2>&1
run "$TMP/tick.out" tick P1.1 --dir "$TMP/bk"
if [ "$RC" -eq 0 ] && grep -q '^- \[x\] P1.1 ' "$TMP/bk/ROADMAP.md" && [ "$(grep -c '^- \[x\]' "$TMP/bk/ROADMAP.md")" = "1" ]; then pass "S41: tick flips exactly one checkbox"; else fail "S41: tick (rc=$RC)"; fi
if grep -q "task-completed P1.1" "$TMP/bk/LEDGER.md" && grep -q 'go test ./internal/domain/user/...' "$TMP/bk/LEDGER.md" && grep -q "graph/evidence/domain-user.log" "$TMP/bk/LEDGER.md"; then pass "S41: tick appends a task-completed entry with cmd, exit and evidence"; else fail "S41: LEDGER entry missing/incomplete"; fi
if grep -q "^updated: $(date -u +%Y-%m-%d)" "$TMP/bk/SPEC.md"; then pass "S41: tick bumps SPEC updated: to today"; else fail "S41: updated not bumped"; fi
run "$TMP/tick2.out" tick P1.3 --dir "$TMP/bk"; [ "$RC" -eq 1 ] && grep -q "no done event" "$TMP/tick2.out" && pass "S41: tick refuses a task with no done event" || fail "S41: tick without event accepted (rc=$RC)"
run "$TMP/led.out" ledger note test "typed timestamp" --ts 4102444800 --dir "$TMP/bk"; [ "$RC" -eq 1 ] && grep -q "FUTURE-TIMESTAMP" "$TMP/led.out" && pass "S41: ledger refuses a future timestamp" || fail "S41: future ledger ts accepted (rc=$RC)"
run "$TMP/led2.out" ledger note test "clock-read entry" --dir "$TMP/bk"; [ "$RC" -eq 0 ] && grep -q "note test" "$TMP/bk/LEDGER.md" && grep -qE "^### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}Z — note test" "$TMP/bk/LEDGER.md" && pass "S41: ledger appends a clock-stamped entry" || fail "S41: ledger append (rc=$RC)"
rm -rf "$TMP/sroot"; mkdir -p "$TMP/sroot/done"; cp -R "$TMP/bk" "$TMP/sroot/2026-09-06-spec-copy"; printf '<!-- x -->\n\n## Active\n\n- _(none)_\n\n## Done\n\n- _(none)_\n' >"$TMP/sroot/INDEX.md"
run "$TMP/si.out" sync-index --specs-root "$TMP/sroot"; [ "$RC" -eq 0 ] && grep -q "\[spec-copy\](2026-09-06-spec-copy/SPEC.md) — running — updated" "$TMP/sroot/INDEX.md" && pass "S41: sync-index rewrites INDEX from SPEC frontmatter" || fail "S41: sync-index (rc=$RC): $(grep -c . "$TMP/sroot/INDEX.md") lines"
# D43 hardening: a bare sync-index (no --specs-root) resolves <repo>/.claude/specs from the engine's
# own location, never dirname(cwd) — the old default wrote $HOME/INDEX.md from the repo root.
rm -f "$ROOT/../INDEX.md"
run "$TMP/sidef.out" sync-index
[ "$RC" -eq 0 ] && grep -q "$ROOT/.claude/specs/INDEX.md" "$TMP/sidef.out" && pass "S41: bare sync-index targets <repo>/.claude/specs" || fail "S41: bare sync-index target wrong (rc=$RC): $(cat "$TMP/sidef.out")"
if [ -e "$ROOT/../INDEX.md" ]; then fail "S41: bare sync-index wrote outside the repo (\$HOME/INDEX.md)"; rm -f "$ROOT/../INDEX.md"; else pass "S41: bare sync-index never writes outside the repo"; fi
run "$TMP/pc.out" phase-check 1 --dir "$TMP/bk"; grep -q "phase 1: 2/11" "$TMP/pc.out" && grep -q "validation:" "$TMP/pc.out" && pass "S41: phase-check reports done/total and the validation command" || fail "S41: phase-check output: $(head -1 "$TMP/pc.out")"

# --- S9 / S35 extractor + drift (P3.1a → P3.2 / P3.3) ---
run "$TMP/ex1.out" extract --root "$FIX/repo-clean"
if [ "$RC" -eq 0 ] && diff -q "$TMP/ex1.out" "$FIX/repo-clean/architecture.extracted.yaml" >/dev/null 2>&1; then pass "S9: extract on repo-clean equals the committed extracted manifest"; else fail "S9: extract repo-clean (rc=$RC)"; fi
run "$TMP/dr0.out" drift --root "$FIX/repo-clean" --dir "$FIX/repo-clean"; [ "$RC" -eq 0 ] && grep -q "0 violation" "$TMP/dr0.out" && pass "S9: drift on repo-clean is 0 == budget 0" || fail "S9: drift repo-clean (rc=$RC)"
run "$TMP/dr1.out" drift --root "$FIX/repo-coupled" --dir "$FIX/repo-coupled"; [ "$RC" -eq 1 ] && grep -q "ADAPTER_TO_ADAPTER internal/adapters/smtp/mail.go" "$TMP/dr1.out" && grep -q "DOMAIN_TO_ADAPTER internal/domain/user/user.go" "$TMP/dr1.out" && grep -q "2 violation" "$TMP/dr1.out" && pass "S9: drift names the adapter→adapter and domain→adapter imports with file paths" || fail "S9: drift repo-coupled (rc=$RC): $(head -3 "$TMP/dr1.out" | tr '\n' ' ')"
rm -rf "$TMP/rc2"; cp -R "$FIX/repo-coupled" "$TMP/rc2"; sed -i.bak 's/  budget: 0/  budget: 2/' "$TMP/rc2/architecture.yaml"
run "$TMP/dr2.out" drift --root "$TMP/rc2" --dir "$TMP/rc2"; [ "$RC" -eq 0 ] && pass "S27: drift with budget == measured passes (brownfield ratchet)" || fail "S27: brownfield budget (rc=$RC)"
sed -i.bak 's/  budget: 2/  budget: 3/' "$TMP/rc2/architecture.yaml"
run "$TMP/dr3.out" drift --root "$TMP/rc2" --dir "$TMP/rc2"; [ "$RC" -eq 1 ] && grep -q "unrecorded gain" "$TMP/dr3.out" && pass "S27: drift under budget fails (unrecorded gain)" || fail "S27: under-budget drift passed"
run "$TMP/py.out" drift --root "$FIX/repo-py-coupled" --dir "$FIX/repo-py-coupled"; [ "$RC" -eq 1 ] && grep -q "ADAPTER_TO_ADAPTER internal/adapters/smtp/__init__.py" "$TMP/py.out" && pass "S35: dotted Python imports resolve to repo paths" || fail "S35: python imports not resolved (rc=$RC)"
run "$TMP/un.out" drift --root "$FIX/repo-unresolved" --dir "$FIX/repo-unresolved"; grep -q "UNRESOLVED-IMPORT.*internal/adapters/nope" "$TMP/un.out" && [ "$RC" -eq 1 ] && pass "S35: an in-repo-looking import that resolves nowhere fails closed" || fail "S35: UNRESOLVED-IMPORT (rc=$RC)"
run "$TMP/ti.out" drift --root "$FIX/repo-test-reaches-infra" --dir "$FIX/repo-test-reaches-infra"; grep -q "TEST-REACHES-INFRA internal/domain/user/user_test.go" "$TMP/ti.out" && pass "S35: a domain test importing an adapter is flagged" || fail "S35: TEST-REACHES-INFRA missing"
run "$TMP/rem.out" drift --root "$FIX/repo-coupled" --dir "$FIX/repo-coupled"; grep -qE "→ (repoint|inject|extract|move)" "$TMP/rem.out" && pass "S40: each violation carries a remediation hint" || fail "S40: remediation hints missing"

# --- S9 divergence classes (P3.3 → P3.4) ---
run "$TMP/dl.out" drift --root "$FIX/repo-coupled" --dir "$FIX/repo-coupled"; grep -qE "ADAPTER_TO_ADAPTER internal/adapters/smtp/mail.go:[0-9]+ " "$TMP/dl.out" && grep -qE "DOMAIN_TO_ADAPTER internal/domain/user/user.go:[0-9]+ " "$TMP/dl.out" && pass "S9: violations carry file:line" || fail "S9: file:line missing: $(head -1 "$TMP/dl.out")"
# manifest-vs-tree divergence: the TREE stays pristine and consistent; only the manifest diverges.
rm -rf "$TMP/div"; cp -R "$FIX/repo-clean" "$TMP/div"
python3 - "$FIX/repo-clean/architecture.extracted.yaml" "$TMP/div/architecture.yaml" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
s = s.replace("ports:\n", "ports:\n  - name: phantom\n    direction: out\n    domain: user\n    path: internal/ports/phantom\n", 1)
s = re.sub(r"  - name: smtp\n    port: notification\n    path: internal/adapters/smtp\n", "", s)
open(sys.argv[2], "w").write(s)
PY
run "$TMP/div.out" drift --root "$TMP/div" --dir "$TMP/div"
[ "$RC" -eq 0 ] && grep -q "0 violation" "$TMP/div.out" && pass "S9: divergence findings do not move the budget count" || fail "S9: divergence changed exit/count (rc=$RC): $(tail -3 "$TMP/div.out" | tr '\n' ' ')"
grep -q "PORT-WITHOUT-ADAPTER phantom" "$TMP/div.out" && pass "S9: a declared port with no adapter in the tree is named" || fail "S9: PORT-WITHOUT-ADAPTER missing"
grep -q "ADAPTER-NOT-IN-MANIFEST internal/adapters/smtp" "$TMP/div.out" && pass "S9: an adapter in the tree absent from the manifest is named" || fail "S9: ADAPTER-NOT-IN-MANIFEST missing"
[ ! -e "$FIX/repo-coupled/graph/events.jsonl" ] && pass "S9: drift without --record wrote no event into the fixture" || fail "S9: drift polluted the fixture with graph/events.jsonl"
rm -rf "$TMP/rec"; cp -R "$FIX/repo-coupled" "$TMP/rec"; run "$TMP/rec.out" drift --root "$TMP/rec" --dir "$TMP/rec" --record
[ "$RC" -eq 1 ] && grep -q '"to": "measured"' "$TMP/rec/graph/events.jsonl" 2>/dev/null && grep -q '"exit": 2' "$TMP/rec/graph/events.jsonl" && pass "S9: drift --record appends a measured event carrying the count" || fail "S9: --record did not append measured (rc=$RC)"
grep -q "re-measur" "$FIX/repo-clean/architecture.extracted.yaml" && grep -q "^# " "$FIX/repo-clean/architecture.extracted.yaml" && pass "S9: extracted manifest header documents budget re-measurement on conflict" || fail "S9: manifest header lacks the re-measure note"

# --- S40 audit (P3.5a → P3.6) ---
# `audit` does not exist yet (P3.6 builds it). These assertions pin the S40 scenario RED so the
# implementing session has a fixed target. `lint --dir <out>` needs a ROADMAP.md/ROADMAP.sample.md
# alongside architecture.yaml (cli.py ROADMAP_CANDIDATES) — audit's own output is only
# architecture.yaml + refactor-plan.md, so we copy refactor-plan.md to ROADMAP.sample.md inside the
# out dir before linting it, rather than assume audit itself writes that filename.
s40_before=$(find "$FIX/repo-coupled" -type f | sort | xargs md5 -q 2>/dev/null)
run "$TMP/aud-c.out" audit --root "$FIX/repo-coupled" --out "$TMP/audit-c"
[ "$RC" -eq 1 ] && pass "S40: audit on repo-coupled exits 1" || fail "S40: audit repo-coupled expected exit 1, got rc=$RC"
grep -qE "→ (repoint|inject|extract|move)" "$TMP/aud-c.out" && grep -q "ADAPTER_TO_ADAPTER" "$TMP/aud-c.out" && grep -q "DOMAIN_TO_ADAPTER" "$TMP/aud-c.out" && pass "S40: audit names each violation with its remediation class and code" || fail "S40: audit output missing remediation class or violation code"
[ -f "$TMP/audit-c/architecture.yaml" ] && grep -q "budget: 2" "$TMP/audit-c/architecture.yaml" 2>/dev/null && pass "S40: audit writes architecture.yaml with budget == measured count (2)" || fail "S40: audit-c/architecture.yaml missing or budget != 2"
cp "$TMP/audit-c/refactor-plan.md" "$TMP/audit-c/ROADMAP.sample.md" 2>/dev/null
run "$TMP/aud-c-lint.out" lint --dir "$TMP/audit-c"
[ -f "$TMP/audit-c/refactor-plan.md" ] && [ "$RC" -eq 0 ] && pass "S40: audit-c/refactor-plan.md exists and lints clean" || fail "S40: refactor-plan.md missing or fails lint (rc=$RC)"
if [ -f "$TMP/audit-c/refactor-plan.md" ]; then
  awk '
    /^ {6}node: test\// { seen = 1 }
    /^ {6}node: (adapter|domain)\// { n++; if (!seen) bad = 1 }
    END { if (n == 0) { print "no-behaviour-nodes"; exit 2 } exit (bad ? 1 : 0) }
  ' "$TMP/audit-c/refactor-plan.md"
  s40_tf_rc=$?
else
  s40_tf_rc=2
fi
[ "$s40_tf_rc" -eq 0 ] && pass "S40: refactor-plan.md orders a test/* node before every adapter/domain node" || fail "S40: test-first ordering violated or no behaviour nodes found (rc=$s40_tf_rc)"
run "$TMP/aud-0.out" audit --root "$FIX/repo-clean" --out "$TMP/audit-0"
if [ -f "$TMP/audit-0/refactor-plan.md" ]; then
  s40_gate_count=$(grep -Ec '^ {6}node: ' "$TMP/audit-0/refactor-plan.md")
  s40_gate_line=$(grep -E '^ {6}node: ' "$TMP/audit-0/refactor-plan.md")
else
  s40_gate_count=0
  s40_gate_line=""
fi
if [ "$RC" -eq 0 ] && grep -q "budget: 0" "$TMP/audit-0/architecture.yaml" 2>/dev/null && [ "$s40_gate_count" = "1" ] && printf '%s' "$s40_gate_line" | grep -q "kind: gate"; then
  pass "S40: audit on repo-clean exits 0 with budget 0 and a gate-only plan"
else
  fail "S40: audit repo-clean (rc=$RC, gate_count=$s40_gate_count)"
fi
s40_after=$(find "$FIX/repo-coupled" -type f | sort | xargs md5 -q 2>/dev/null)
[ -n "$s40_before" ] && [ "$s40_before" = "$s40_after" ] && pass "S40: audit never writes into the audited tree (repo-coupled unchanged)" || fail "S40: repo-coupled fixture tree changed by audit"

# --- S42 rotation cost telemetry (P2.13a → P2.13) ---
# retro sums the result-JSON that `claude -p --output-format json` writes into each rotation log,
# and reports an unreadable (truncated) log without counting it. Deterministic, no model call.
run "$TMP/rc.out" retro --dir "$FIX/rotation-cost"
[ "$RC" -eq 0 ] && grep -qE "rotations +: 2" "$TMP/rc.out" && grep -q "0.7540" "$TMP/rc.out" && grep -q "in 62" "$TMP/rc.out" && grep -q "out 8130" "$TMP/rc.out" && grep -q "turns 12" "$TMP/rc.out" && pass "S42: retro sums cost/tokens/turns across rotation logs" || fail "S42: retro rotation summary wrong (rc=$RC): $(grep -i rotation "$TMP/rc.out" | tr '\n' ' ')"
grep -q "ROTATION-LOG-UNREADABLE" "$TMP/rc.out" && grep -q "20260906T030000Z.log" "$TMP/rc.out" && pass "S42: retro names the truncated log and does not count it" || fail "S42: unreadable log not reported"
run "$TMP/rcdry.out" retro --dir "$FIX/spec-copy"; [ "$RC" -eq 0 ] && grep -qE "rotations +: 0" "$TMP/rcdry.out" && pass "S42: retro with no rotation logs reports 0, exit 0" || fail "S42: retro no-logs (rc=$RC)"
if grep -q -- "--output-format json" "$TMP/rot1.out"; then pass "S42: rotate dry-run launches the successor with --output-format json"; else fail "S42: rotate command lacks --output-format json"; fi


# --- S43 health / watchdog (P2.14a → P2.14) ---
# progress prints a machine-readable HEALTH line; a deterministic watchdog acts on it (no model call).
run "$TMP/hrun.out" progress --dir "$FIX/spec-copy"; grep -qE "^HEALTH (running|stalled|rate-limited|done|blocked) " "$TMP/hrun.out" && pass "S43: progress prints a HEALTH <state> line" || fail "S43: no HEALTH line ($(head -3 "$TMP/hrun.out" | tr '\n' ' '))"
run "$TMP/hst.out" progress --dir "$FIX/health-stalled"; grep -qE "^HEALTH stalled " "$TMP/hst.out" && pass "S43: an old LEDGER tail with no live successor reads stalled" || fail "S43: stalled not detected ($(grep HEALTH "$TMP/hst.out"))"
run "$TMP/hrl.out" progress --dir "$FIX/health-rate-limited"; grep -qE "^HEALTH rate-limited " "$TMP/hrl.out" && pass "S43: a usage-limit rotation log reads rate-limited" || fail "S43: rate-limited not detected ($(grep HEALTH "$TMP/hrl.out"))"
run "$TMP/hdn.out" progress --dir "$FIX/health-done"; grep -qE "^HEALTH done " "$TMP/hdn.out" && pass "S43: a fully-ticked ROADMAP reads done" || fail "S43: done not detected ($(grep HEALTH "$TMP/hdn.out"))"
SUP="$ROOT/.claude/scripts/claudart-supervise.sh"
if [ -x "$SUP" ]; then
  run2() { bash "$SUP" "$@" >"$TMP/sup.out" 2>&1; SRC=$?; }
  CLAUDART_SPECS_ROOT="$FIX" run2 --dry-run health-stalled
  [ "$SRC" -eq 0 ] && grep -qE "health: stalled" "$TMP/sup.out" && grep -qE "action: relaunch" "$TMP/sup.out" && pass "S43: supervise --dry-run on a stalled spec would relaunch" || fail "S43: supervise stalled decision ($SRC): $(cat "$TMP/sup.out")"
  CLAUDART_SPECS_ROOT="$FIX" run2 --dry-run health-rate-limited
  grep -qE "action: back-off" "$TMP/sup.out" && pass "S43: supervise --dry-run on a rate-limited spec would back off" || fail "S43: supervise rate-limit decision: $(cat "$TMP/sup.out")"
  CLAUDART_SPECS_ROOT="$FIX" run2 --dry-run health-done
  grep -qE "action: exit: done" "$TMP/sup.out" && pass "S43: supervise --dry-run on a done spec exits" || fail "S43: supervise done decision: $(cat "$TMP/sup.out")"
  grep -q "claude" "$TMP/sup.out"; if grep -qE "dangerously-skip-permissions" "$TMP/sup.out"; then fail "S43: supervise leaks a permission bypass"; else pass "S43: supervise never adds a permission bypass"; fi
else
  fail "S43: supervise stalled decision (script missing $SUP)"; fail "S43: supervise rate-limit decision"; fail "S43: supervise done decision"; fail "S43: supervise no bypass"
fi


printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
