#!/usr/bin/env bash
# tests/law/mutate.sh — persisted manual mutation runner for the law engine (evidence-gauntlet.md
# §5). No mutation tool exists for this repo's plain-stdlib Python, so the procedure is scripted
# rather than hand-driven: hand-editing invites restore mistakes, and the gauntlet requires the
# mutants to be re-runnable.
#
#   usage: bash tests/law/mutate.sh <group>          groups: core | fold
#
# For every module in the group it: saves an explicit copy, applies 5 named mutants one at a time,
# runs the unit suite after each, restores from the saved copy, and verifies the restore by
# `diff` against that copy — never with `git diff` against HEAD, because the implementation under
# mutation is normally uncommitted, so a HEAD diff shows in-progress work and could not tell a bad
# restore from it (verification-mechanics.md §5).
#
# Mutant palette: flipped-comparison · off-by-one · deleted-branch · swapped-and-or ·
# constant-return. Two substitutions, because the construct does not exist in that module:
#   * schema.py has no numeric bound, so its off-by-one is on a regex quantifier
#     (`\d{2}` seconds -> `\d{1}`), which is the same class of bug.
#   * budget.py contains no boolean connective, so `swapped-operands` (today-expiry reversed)
#     stands in for swapped-and-or. It is a real, plausible bug of the same "swapped" family.
#
# Group `fold` covers tally.py / agreement.py / render.py, same palette, one substitution:
#   * render.py has no numeric bound and no boolean connective. Its off-by-one drops one element
#     from the fixed line list (`["", INTRO, ""]` -> `["", INTRO]`) — an off-by-one on the emitted
#     line count — and `swapped-operands` (the marking and the trigger swapped in the bullet's
#     format arguments) stands in for swapped-and-or, the same family as budget.py's.
#
# KNOWN COVERAGE GAP, NOT a script defect: agreement.py/flipped-comparison SURVIVES. Flipping the
# pair-agreement test (`==` -> `!=`) is undetectable because the frozen D9 fixture in
# tests/law/unit/test_fold.py is symmetric — 2 of its 4 pairs agree and 2 disagree, so counting
# agreements and counting disagreements both yield (2, 4). Nothing pins the DIRECTION of the
# agreement comparison. An asymmetric fixture (e.g. 3 agreeing of 4 pairs) would kill it. The
# mutant is kept because it is a real bug and its survival is the information; do not delete it,
# and do not "fix" it by choosing a weaker mutant.
#
# Fail-closed contract (evidence-gauntlet.md §6): `set -euo pipefail`; no `|| true`; no
# `2>/dev/null`; every exit status is captured on the command's own line and never read through a
# pipe. A mutant whose anchor is missing or ambiguous is a hard error (exit 2), never a silent
# pass. The script exits nonzero if ANY mutant survives or ANY restore fails to verify — a runner
# that prints a score and exits 0 regardless is a report, not a gate.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export PYTHONDONTWRITEBYTECODE=1

usage() { printf 'usage: bash tests/law/mutate.sh <group>   (groups: core | fold)\n' >&2; }

# =====================================================================================================
# Mutant specs. One line per mutant: <module>@@<name>@@<exact source line>@@<replacement line>.
# The anchor must occur EXACTLY once in the module, or the run aborts.
# =====================================================================================================
core_mutants() {
  cat <<'SPEC'
schema.py@@flipped-comparison@@        if field not in record:@@        if field in record:
schema.py@@off-by-one-seconds@@INSTANT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")@@INSTANT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{1}Z$")
schema.py@@deleted-branch@@    if text == "judgement":@@    if False:
schema.py@@swapped-and-or@@    if separator and prefix in ENFORCER_PREFIXES:@@    if separator or prefix in ENFORCER_PREFIXES:
schema.py@@constant-return@@    return findings@@    return []
overlap.py@@flipped-comparison@@            if _level_of(records, target) != "law":@@            if _level_of(records, target) == "law":
overlap.py@@off-by-one-pair-index@@        for second in law_ids[index + 1:]:@@        for second in law_ids[index:]:
overlap.py@@deleted-branch@@            if _declares(records[first], second) or _declares(records[second], first):@@            if False:
overlap.py@@swapped-and-or@@    return _shares_tag(first, second) and _paths_can_overlap(first, second)@@    return _shares_tag(first, second) or _paths_can_overlap(first, second)
overlap.py@@constant-return@@    return _walk_segments(first.split("/"), 0, second.split("/"), 0)@@    return True
retirement.py@@flipped-comparison@@    return today > _effective_date(record)@@    return today < _effective_date(record)
retirement.py@@off-by-one-grace@@    if grace is not None and (today - expiry).days > grace:@@    if grace is not None and (today - expiry).days > grace + 1:
retirement.py@@deleted-branch@@    if explicit is not None:@@    if False:
retirement.py@@swapped-and-or@@    if grace is not None and (today - expiry).days > grace:@@    if grace is not None or (today - expiry).days > grace:
retirement.py@@constant-return@@        return (True, MARKING % expiry.isoformat())@@        return (False, None)
budget.py@@flipped-comparison@@        if (today - expiry).days > max_age:@@        if (today - expiry).days < max_age:
budget.py@@off-by-one-cap@@    if existing_count_this_month + 1 > cap:@@    if existing_count_this_month > cap:
budget.py@@deleted-branch@@    items += [(item["id"], item["stale_after"]) for item in expired_laws]@@    items += []
budget.py@@swapped-operands@@        if (today - expiry).days > max_age:@@        if (expiry - today).days > max_age:
budget.py@@constant-return@@            return True@@            return False
SPEC
}

fold_mutants() {
  cat <<'SPEC'
tally.py@@flipped-comparison@@        if _age_days(proposal, today) > expires_days@@        if _age_days(proposal, today) < expires_days
tally.py@@off-by-one-cap@@        if reason is None and granted + 1 > cap:@@        if reason is None and granted > cap:
tally.py@@deleted-branch@@        if reason is None and not entry["deterministic"]:@@        if False:
tally.py@@swapped-and-or@@        if reason is None and granted + 1 > cap:@@        if reason is None or granted + 1 > cap:
tally.py@@constant-return@@    return minutes / 60.0@@    return 0.0
agreement.py@@flipped-comparison@@        if passes[FIRST_PASS] == passes[SECOND_PASS]:@@        if passes[FIRST_PASS] != passes[SECOND_PASS]:
agreement.py@@off-by-one-pass@@SECOND_PASS = 2@@SECOND_PASS = 3
agreement.py@@deleted-branch@@        if FIRST_PASS not in passes or SECOND_PASS not in passes:@@        if False:
agreement.py@@swapped-and-or@@        if FIRST_PASS not in passes or SECOND_PASS not in passes:@@        if FIRST_PASS not in passes and SECOND_PASS not in passes:
agreement.py@@constant-return@@    return (agree, pairs)@@    return (0, 0)
render.py@@flipped-comparison@@    ids = [law_id for law_id in laws if laws[law_id].get("load") == load]@@    ids = [law_id for law_id in laws if laws[law_id].get("load") != load]
render.py@@off-by-one-lines@@    lines += ["", INTRO, ""]@@    lines += ["", INTRO]
render.py@@deleted-branch@@    if should_mark:@@    if False:
render.py@@swapped-operands@@    return TRIGGER_LINE % (law_id, mark, record["trigger"], record["digest"])@@    return TRIGGER_LINE % (law_id, record["trigger"], mark, record["digest"])
render.py@@constant-return@@    return "\n".join(lines)@@    return ""
SPEC
}

# =====================================================================================================
# Group registry — adding a group is one line here plus its <group>_mutants function above.
# =====================================================================================================
GROUP="${1:-}"
if [ -z "$GROUP" ]; then usage; exit 2; fi
case "$GROUP" in
  core) SRC_DIR="$ROOT/.claude/scripts/law/core"; SPEC_FN=core_mutants; PATTERN='test_core.py' ;;
  fold) SRC_DIR="$ROOT/.claude/scripts/law/core"; SPEC_FN=fold_mutants; PATTERN='test_fold.py' ;;
  *) printf 'mutate.sh: unknown group %s\n' "$GROUP" >&2; usage; exit 2 ;;
esac

if [ ! -d "$SRC_DIR" ]; then
  printf 'mutate.sh: source dir not found: %s\n' "$SRC_DIR" >&2
  exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/law-mutate.XXXXXX")
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/saved"

# Stale bytecode of the package under mutation would let a mutant go unexecuted.
find "$ROOT/.claude/scripts/law" -type d -name __pycache__ -prune -exec rm -rf {} +

cat >"$TMP/apply.py" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as fh:
    src = fh.read()
count = src.count(old)
if count != 1:
    sys.stderr.write("anchor occurs %d times (expected 1) in %s: %r\n" % (count, path, old))
    sys.exit(2)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(src.replace(old, new))
PY

run_suite() {
  local log="$1" rc=0
  python3 -m unittest discover -s "$ROOT/tests/law/unit" -p "$PATTERN" >"$log" 2>&1 || rc=$?
  return "$rc"
}

SPEC_FILE="$TMP/mutants.spec"
"$SPEC_FN" >"$SPEC_FILE"

# --- baseline: a red suite would make every mutant look "killed" -------------------------------------
baseline_rc=0
run_suite "$TMP/baseline.log" || baseline_rc=$?
if [ "$baseline_rc" -ne 0 ]; then
  printf 'mutate.sh: baseline suite is RED (rc=%d) — a mutation score would be meaningless\n' "$baseline_rc" >&2
  sed 's/^/  /' "$TMP/baseline.log" >&2
  exit 2
fi
printf 'baseline: unit suite green before any mutant (%s)\n' "$(tail -n 3 "$TMP/baseline.log" | head -n 1)"

# --- explicit saved copy of every module, taken before the first mutant -------------------------------
MODULE_LIST="$TMP/modules.txt"
awk -F'@@' '{print $1}' "$SPEC_FILE" | sort -u >"$MODULE_LIST"
while IFS= read -r module; do
  if [ ! -f "$SRC_DIR/$module" ]; then
    printf 'mutate.sh: module not found: %s\n' "$SRC_DIR/$module" >&2
    exit 2
  fi
  cp "$SRC_DIR/$module" "$TMP/saved/$module"
  printf 'saved: %s -> %s\n' "$module" "$TMP/saved/$module"
done <"$MODULE_LIST"

# --- one mutant at a time ------------------------------------------------------------------------------
total=0
killed=0
survived=0
restore_failures=0

while IFS= read -r line; do
  [ -n "$line" ] || continue
  module="${line%%@@*}"; rest="${line#*@@}"
  name="${rest%%@@*}"; rest="${rest#*@@}"
  old="${rest%%@@*}"; new="${rest#*@@}"
  target="$SRC_DIR/$module"
  total=$((total + 1))

  apply_rc=0
  python3 "$TMP/apply.py" "$target" "$old" "$new" || apply_rc=$?
  if [ "$apply_rc" -ne 0 ]; then
    printf 'mutate.sh: mutant %s/%s could not be applied — source drifted from its anchor\n' "$module" "$name" >&2
    cp "$TMP/saved/$module" "$target"
    exit 2
  fi

  suite_rc=0
  run_suite "$TMP/mutant.log" || suite_rc=$?
  if [ "$suite_rc" -ne 0 ]; then
    verdict="killed"
    killed=$((killed + 1))
  else
    verdict="SURVIVED"
    survived=$((survived + 1))
  fi

  cp "$TMP/saved/$module" "$target"
  diff_rc=0
  diff -u "$TMP/saved/$module" "$target" >"$TMP/restore.diff" || diff_rc=$?
  if [ "$diff_rc" -ne 0 ]; then
    printf 'mutate.sh: restore of %s NOT verified against its saved copy (%s):\n' "$module" "$name" >&2
    sed 's/^/  /' "$TMP/restore.diff" >&2
    restore_failures=$((restore_failures + 1))
  fi

  printf '%-9s %-14s %-22s suite rc=%d\n' "$verdict" "$module" "$name" "$suite_rc"
done <"$SPEC_FILE"

# --- final restore verification, module by module ------------------------------------------------------
while IFS= read -r module; do
  final_rc=0
  diff -u "$TMP/saved/$module" "$SRC_DIR/$module" >"$TMP/final.diff" || final_rc=$?
  if [ "$final_rc" -ne 0 ]; then
    printf 'mutate.sh: %s does not match its saved copy after the run:\n' "$module" >&2
    sed 's/^/  /' "$TMP/final.diff" >&2
    restore_failures=$((restore_failures + 1))
  else
    printf 'restore verified: %s identical to its saved copy\n' "$module"
  fi
done <"$MODULE_LIST"

printf 'mutation: %d/%d\n' "$killed" "$total"

if [ "$survived" -ne 0 ] || [ "$restore_failures" -ne 0 ]; then
  printf 'mutate.sh: %d mutant(s) survived, %d restore(s) unverified\n' "$survived" "$restore_failures" >&2
  exit 1
fi
exit 0
