#!/usr/bin/env bash
# .claude/scripts/constitution-check.sh — legislation for the Engineering Constitution and the
# graph rules. A rule with no enforcement is meaningless: this script fails `npm run check` when
# the harness's own rules drift. It ships to every project, so it stays generic and fail-closed.
#
# Fail-closed contract (evidence-gauntlet.md §6, verification-mechanics.md §5):
#   - `set -u`; no `|| true`; no `2>/dev/null` swallowing.
#   - A must-find-nothing grep treats rc 1 (clean) as the ONLY pass; rc 0 (found) fails the check
#     and rc >= 2 (the check itself broke) also fails the check.
#   - Any check whose machinery breaks (missing python3, unreadable input) FAILS, never passes.
#
# Checks (exit nonzero if ANY fails, naming which):
#   1. roadmap node/verify   — every `- [ ] P<n>.<n>` / `- [x]` task line in $CC_ROADMAP carries an
#                              inline `(verify: …)` and a following `node:` metadata line. Runs only
#                              when CC_ROADMAP names a file; otherwise skips with a printed note
#                              (npm check has no active spec).
#   2. no verbatim duplication — no rule file under $CC_RULES_DIR contains a verbatim run of >= 12
#                              consecutive words (WORD_RUN below) copied from $CC_CONSTITUTION's
#                              PROSE BODY, the constitution file itself excluded. Shingle/n-gram
#                              scan. The source corpus is the constitution's body only: its own YAML
#                              frontmatter is machine-generated law-record metadata (level/authority/
#                              status/since/stale_after/verified/enforcer per .claude/scripts/law/
#                              SCHEMA.md), and every law record repeats those field names, dates and
#                              enforcer paths by construction — matching them is a false positive,
#                              not plagiarism. Each RULE file is still scanned in full, frontmatter
#                              included, so a rule that copies constitution prose into a description,
#                              trigger or digest is still caught.
#   3. auto-import budget     — the SUM of line counts of the `@.claude/rules/<x>.md` files imported
#                              by $CC_CLAUDE_MD is <= $CC_IMPORT_BUDGET, and each imported file is
#                              <= 150 lines.
#   4. core purity (D15)      — the exact AST walk from tests/graph/run.sh ("core purity (D15)") over
#                              $CC_CORE_DIR: no banned module/import/call, no graph.adapters import.
#   5. rule->enforcer map(D29)— in $CC_TAGGED_RULES every MUST rule bullet carries `⟦enforcer: <ID>⟧`
#                              or `⟦judgement…⟧`, and every <ID> appears in the first column of
#                              `claudart-graph.sh rules`.
#
# MEASURED BUDGET (hardcoded so growth trips the check — re-measure if imports change):
#   Re-measured 2026-09-06 after the law-record frontmatter migration: $CC_CLAUDE_MD imports
#   .claude/rules/constitution.md (59 lines) + .claude/rules/ai-behavior.md (83 lines) = 142 lines.
#   Both limits are unchanged — 142 <= 200 and 83 <= the per-file cap of 150 — so neither was
#   raised; ai-behavior.md at 83 is the current high-water mark.

set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# --- word-run length for the duplication shingle scan (check 2) -------------------------------------
WORD_RUN=12

# --- configuration (env overrides; defaults resolve under the repo root) ---------------------------
CC_ROADMAP="${CC_ROADMAP:-}"
CC_RULES_DIR="${CC_RULES_DIR:-$ROOT/.claude/rules}"
CC_CONSTITUTION="${CC_CONSTITUTION:-$ROOT/.claude/rules/constitution.md}"
CC_CLAUDE_MD="${CC_CLAUDE_MD:-$ROOT/.claude/CLAUDE.md}"
# Imported paths in CLAUDE.md are project-root-relative (`.claude/rules/x.md`); resolve them against
# the dir two levels above CLAUDE.md (its `.claude/` parent), overridable for fixtures.
CC_IMPORT_BASE="${CC_IMPORT_BASE:-$(cd "$(dirname "$CC_CLAUDE_MD")/.." && pwd 2>/dev/null || echo "$ROOT")}"
CC_IMPORT_BUDGET="${CC_IMPORT_BUDGET:-200}"
CC_CORE_DIR="${CC_CORE_DIR:-$ROOT/.claude/scripts/graph/core}"
CC_TAGGED_RULES="${CC_TAGGED_RULES:-$ROOT/.claude/rules/graph-development.md $ROOT/.claude/rules/constitution.md}"
CC_GRAPH="${CC_GRAPH:-$ROOT/.claude/scripts/claudart-graph.sh}"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/constitution-check.XXXXXX")
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

FAILURES=0
fail() { printf 'FAIL [%s] %s\n' "$1" "$2" >&2; FAILURES=$((FAILURES + 1)); }
ok() { printf 'ok   [%s] %s\n' "$1" "$2"; }

PY=python3
if ! command -v "$PY" >/dev/null 2>&1; then
  printf 'constitution-check: python3 is required\n' >&2
  exit 2
fi

# =====================================================================================================
# Check 1 — roadmap node/verify
# =====================================================================================================
check_roadmap() {
  if [ -z "$CC_ROADMAP" ] || [ ! -f "$CC_ROADMAP" ]; then
    printf 'SKIP [roadmap] CC_ROADMAP not set to a file; no active spec to check\n'
    return 0
  fi
  local out="$TMP/roadmap.out" rc
  "$PY" - "$CC_ROADMAP" >"$out" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
task = re.compile(r"^\s*-\s\[[ xX]\]\s+P\d+\.\d+")
bad = []
for i, ln in enumerate(lines):
    if not task.match(ln):
        continue
    tid = ln.strip()[:60]
    has_verify = "(verify:" in ln
    # metadata block: following indented, non-blank lines that do not open a new checkbox bullet
    has_node = False
    j = i + 1
    while j < len(lines):
        nxt = lines[j]
        if nxt.strip() == "":
            break
        if not (nxt[:1].isspace()):
            break
        if re.match(r"^\s*-\s\[[ xX]\]", nxt):
            break
        if re.search(r"\bnode:", nxt):
            has_node = True
        j += 1
    if not has_verify:
        bad.append("%s -> missing (verify: …)" % tid)
    if not has_node:
        bad.append("%s -> missing node: metadata" % tid)
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
  rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "roadmap" "every task line carries (verify: …) and a node: line ($CC_ROADMAP)"
  else
    fail "roadmap" "task lines missing verify/node in $CC_ROADMAP:"
    sed 's/^/       /' "$out" >&2
  fi
}

# =====================================================================================================
# Check 2 — no verbatim duplication (>= WORD_RUN consecutive words copied from the constitution)
# =====================================================================================================
check_duplication() {
  if [ ! -f "$CC_CONSTITUTION" ]; then
    fail "duplication" "constitution not found: $CC_CONSTITUTION"
    return
  fi
  if [ ! -d "$CC_RULES_DIR" ]; then
    fail "duplication" "rules dir not found: $CC_RULES_DIR"
    return
  fi
  local out="$TMP/dup.out" rc
  "$PY" - "$CC_CONSTITUTION" "$CC_RULES_DIR" "$WORD_RUN" >"$out" <<'PY'
import os, re, sys
constitution, rules_dir, run = sys.argv[1], sys.argv[2], int(sys.argv[3])
word = re.compile(r"[A-Za-z0-9']+")

def shingles(text):
    words = [w.lower() for w in word.findall(text)]
    return {tuple(words[i:i + run]): i for i in range(0, len(words) - run + 1)}, words

const_real = os.path.realpath(constitution)
def body(text):
    """The Markdown body, with any leading `---` YAML frontmatter block removed."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return text
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            return "\n".join(lines[idx + 1:])
    return text

const_text = body(open(constitution, encoding="utf-8").read())
const_grams, _ = shingles(const_text)
const_set = set(const_grams)

findings = []
for dirpath, _, files in os.walk(rules_dir):
    for f in sorted(files):
        if not f.endswith(".md"):
            continue
        p = os.path.join(dirpath, f)
        if os.path.realpath(p) == const_real:
            continue
        grams, _ = shingles(open(p, encoding="utf-8").read())
        hit = next((g for g in grams if g in const_set), None)
        if hit is not None:
            findings.append("%s copies %d+ words: \"%s …\"" % (p, run, " ".join(hit)))

for x in findings:
    print(x)
sys.exit(1 if findings else 0)
PY
  rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "duplication" "no rule file copies >= $WORD_RUN consecutive words from the constitution"
  else
    fail "duplication" "verbatim runs of >= $WORD_RUN words copied from the constitution:"
    sed 's/^/       /' "$out" >&2
  fi
}

# =====================================================================================================
# Check 3 — auto-import budget
# =====================================================================================================
check_import_budget() {
  if [ ! -f "$CC_CLAUDE_MD" ]; then
    fail "import-budget" "CLAUDE.md not found: $CC_CLAUDE_MD"
    return
  fi
  local imports total=0 rel abs n over_file=0 missing=0
  imports=$(grep -oE '@\.claude/rules/[A-Za-z0-9_-]+\.md' "$CC_CLAUDE_MD" | sort -u)
  if [ -z "$imports" ]; then
    ok "import-budget" "no @.claude/rules imports in $CC_CLAUDE_MD (sum 0 <= $CC_IMPORT_BUDGET)"
    return
  fi
  local detail="$TMP/imports.txt"
  : >"$detail"
  local i
  for i in $imports; do
    rel="${i#@}"
    abs="$CC_IMPORT_BASE/$rel"
    if [ ! -f "$abs" ]; then
      fail "import-budget" "imported file not found: $rel (resolved $abs)"
      missing=1
      continue
    fi
    n=$(wc -l <"$abs")
    n=$((n + 0))
    printf '  %s: %d lines\n' "$rel" "$n" >>"$detail"
    total=$((total + n))
    if [ "$n" -gt 150 ]; then
      fail "import-budget" "$rel is $n lines (> 150 per-file cap)"
      over_file=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    return
  fi
  if [ "$total" -gt "$CC_IMPORT_BUDGET" ]; then
    fail "import-budget" "imported lines total $total > budget $CC_IMPORT_BUDGET"
    sed 's/^/     /' "$detail" >&2
  elif [ "$over_file" -eq 0 ]; then
    ok "import-budget" "imported lines total $total <= budget $CC_IMPORT_BUDGET, each file <= 150"
  fi
}

# =====================================================================================================
# Check 4 — core purity (D15). AST walk copied verbatim from tests/graph/run.sh, "core purity (D15)".
# =====================================================================================================
purity() {
  # $1 = directory to walk. Prints violations; exits 1 if any.
  "$PY" - "$1" <<'PY'
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
check_core_purity() {
  if [ ! -d "$CC_CORE_DIR" ]; then
    fail "core-purity" "core dir not found: $CC_CORE_DIR"
    return
  fi
  local out="$TMP/purity.out" rc
  purity "$CC_CORE_DIR" >"$out"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "core-purity" "no I/O, no banned module/call, no adapter import under $CC_CORE_DIR"
  else
    fail "core-purity" "purity violated under $CC_CORE_DIR:"
    sed 's/^/       /' "$out" >&2
  fi
}

# =====================================================================================================
# Check 5 — rule->enforcer map (D29)
# =====================================================================================================
# python for check 5: argv[1]=registry file, argv[2:]=tagged rule files
cat >"$TMP/map.py" <<'PY'
import re, sys
reg_file = sys.argv[1]
rule_files = sys.argv[2:]

# enforcer registry: first whitespace-delimited token of each line, header "ENFORCER" ignored
registry = set()
for ln in open(reg_file, encoding="utf-8").read().splitlines():
    ln = ln.strip()
    if not ln:
        continue
    tok = ln.split()[0]
    if tok == "ENFORCER":
        continue
    registry.add(tok)

id_re = re.compile(r"[A-Z][A-Z0-9_-]+")
bullet_must = re.compile(r"^\s*-\s.*\bMUST\b")
enforcer_tag = re.compile(r"⟦enforcer:([^⟧]*)⟧")

findings = []
for path in rule_files:
    for i, ln in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
        if bullet_must.match(ln):
            if ("⟦enforcer:" not in ln) and ("⟦judgement" not in ln):
                findings.append("%s:%d untagged MUST clause: %s" % (path, i, ln.strip()[:70]))
        for m in enforcer_tag.finditer(ln):
            for eid in id_re.findall(m.group(1)):
                if eid not in registry:
                    findings.append("%s:%d unknown enforcer ID: %s" % (path, i, eid))

for x in findings:
    print(x)
sys.exit(1 if findings else 0)
PY

check_enforcer_map() {
  local reg="$TMP/registry.txt" rc out="$TMP/map.out"
  if [ ! -x "$CC_GRAPH" ] && [ ! -f "$CC_GRAPH" ]; then
    fail "enforcer-map" "graph engine not found: $CC_GRAPH"
    return
  fi
  bash "$CC_GRAPH" rules >"$reg"
  rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$reg" ]; then
    fail "enforcer-map" "'claudart-graph rules' failed (rc=$rc) or produced no registry"
    return
  fi
  "$PY" "$TMP/map.py" "$reg" $CC_TAGGED_RULES >"$out"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "enforcer-map" "every MUST bullet is tagged and every enforcer ID is registered"
  else
    fail "enforcer-map" "untagged MUST clause(s) or unknown enforcer ID(s):"
    sed 's/^/       /' "$out" >&2
  fi
}

# --- run every check --------------------------------------------------------------------------------
check_roadmap
check_duplication
check_import_budget
check_core_purity
check_enforcer_map

if [ "$FAILURES" -ne 0 ]; then
  printf '\nconstitution-check: %d check(s) FAILED\n' "$FAILURES" >&2
  exit 1
fi
printf '\nconstitution-check: all checks passed\n'
exit 0
