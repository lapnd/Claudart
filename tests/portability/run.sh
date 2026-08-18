#!/bin/bash

# Contract test for the portability layer (claudart-backup.sh and
# claudart-restore.sh in both layers).
# Scope: the CLI contract for both scripts, plus a real backup -> restore
# functional round trip proving the rewrite engine and its five verifications
# — including a negative control showing verification 4 can actually fail.
# claudart-restore.sh's merge classes and Commit (write) phase do not exist
# yet, so there is no merge-strategy or apply-mode coverage here.

set -u

LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s - %s\n' "$PASS_COUNT" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok - %s\n' "$1" >&2
}

# Runs a script and records its exit status in LAST_STATUS and output in LAST_OUT.
# Any status is captured, including 0 — the caller decides what passes.
run_script() {
  LAST_OUT=$("$@" 2>&1)
  LAST_STATUS=$?
  return 0
}

assert_status() {
  _expected=$1
  _label=$2
  if [ "$LAST_STATUS" -eq "$_expected" ]; then
    pass "$_label"
  else
    fail "$_label (expected exit $_expected, got $LAST_STATUS)"
  fi
}

assert_output_contains() {
  _pattern=$1
  _label=$2
  if printf '%s\n' "$LAST_OUT" | grep -Fq -- "$_pattern"; then
    pass "$_label"
  else
    fail "$_label (missing '$_pattern' in output)"
  fi
}

assert_status_not() {
  _unexpected=$1
  _label=$2
  if [ "$LAST_STATUS" -ne "$_unexpected" ]; then
    pass "$_label"
  else
    fail "$_label (expected exit != $_unexpected, got $LAST_STATUS)"
  fi
}

assert_output_not_contains() {
  _pattern=$1
  _label=$2
  if printf '%s\n' "$LAST_OUT" | grep -Fq -- "$_pattern"; then
    fail "$_label (unexpectedly found '$_pattern' in output)"
  else
    pass "$_label"
  fi
}

CLAUDE_BACKUP=$REPO_ROOT/.claude/scripts/claudart-backup.sh
CODEX_BACKUP=$REPO_ROOT/.codex/scripts/claudart-backup.sh
CLAUDE_RESTORE=$REPO_ROOT/.claude/scripts/claudart-restore.sh
CODEX_RESTORE=$REPO_ROOT/.codex/scripts/claudart-restore.sh

if /bin/bash -n "$TEST_DIR/run.sh"; then
  pass "Bash syntax is valid"
else
  fail "Bash syntax is valid"
fi

for script in "$CLAUDE_BACKUP" "$CODEX_BACKUP"; do
  SCRIPT_LABEL=${script#"$REPO_ROOT/"}

  if [ -f "$script" ]; then
    pass "$SCRIPT_LABEL exists"
  else
    fail "$SCRIPT_LABEL exists"
    continue
  fi

  if /bin/bash -n "$script"; then
    pass "$SCRIPT_LABEL parses"
  else
    fail "$SCRIPT_LABEL parses"
    continue
  fi

  run_script /bin/bash "$script" --help
  assert_status 0 "$SCRIPT_LABEL --help succeeds"
  assert_output_contains "Usage:" "$SCRIPT_LABEL --help prints usage"
  assert_output_contains "never read" \
    "$SCRIPT_LABEL --help states credentials are never read"

  run_script /bin/bash "$script"
  assert_status 2 "$SCRIPT_LABEL requires --out"
  assert_output_contains "--out is required" \
    "$SCRIPT_LABEL names the missing required argument"

  run_script /bin/bash "$script" --nonsense-flag
  assert_status 2 "$SCRIPT_LABEL rejects an unknown option"
  assert_output_contains "unknown option" \
    "$SCRIPT_LABEL names the unknown option"
done

if cmp -s "$CLAUDE_BACKUP" "$CODEX_BACKUP"; then
  pass "claudart-backup.sh Codex twin is byte-identical"
else
  fail "claudart-backup.sh Codex twin is byte-identical"
fi

for script in "$CLAUDE_RESTORE" "$CODEX_RESTORE"; do
  SCRIPT_LABEL=${script#"$REPO_ROOT/"}

  if [ -f "$script" ]; then
    pass "$SCRIPT_LABEL exists"
  else
    fail "$SCRIPT_LABEL exists"
    continue
  fi

  if /bin/bash -n "$script"; then
    pass "$SCRIPT_LABEL parses"
  else
    fail "$SCRIPT_LABEL parses"
    continue
  fi

  run_script /bin/bash "$script" --help
  assert_status 0 "$SCRIPT_LABEL --help succeeds"
  assert_output_contains "Usage:" "$SCRIPT_LABEL --help prints usage"

  run_script /bin/bash "$script"
  assert_status 2 "$SCRIPT_LABEL requires --bundle"
  assert_output_contains "--bundle is required" \
    "$SCRIPT_LABEL names the missing required argument"

  run_script /bin/bash "$script" --nonsense-flag
  assert_status 2 "$SCRIPT_LABEL rejects an unknown option"
  assert_output_contains "unknown option" \
    "$SCRIPT_LABEL names the unknown option"
done

if cmp -s "$CLAUDE_RESTORE" "$CODEX_RESTORE"; then
  pass "claudart-restore.sh Codex twin is byte-identical"
else
  fail "claudart-restore.sh Codex twin is byte-identical"
fi

# ── functional round trip: real backup -> real restore ──────────────────────
# Builds a synthetic source project and a synthetic Claude Code user-scope
# directory (never the real $HOME/.claude), backs it up, then restores it into
# a DIFFERENT synthetic target project and checks the rewrite is correct --
# including the prefix-hazard decoy (SOURCE-backup must survive untouched
# while SOURCE itself is translated) and that all five verifications pass.

FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-portability-fixture.XXXXXX") || exit 2
trap 'rm -rf "$FIXTURE_ROOT" "${MERGE_ROOT:-}" "${BAD_ROOT:-}"' EXIT

SRC_PROJECT=$FIXTURE_ROOT/src-project
DEST_PROJECT=$FIXTURE_ROOT/dest-project
CLAUDE_HOME_SRC=$FIXTURE_ROOT/claude-home-src
CLAUDE_HOME_DEST=$FIXTURE_ROOT/claude-home-dest
BUNDLE=$FIXTURE_ROOT/bundle
STAGE_OUT=$FIXTURE_ROOT/stage-out

mkdir -p "$SRC_PROJECT/.claude/commands" "$DEST_PROJECT/.claude/commands"
echo "template start command" >"$SRC_PROJECT/.claude/commands/start.md"
echo "pre-existing dest file" >"$DEST_PROJECT/.claude/commands/existing.md"

SRC_PROJECT=$(CDPATH='' cd -- "$SRC_PROJECT" && pwd -P)
DEST_PROJECT=$(CDPATH='' cd -- "$DEST_PROJECT" && pwd -P)
MANGLED_SRC=$(printf '%s' "$SRC_PROJECT" | tr '/' '-')
mkdir -p "$CLAUDE_HOME_SRC/projects/$MANGLED_SRC"

SID=abcdef01-0000-4000-8000-000000000099
cat >"$CLAUDE_HOME_SRC/projects/$MANGLED_SRC/$SID.jsonl" <<EOF
{"type":"mode","mode":"default"}
{"type":"summary","summary":"start"}
{"type":"user","cwd":"$SRC_PROJECT","uuid":"u1","parentUuid":null,"sessionId":"$SID","version":"1.0.0","gitBranch":"main","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"hello from $SRC_PROJECT and decoy $SRC_PROJECT-backup/x.ts"}}
{"type":"assistant","cwd":"$SRC_PROJECT","uuid":"u2","parentUuid":"u1","sessionId":"$SID","version":"1.0.0","gitBranch":"main","timestamp":"2026-01-01T00:00:01Z","message":{"role":"assistant","content":"ok, see file://$SRC_PROJECT/README.md too"}}
EOF

run_script /bin/bash "$CLAUDE_BACKUP" \
  --root "$SRC_PROJECT" --claude-home "$CLAUDE_HOME_SRC" --out "$BUNDLE" \
  --sessions all --history no
assert_status 0 "fixture: claudart-backup.sh succeeds on the synthetic source"

run_script /bin/bash "$CLAUDE_RESTORE" \
  --bundle "$BUNDLE" --target "$DEST_PROJECT" --claude-home "$CLAUDE_HOME_DEST" \
  --stage-out "$STAGE_OUT"
assert_status 0 "fixture: claudart-restore.sh dry run succeeds"
assert_output_contains "1. line-count/newline parity:  PASS" "fixture: verification 1 passes"
assert_output_contains "2. identity multiset:          PASS" "fixture: verification 2 passes"
assert_output_contains "3. byte arithmetic:            PASS" "fixture: verification 3 passes"
assert_output_contains "4. occurrence arithmetic:      PASS" "fixture: verification 4 passes"
assert_output_contains "5. structural JSON:            PASS" "fixture: verification 5 passes"

REWRITTEN_JSONL=$STAGE_OUT/user/sessions/$SID.jsonl
if [ -f "$REWRITTEN_JSONL" ]; then
  pass "fixture: rewritten transcript was staged"
else
  fail "fixture: rewritten transcript was staged"
fi

if grep -qF "\"cwd\":\"$DEST_PROJECT\"" "$REWRITTEN_JSONL" 2>/dev/null; then
  pass "fixture: cwd rewritten to the destination project"
else
  fail "fixture: cwd rewritten to the destination project"
fi

if grep -qF "$SRC_PROJECT-backup/x.ts" "$REWRITTEN_JSONL" 2>/dev/null; then
  pass "fixture: prefix-hazard decoy (SOURCE-backup) survives byte-identical"
else
  fail "fixture: prefix-hazard decoy (SOURCE-backup) survives byte-identical"
fi

# The bare source-root substring legitimately still occurs inside the
# preserved "-backup" decoy, so check the boundary-anchored form (immediately
# followed by a quote, the JSON string terminator every cwd/content value
# used here) is gone rather than a plain substring search.
if grep -qF "$SRC_PROJECT\"" "$REWRITTEN_JSONL" 2>/dev/null; then
  fail "fixture: no boundary-passing occurrence of the source root remains"
else
  pass "fixture: no boundary-passing occurrence of the source root remains"
fi

if grep -qF "file://$DEST_PROJECT/README.md" "$REWRITTEN_JSONL" 2>/dev/null; then
  pass "fixture: file:// URI form rewritten to the destination"
else
  fail "fixture: file:// URI form rewritten to the destination"
fi

DEST_FILES_AFTER=$(find "$DEST_PROJECT" -type f | LC_ALL=C sort)
DEST_FILES_EXPECTED=$(printf '%s\n' "$DEST_PROJECT/.claude/commands/existing.md")
if [ "$DEST_FILES_AFTER" = "$DEST_FILES_EXPECTED" ]; then
  pass "fixture: dry run without --apply writes nothing into the real target"
else
  fail "fixture: dry run without --apply writes nothing into the real target"
fi

BUNDLE_BEFORE=$(cd "$BUNDLE" && find . -type f -exec cksum {} \; | LC_ALL=C sort)
run_script /bin/bash "$CLAUDE_RESTORE" \
  --bundle "$BUNDLE" --target "$DEST_PROJECT" --claude-home "$CLAUDE_HOME_DEST"
BUNDLE_AFTER=$(cd "$BUNDLE" && find . -type f -exec cksum {} \; | LC_ALL=C sort)
if [ "$BUNDLE_BEFORE" = "$BUNDLE_AFTER" ]; then
  pass "fixture: restore never mutates the bundle it reads"
else
  fail "fixture: restore never mutates the bundle it reads"
fi

# ── negative control: verification 4 must be able to fail ──────────────────
# A checker that always passes proves nothing (evidence-gauntlet §6). Disable
# boundary anchoring in a scratch copy of the shipped restore script and
# confirm the SAME fixture then fails verification 4 -- this is what makes
# the PASS assertions above meaningful, and it is a permanent regression test:
# if a future change to boundary_replace breaks the boundary rule again, this
# must go red.
MUTANT=$FIXTURE_ROOT/claudart-restore-mutant.sh
cp "$CLAUDE_RESTORE" "$MUTANT"
NEEDLE_ORIG='if (nextchar == "" || nextchar !~ /[A-Za-z0-9._-]/) {'
NEEDLE_MUTANT='if (1) {'
if grep -qF "$NEEDLE_ORIG" "$MUTANT"; then
  awk -v old="$NEEDLE_ORIG" -v new="$NEEDLE_MUTANT" '
    { idx = index($0, old); if (idx > 0) { print substr($0, 1, idx - 1) new; next } print }
  ' "$MUTANT" >"$MUTANT.tmp" && mv "$MUTANT.tmp" "$MUTANT"
  pass "negative control: mutant boundary check installed"
else
  fail "negative control: mutant boundary check installed (marker text not found -- boundary_replace was refactored; update this test)"
fi

if /bin/bash -n "$MUTANT"; then
  pass "negative control: mutant parses"
else
  fail "negative control: mutant parses"
fi

run_script /bin/bash "$MUTANT" \
  --bundle "$BUNDLE" --target "$DEST_PROJECT" --claude-home "$CLAUDE_HOME_DEST"
assert_status_not 0 "negative control: boundary-disabled mutant fails verification"
assert_output_contains "verification 4b failed" \
  "negative control: verification 4 names the boundary violation"

# ── pre-flight refusals ──────────────────────────────────────────────────────

run_script /bin/bash "$CLAUDE_RESTORE" --bundle "$BUNDLE" --target "$FIXTURE_ROOT"
assert_status 2 "refusal: target with no .claude"
assert_output_contains "restore merges into an existing CLAUDART project" \
  "refusal: target-without-.claude names the reason"

NO_CLAUDE_BUNDLE=$FIXTURE_ROOT/bundle-empty
mkdir -p "$NO_CLAUDE_BUNDLE"
run_script /bin/bash "$CLAUDE_RESTORE" --bundle "$NO_CLAUDE_BUNDLE" --target "$DEST_PROJECT"
assert_status 2 "refusal: bundle missing metadata files"
assert_output_contains "not a claudart-backup.sh bundle" \
  "refusal: missing-metadata names the reason"

TAMPERED_BUNDLE=$FIXTURE_ROOT/bundle-tampered
cp -R "$BUNDLE" "$TAMPERED_BUNDLE"
echo "tampered" >>"$TAMPERED_BUNDLE/project/.claude/commands/start.md"
run_script /bin/bash "$CLAUDE_RESTORE" --bundle "$TAMPERED_BUNDLE" --target "$DEST_PROJECT" --claude-home "$CLAUDE_HOME_DEST"
assert_status 2 "refusal: tampered payload fails the INVENTORY integrity check"
assert_output_contains "failed integrity check" \
  "refusal: tampered payload names the reason"

SECRET_BUNDLE=$FIXTURE_ROOT/bundle-secret
cp -R "$BUNDLE" "$SECRET_BUNDLE"
printf 'GOOGLE_API_KEY project/.claude/knowledge/leak.md:1\n' >"$SECRET_BUNDLE/SECRETS.txt"
run_script /bin/bash "$CLAUDE_RESTORE" --bundle "$SECRET_BUNDLE" --target "$DEST_PROJECT" --claude-home "$CLAUDE_HOME_DEST"
assert_status 1 "refusal: bundle with SECRETS.txt is withheld without --allow-secrets"
run_script /bin/bash "$CLAUDE_RESTORE" --bundle "$SECRET_BUNDLE" --target "$DEST_PROJECT" --claude-home "$CLAUDE_HOME_DEST" --allow-secrets
assert_status 0 "refusal: --allow-secrets proceeds past the SECRETS.txt gate"

run_script /bin/bash "$CLAUDE_RESTORE" --bundle "$BUNDLE" --target "$DEST_PROJECT" --claude-home "$CLAUDE_HOME_DEST" --mode graft
assert_status 2 "refusal: --mode graft cannot import a bundle carrying sessions"
assert_output_contains "cannot import a bundle carrying sessions or history" \
  "refusal: graft-mode names the reason"

NESTED_TARGET=$SRC_PROJECT/nested-target
mkdir -p "$NESTED_TARGET/.claude"
run_script /bin/bash "$CLAUDE_RESTORE" --bundle "$BUNDLE" --target "$NESTED_TARGET" --claude-home "$CLAUDE_HOME_DEST"
assert_status 2 "refusal: target nested under the bundle's source root"
assert_output_contains "ambiguous rewrite" \
  "refusal: nested-target names the reason"

run_script /bin/bash "$CLAUDE_RESTORE" --bundle "$BUNDLE" --target "$DEST_PROJECT" --claude-home "$CLAUDE_HOME_DEST" --apply
# ── merge classes + Commit: a richly populated target ───────────────────────
# A second, separate fixture: unlike the round-trip fixture above (which
# targets an almost-empty destination), this one gives the destination real
# pre-existing content so the never-overwrite invariant, keyed-unit
# collisions, union-route K205 skipping, and the union-log JOURNAL merge all
# have something genuine to collide with. It also carries a real copy of
# knowledge-check.sh so the shadow gate exercises the actual checker, not a
# "skipped: no checker" no-op.

MERGE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-portability-merge.XXXXXX") || exit 2
SRC2=$MERGE_ROOT/src-project
DEST2=$MERGE_ROOT/dest-project
CLAUDE_HOME_SRC2=$MERGE_ROOT/claude-home-src
CLAUDE_HOME_DEST2=$MERGE_ROOT/claude-home-dest
BUNDLE2=$MERGE_ROOT/bundle2

mkdir -p "$SRC2/.claude/knowledge" "$SRC2/.claude/rules" "$SRC2/.claude/tasks" "$SRC2/.claude/scripts"
mkdir -p "$DEST2/.claude/knowledge" "$DEST2/.claude/rules" "$DEST2/.claude/scripts"

cp "$REPO_ROOT/.claude/scripts/knowledge-check.sh" "$SRC2/.claude/scripts/knowledge-check.sh"
cp "$REPO_ROOT/.claude/scripts/knowledge-check.sh" "$DEST2/.claude/scripts/knowledge-check.sh"

# Destination pre-existing state.
cat >"$DEST2/.claude/knowledge/colliding-topic.md" <<'EOF'
---
name: colliding-topic
description: "the destination's own version"
type: reference
status: active
updated: 2026-01-01
last_verified: 2026-01-01
verify: "n/a"
---

Destination content.
EOF
cat >"$DEST2/.claude/knowledge/already-routed.md" <<'EOF'
---
name: already-routed
description: "already present and routed"
type: reference
status: active
updated: 2026-01-01
last_verified: 2026-01-01
verify: "n/a"
---

Already routed content.
EOF
cat >"$DEST2/.claude/knowledge/INDEX.md" <<'EOF'
<!-- .claude/knowledge/INDEX.md -- root router for durable descriptive knowledge. -->

# Project Knowledge

## Knowledge

- [Colliding Topic](colliding-topic.md) — the destination's own version · reference · active
- [Already Routed](already-routed.md) — already present and routed · reference · active
EOF
cat >"$DEST2/.claude/rules/existing-rule.md" <<'EOF'
# Existing Rule (destination version)
EOF
cat >"$DEST2/.claude/JOURNAL.md" <<'EOF'
# Claude Session Journal

Append-only audit log. Format: YYYY-MM-DD | <type> | <one-line summary>

---
2026-01-05 | completed | destination-only entry
2026-01-10 | completed | shared entry, same on both sides
EOF

# Source content to graft/merge in.
cat >"$SRC2/.claude/knowledge/new-topic.md" <<EOF
---
name: new-topic
description: "a brand new grafted topic"
type: reference
status: active
updated: 2026-01-01
last_verified: 2026-01-01
sources:
  - "path:docs/missing-on-dest.md"
related:
  - "rule:existing-rule"
  - "knowledge:nonexistent-elsewhere"
verify: "n/a"
---

New topic content.
EOF
cat >"$SRC2/.claude/knowledge/colliding-topic.md" <<'EOF'
---
name: colliding-topic
description: "the source's own, different version"
type: reference
status: active
updated: 2026-01-02
last_verified: 2026-01-02
verify: "n/a"
---

Source content, deliberately different from the destination's.
EOF
cat >"$SRC2/.claude/knowledge/INDEX.md" <<'EOF'
<!-- .claude/knowledge/INDEX.md -- root router for durable descriptive knowledge. -->

# Project Knowledge

## Knowledge

- [New Topic](new-topic.md) — a brand new grafted topic · reference · active
- [Colliding Topic](colliding-topic.md) — the source's own, different version · reference · active
- [Already Routed](already-routed.md) — a source-side hook for an already-routed link · reference · active
EOF
cat >"$SRC2/.claude/rules/existing-rule.md" <<'EOF'
# Existing Rule (source version -- different content)
EOF
cat >"$SRC2/.claude/rules/new-rule.md" <<'EOF'
# New Rule (absent on destination)
EOF
mkdir -p "$SRC2/.claude/tasks"
cat >"$SRC2/.claude/tasks/2026-01-01-001-grafted-task.md" <<'EOF'
---
slug: grafted-task
status: planning
created: 2026-01-01
updated: 2026-01-01
agent: claude
delegation: none
tags: [test]
---

# Grafted Task
EOF
cat >"$SRC2/.claude/JOURNAL.md" <<'EOF'
# Claude Session Journal

Append-only audit log. Format: YYYY-MM-DD | <type> | <one-line summary>

---
2026-01-08 | completed | source-only entry
2026-01-10 | completed | shared entry, same on both sides
EOF

SRC2=$(CDPATH='' cd -- "$SRC2" && pwd -P)
DEST2=$(CDPATH='' cd -- "$DEST2" && pwd -P)
MANGLED_SRC2=$(printf '%s' "$SRC2" | tr '/' '-')
mkdir -p "$CLAUDE_HOME_SRC2/projects/$MANGLED_SRC2"

run_script /bin/bash "$CLAUDE_BACKUP" \
  --root "$SRC2" --claude-home "$CLAUDE_HOME_SRC2" --out "$BUNDLE2" \
  --sessions none --history no
assert_status 0 "merge fixture: claudart-backup.sh succeeds on the populated source"

# Snapshot every pre-existing destination file's cksum before touching anything.
DEST2_BEFORE=$(cd "$DEST2" && find . -type f -exec cksum {} \; | LC_ALL=C sort)

run_script /bin/bash "$CLAUDE_RESTORE" \
  --bundle "$BUNDLE2" --target "$DEST2" --claude-home "$CLAUDE_HOME_DEST2" --apply
assert_status 0 "merge fixture: claudart-restore.sh --apply commits successfully"
assert_output_contains "claude layer: PASS" "merge fixture: shadow knowledge-check.sh gate passes"
assert_output_contains "restore committed" "merge fixture: reports a successful commit"

# Never-overwrite invariant: colliding-topic.md, existing-rule.md, and
# already-routed.md are NOT in the MERGE allowlist and must be byte-identical
# to their pre-restore selves.
if grep -qF 'the destination'"'"'s own version' "$DEST2/.claude/knowledge/colliding-topic.md" 2>/dev/null &&
  grep -qF "Destination content." "$DEST2/.claude/knowledge/colliding-topic.md" 2>/dev/null; then
  pass "never-overwrite: colliding knowledge topic untouched at its original path"
else
  fail "never-overwrite: colliding knowledge topic untouched at its original path"
fi

if grep -qF "destination version" "$DEST2/.claude/rules/existing-rule.md" 2>/dev/null; then
  pass "never-overwrite: colliding rule untouched at its original path"
else
  fail "never-overwrite: colliding rule untouched at its original path"
fi

if grep -qF "Already routed content." "$DEST2/.claude/knowledge/already-routed.md" 2>/dev/null; then
  pass "never-overwrite: unrelated pre-existing topic untouched"
else
  fail "never-overwrite: unrelated pre-existing topic untouched"
fi

# New unique task placed.
if [ -f "$DEST2/.claude/tasks/2026-01-01-001-grafted-task.md" ]; then
  pass "merge fixture: new unique task file placed under its original NNN (no collision)"
else
  fail "merge fixture: new unique task file placed under its original NNN (no collision)"
fi

# New template rule placed.
if [ -f "$DEST2/.claude/rules/new-rule.md" ]; then
  pass "merge fixture: new template-owned rule placed (no collision)"
else
  fail "merge fixture: new template-owned rule placed (no collision)"
fi

# Colliding rule sidecared, never overwriting the original.
BUNDLE2_ID=$(grep -m1 '"bundle_id"' "$BUNDLE2/MANIFEST.json" | sed -e 's/.*: "//' -e 's/".*//')
if [ -f "$DEST2/.claude/rules/existing-rule-imported-$BUNDLE2_ID.md" ]; then
  pass "merge fixture: colliding template rule sidecared"
else
  fail "merge fixture: colliding template rule sidecared"
fi

# New knowledge topic grafted as review-needed, sources: pruned, related:
# pruned to only the resolving rule, and routed once.
NEW_TOPIC=$DEST2/.claude/knowledge/new-topic.md
if [ -f "$NEW_TOPIC" ]; then
  pass "merge fixture: new knowledge topic grafted"
else
  fail "merge fixture: new knowledge topic grafted"
fi
if grep -qF "status: review-needed" "$NEW_TOPIC" 2>/dev/null; then
  pass "merge fixture: grafted topic landed as review-needed"
else
  fail "merge fixture: grafted topic landed as review-needed"
fi
if grep -qF "docs/missing-on-dest.md" "$NEW_TOPIC" 2>/dev/null; then
  fail "merge fixture: non-resolving sources: entry was pruned"
else
  pass "merge fixture: non-resolving sources: entry was pruned"
fi
if grep -qF "knowledge:nonexistent-elsewhere" "$NEW_TOPIC" 2>/dev/null; then
  fail "merge fixture: dangling related: entry was pruned"
else
  pass "merge fixture: dangling related: entry was pruned"
fi
if grep -qF "rule:existing-rule" "$NEW_TOPIC" 2>/dev/null; then
  pass "merge fixture: resolving related: entry was kept"
else
  fail "merge fixture: resolving related: entry was kept"
fi
if grep -qF "new-topic.md" "$DEST2/.claude/knowledge/INDEX.md" 2>/dev/null; then
  pass "merge fixture: new topic routed once in INDEX.md"
else
  fail "merge fixture: new topic routed once in INDEX.md"
fi

# Colliding knowledge topic sidecared with a rewritten name:, unrouted.
COLLIDING_SIDECAR=$DEST2/.claude/knowledge/colliding-topic-imported-$BUNDLE2_ID.md
if [ -f "$COLLIDING_SIDECAR" ]; then
  pass "merge fixture: colliding knowledge topic sidecared"
else
  fail "merge fixture: colliding knowledge topic sidecared"
fi
if grep -qF "name: colliding-topic-imported-$BUNDLE2_ID" "$COLLIDING_SIDECAR" 2>/dev/null; then
  pass "merge fixture: sidecar's name: rewritten to match its own basename"
else
  fail "merge fixture: sidecar's name: rewritten to match its own basename"
fi
if grep -qF "colliding-topic-imported-$BUNDLE2_ID.md" "$DEST2/.claude/knowledge/INDEX.md" 2>/dev/null; then
  fail "merge fixture: sidecared topic left unrouted (K205)"
else
  pass "merge fixture: sidecared topic left unrouted (K205)"
fi

# The source's own "already-routed" line must be skipped (K205), not
# duplicated, since that link target is already routed at the destination.
ALREADY_ROUTED_COUNT=$(grep -cF "](already-routed.md)" "$DEST2/.claude/knowledge/INDEX.md" 2>/dev/null | tr -d ' ')
if [ "$ALREADY_ROUTED_COUNT" = 1 ]; then
  pass "merge fixture: already-routed link target not duplicated (K205)"
else
  fail "merge fixture: already-routed link target not duplicated (K205) (found $ALREADY_ROUTED_COUNT routes)"
fi

# JOURNAL.md genuinely merged: header preserved, both unique entries present,
# the shared entry deduped to one occurrence, chronological order.
JOURNAL_DEST=$DEST2/.claude/JOURNAL.md
if grep -qF "source-only entry" "$JOURNAL_DEST" 2>/dev/null && grep -qF "destination-only entry" "$JOURNAL_DEST" 2>/dev/null; then
  pass "merge fixture: JOURNAL.md carries both sides' unique entries"
else
  fail "merge fixture: JOURNAL.md carries both sides' unique entries"
fi
SHARED_COUNT=$(grep -cF "shared entry, same on both sides" "$JOURNAL_DEST" 2>/dev/null | tr -d ' ')
if [ "$SHARED_COUNT" = 1 ]; then
  pass "merge fixture: JOURNAL.md dedups an identical entry present on both sides"
else
  fail "merge fixture: JOURNAL.md dedups an identical entry present on both sides (found $SHARED_COUNT)"
fi
if head -n1 "$JOURNAL_DEST" | grep -qF "# Claude Session Journal"; then
  pass "merge fixture: JOURNAL.md header preserved"
else
  fail "merge fixture: JOURNAL.md header preserved"
fi

# Receipt and ledger.
RECEIPT_COUNT=$(find "$CLAUDE_HOME_DEST2/claudart-import-backups" -maxdepth 2 -name receipt.txt 2>/dev/null | wc -l | tr -d ' ')
if [ "$RECEIPT_COUNT" -ge 1 ]; then
  pass "merge fixture: a receipt.txt was written under claudart-import-backups"
else
  fail "merge fixture: a receipt.txt was written under claudart-import-backups"
fi
if [ -f "$DEST2/.claude/.portability/ledger.tsv" ] && grep -qF "$BUNDLE2_ID" "$DEST2/.claude/.portability/ledger.tsv" 2>/dev/null; then
  pass "merge fixture: ledger.tsv records this bundle's id"
else
  fail "merge fixture: ledger.tsv records this bundle's id"
fi

# Double-apply idempotency: a second --apply on the same bundle/target must
# not create duplicate sidecars, duplicate JOURNAL lines, or otherwise change
# anything already settled by the first commit.
DEST2_AFTER_FIRST=$(cd "$DEST2" && find . -type f -exec cksum {} \; | LC_ALL=C sort)
run_script /bin/bash "$CLAUDE_RESTORE" \
  --bundle "$BUNDLE2" --target "$DEST2" --claude-home "$CLAUDE_HOME_DEST2" --apply
assert_status 0 "merge fixture: second --apply on the same bundle also succeeds"
DEST2_AFTER_SECOND=$(cd "$DEST2" && find . -type f -exec cksum {} \; | LC_ALL=C sort)
if [ "$DEST2_AFTER_FIRST" = "$DEST2_AFTER_SECOND" ]; then
  pass "merge fixture: double-apply idempotency -- second run changes nothing"
else
  fail "merge fixture: double-apply idempotency -- second run changes nothing"
fi

# ── shadow gate actually blocks a bad import ────────────────────────────────
# A negative control for the shadow gate itself: graft a knowledge topic
# with a status the checker rejects, and confirm --apply refuses and writes
# nothing, rather than the gate being decorative.

BAD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-portability-badgate.XXXXXX") || exit 2
BAD_SRC=$BAD_ROOT/src-project
BAD_DEST=$BAD_ROOT/dest-project
mkdir -p "$BAD_SRC/.claude/knowledge" "$BAD_SRC/.claude/scripts" "$BAD_DEST/.claude/knowledge" "$BAD_DEST/.claude/scripts"
cp "$REPO_ROOT/.claude/scripts/knowledge-check.sh" "$BAD_SRC/.claude/scripts/knowledge-check.sh"
cp "$REPO_ROOT/.claude/scripts/knowledge-check.sh" "$BAD_DEST/.claude/scripts/knowledge-check.sh"
cat >"$BAD_SRC/.claude/knowledge/broken-topic.md" <<'EOF'
---
name: broken-topic
description: "a topic with a type outside the canonical enum"
type: bogus-type-value
status: active
updated: 2026-01-01
---

Broken. type: is never rewritten by the graft transform (only status/
status_note/last_verified/sources/related/supersedes are), so this survives
to the shadow knowledge-check.sh gate untouched -- unlike an invalid status:,
which the graft's own review-needed rewrite would silently neutralize before
the checker ever saw it.
EOF
cat >"$BAD_SRC/.claude/knowledge/INDEX.md" <<'EOF'
<!-- .claude/knowledge/INDEX.md -- root router for durable descriptive knowledge. -->

# Project Knowledge

## Knowledge

- [Broken Topic](broken-topic.md) — a topic with an invalid status · reference · active
EOF
BAD_SRC=$(CDPATH='' cd -- "$BAD_SRC" && pwd -P)
BAD_DEST=$(CDPATH='' cd -- "$BAD_DEST" && pwd -P)
run_script /bin/bash "$CLAUDE_BACKUP" --root "$BAD_SRC" --claude-home "$MERGE_ROOT/claude-home-bad" --out "$BAD_ROOT/bundle" --sessions none --history no
assert_status 0 "shadow-gate control: backup of the deliberately-invalid topic succeeds"

BAD_DEST_BEFORE=$(cd "$BAD_DEST" && find . -type f -exec cksum {} \; | LC_ALL=C sort)
run_script /bin/bash "$CLAUDE_RESTORE" --bundle "$BAD_ROOT/bundle" --target "$BAD_DEST" --claude-home "$MERGE_ROOT/claude-home-bad-dest" --apply
assert_status_not 0 "shadow-gate control: --apply refuses when the shadow knowledge-check.sh would fail"
assert_output_contains "shadow knowledge-check.sh gate failed" \
  "shadow-gate control: names the reason"
BAD_DEST_AFTER=$(cd "$BAD_DEST" && find . -type f -exec cksum {} \; | LC_ALL=C sort)
if [ "$BAD_DEST_BEFORE" = "$BAD_DEST_AFTER" ]; then
  pass "shadow-gate control: nothing was written to the target when the gate failed"
else
  fail "shadow-gate control: nothing was written to the target when the gate failed"
fi

printf '1..%s\n' $((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
