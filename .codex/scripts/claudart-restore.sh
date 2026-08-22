#!/bin/bash

# Import a portable CLAUDART bundle produced by claudart-backup.sh. Three
# phases: Plan (pre-flight refusals), Materialize (path rewrite + five
# verifications, then the merge classes applied to a shadow copy of the
# target and gated by a shadow knowledge-check.sh run), and Commit (backups,
# then the same merge applied for real, a receipt, and a lineage ledger
# append) -- only reached with --apply; without it, everything through the
# shadow gate still runs and reports, but nothing is written. Runtime
# dependencies are limited to Bash 3.2 and common POSIX utilities.

set -u

umask 077

LC_ALL=C
export LC_ALL

PROGRAM=${0##*/}
SEP=$(printf '\034')
SCHEMA=claudart-bundle/1
# Must match claudart-backup.sh's REWRITE_ORDER exactly -- most specific class
# first, so a nested token (PROJECT_SUBPATH contains PROJECT_ROOT contains
# HOME) is rewritten before its container is touched. Verified against the
# bundle's own MANIFEST.json paths.rewrite_order during pre-flight; a mismatch
# refuses rather than silently using a stale order.
REWRITE_ORDER_EXPECTED="PROJECT_SUBPATH,ALIAS_ROOT,PROJECT_ROOT,CLAUDE_HOME,PROJECTS_DIR,HOME"

BUNDLE_DIR=
TARGET_OVERRIDE=
CLAUDE_HOME_OVERRIDE=
MODE=full
REWRITE_HOME=false
ALLOW_SECRETS=false
ALLOW_DIRTY=false
STAGE_OUT=
APPLY=false

usage() {
  cat <<'EOF'
Usage: claudart-restore.sh --bundle DIR [options]

Plan, verify, and import a portable CLAUDART bundle. Reports what would be
rewritten and merged; writes nothing unless --apply is given.

Options:
  --bundle DIR         Bundle directory produced by claudart-backup.sh (required)
  --target DIR         Project root to import into (default: inferred from script path)
  --claude-home DIR    Destination Claude Code user directory
                        (default: $CLAUDE_CONFIG_DIR, else $HOME/.claude)
  --mode full|graft    full = project + user-scope data; graft = knowledge/ and
                        rules/ only, hard-refuses a bundle carrying sessions or
                        history (default: full)
  --rewrite-home       Also rewrite bare references to the source $HOME, not only
                        structural $HOME/.claude paths (default: off)
  --allow-secrets       Proceed even though the bundle's SECRETS.txt reports findings
  --allow-dirty         Proceed even though the target's git tree is dirty
  --stage-out DIR       On a clean dry run, copy the rewritten (not yet merged)
                        payload here for inspection; must not already exist
  --apply               Write the merged result: backups first, then receipt.txt
                        and a lineage-ledger append
  --help                 Show this help

Exit status:
  0  plan/verification completed cleanly
  1  a rewrite verification failed, or the bundle has unacknowledged secrets
  2  invalid usage or a pre-flight refusal
EOF
}

usage_error() {
  printf '%s: %s\n' "$PROGRAM" "$1" >&2
  printf '%s\n' "Try '$PROGRAM --help' for usage." >&2
  exit 2
}

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) ||
  usage_error "cannot resolve the script directory"
INFERRED_TARGET=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." 2>/dev/null && pwd -P) ||
  usage_error "cannot infer the repository root"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle)
      [ "$#" -ge 2 ] || usage_error "--bundle requires a directory"
      BUNDLE_DIR=$2
      shift 2
      ;;
    --target)
      [ "$#" -ge 2 ] || usage_error "--target requires a directory"
      TARGET_OVERRIDE=$2
      shift 2
      ;;
    --claude-home)
      [ "$#" -ge 2 ] || usage_error "--claude-home requires a directory"
      CLAUDE_HOME_OVERRIDE=$2
      shift 2
      ;;
    --mode)
      [ "$#" -ge 2 ] || usage_error "--mode requires full or graft"
      MODE=$2
      shift 2
      ;;
    --rewrite-home)
      REWRITE_HOME=true
      shift
      ;;
    --allow-secrets)
      ALLOW_SECRETS=true
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=true
      shift
      ;;
    --stage-out)
      [ "$#" -ge 2 ] || usage_error "--stage-out requires a directory"
      STAGE_OUT=$2
      shift 2
      ;;
    --apply)
      APPLY=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    --*)
      usage_error "unknown option: $1"
      ;;
    *)
      usage_error "unexpected argument: $1"
      ;;
  esac
done

case "$MODE" in
  full | graft) ;;
  *) usage_error "--mode must be full or graft" ;;
esac

if [ -n "$STAGE_OUT" ] && [ -e "$STAGE_OUT" ]; then
  usage_error "--stage-out already exists: $STAGE_OUT"
fi

[ -n "$BUNDLE_DIR" ] || usage_error "--bundle is required"
[ -d "$BUNDLE_DIR" ] || usage_error "--bundle is not a directory: $BUNDLE_DIR"
BUNDLE=$(CDPATH='' cd -- "$BUNDLE_DIR" 2>/dev/null && pwd -P) ||
  usage_error "cannot resolve --bundle"

if [ -n "$TARGET_OVERRIDE" ]; then
  [ -d "$TARGET_OVERRIDE" ] || usage_error "--target is not a directory"
  TARGET=$(CDPATH='' cd -- "$TARGET_OVERRIDE" 2>/dev/null && pwd -P) ||
    usage_error "cannot resolve --target"
else
  TARGET=$INFERRED_TARGET
fi

if [ -n "$CLAUDE_HOME_OVERRIDE" ]; then
  CLAUDE_HOME_DEST=$CLAUDE_HOME_OVERRIDE
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  CLAUDE_HOME_DEST=$CLAUDE_CONFIG_DIR
else
  CLAUDE_HOME_DEST=${HOME:-}/.claude
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claudart-restore.XXXXXX" 2>/dev/null) ||
  usage_error "cannot create a temporary directory"

# Invoked indirectly by trap.
# shellcheck disable=SC2329
cleanup() {
  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf -- "$TMP_DIR"
  fi
}
# Invoked indirectly by trap.
# shellcheck disable=SC2329
on_signal() {
  trap - HUP INT TERM
  exit 2
}
trap cleanup EXIT
trap on_signal HUP INT TERM

STAGE=$TMP_DIR/stage
mkdir -p "$STAGE" || usage_error "cannot create the staging directory"

# ── helpers ──────────────────────────────────────────────────────────────────

# Replace every literal occurrence of $2 in $1 with $3. Byte-literal via sed
# with a "#" delimiter so a "/"-heavy path never needs escaping in the
# pattern; used only on small metadata strings (path tokens), never on bundle
# file content, so sed's per-invocation cost is irrelevant here.
literal_replace() {
  printf '%s' "$1" | sed "s#$(printf '%s' "$2" | sed 's/[&#\]/\\&/g')#$(printf '%s' "$3" | sed 's/[&#\]/\\&/g')#g"
}

# Encode a raw path into one of the four positional encodings backup emits.
encode_path() {
  ep_raw=$1
  ep_enc=$2
  case "$ep_enc" in
    raw) printf '%s' "$ep_raw" ;;
    uri) printf 'file://%s' "$ep_raw" ;;
    escaped) literal_replace "$ep_raw" "/" '\/' ;;
    percent) literal_replace "$ep_raw" "/" "%2F" ;;
    *) printf '%s' "$ep_raw" ;;
  esac
}

# Inverse of encode_path: recover the raw path a token represents, given its
# encoding. Only defined for the four generic path encodings -- "mangled" and
# "tilde" tokens are handled as direct special cases by the caller.
decode_path() {
  dp_token=$1
  dp_enc=$2
  case "$dp_enc" in
    raw) printf '%s' "$dp_token" ;;
    uri) printf '%s' "${dp_token#file://}" ;;
    escaped) literal_replace "$dp_token" '\/' "/" ;;
    percent) literal_replace "$dp_token" "%2F" "/" ;;
    *) printf '%s' "$dp_token" ;;
  esac
}

# Escape every ERE metacharacter so a literal path token can be used inside a
# grep -E pattern. Used only by the independent boundary recount in
# verification 4 -- a second, differently-implemented check on the same
# boundary rule the rewrite's own awk scanner enforces, so a bug shared by
# both would have to be a coincidence of two different implementations
# rather than one bug the verification merely restates.
regex_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/[].^$*+?()[{}|]/\\&/g'
}

class_rank() {
  case "$1" in
    PROJECT_SUBPATH) printf 1 ;;
    ALIAS_ROOT) printf 2 ;;
    PROJECT_ROOT) printf 3 ;;
    CLAUDE_HOME) printf 4 ;;
    PROJECTS_DIR) printf 5 ;;
    HOME) printf 6 ;;
    *) printf 9 ;;
  esac
}

# ── pre-flight: bundle shape and integrity ──────────────────────────────────

for f in MANIFEST.json INVENTORY MERGEPLAN PATHMAP PATHMAP.files SELFTEST SELFTEST.cksum README.txt; do
  [ -f "$BUNDLE/$f" ] || usage_error "bundle is missing $f -- not a claudart-backup.sh bundle"
done

if find "$BUNDLE" -type l 2>/dev/null | grep -q .; then
  usage_error "refusing to import: bundle contains a symlink"
fi

# SELFTEST proves this machine's cksum agrees with the exporter's before
# INVENTORY is trusted at all -- macOS/Linux cksum agreement is assumed
# nowhere else in this script.
SELFTEST_EXPECTED=$(cksum <"$BUNDLE/SELFTEST" | awk '{ print $1, $2 }')
SELFTEST_RECORDED=$(cat "$BUNDLE/SELFTEST.cksum")
if [ "$SELFTEST_EXPECTED" != "$SELFTEST_RECORDED" ]; then
  usage_error "cksum disagreement on this machine (SELFTEST): expected [$SELFTEST_RECORDED] got [$SELFTEST_EXPECTED] -- refusing to trust INVENTORY"
fi

# Recompute cksum over every payload file (everything except the bundle's own
# metadata) and diff against INVENTORY. Payload paths are relative and must
# never be absolute or carry a ".." component -- refusing here is the
# path-traversal defense for a bundle that did not come from this repo's own
# claudart-backup.sh.
(cd "$BUNDLE" && find . -type f 2>/dev/null \
  ! -name MANIFEST.json ! -name INVENTORY ! -name MERGEPLAN ! -name PATHMAP \
  ! -name PATHMAP.files ! -name SELFTEST ! -name SELFTEST.cksum ! -name README.txt \
  ! -name SECRETS.txt -exec cksum {} \;) | sed -e 's| \./| |' | LC_ALL=C sort >"$TMP_DIR/recomputed-inventory"

grep -v -E ' (MANIFEST\.json|MERGEPLAN|PATHMAP|PATHMAP\.files|SELFTEST|SELFTEST\.cksum|README\.txt|SECRETS\.txt)$' \
  "$BUNDLE/INVENTORY" 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/declared-inventory"

while read -r icrc isize ipath; do
  [ -n "$ipath" ] || continue
  case "$ipath" in
    /* | *..*) usage_error "refusing to import: unsafe path in INVENTORY: $ipath" ;;
  esac
done <"$TMP_DIR/declared-inventory"

if ! diff -q "$TMP_DIR/declared-inventory" "$TMP_DIR/recomputed-inventory" >/dev/null 2>&1; then
  usage_error "bundle failed integrity check: recomputed cksums do not match INVENTORY"
fi

# ── pre-flight: manifest-derived policy checks ──────────────────────────────

manifest_field() {
  # Single-line "key": value|"value" extraction. MANIFEST.json is emitted by
  # claudart-backup.sh with one field per line by construction, so a grep+sed
  # slice is sufficient and this never needs a general JSON parser.
  grep -m1 "\"$1\":" "$BUNDLE/MANIFEST.json" 2>/dev/null |
    sed -e "s/.*\"$1\": *//" -e 's/^"//' -e 's/",\{0,1\}$//' -e 's/,$//'
}

MERGEPLAN=$BUNDLE/MERGEPLAN

BUNDLE_SCHEMA=$(manifest_field schema)
[ "$BUNDLE_SCHEMA" = "$SCHEMA" ] || usage_error "unsupported bundle schema: $BUNDLE_SCHEMA"

BUNDLE_MODE_SESSIONS=$(manifest_field sessions)
BUNDLE_MODE_HISTORY=$(manifest_field history)
BUNDLE_SOURCE_ROOT=$(manifest_field project_root)
BUNDLE_CLAUDE_HOME=$(manifest_field claude_home)
BUNDLE_MANGLED=$(manifest_field projects_dir)
BUNDLE_HOME=$(manifest_field home)

REWRITE_ORDER_ACTUAL=$(grep -m1 '"rewrite_order"' "$BUNDLE/MANIFEST.json" 2>/dev/null |
  sed -e 's/.*\[//' -e 's/\].*//' -e 's/"//g' -e 's/ //g')
if [ -n "$REWRITE_ORDER_ACTUAL" ] && [ "$REWRITE_ORDER_ACTUAL" != "$REWRITE_ORDER_EXPECTED" ]; then
  usage_error "bundle rewrite_order ($REWRITE_ORDER_ACTUAL) does not match this script's expectation ($REWRITE_ORDER_EXPECTED)"
fi

if [ "$MODE" = graft ]; then
  if [ "$BUNDLE_MODE_SESSIONS" != none ] || [ "$BUNDLE_MODE_HISTORY" != no ]; then
    usage_error "refusing: --mode graft cannot import a bundle carrying sessions or history"
  fi
fi

if [ -f "$BUNDLE/SECRETS.txt" ] && [ "$ALLOW_SECRETS" != true ]; then
  printf '%s: bundle SECRETS.txt reports findings; refusing without --allow-secrets:\n' "$PROGRAM" >&2
  cat "$BUNDLE/SECRETS.txt" >&2
  exit 1
fi

# ── pre-flight: target checks ────────────────────────────────────────────────

[ -d "$TARGET/.claude" ] || usage_error "target has no .claude -- restore merges into an existing CLAUDART project"

for s in '"' '\'; do
  for v in "$BUNDLE_SOURCE_ROOT" "$TARGET" "$BUNDLE_CLAUDE_HOME" "$CLAUDE_HOME_DEST"; do
    case "$v" in
      *"$s"*) usage_error "refusing: a source or target path contains a quote or backslash byte: $v" ;;
    esac
  done
done

case "$TARGET" in
  "$BUNDLE_SOURCE_ROOT") ;; # identity restore into the same project: fine
  "$BUNDLE_SOURCE_ROOT"*) usage_error "refusing: target ($TARGET) is nested under the bundle's source root ($BUNDLE_SOURCE_ROOT) -- ambiguous rewrite" ;;
esac
case "$BUNDLE_SOURCE_ROOT" in
  "$TARGET"*)
    if [ "$BUNDLE_SOURCE_ROOT" != "$TARGET" ]; then
      usage_error "refusing: bundle source root ($BUNDLE_SOURCE_ROOT) is nested under target ($TARGET) -- ambiguous rewrite"
    fi
    ;;
esac

if [ "$MODE" = full ] && [ "$BUNDLE_MODE_SESSIONS" != none ] || [ "$BUNDLE_MODE_HISTORY" = yes ]; then
  if command -v git >/dev/null 2>&1 && git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ] && [ "$ALLOW_DIRTY" != true ]; then
      usage_error "refusing: target git tree is dirty -- commit first or pass --allow-dirty"
    fi
  fi
fi

TARGET_MANGLED=$(printf '%s' "$TARGET" | tr '/' '-')

# ── destination token map ───────────────────────────────────────────────────

# One resolved raw target per source class. PROJECT_SUBPATH is resolved per
# row below (it needs the individual subpath suffix, not one fixed value).
target_for_class() {
  case "$1" in
    PROJECT_ROOT | ALIAS_ROOT) printf '%s' "$TARGET" ;;
    CLAUDE_HOME) printf '%s' "$CLAUDE_HOME_DEST" ;;
    HOME) printf '%s' "${HOME:-}" ;;
    *) printf '' ;;
  esac
}

# ── build the rewrite plan from PATHMAP ─────────────────────────────────────

REWRITE_PLAN=$TMP_DIR/rewrite-plan
: >"$REWRITE_PLAN"
SKIP_REPORT=$TMP_DIR/skip-report
: >"$SKIP_REPORT"
SENTINEL_N=0

while IFS="$SEP" read -r pclass ptok penc pocc pfc; do
  [ -n "$pclass" ] || continue
  case "$pclass" in
    FOREIGN)
      continue
      ;;
    HOME)
      if [ "$REWRITE_HOME" != true ]; then
        printf 'HOME (%s occurrence(s) across %s file(s)) left as-is; pass --rewrite-home to translate\n' "$pocc" "$pfc" >>"$SKIP_REPORT"
        continue
      fi
      if [ "$penc" != raw ]; then
        continue
      fi
      target_raw=$(target_for_class HOME)
      [ -n "$target_raw" ] || continue
      target_tok=$target_raw
      ;;
    PROJECTS_DIR)
      if [ "$penc" != mangled ]; then
        continue
      fi
      target_tok=$TARGET_MANGLED
      ;;
    CLAUDE_HOME)
      if [ "$penc" = tilde ]; then
        default_dest="${HOME:-}/.claude"
        if [ "$CLAUDE_HOME_DEST" = "$default_dest" ]; then
          continue # tilde still resolves correctly on the destination; no-op
        fi
        target_tok=$CLAUDE_HOME_DEST
      else
        raw_form=$(decode_path "$ptok" "$penc")
        [ -n "$raw_form" ] || continue
        target_tok=$(encode_path "$CLAUDE_HOME_DEST" "$penc")
      fi
      ;;
    PROJECT_ROOT | ALIAS_ROOT)
      case "$penc" in
        raw | uri | escaped | percent) ;;
        *) continue ;;
      esac
      target_raw=$(target_for_class "$pclass")
      target_tok=$(encode_path "$target_raw" "$penc")
      ;;
    PROJECT_SUBPATH)
      case "$penc" in
        raw | uri | escaped | percent) ;;
        *) continue ;;
      esac
      raw_form=$(decode_path "$ptok" "$penc")
      case "$raw_form" in
        "$BUNDLE_SOURCE_ROOT"/*)
          suffix=${raw_form#"$BUNDLE_SOURCE_ROOT"}
          target_raw="$TARGET$suffix"
          ;;
        "$BUNDLE_SOURCE_ROOT")
          target_raw=$TARGET
          ;;
        *)
          # Not actually a descendant once decoded (should not happen given
          # backup's own construction) -- skip rather than guess.
          continue
          ;;
      esac
      target_tok=$(encode_path "$target_raw" "$penc")
      ;;
    *)
      continue
      ;;
  esac

  [ "$ptok" != "$target_tok" ] || continue
  SENTINEL_N=$((SENTINEL_N + 1))
  sentinel=$(printf '\002CLAUDART-SENTINEL-%d\002' "$SENTINEL_N")
  rank=$(class_rank "$pclass")
  printf '%s%s%s%s%s%s%s%s%s\n' \
    "$rank" "$SEP" "$ptok" "$SEP" "$sentinel" "$SEP" "$target_tok" "$SEP" "$pclass" >>"$REWRITE_PLAN"
done <"$BUNDLE/PATHMAP"

# Longest-source-token-first within each rank, so a token that is itself a
# substring of another same-rank token never shadows the more specific one.
LC_ALL=C awk -F'\034' -v OFS='\034' '{ print length($2), $0 }' "$REWRITE_PLAN" |
  LC_ALL=C sort -t'\034' -k2,2n -k1,1nr |
  awk -F'\034' -v OFS='\034' '{ $1=""; sub(/^\034/,""); print }' >"$TMP_DIR/rewrite-plan-sorted"
mv "$TMP_DIR/rewrite-plan-sorted" "$REWRITE_PLAN"

PLAN_TOKEN_COUNT=$(wc -l <"$REWRITE_PLAN" | tr -d ' ')

# ── materialize: copy payload, then rewrite in place ────────────────────────

PAYLOAD_ROOT=$STAGE/payload
mkdir -p "$PAYLOAD_ROOT"
while read -r icrc isize ipath; do
  [ -n "$ipath" ] || continue
  srcf=$BUNDLE/$ipath
  dstf=$PAYLOAD_ROOT/$ipath
  mkdir -p "$(dirname -- "$dstf")" 2>/dev/null
  cp -- "$srcf" "$dstf" 2>/dev/null || usage_error "cannot stage bundle payload file: $ipath"
done <"$TMP_DIR/declared-inventory"

COUNTS=$TMP_DIR/replace-counts
: >"$COUNTS"

# Phase 1: replace each source token with its unique sentinel, longest token
# and most-specific class first (REWRITE_ORDER), boundary-anchored so a
# prefix collision (e.g. /w/demo-app inside /w/demo-app-backup) is left
# byte-identical. Sentinels are synthetic control-byte-wrapped markers that
# cannot appear in real path text, so scanning for the NEXT token after some
# sentinels are already inserted can never re-match already-replaced text --
# a single coordinated left-to-right-per-token pass is safe without needing
# to avoid revisiting output, unlike chained sed -e over the same buffer.
rewrite_phase1() {
  rp_file=$1
  PLANFILE="$REWRITE_PLAN" COUNTSFILE="$COUNTS" RELPATH="$2" awk -F'\034' '
    BEGIN {
      planfile = ENVIRON["PLANFILE"]
      n = 0
      while ((getline line < planfile) > 0) {
        split(line, f, "\034")
        n++
        rank[n] = f[1]; src[n] = f[2]; sen[n] = f[3]; tgt[n] = f[4]; cls[n] = f[5]
      }
      close(planfile)
      countsfile = ENVIRON["COUNTSFILE"]
      relpath = ENVIRON["RELPATH"]
    }
    function boundary_replace(str, token, sentinel,   result, pos, idx, tlen, mstart, nextchar, replaced) {
      result = ""; pos = 1; tlen = length(token); replaced = 0
      if (tlen == 0) return str
      while (pos <= length(str)) {
        idx = index(substr(str, pos), token)
        if (idx == 0) { result = result substr(str, pos); break }
        mstart = pos + idx - 1
        result = result substr(str, pos, idx - 1)
        nextchar = substr(str, mstart + tlen, 1)
        if (nextchar == "" || nextchar !~ /[A-Za-z0-9._-]/) {
          result = result sentinel
          pos = mstart + tlen
          replaced++
        } else {
          result = result substr(str, mstart, 1)
          pos = mstart + 1
        }
      }
      if (replaced > 0) printf "%s\034%s\034%d\n", relpath, token, replaced >> countsfile
      return result
    }
    {
      line = $0
      for (i = 1; i <= n; i++) line = boundary_replace(line, src[i], sen[i])
      print line
    }
  ' "$rp_file"
}

rewrite_phase2() {
  rp_file=$1
  PLANFILE="$REWRITE_PLAN" awk -F'\034' '
    BEGIN {
      planfile = ENVIRON["PLANFILE"]
      n = 0
      while ((getline line < planfile) > 0) {
        split(line, f, "\034")
        n++
        sen[n] = f[3]; tgt[n] = f[4]
      }
      close(planfile)
    }
    function literal_replace(str, from, to,   result, pos, idx, flen) {
      result = ""; pos = 1; flen = length(from)
      if (flen == 0) return str
      while (pos <= length(str)) {
        idx = index(substr(str, pos), from)
        if (idx == 0) { result = result substr(str, pos); break }
        result = result substr(str, pos, idx - 1) to
        pos = pos + idx - 1 + flen
      }
      return result
    }
    {
      line = $0
      for (i = 1; i <= n; i++) line = literal_replace(line, sen[i], tgt[i])
      print line
    }
  ' "$rp_file"
}

REWRITTEN_FILES=$TMP_DIR/rewritten-files
: >"$REWRITTEN_FILES"

if [ "$PLAN_TOKEN_COUNT" -gt 0 ]; then
  find "$PAYLOAD_ROOT" -type f 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/payload-files"
  while IFS= read -r pf; do
    [ -n "$pf" ] || continue
    prel=${pf#"$PAYLOAD_ROOT/"}
    tr '\000' '\001' <"$pf" >"$TMP_DIR/p1-in" 2>/dev/null
    rewrite_phase1 "$TMP_DIR/p1-in" "$prel" >"$TMP_DIR/p1-out"
    if ! cmp -s "$TMP_DIR/p1-in" "$TMP_DIR/p1-out"; then
      printf '%s\n' "$prel" >>"$REWRITTEN_FILES"
    fi
    rewrite_phase2 "$TMP_DIR/p1-out" >"$TMP_DIR/p2-out"
    tr '\001' '\000' <"$TMP_DIR/p2-out" >"$pf" 2>/dev/null
  done <"$TMP_DIR/payload-files"
fi

REWRITTEN_COUNT=$(wc -l <"$REWRITTEN_FILES" | tr -d ' ')

# ── verification 1: line-count parity + trailing newline ───────────────────

V1_OK=true
while read -r icrc isize ipath; do
  [ -n "$ipath" ] || continue
  before=$BUNDLE/$ipath
  after=$PAYLOAD_ROOT/$ipath
  bl=$(wc -l <"$before" | tr -d ' ')
  al=$(wc -l <"$after" | tr -d ' ')
  if [ "$bl" != "$al" ]; then
    V1_OK=false
    printf '%s: line count changed for %s: %s -> %s\n' "$PROGRAM" "$ipath" "$bl" "$al" >&2
  fi
  btail=$(tail -c1 "$before" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  atail=$(tail -c1 "$after" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  if [ "$btail" != "$atail" ]; then
    V1_OK=false
    printf '%s: trailing-newline state changed for %s\n' "$PROGRAM" "$ipath" >&2
  fi
done <"$TMP_DIR/declared-inventory"

# ── verification 2: identity multiset (DAG integrity) ───────────────────────

ID_FIELDS='"(uuid|parentUuid|sessionId|agentId|toolUseId|gitBranch|version|timestamp)":"[^"]*"'
: >"$TMP_DIR/ids-before"
: >"$TMP_DIR/ids-after"
find "$BUNDLE/user/sessions" -type f -name '*.jsonl' 2>/dev/null \
  -exec grep -aoh -E "$ID_FIELDS" {} + 2>/dev/null >>"$TMP_DIR/ids-before" || :
find "$PAYLOAD_ROOT/user/sessions" -type f -name '*.jsonl' 2>/dev/null \
  -exec grep -aoh -E "$ID_FIELDS" {} + 2>/dev/null >>"$TMP_DIR/ids-after" || :
LC_ALL=C sort "$TMP_DIR/ids-before" >"$TMP_DIR/ids-before-sorted"
LC_ALL=C sort "$TMP_DIR/ids-after" >"$TMP_DIR/ids-after-sorted"
V2_OK=true
if ! diff -q "$TMP_DIR/ids-before-sorted" "$TMP_DIR/ids-after-sorted" >/dev/null 2>&1; then
  V2_OK=false
  printf '%s: identity multiset (uuid/parentUuid/sessionId/...) changed by the rewrite\n' "$PROGRAM" >&2
fi

# ── verification 3: byte arithmetic ──────────────────────────────────────────

BYTES_BEFORE=$(awk '{ t += $2 } END { printf "%d", t + 0 }' "$TMP_DIR/declared-inventory")
BYTES_AFTER=0
while read -r icrc isize ipath; do
  [ -n "$ipath" ] || continue
  sz=$(wc -c <"$PAYLOAD_ROOT/$ipath" | tr -d ' ')
  BYTES_AFTER=$((BYTES_AFTER + sz))
done <"$TMP_DIR/declared-inventory"

DELTA_EXPECTED=0
if [ -s "$COUNTS" ]; then
  DELTA_EXPECTED=$(
    PLANFILE="$REWRITE_PLAN" awk -F'\034' '
      BEGIN {
        planfile = ENVIRON["PLANFILE"]
        while ((getline line < planfile) > 0) {
          split(line, f, "\034")
          d[f[2]] = length(f[4]) - length(f[2])
        }
        close(planfile)
      }
      { total += d[$2] * $3 }
      END { printf "%d", total + 0 }
    ' "$COUNTS"
  )
fi
BYTES_EXPECTED=$((BYTES_BEFORE + DELTA_EXPECTED))
V3_OK=true
if [ "$BYTES_AFTER" != "$BYTES_EXPECTED" ]; then
  V3_OK=false
  printf '%s: byte arithmetic mismatch: expected %s, got %s\n' "$PROGRAM" "$BYTES_EXPECTED" "$BYTES_AFTER" >&2
fi

# ── verification 4: boundary correctness (independent, two-sided) ──────────
# Pre-flight already refused any target/source pattern-aliasing (T contains S
# or vice versa), so this only needs to prove the boundary rule was honored.
#
# Comparing against the rewrite loop's own "replaced" counters is not proof:
# a count recorded by the same code that does the replacing only shows the
# loop agrees with itself, and cannot catch a bug in its own boundary logic
# (measured: a boundary-check mutant that replaces every occurrence,
# including inside a "-backup" suffix, still reports a self-consistent
# count). Comparing raw per-token occurrence totals against PATHMAP is also
# unsound here, because a shorter token's raw text can be legitimately
# consumed as a substring of a longer, differently-encoded sibling token
# processed earlier in REWRITE_ORDER (e.g. the raw form of PROJECT_ROOT is a
# substring of its own "uri" encoding) -- that is correct nesting, not a
# defect, and an arithmetic check keyed only on one token's own count cannot
# tell the two apart.
#
# So this checks the actual guarantee directly, from both directions, using
# a differently-implemented grep -E boundary lookahead (not the rewrite's
# own awk substr scanner) as the independent method:
#   4a. no boundary-PASSING occurrence of any source token remains anywhere
#       in the rewritten output (catches under-replacement / leftovers).
#   4b. every boundary-FAILING occurrence's literal fingerprint (token plus
#       its disallowed next byte) from the original still occurs, with the
#       same total count, in the rewritten output (catches over-replacement
#       -- exactly the prefix-hazard corruption a boundary-check bug causes).

V4_OK=true
if [ "$PLAN_TOKEN_COUNT" -gt 0 ]; then
  find "$PAYLOAD_ROOT" -type f 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/v4-out-files"
  while IFS="$SEP" read -r rank srctok sentinel tgttok cls; do
    [ -n "$srctok" ] || continue
    esc=$(regex_escape "$srctok")

    leftover=0
    while IFS= read -r pf; do
      [ -n "$pf" ] || continue
      n=$(grep -aoE -- "${esc}([^A-Za-z0-9._-]|\$)" "$pf" 2>/dev/null | wc -l | tr -d ' ')
      leftover=$((leftover + n))
    done <"$TMP_DIR/v4-out-files"
    if [ "$leftover" -gt 0 ]; then
      V4_OK=false
      printf '%s: verification 4a failed for token class %s: %s boundary-passing occurrence(s) left untranslated\n' \
        "$PROGRAM" "$cls" "$leftover" >&2
    fi

    : >"$TMP_DIR/v4-fingerprints"
    while read -r icrc isize ipath; do
      [ -n "$ipath" ] || continue
      grep -aoE -- "${esc}[A-Za-z0-9._-]" "$BUNDLE/$ipath" 2>/dev/null >>"$TMP_DIR/v4-fingerprints"
    done <"$TMP_DIR/declared-inventory"
    if [ -s "$TMP_DIR/v4-fingerprints" ]; then
      LC_ALL=C sort "$TMP_DIR/v4-fingerprints" | uniq -c >"$TMP_DIR/v4-fp-counts"
      while read -r fpcount fp; do
        [ -n "$fp" ] || continue
        after=0
        while IFS= read -r pf; do
          [ -n "$pf" ] || continue
          n=$(grep -aoF -e "$fp" -- "$pf" 2>/dev/null | wc -l | tr -d ' ')
          after=$((after + n))
        done <"$TMP_DIR/v4-out-files"
        if [ "$after" != "$fpcount" ]; then
          V4_OK=false
          printf '%s: verification 4b failed for token class %s: boundary-failing fingerprint "%s" occurred %s time(s) originally, %s time(s) after rewrite\n' \
            "$PROGRAM" "$cls" "$fp" "$fpcount" "$after" >&2
        fi
      done <"$TMP_DIR/v4-fp-counts"
    fi
  done <"$REWRITE_PLAN"
fi

# ── verification 5: structural JSON check on rewritten .jsonl files ─────────
# Structural, not full grammar: tracks brace depth and string/escape state
# per line and asserts depth returns to 0 with quotes balanced and no raw
# control byte inside a string. Sufficient because literal substitution of
# safe-set characters can only alter string interiors; anything that breaks
# JSON grammar breaks quote balance or depth first.

V5_OK=true
find "$PAYLOAD_ROOT" -type f -name '*.jsonl' 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/jsonl-files"
while IFS= read -r jf; do
  [ -n "$jf" ] || continue
  if ! awk '
    {
      depth = 0; in_str = 0; esc = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (esc) { esc = 0; continue }
        if (in_str) {
          if (c == "\\") { esc = 1; continue }
          if (c == "\"") { in_str = 0; continue }
          b = index("\001\002\003\004\005\006\007\010\013\014\016\017", c)
          if (b > 0) { print "control-byte-in-string:" NR; exit 1 }
          continue
        }
        if (c == "\"") { in_str = 1; continue }
        if (c == "{" || c == "[") depth++
        else if (c == "}" || c == "]") depth--
      }
      if (in_str) { print "unterminated-string:" NR; exit 1 }
      if (depth != 0) { print "unbalanced-braces:" NR; exit 1 }
    }
    END { exit 0 }
  ' "$jf" >"$TMP_DIR/jsoncheck-out" 2>&1; then
    V5_OK=false
    printf '%s: structural JSON check failed for %s: %s\n' "$PROGRAM" "${jf#"$PAYLOAD_ROOT/"}" "$(cat "$TMP_DIR/jsoncheck-out")" >&2
  fi
done <"$TMP_DIR/jsonl-files"

# ── merge classes: shared helpers ───────────────────────────────────────────
# CUR_DEST_ROOT is set once per apply_project_merge() call rather than
# threaded through every helper -- Bash 3.2 has no `local`, and this repo's
# style (see claudart-backup.sh) already prefers shared script-scope state
# with prefixed variable names over parameter-threading for this reason.

MERGE_LOG=$TMP_DIR/merge-log
: >"$MERGE_LOG"
log_action() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$MERGE_LOG"
}

BUNDLE_ID_VAL=$(manifest_field bundle_id)
CUR_DEST_ROOT=

frontmatter_field() {
  ff_file=$1
  ff_key=$2
  awk -v key="$ff_key" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && $0 ~ "^" key ":[[:space:]]" {
      sub("^" key ":[[:space:]]*", "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$ff_file" 2>/dev/null
}

title_case() {
  printf '%s' "$1" | awk -F'-' '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2); print }' OFS=' '
}

sidecar_path() {
  sp_dst=$1
  sp_dir=$(dirname -- "$sp_dst")
  sp_base=$(basename -- "$sp_dst")
  case "$sp_base" in
    *.*) sp_ext=".${sp_base##*.}"; sp_stem=${sp_base%.*} ;;
    *) sp_ext=""; sp_stem=$sp_base ;;
  esac
  printf '%s/%s-imported-%s%s' "$sp_dir" "$sp_stem" "$BUNDLE_ID_VAL" "$sp_ext"
}

write_new() {
  wn_src=$1
  wn_dst=$2
  wn_sub=$3
  wn_label=$4
  mkdir -p "$(dirname -- "$wn_dst")" 2>/dev/null
  cp -- "$wn_src" "$wn_dst"
  log_action "$wn_label" "$wn_sub" "new"
}

take_backup() {
  tb_dst=$1
  tb_sub=$2
  [ -n "${BACKUPS_DIR:-}" ] || return 0
  [ -f "$tb_dst" ] || return 0
  tb_bak=$BACKUPS_DIR/$tb_sub
  mkdir -p "$(dirname -- "$tb_bak")" 2>/dev/null
  cp -- "$tb_dst" "$tb_bak"
}

# Never-merge-never-overwrite family (sectioned / singleton-state / template
# classes): place if absent, no-op if byte-identical, otherwise a
# deterministic sidecar -- never touches the original.
merge_no_touch_sidecar() {
  mts_src=$1
  mts_dst=$2
  mts_backup=$3
  mts_sub=$4
  if [ ! -f "$mts_dst" ]; then
    write_new "$mts_src" "$mts_dst" "$mts_sub" placed
    return 0
  fi
  if cmp -s "$mts_src" "$mts_dst"; then
    log_action noop "$mts_sub" "already identical"
    return 0
  fi
  mts_sc=$(sidecar_path "$mts_dst")
  if [ -f "$mts_sc" ]; then
    if cmp -s "$mts_src" "$mts_sc"; then
      log_action noop "$mts_sub" "sidecar already present"
    else
      log_action anomaly "$mts_sub" "sidecar path exists with different content -- not touched: $mts_sc"
    fi
    return 0
  fi
  mkdir -p "$(dirname -- "$mts_sc")" 2>/dev/null
  cp -- "$mts_src" "$mts_sc"
  log_action sidecar "$mts_sub" "$(basename -- "$mts_sc")"
}

# ── union-route: knowledge/INDEX.md and _maps/*.md line-union ──────────────

is_routed_anywhere() {
  ira_dir=$1
  ira_tgt=$2
  ira_needle="]($ira_tgt)"
  case "$ira_dir" in
    */_maps) ira_kdir=$(dirname -- "$ira_dir") ;;
    *) ira_kdir=$ira_dir ;;
  esac
  if [ -f "$ira_kdir/INDEX.md" ] && grep -qF -- "$ira_needle" "$ira_kdir/INDEX.md" 2>/dev/null; then
    return 0
  fi
  if [ -d "$ira_kdir/_maps" ]; then
    find "$ira_kdir/_maps" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/ira-maps"
    while IFS= read -r ira_m; do
      [ -n "$ira_m" ] || continue
      grep -qF -- "$ira_needle" "$ira_m" 2>/dev/null && return 0
    done <"$TMP_DIR/ira-maps"
  fi
  return 1
}

# Appends lines from $2 into $1, replacing a lone "- _(none)_" placeholder if
# present, else inserting immediately after the last existing "- [" route
# line so curated ordering, grouping, and comments are never disturbed.
append_route_lines_to() {
  arlt_dst=$1
  arlt_new=$2
  [ -s "$arlt_new" ] || return 0
  if grep -qF -- '- _(none)_' "$arlt_dst" 2>/dev/null; then
    NEWF="$arlt_new" awk '
      /^- _\(none\)_$/ { while ((getline line < ENVIRON["NEWF"]) > 0) print line; next }
      { print }
    ' "$arlt_dst" >"$arlt_dst.new" && mv "$arlt_dst.new" "$arlt_dst"
    return 0
  fi
  arlt_lastline=$(grep -n '^- \[' "$arlt_dst" 2>/dev/null | tail -1 | cut -d: -f1)
  if [ -n "$arlt_lastline" ]; then
    LN="$arlt_lastline" NEWF="$arlt_new" awk '
      { print }
      NR == ENVIRON["LN"] + 0 { while ((getline line < ENVIRON["NEWF"]) > 0) print line }
    ' "$arlt_dst" >"$arlt_dst.new" && mv "$arlt_dst.new" "$arlt_dst"
  else
    cat "$arlt_new" >>"$arlt_dst"
  fi
}

merge_route() {
  mr_src=$1
  mr_dst=$2
  mr_backup=$3
  mr_sub=$4
  if [ ! -f "$mr_dst" ]; then
    write_new "$mr_src" "$mr_dst" "$mr_sub" route-init
    return 0
  fi
  if cmp -s "$mr_src" "$mr_dst"; then
    log_action noop "$mr_sub" "already identical"
    return 0
  fi
  : >"$TMP_DIR/route-newlines"
  while IFS= read -r mr_line; do
    case "$mr_line" in
      "- ["*)
        mr_tgt=$(printf '%s' "$mr_line" | sed -n 's/^- \[[^]]*\](\([^)]*\)).*/\1/p')
        [ -n "$mr_tgt" ] || continue
        if is_routed_anywhere "$(dirname -- "$mr_dst")" "$mr_tgt"; then
          log_action skip-k205 "$mr_sub" "already routed: $mr_tgt"
        else
          printf '%s\n' "$mr_line" >>"$TMP_DIR/route-newlines"
        fi
        ;;
    esac
  done <"$mr_src"
  if [ ! -s "$TMP_DIR/route-newlines" ]; then
    log_action noop "$mr_sub" "no new routes"
    return 0
  fi
  [ "$mr_backup" = true ] && take_backup "$mr_dst" "$mr_sub"
  append_route_lines_to "$mr_dst" "$TMP_DIR/route-newlines"
  log_action union-route "$mr_sub" "$(wc -l <"$TMP_DIR/route-newlines" | tr -d ' ') new route(s)"
}

# ── keyed-unit: knowledge/<topic>.md and memory/<slug>.md ───────────────────

find_keyed_target() {
  fk_dir=$1
  fk_key=$2
  fk_result=
  [ -d "$fk_dir" ] || { printf ''; return 0; }
  find "$fk_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/fk-candidates"
  while IFS= read -r fk_f; do
    [ -n "$fk_f" ] || continue
    fk_name=$(frontmatter_field "$fk_f" name)
    [ -n "$fk_name" ] || fk_name=$(basename -- "$fk_f" .md)
    if [ "$fk_name" = "$fk_key" ]; then
      fk_result=$fk_f
      break
    fi
  done <"$TMP_DIR/fk-candidates"
  printf '%s' "$fk_result"
}

# Copy + the three mechanical frontmatter transforms for a newly grafted
# knowledge topic: status -> review-needed with a status_note, drop
# last_verified (no longer meaningful once not active), and prune sources:/
# related:/supersedes: list items that do not resolve under the destination
# root (kills knowledge-check K131/K141 rather than shipping a topic that
# fails the checker on arrival).
prune_knowledge_frontmatter() {
  pk_src=$1
  pk_dst=$2
  pk_destroot=$3
  pk_nameoverride=${4:-}
  DESTROOT="$pk_destroot" BUNDLEID="$BUNDLE_ID_VAL" NAMEOVERRIDE="$pk_nameoverride" awk '
    function flush_list() {
      if (cur_key != "" && nbuf > 0) {
        print cur_key ":"
        for (i = 1; i <= nbuf; i++) print "  - \"" buf[i] "\""
      }
      cur_key = ""; nbuf = 0
    }
    BEGIN {
      destroot = ENVIRON["DESTROOT"]; bundleid = ENVIRON["BUNDLEID"]; nameoverride = ENVIRON["NAMEOVERRIDE"]
      in_fm = 0; cur_key = ""; nbuf = 0; status_written = 0; note_written = 0
    }
    NR == 1 && $0 != "---" { print; in_fm = -1; next }
    in_fm == -1 { print; next }
    NR == 1 && $0 == "---" { in_fm = 1; print; next }
    in_fm == 1 && $0 == "---" {
      flush_list()
      if (!status_written) print "status: review-needed"
      if (!note_written) print "status_note: \"graft-imported via /restore (bundle " bundleid "); verify before treating as active\""
      print
      in_fm = 0
      next
    }
    in_fm == 1 && nameoverride != "" && /^name:[[:space:]]/ { print "name: " nameoverride; next }
    in_fm == 1 && /^status:[[:space:]]/ { flush_list(); print "status: review-needed"; status_written = 1; next }
    in_fm == 1 && /^status_note:[[:space:]]/ {
      flush_list()
      print "status_note: \"graft-imported via /restore (bundle " bundleid "); verify before treating as active\""
      note_written = 1
      next
    }
    in_fm == 1 && /^last_verified:[[:space:]]/ { flush_list(); next }
    in_fm == 1 && /^(sources|related|supersedes):[[:space:]]*$/ { flush_list(); cur_key = $0; sub(/:.*/, "", cur_key); next }
    in_fm == 1 && cur_key != "" && /^  - "/ {
      val = $0; sub(/^  - "/, "", val); sub(/"[[:space:]]*$/, "", val)
      keep = 0
      if (cur_key == "sources") {
        p = val
        sub(/^path:/, "", p)
        if (p != val) {
          if (system("test -e \"" destroot "/" p "\" 2>/dev/null") == 0) keep = 1
        } else {
          keep = 1
        }
      } else {
        typ = val; slug = val
        sub(/:.*/, "", typ); sub(/^[a-z]+:/, "", slug)
        if (typ == "knowledge") {
          if (system("test -f \"" destroot "/.claude/knowledge/" slug ".md\" 2>/dev/null || test -f \"" destroot "/.codex/knowledge/" slug ".md\" 2>/dev/null") == 0) keep = 1
        } else if (typ == "rule") {
          if (system("test -f \"" destroot "/.claude/rules/" slug ".md\" 2>/dev/null || test -f \"" destroot "/.codex/guidelines/" slug ".md\" 2>/dev/null") == 0) keep = 1
        } else {
          keep = 1
        }
      }
      if (keep) { nbuf++; buf[nbuf] = val }
      next
    }
    in_fm == 1 { flush_list(); print; next }
    { print }
  ' "$pk_src" >"$pk_dst"
}

route_new_topic() {
  rnt_file=$1
  rnt_kdir=$2
  rnt_index=$rnt_kdir/INDEX.md
  rnt_rel=$(basename -- "$rnt_file")
  rnt_title=$(title_case "$(basename -- "$rnt_file" .md)")
  rnt_desc=$(frontmatter_field "$rnt_file" description)
  [ -n "$rnt_desc" ] || rnt_desc="graft-imported topic"
  rnt_type=$(frontmatter_field "$rnt_file" type)
  [ -n "$rnt_type" ] || rnt_type=reference
  rnt_line="- [${rnt_title}](${rnt_rel}) — ${rnt_desc} · ${rnt_type} · review-needed"
  if [ ! -f "$rnt_index" ]; then
    {
      printf '<!-- knowledge/INDEX.md -- root router for durable descriptive knowledge. -->\n\n'
      printf '# Project Knowledge\n\n## Knowledge\n\n'
      printf '%s\n' "$rnt_line"
    } >"$rnt_index"
    return 0
  fi
  is_routed_anywhere "$rnt_kdir" "$rnt_rel" && return 0
  printf '%s\n' "$rnt_line" >"$TMP_DIR/route-single"
  append_route_lines_to "$rnt_index" "$TMP_DIR/route-single"
}

route_memory_entry() {
  rme_file=$1
  rme_memdir=$2
  rme_memory=$rme_memdir/MEMORY.md
  [ -f "$rme_memory" ] || return 0
  rme_rel=$(basename -- "$rme_file")
  rme_needle="]($rme_rel)"
  grep -qF -- "$rme_needle" "$rme_memory" 2>/dev/null && return 0
  rme_title=$(title_case "$(basename -- "$rme_file" .md)")
  rme_desc=$(frontmatter_field "$rme_file" description)
  [ -n "$rme_desc" ] || rme_desc="graft-imported memory"
  printf '- [%s](%s) — %s\n' "$rme_title" "$rme_rel" "$rme_desc" >"$TMP_DIR/mem-route-single"
  append_route_lines_to "$rme_memory" "$TMP_DIR/mem-route-single"
}

merge_keyed_unit() {
  mk2_src=$1
  mk2_dst=$2
  mk2_backup=$3
  mk2_sub=$4
  mk2_key=$5
  mk2_dir=$(dirname -- "$mk2_dst")
  mk2_subtype=generic
  case "$mk2_sub" in
    */knowledge/*) mk2_subtype=knowledge ;;
    */memory/*) mk2_subtype=memory ;;
  esac

  # Compare/place using the file's TRANSFORMED bytes, not the raw graft
  # source. A knowledge topic's destination copy has already been through
  # the review-needed transform (from an earlier restore run); comparing the
  # untransformed source against it would never match, so every re-run would
  # wrongly treat an already-applied graft as a fresh collision.
  mk2_effective=$TMP_DIR/mk2-effective
  if [ "$mk2_subtype" = knowledge ]; then
    prune_knowledge_frontmatter "$mk2_src" "$mk2_effective" "$CUR_DEST_ROOT"
  else
    cp -- "$mk2_src" "$mk2_effective"
  fi

  mk2_match=$(find_keyed_target "$mk2_dir" "$mk2_key")
  if [ -z "$mk2_match" ]; then
    mkdir -p "$mk2_dir" 2>/dev/null
    cp -- "$mk2_effective" "$mk2_dst"
    case "$mk2_subtype" in
      knowledge)
        log_action graft-review-needed "$mk2_sub" "key=$mk2_key"
        route_new_topic "$mk2_dst" "$mk2_dir"
        ;;
      memory)
        log_action memory-graft "$mk2_sub" "key=$mk2_key"
        route_memory_entry "$mk2_dst" "$mk2_dir" "$mk2_key"
        ;;
      *) log_action placed "$mk2_sub" new ;;
    esac
    return 0
  fi
  if cmp -s "$mk2_effective" "$mk2_match"; then
    log_action noop "$mk2_sub" "already identical (key=$mk2_key)"
    return 0
  fi
  mk2_sc=$(sidecar_path "$mk2_dst")
  mk2_sc_effective=$TMP_DIR/mk2-sc-effective
  if [ "$mk2_subtype" = knowledge ]; then
    # Sidecared and unrouted, so it must land as review-needed too -- an
    # unrouted "active" topic is a K205 error, not the tolerable K206 warn
    # the plan's sidecar convention assumes.
    mk2_newname=$(basename -- "$mk2_sc" .md)
    prune_knowledge_frontmatter "$mk2_src" "$mk2_sc_effective" "$CUR_DEST_ROOT" "$mk2_newname"
  else
    cp -- "$mk2_effective" "$mk2_sc_effective"
  fi
  if [ -f "$mk2_sc" ]; then
    if cmp -s "$mk2_sc_effective" "$mk2_sc"; then
      log_action noop "$mk2_sub" "sidecar already present"
    else
      log_action anomaly "$mk2_sub" "sidecar exists with different content"
    fi
    return 0
  fi
  mkdir -p "$(dirname -- "$mk2_sc")" 2>/dev/null
  cp -- "$mk2_sc_effective" "$mk2_sc"
  log_action sidecar "$mk2_sub" "$(basename -- "$mk2_sc") (key collision: $mk2_key)"
}

# ── unique: tasks/, specs/, sessions/ ────────────────────────────────────────

merge_task_file() {
  mtf_src=$1
  mtf_sub=$2
  mtf_dstdir=$(dirname -- "$CUR_DEST_ROOT/$mtf_sub")
  mtf_base=$(basename -- "$mtf_sub" .md)
  mtf_date=$(printf '%s' "$mtf_base" | sed -n 's/^\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)-.*/\1/p')
  mtf_slug=$(printf '%s' "$mtf_base" | sed -n 's/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9]-//p')
  if [ -z "$mtf_date" ] || [ -z "$mtf_slug" ]; then
    # Doesn't match the YYYY-MM-DD-NNN-slug convention (unexpected) -- place
    # verbatim rather than guess at a rename.
    if [ -f "$CUR_DEST_ROOT/$mtf_sub" ]; then
      cmp -s "$mtf_src" "$CUR_DEST_ROOT/$mtf_sub" && log_action noop "$mtf_sub" "already present" ||
        log_action anomaly "$mtf_sub" "unexpected task filename collision -- not overwriting"
    else
      write_new "$mtf_src" "$CUR_DEST_ROOT/$mtf_sub" "$mtf_sub" placed
    fi
    return 0
  fi
  mtf_existing=$(find "$mtf_dstdir" -maxdepth 1 -type f -name "${mtf_date}-*-${mtf_slug}.md" 2>/dev/null | LC_ALL=C sort | head -1)
  if [ -n "$mtf_existing" ]; then
    if cmp -s "$mtf_src" "$mtf_existing"; then
      log_action noop "$mtf_sub" "already imported as $(basename -- "$mtf_existing")"
    else
      log_action anomaly "$mtf_sub" "same date+slug already exists at $(basename -- "$mtf_existing") with different content -- not overwriting"
    fi
    return 0
  fi
  mtf_max=0
  find "$mtf_dstdir" -maxdepth 1 -type f -name "${mtf_date}-*.md" 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/task-nnn-candidates"
  while IFS= read -r mtf_f; do
    [ -n "$mtf_f" ] || continue
    mtf_nnn=$(basename -- "$mtf_f" .md | sed -n "s/^${mtf_date}-\([0-9][0-9][0-9]\)-.*/\1/p")
    [ -n "$mtf_nnn" ] || continue
    mtf_nnn=$((10#$mtf_nnn))
    [ "$mtf_nnn" -gt "$mtf_max" ] && mtf_max=$mtf_nnn
  done <"$TMP_DIR/task-nnn-candidates"
  mtf_newnnn=$(printf '%03d' $((mtf_max + 1)))
  mtf_newname="${mtf_date}-${mtf_newnnn}-${mtf_slug}.md"
  write_new "$mtf_src" "$mtf_dstdir/$mtf_newname" "$mtf_sub" "renumbered to $mtf_newname"
}

merge_spec_file() {
  msf_src=$1
  msf_sub=$2
  case "$msf_sub" in
    */specs/INDEX.md) return 0 ;; # derived-index, handled separately
  esac
  msf_specsdir=$(printf '%s' "$msf_sub" | sed -n 's#\(.*specs\)/.*#\1#p')
  msf_rest=${msf_sub#*specs/}
  msf_srcfolder=${msf_rest%%/*}
  case "$msf_srcfolder" in
    done)
      msf_specsdir="$msf_specsdir/done"
      msf_rest=${msf_rest#done/}
      msf_srcfolder=${msf_rest%%/*}
      ;;
  esac
  msf_tail=${msf_rest#"$msf_srcfolder"/}
  msf_key="$msf_specsdir${SEP}$msf_srcfolder"
  msf_dest=$(awk -F"$SEP" -v k="$msf_key" '$1==k{print $2; exit}' "$TMP_DIR/spec-folder-map" 2>/dev/null)
  if [ -z "$msf_dest" ]; then
    if [ ! -d "$CUR_DEST_ROOT/$msf_specsdir/$msf_srcfolder" ]; then
      msf_dest=$msf_srcfolder
    else
      msf_date=$(printf '%s' "$msf_srcfolder" | sed -n 's/^\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)-.*/\1/p')
      msf_slug=$(printf '%s' "$msf_srcfolder" | sed -n 's/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-//p')
      msf_dest="${msf_date}-${msf_slug}-imported-${BUNDLE_ID_VAL}"
    fi
    printf '%s%s%s\n' "$msf_key" "$SEP" "$msf_dest" >>"$TMP_DIR/spec-folder-map"
  fi
  msf_dstfile=$CUR_DEST_ROOT/$msf_specsdir/$msf_dest/$msf_tail
  if [ -f "$msf_dstfile" ]; then
    if cmp -s "$msf_src" "$msf_dstfile"; then
      log_action noop "$msf_sub" "already present under $msf_dest"
    else
      log_action anomaly "$msf_sub" "unexpected collision under $msf_dest -- not overwriting"
    fi
    return 0
  fi
  mkdir -p "$(dirname -- "$msf_dstfile")" 2>/dev/null
  if [ "$msf_tail" = SPEC.md ] && [ "$msf_dest" != "$msf_srcfolder" ]; then
    NEWSLUG=${msf_dest%"-imported-${BUNDLE_ID_VAL}"} awk '
      NR == 1 && $0 != "---" { print; in_fm = -1; next }
      in_fm == -1 { print; next }
      NR == 1 { print; in_fm = 1; next }
      in_fm == 1 && $0 == "---" { print; in_fm = 0; next }
      in_fm == 1 && /^slug:[[:space:]]/ {
        n = ENVIRON["NEWSLUG"]
        sub(/^[0-9]{4}-[0-9]{2}-[0-9]{2}-/, "", n)
        print "slug: " n
        next
      }
      { print }
    ' "$msf_src" >"$msf_dstfile"
    log_action renamed-spec "$msf_sub" "-> $msf_dest/$msf_tail (slug patched)"
  else
    cp -- "$msf_src" "$msf_dstfile"
    log_action placed "$msf_sub" "-> $msf_dest/$msf_tail"
  fi
}

merge_session_file() {
  msf2_src=$1
  msf2_dst=$2
  msf2_sub=$3
  if [ -f "$msf2_dst" ]; then
    if cmp -s "$msf2_src" "$msf2_dst"; then
      log_action noop "$msf2_sub" "identical session data already present"
    else
      msf2_park="$CONFLICTS_DIR/$msf2_sub"
      mkdir -p "$(dirname -- "$msf2_park")" 2>/dev/null
      cp -- "$msf2_src" "$msf2_park"
      log_action conflict-parked "$msf2_sub" "divergent session DAG -- incoming version parked at .claude/.portability/conflicts/$COMMIT_EPOCH/$msf2_sub, target's own copy untouched"
    fi
    return 0
  fi
  write_new "$msf2_src" "$msf2_dst" "$msf2_sub" placed
}

merge_unique() {
  mu_src=$1
  mu_dst=$2
  mu_backup=$3
  mu_sub=$4
  case "$mu_sub" in
    */tasks/*) merge_task_file "$mu_src" "$mu_sub" ;;
    */specs/*) merge_spec_file "$mu_src" "$mu_sub" ;;
    *)
      if [ -f "$mu_dst" ]; then
        if cmp -s "$mu_src" "$mu_dst"; then
          log_action noop "$mu_sub" "already present"
        else
          log_action anomaly "$mu_sub" "unique path collision with different content -- not overwriting"
        fi
      else
        write_new "$mu_src" "$mu_dst" "$mu_sub" placed
      fi
      ;;
  esac
}

# ── union-log: JOURNAL.md, history.jsonl, .portability/ledger.tsv ──────────

split_journal_header() {
  sjh_file=$1
  sjh_header=$2
  sjh_body=$3
  HF="$sjh_header" BF="$sjh_body" awk '
    BEGIN { done = 0 }
    !done { print > ENVIRON["HF"]; if ($0 == "---") done = 1; next }
    { print > ENVIRON["BF"] }
  ' "$sjh_file"
  [ -f "$sjh_header" ] || : >"$sjh_header"
  [ -f "$sjh_body" ] || : >"$sjh_body"
}

merge_journal_file() {
  mj_src=$1
  mj_dst=$2
  mj_backup=$3
  mj_sub=$4
  if [ ! -f "$mj_dst" ]; then
    write_new "$mj_src" "$mj_dst" "$mj_sub" placed
    return 0
  fi
  split_journal_header "$mj_dst" "$TMP_DIR/jh-t-header" "$TMP_DIR/jh-t-body"
  split_journal_header "$mj_src" "$TMP_DIR/jh-i-header" "$TMP_DIR/jh-i-body"
  awk '
    BEGIN { seq = 0; lastdate = "0000-00-00" }
    {
      seq++
      if ($0 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] /) lastdate = substr($0, 1, 10)
      printf "%s\034%05d\034%s\n", lastdate, seq, $0
    }
  ' "$TMP_DIR/jh-t-body" "$TMP_DIR/jh-i-body" >"$TMP_DIR/jh-decorated"
  LC_ALL=C sort -t"$SEP" -k1,1 -k2,2 "$TMP_DIR/jh-decorated" >"$TMP_DIR/jh-sorted"
  awk -F'\034' '{ line = $0; sub(/^[^\034]*\034[^\034]*\034/, "", line); if (!seen[line]++) print line }' \
    "$TMP_DIR/jh-sorted" >"$TMP_DIR/jh-final-body"
  cat "$TMP_DIR/jh-t-header" "$TMP_DIR/jh-final-body" >"$TMP_DIR/jh-final"
  if cmp -s "$TMP_DIR/jh-final" "$mj_dst"; then
    log_action noop "$mj_sub" "no new entries"
    return 0
  fi
  [ "$mj_backup" = true ] && take_backup "$mj_dst" "$mj_sub"
  cp -- "$TMP_DIR/jh-final" "$mj_dst"
  log_action union-log "$mj_sub" "journal merged (header preserved, chronological, deduped)"
}

merge_history_file() {
  mh_src=$1
  mh_dst=$2
  mh_backup=$3
  mh_sub=$4
  if [ ! -f "$mh_dst" ]; then
    write_new "$mh_src" "$mh_dst" "$mh_sub" placed
    return 0
  fi
  awk -F'"timestamp":|"sessionId":"' '
    { ts = $2; sub(/,.*/, "", ts); sid = $3; sub(/".*/, "", sid); print ts "\034" sid }
  ' "$mh_dst" >"$TMP_DIR/hist-target-keys"
  : >"$TMP_DIR/hist-to-append"
  while IFS= read -r mh_line; do
    [ -n "$mh_line" ] || continue
    mh_ts=$(printf '%s' "$mh_line" | sed -n 's/.*"timestamp":\([0-9]*\).*/\1/p')
    mh_sid=$(printf '%s' "$mh_line" | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')
    mh_key=$(printf '%s\034%s' "$mh_ts" "$mh_sid")
    grep -aFxq -- "$mh_key" "$TMP_DIR/hist-target-keys" 2>/dev/null || printf '%s\n' "$mh_line" >>"$TMP_DIR/hist-to-append"
  done <"$mh_src"
  if [ ! -s "$TMP_DIR/hist-to-append" ]; then
    log_action noop "$mh_sub" "no new entries"
    return 0
  fi
  [ "$mh_backup" = true ] && take_backup "$mh_dst" "$mh_sub"
  cat "$TMP_DIR/hist-to-append" >>"$mh_dst"
  log_action union-log "$mh_sub" "$(wc -l <"$TMP_DIR/hist-to-append" | tr -d ' ') new line(s) appended"
}

merge_ledger_file() {
  ml_src=$1
  ml_dst=$2
  ml_backup=$3
  ml_sub=$4
  case "$ml_sub" in
    */conflicts/*) return 0 ;; # backup already denies these; defensive no-op
  esac
  if [ ! -f "$ml_dst" ]; then
    write_new "$ml_src" "$ml_dst" "$ml_sub" placed
    return 0
  fi
  : >"$TMP_DIR/ledger-to-append"
  while IFS= read -r ml_line; do
    [ -n "$ml_line" ] || continue
    grep -qF -- "$ml_line" "$ml_dst" 2>/dev/null || printf '%s\n' "$ml_line" >>"$TMP_DIR/ledger-to-append"
  done <"$ml_src"
  if [ ! -s "$TMP_DIR/ledger-to-append" ]; then
    log_action noop "$ml_sub" "no new entries"
    return 0
  fi
  [ "$ml_backup" = true ] && take_backup "$ml_dst" "$ml_sub"
  cat "$TMP_DIR/ledger-to-append" >>"$ml_dst"
  log_action union-log "$ml_sub" "$(wc -l <"$TMP_DIR/ledger-to-append" | tr -d ' ') new row(s) appended"
}

merge_union_log() {
  mul_src=$1
  mul_dst=$2
  mul_backup=$3
  mul_sub=$4
  case "$mul_sub" in
    */JOURNAL.md) merge_journal_file "$mul_src" "$mul_dst" "$mul_backup" "$mul_sub" ;;
    history.jsonl) merge_history_file "$mul_src" "$mul_dst" "$mul_backup" "$mul_sub" ;;
    */.portability/*) merge_ledger_file "$mul_src" "$mul_dst" "$mul_backup" "$mul_sub" ;;
    *)
      if [ -f "$mul_dst" ]; then
        cmp -s "$mul_src" "$mul_dst" && log_action noop "$mul_sub" "already identical" ||
          log_action anomaly "$mul_sub" "unrecognized union-log path collision -- not overwriting"
      else
        write_new "$mul_src" "$mul_dst" "$mul_sub" placed
      fi
      ;;
  esac
}

# ── orchestration: apply every project-layer MERGEPLAN entry to a root ──────
# Called with $2=false against a disposable shadow copy (so knowledge-check.sh
# can validate the actual resulting tree before anything real is touched),
# then, only if that gate passes and --apply was given, with $2=true against
# the real target (each modification of a pre-existing file backed up first).

apply_project_merge() {
  apm_dest=$1
  apm_backup=$2
  CUR_DEST_ROOT=$apm_dest
  while IFS="$SEP" read -r apm_rel apm_class apm_key; do
    [ -n "$apm_rel" ] || continue
    case "$apm_rel" in
      project/*) apm_sub=${apm_rel#project/} ;;
      project-derived/*) continue ;; # quarantined index caches -- never written directly
      *) continue ;;
    esac
    [ "$PROJECT_STANDDOWN" = true ] && continue
    apm_src=$PAYLOAD_ROOT/$apm_rel
    [ -f "$apm_src" ] || continue
    apm_dst=$apm_dest/$apm_sub
    case "$apm_class" in
      derived-index) continue ;; # regenerated after unique-class placement, or skipped (MEMORY.md)
      union-route) merge_route "$apm_src" "$apm_dst" "$apm_backup" "$apm_sub" ;;
      union-log) merge_union_log "$apm_src" "$apm_dst" "$apm_backup" "$apm_sub" ;;
      keyed-unit) merge_keyed_unit "$apm_src" "$apm_dst" "$apm_backup" "$apm_sub" "$apm_key" ;;
      unique) merge_unique "$apm_src" "$apm_dst" "$apm_backup" "$apm_sub" ;;
      sectioned | singleton-state | template) merge_no_touch_sidecar "$apm_src" "$apm_dst" "$apm_backup" "$apm_sub" ;;
      *) merge_no_touch_sidecar "$apm_src" "$apm_dst" "$apm_backup" "$apm_sub" ;;
    esac
  done <"$MERGEPLAN"
}

# ── orchestration: user-scope (memory/sessions/history), real Commit only ──
# Never run against the shadow root: knowledge-check.sh never inspects the
# Claude home, so shadow-validating it would cost real work for zero signal.

apply_user_merge() {
  aum_userdir=$1
  CUR_DEST_ROOT=$TARGET
  while IFS="$SEP" read -r aum_rel aum_class aum_key; do
    [ -n "$aum_rel" ] || continue
    case "$aum_rel" in
      user/*) aum_sub=${aum_rel#user/} ;;
      user-derived/*) continue ;;
      *) continue ;;
    esac
    aum_src=$PAYLOAD_ROOT/$aum_rel
    [ -f "$aum_src" ] || continue
    aum_dst=$aum_userdir/$aum_sub
    case "$aum_class" in
      derived-index) continue ;; # MEMORY.md regeneration is a documented gap; see NOTES
      union-log) merge_union_log "$aum_src" "$aum_dst" true "$aum_sub" ;;
      keyed-unit) merge_keyed_unit "$aum_src" "$aum_dst" true "$aum_sub" "$aum_key" ;;
      unique)
        case "$aum_sub" in
          sessions/*) merge_session_file "$aum_src" "$aum_dst" "$aum_sub" ;;
          *)
            if [ -f "$aum_dst" ]; then
              cmp -s "$aum_src" "$aum_dst" && log_action noop "$aum_sub" "already present" ||
                log_action anomaly "$aum_sub" "unique path collision -- not overwriting"
            else
              write_new "$aum_src" "$aum_dst" "$aum_sub" placed
            fi
            ;;
        esac
        ;;
      *) merge_no_touch_sidecar "$aum_src" "$aum_dst" true "$aum_sub" ;;
    esac
  done <"$MERGEPLAN"
}

# ── derived-index regeneration: tasks/index.md and specs/INDEX.md ──────────
# Mechanical, not a merge: both files declare themselves convenience caches
# over the unit files that are now the source of truth on TARGET, so a fresh
# render from disk is strictly more correct than any textual merge could be.
# MEMORY.md is NOT regenerated here -- its format is outside this project's
# own rule set, so a wrong guess risks corrupting a system this repo does
# not own the schema for. See task NOTES for the disclosed gap.

regenerate_tasks_index() {
  rti_tasksdir=$1
  rti_index=$rti_tasksdir/index.md
  [ -d "$rti_tasksdir" ] || return 0
  : >"$TMP_DIR/ri-active"
  : >"$TMP_DIR/ri-done"
  find "$rti_tasksdir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/ri-files"
  while IFS= read -r rti_f; do
    [ -n "$rti_f" ] || continue
    rti_slug=$(frontmatter_field "$rti_f" slug)
    rti_status=$(frontmatter_field "$rti_f" status)
    rti_updated=$(frontmatter_field "$rti_f" updated)
    [ -n "$rti_slug" ] || continue
    case "$rti_status" in
      planning | in-progress | blocked | awaiting-review)
        rti_line="- [$rti_slug]($(basename -- "$rti_f")) — $rti_status — updated $rti_updated"
        [ "$rti_status" = awaiting-review ] && rti_line="$rti_line ⏳ awaiting your confirmation"
        printf '%s\n' "$rti_line" >>"$TMP_DIR/ri-active"
        ;;
    esac
  done <"$TMP_DIR/ri-files"
  if [ -d "$rti_tasksdir/done" ]; then
    find "$rti_tasksdir/done" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/ri-done-files"
    while IFS= read -r rti_f; do
      [ -n "$rti_f" ] || continue
      rti_slug=$(frontmatter_field "$rti_f" slug)
      rti_updated=$(frontmatter_field "$rti_f" updated)
      [ -n "$rti_slug" ] || continue
      printf '- [%s](done/%s) — done %s\n' "$rti_slug" "$(basename -- "$rti_f")" "$rti_updated" >>"$TMP_DIR/ri-done"
    done <"$TMP_DIR/ri-done-files"
  fi
  {
    printf '<!-- .claude/tasks/index.md -- dashboard of task documents. Maintained by /plan and /checkpoint.\n'
    printf '     Task files are source of truth; this index is a convenience cache. Hard ceiling: 100 lines. -->\n\n'
    printf '## Active\n\n'
    if [ -s "$TMP_DIR/ri-active" ]; then cat "$TMP_DIR/ri-active"; else printf -- '- _(none)_\n'; fi
    printf '\n## Recently Done (last 14 days)\n\n'
    if [ -s "$TMP_DIR/ri-done" ]; then cat "$TMP_DIR/ri-done"; else printf -- '- _(none)_\n'; fi
  } >"$TMP_DIR/ri-new-index"
  rti_rel=${rti_tasksdir#"$CUR_DEST_ROOT"/}/index.md
  if [ -f "$rti_index" ] && cmp -s "$TMP_DIR/ri-new-index" "$rti_index"; then
    log_action noop "$rti_rel" "already current"
    return 0
  fi
  [ -f "$rti_index" ] && take_backup "$rti_index" "$rti_rel"
  cp -- "$TMP_DIR/ri-new-index" "$rti_index"
  log_action derived-index "$rti_rel" regenerated
}

regenerate_specs_index() {
  rsi_specsdir=$1
  rsi_index=$rsi_specsdir/INDEX.md
  [ -d "$rsi_specsdir" ] || return 0
  : >"$TMP_DIR/rsi-active"
  : >"$TMP_DIR/rsi-done"
  find "$rsi_specsdir" -mindepth 2 -maxdepth 2 -type f -name 'SPEC.md' 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/rsi-files"
  while IFS= read -r rsi_f; do
    [ -n "$rsi_f" ] || continue
    rsi_folder=$(basename -- "$(dirname -- "$rsi_f")")
    rsi_status=$(frontmatter_field "$rsi_f" status)
    rsi_updated=$(frontmatter_field "$rsi_f" updated)
    case "$rsi_status" in
      drafting | poc-review | ready | running | blocked | awaiting-final-review)
        rsi_line="- [$rsi_folder]($rsi_folder/SPEC.md) — $rsi_status — updated $rsi_updated"
        case "$rsi_status" in poc-review | awaiting-final-review) rsi_line="$rsi_line ⏳ awaiting your review" ;; esac
        printf '%s\n' "$rsi_line" >>"$TMP_DIR/rsi-active"
        ;;
    esac
  done <"$TMP_DIR/rsi-files"
  if [ -d "$rsi_specsdir/done" ]; then
    find "$rsi_specsdir/done" -mindepth 2 -maxdepth 2 -type f -name 'SPEC.md' 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/rsi-done-files"
    while IFS= read -r rsi_f; do
      [ -n "$rsi_f" ] || continue
      rsi_folder=$(basename -- "$(dirname -- "$rsi_f")")
      rsi_status=$(frontmatter_field "$rsi_f" status)
      printf '- [%s](done/%s/SPEC.md) — %s\n' "$rsi_folder" "$rsi_folder" "$rsi_status" >>"$TMP_DIR/rsi-done"
    done <"$TMP_DIR/rsi-done-files"
  fi
  {
    printf '<!-- .claude/specs/INDEX.md -- registry of spec missions. Maintained by /spec, /spec-run, /checkpoint.\n'
    printf '     SPEC.md frontmatter is the source of truth; this index is a convenience cache. -->\n\n'
    printf '## Active\n\n'
    if [ -s "$TMP_DIR/rsi-active" ]; then cat "$TMP_DIR/rsi-active"; else printf -- '- _(none — run `/spec <mission description>` to create one)_\n'; fi
    printf '\n## Done\n\n'
    if [ -s "$TMP_DIR/rsi-done" ]; then cat "$TMP_DIR/rsi-done"; else printf -- '- _(none)_\n'; fi
  } >"$TMP_DIR/rsi-new-index"
  rsi_rel=${rsi_specsdir#"$CUR_DEST_ROOT"/}/INDEX.md
  if [ -f "$rsi_index" ] && cmp -s "$TMP_DIR/rsi-new-index" "$rsi_index"; then
    log_action noop "$rsi_rel" "already current"
    return 0
  fi
  [ -f "$rsi_index" ] && take_backup "$rsi_index" "$rsi_rel"
  cp -- "$TMP_DIR/rsi-new-index" "$rsi_index"
  log_action derived-index "$rsi_rel" regenerated
}

# ── report ───────────────────────────────────────────────────────────────────

printf 'bundle:              %s\n' "$BUNDLE"
printf 'bundle id:           %s\n' "$(manifest_field bundle_id)"
printf 'target:               %s\n' "$TARGET"
printf 'mode:                 %s\n' "$MODE"
printf 'payload files:        %s\n' "$(wc -l <"$TMP_DIR/declared-inventory" | tr -d ' ')"
printf 'rewrite tokens:       %s\n' "$PLAN_TOKEN_COUNT"
printf 'files rewritten:      %s\n' "$REWRITTEN_COUNT"
if [ -s "$SKIP_REPORT" ]; then
  printf 'left untranslated:\n'
  sed 's/^/  /' "$SKIP_REPORT"
fi
printf '\nverifications:\n'
printf '  1. line-count/newline parity:  %s\n' "$([ "$V1_OK" = true ] && echo PASS || echo FAIL)"
printf '  2. identity multiset:          %s\n' "$([ "$V2_OK" = true ] && echo PASS || echo FAIL)"
printf '  3. byte arithmetic:            %s\n' "$([ "$V3_OK" = true ] && echo PASS || echo FAIL)"
printf '  4. occurrence arithmetic:      %s\n' "$([ "$V4_OK" = true ] && echo PASS || echo FAIL)"
printf '  5. structural JSON:            %s\n' "$([ "$V5_OK" = true ] && echo PASS || echo FAIL)"

ALL_OK=true
[ "$V1_OK" = true ] || ALL_OK=false
[ "$V2_OK" = true ] || ALL_OK=false
[ "$V3_OK" = true ] || ALL_OK=false
[ "$V4_OK" = true ] || ALL_OK=false
[ "$V5_OK" = true ] || ALL_OK=false

if [ "$ALL_OK" != true ]; then
  printf '\n%s: one or more rewrite verifications failed; nothing would be written.\n' "$PROGRAM" >&2
  exit 1
fi

if [ -n "$STAGE_OUT" ]; then
  STAGE_OUT_PARENT=$(dirname -- "$STAGE_OUT")
  [ -d "$STAGE_OUT_PARENT" ] || usage_error "--stage-out parent directory does not exist: $STAGE_OUT_PARENT"
  cp -R "$PAYLOAD_ROOT" "$STAGE_OUT" || usage_error "cannot write --stage-out: $STAGE_OUT"
  printf '\n%s: rewritten (not yet merged) payload written to %s for inspection.\n' "$PROGRAM" "$STAGE_OUT"
fi

# ── Materialize (continued): merge classes on a shadow copy + shadow gate ──

COMMIT_EPOCH=$(date -u +%s 2>/dev/null || printf '0')
COMMIT_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')
COMMIT_UTC_SAFE=$(printf '%s' "$COMMIT_UTC" | tr -d ':')
CONFLICTS_DIR=$TARGET/.claude/.portability/conflicts/$COMMIT_EPOCH
BACKUPS_DIR=$CLAUDE_HOME_DEST/claudart-import-backups/${COMMIT_UTC_SAFE}-${BUNDLE_ID_VAL}

# Git-lineage stand-down: if the target's current HEAD already contains the
# bundle's git_head, the project layer already travels via git and importing
# it again would be redundant work at best, a stale-content downgrade at
# worst.
PROJECT_STANDDOWN=false
BUNDLE_GIT_HEAD=$(manifest_field git_head)
if [ -n "$BUNDLE_GIT_HEAD" ] && command -v git >/dev/null 2>&1 && git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$TARGET" cat-file -e "$BUNDLE_GIT_HEAD" 2>/dev/null &&
    git -C "$TARGET" merge-base --is-ancestor "$BUNDLE_GIT_HEAD" HEAD 2>/dev/null; then
    PROJECT_STANDDOWN=true
  fi
fi

: >"$TMP_DIR/spec-folder-map"
SHADOW_ROOT=$TMP_DIR/shadow
mkdir -p "$SHADOW_ROOT"
(cd "$TARGET" && find . -mindepth 1 -maxdepth 1 ! -name .git -exec cp -R {} "$SHADOW_ROOT/" \;) 2>/dev/null

if [ "$PROJECT_STANDDOWN" != true ]; then
  apply_project_merge "$SHADOW_ROOT" false
  regenerate_tasks_index "$SHADOW_ROOT/.claude/tasks"
  regenerate_tasks_index "$SHADOW_ROOT/.codex/tasks"
  regenerate_specs_index "$SHADOW_ROOT/.claude/specs"
  regenerate_specs_index "$SHADOW_ROOT/.codex/specs"
fi

SHADOW_GATE_OK=true
SHADOW_GATE_REPORT=$TMP_DIR/shadow-gate-report
: >"$SHADOW_GATE_REPORT"
if [ "$PROJECT_STANDDOWN" = true ]; then
  printf 'skipped: project layer already reachable via git (bundle git_head is an ancestor of target HEAD)\n' >>"$SHADOW_GATE_REPORT"
else
  for kc_layer_dir in "$SHADOW_ROOT/.claude" "$SHADOW_ROOT/.codex"; do
    [ -d "$kc_layer_dir" ] || continue
    kc_layer=claude
    kc_dotdir=.claude
    if [ "$kc_layer_dir" = "$SHADOW_ROOT/.codex" ]; then kc_layer=codex; kc_dotdir=.codex; fi
    kc_script=$kc_layer_dir/scripts/knowledge-check.sh
    if [ ! -f "$kc_script" ]; then
      printf 'skipped: no %s/scripts/knowledge-check.sh in the target -- cannot shadow-validate the %s layer\n' "$kc_dotdir" "$kc_layer" >>"$SHADOW_GATE_REPORT"
      continue
    fi
    if /bin/bash "$kc_script" --root "$SHADOW_ROOT" --layer "$kc_layer" >"$TMP_DIR/kc-out-$kc_layer" 2>&1; then
      printf '%s layer: PASS\n' "$kc_layer" >>"$SHADOW_GATE_REPORT"
    else
      SHADOW_GATE_OK=false
      printf '%s layer: FAIL\n' "$kc_layer" >>"$SHADOW_GATE_REPORT"
      tail -n 20 "$TMP_DIR/kc-out-$kc_layer" | sed 's/^/  /' >>"$SHADOW_GATE_REPORT"
    fi
  done
fi

# ── report ───────────────────────────────────────────────────────────────────

printf '\nmerge plan (against a shadow copy of the target):\n'
if [ -s "$MERGE_LOG" ]; then
  awk -F'\t' '{ printf "  %-20s %-45s %s\n", $1, $2, $3 }' "$MERGE_LOG"
else
  printf '  (no project-layer entries in this bundle, or the project layer is standing down via git)\n'
fi
printf '\nshadow knowledge-check.sh gate:\n'
sed 's/^/  /' "$SHADOW_GATE_REPORT"

if [ "$SHADOW_GATE_OK" != true ]; then
  printf '\n%s: shadow knowledge-check.sh gate failed; nothing was written to the target.\n' "$PROGRAM" >&2
  exit 1
fi

if [ "$APPLY" != true ]; then
  printf '\n%s: dry run only -- merge plan and shadow gate verified clean; rerun with --apply to write.\n' "$PROGRAM"
  exit 0
fi

# ── Commit: backups, the same merge for real, user-scope, indexes, receipt,
#    ledger ──────────────────────────────────────────────────────────────────

: >"$MERGE_LOG"
mkdir -p "$BACKUPS_DIR" 2>/dev/null

if [ "$PROJECT_STANDDOWN" != true ]; then
  apply_project_merge "$TARGET" true
  regenerate_tasks_index "$TARGET/.claude/tasks"
  regenerate_tasks_index "$TARGET/.codex/tasks"
  regenerate_specs_index "$TARGET/.claude/specs"
  regenerate_specs_index "$TARGET/.codex/specs"
fi

TARGET_PROJECT_DIR=$CLAUDE_HOME_DEST/projects/$TARGET_MANGLED
mkdir -p "$TARGET_PROJECT_DIR" 2>/dev/null
apply_user_merge "$TARGET_PROJECT_DIR"

LEDGER_FILE=$TARGET/.claude/.portability/ledger.tsv
mkdir -p "$(dirname -- "$LEDGER_FILE")" 2>/dev/null
# Skip if the most recent row already records this exact bundle: a repeated
# --apply of an unchanged bundle carries no new lineage information, and
# appending a fresh epoch-stamped row every time would make the ledger (and
# the whole target tree) never settle to a fixed point on re-application.
LEDGER_LAST_BUNDLE=$(awk -F"$SEP" 'NF >= 1 { last = $1 } END { print last }' "$LEDGER_FILE" 2>/dev/null)
if [ "$LEDGER_LAST_BUNDLE" != "$BUNDLE_ID_VAL" ]; then
  printf '%s%s%s%s%s\n' "$BUNDLE_ID_VAL" "$SEP" "$COMMIT_EPOCH" "$SEP" "$MODE" >>"$LEDGER_FILE"
fi

RECEIPT=$BACKUPS_DIR/receipt.txt
{
  printf 'CLAUDART restore receipt\n=========================\n\n'
  printf 'bundle:      %s\n' "$BUNDLE"
  printf 'bundle id:   %s\n' "$BUNDLE_ID_VAL"
  printf 'target:      %s\n' "$TARGET"
  printf 'claude home: %s\n' "$CLAUDE_HOME_DEST"
  printf 'mode:        %s\n' "$MODE"
  printf 'committed:   %s\n' "$COMMIT_UTC"
  printf 'project layer standdown (git already has it): %s\n\n' "$PROJECT_STANDDOWN"
  printf 'Pre-existing files backed up before modification are under this same\n'
  printf 'directory (%s), mirroring their path under the target.\n\n' "$BACKUPS_DIR"
  printf 'Actions taken:\n'
  awk -F'\t' '{ printf "  %-20s %-45s %s\n", $1, $2, $3 }' "$MERGE_LOG"
} >"$RECEIPT"

printf '\ncommitted actions:\n'
awk -F'\t' '{ printf "  %-20s %-45s %s\n", $1, $2, $3 }' "$MERGE_LOG"
printf '\n%s: restore committed. Backups + receipt at %s.\n' "$PROGRAM" "$BACKUPS_DIR"

ANOMALY_COUNT=$(awk -F'\t' '$1 == "anomaly"' "$MERGE_LOG" | wc -l | tr -d ' ')
CONFLICT_COUNT=$(awk -F'\t' '$1 == "conflict-parked"' "$MERGE_LOG" | wc -l | tr -d ' ')
GRAFT_COUNT=$(awk -F'\t' '$1 == "graft-review-needed" || $1 == "sidecar" || $1 == "memory-graft"' "$MERGE_LOG" | wc -l | tr -d ' ')
if [ "$GRAFT_COUNT" -gt 0 ]; then
  printf '\n%s new/grafted or sidecared item(s) need a follow-up pass -- run /refactor-memory (knowledge sidecars, review-needed grafts) and /learn (register any grafted rules in CLAUDE.md; grafted rules are inert until registered).\n' "$GRAFT_COUNT"
fi
if [ "$CONFLICT_COUNT" -gt 0 ]; then
  printf '%s divergent session(s) parked under .claude/.portability/conflicts/%s/ -- review manually; no mechanical rule can pick a winner between two continuations of the same session.\n' "$CONFLICT_COUNT" "$COMMIT_EPOCH"
fi
if [ "$ANOMALY_COUNT" -gt 0 ]; then
  printf '%s: %s anomaly/anomalies logged -- see receipt at %s\n' "$PROGRAM" "$ANOMALY_COUNT" "$RECEIPT" >&2
fi

exit 0
