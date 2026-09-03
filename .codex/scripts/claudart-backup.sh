#!/bin/bash

# Export a portable CLAUDART bundle: the project .claude/ layer plus the Claude
# Code user-scope context for this project. Configuration and credentials are
# never read -- collection is an allow-list, not a filtered directory walk.
# Runtime dependencies are limited to Bash 3.2 and common POSIX utilities.

set -u

# Transcripts are mode 0600; never widen them in the bundle.
umask 077

LC_ALL=C
export LC_ALL

PROGRAM=${0##*/}
SEP=$(printf '\034')
SCHEMA=claudart-bundle/1

ROOT_OVERRIDE=
OUT_DIR=
CLAUDE_HOME_OVERRIDE=
SESSIONS_MODE=recent
SESSIONS_EXPLICIT=false
RECENT_N=5
RECENT_EXPLICIT=false
HISTORY_MODE=yes
HISTORY_EXPLICIT=false
PROJECT_SCOPE=all
ALIAS_ROOT_RAW=
ARCHIVE=false
ALLOW_SECRETS=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: claudart-backup.sh --out DIR [options]

Export a portable CLAUDART bundle: the project .claude/ layer plus the Claude
Code user-scope context for this project. Configuration and credentials are
never read.

Options:
  --root DIR                  Project root to export (default: inferred from script path)
  --out DIR                   Bundle destination; must not already exist (required)
  --claude-home DIR           Claude Code user directory
                              (default: $CLAUDE_CONFIG_DIR, else $HOME/.claude)
  --sessions all|recent|none  Session transcript scope (default: recent)
  --recent N                  Sessions to keep with --sessions recent (default: 5)
  --history yes|no            Include this project's slice of history.jsonl (default: yes)
  --project-scope all|graft   Project-layer subset (default: all)
                              graft = knowledge/ and rules/ only, for grafting
                              context into a different project; implies
                              --sessions none --history no unless set explicitly
  --alias-root PATH           Declare a historical root this project used to live
                              at, so restore can translate it. Repeatable. A path
                              with no occurrences is an error, not a no-op.
  --archive                   Also write <out>.tar.gz beside the bundle directory
  --allow-secrets             Write the bundle even if the secret scan finds something
  --dry-run                   Report what would be exported and write nothing
  --help                      Show this help

Never included: Claude Code settings, ~/.claude.json, OAuth or API credentials,
session keys, IDE lock files, paste cache, plugins, installed agents and skills,
file-history snapshots, and ~/.claude/plans.

Exit status:
  0  bundle written and the secret scan found nothing
  1  the secret scan found something (bundle withheld unless --allow-secrets)
  2  invalid usage or an internal runtime failure
EOF
}

usage_error() {
  printf '%s: %s\n' "$PROGRAM" "$1" >&2
  printf '%s\n' "Try '$PROGRAM --help' for usage." >&2
  exit 2
}

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) ||
  usage_error "cannot resolve the script directory"
INFERRED_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." 2>/dev/null && pwd -P) ||
  usage_error "cannot infer the repository root"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] || usage_error "--root requires a directory"
      ROOT_OVERRIDE=$2
      shift 2
      ;;
    --out)
      [ "$#" -ge 2 ] || usage_error "--out requires a directory"
      OUT_DIR=$2
      shift 2
      ;;
    --claude-home)
      [ "$#" -ge 2 ] || usage_error "--claude-home requires a directory"
      CLAUDE_HOME_OVERRIDE=$2
      shift 2
      ;;
    --sessions)
      [ "$#" -ge 2 ] || usage_error "--sessions requires all, recent, or none"
      SESSIONS_MODE=$2
      SESSIONS_EXPLICIT=true
      shift 2
      ;;
    --recent)
      [ "$#" -ge 2 ] || usage_error "--recent requires a positive integer"
      RECENT_N=$2
      RECENT_EXPLICIT=true
      shift 2
      ;;
    --history)
      [ "$#" -ge 2 ] || usage_error "--history requires yes or no"
      HISTORY_MODE=$2
      HISTORY_EXPLICIT=true
      shift 2
      ;;
    --project-scope)
      [ "$#" -ge 2 ] || usage_error "--project-scope requires all or graft"
      PROJECT_SCOPE=$2
      shift 2
      ;;
    --alias-root)
      [ "$#" -ge 2 ] || usage_error "--alias-root requires an absolute path"
      case "$2" in
        /*) ;;
        *) usage_error "--alias-root must be an absolute path: $2" ;;
      esac
      ALIAS_ROOT_RAW="$ALIAS_ROOT_RAW$2
"
      shift 2
      ;;
    --archive)
      ARCHIVE=true
      shift
      ;;
    --allow-secrets)
      ALLOW_SECRETS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
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

case "$SESSIONS_MODE" in
  all | recent | none) ;;
  *) usage_error "--sessions must be all, recent, or none" ;;
esac

case "$HISTORY_MODE" in
  yes | no) ;;
  *) usage_error "--history must be yes or no" ;;
esac

case "$PROJECT_SCOPE" in
  all | graft) ;;
  *) usage_error "--project-scope must be all or graft" ;;
esac

case "$RECENT_N" in
  '' | *[!0-9]*) usage_error "--recent must be a positive integer" ;;
  *) ;;
esac
[ "$RECENT_N" -gt 0 ] 2>/dev/null || usage_error "--recent must be a positive integer"

if [ "$RECENT_EXPLICIT" = true ] && [ "$SESSIONS_MODE" != recent ]; then
  usage_error "--recent applies only with --sessions recent"
fi

# --project-scope graft is about reusing knowledge in a DIFFERENT project.
# Carrying transcripts there would rewrite every cwd and fabricate a history of
# work that never happened in the target, so both default off. Explicit flags
# still win -- this is a default, not a lock.
if [ "$PROJECT_SCOPE" = graft ]; then
  [ "$SESSIONS_EXPLICIT" = true ] || SESSIONS_MODE=none
  [ "$HISTORY_EXPLICIT" = true ] || HISTORY_MODE=no
fi

[ -n "$OUT_DIR" ] || usage_error "--out is required"

if [ -n "$ROOT_OVERRIDE" ]; then
  [ -d "$ROOT_OVERRIDE" ] || usage_error "--root is not a directory"
  ROOT=$(CDPATH='' cd -- "$ROOT_OVERRIDE" 2>/dev/null && pwd -P) ||
    usage_error "cannot resolve --root"
else
  ROOT=$INFERRED_ROOT
fi

if [ -n "$CLAUDE_HOME_OVERRIDE" ]; then
  CLAUDE_HOME=$CLAUDE_HOME_OVERRIDE
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  CLAUDE_HOME=$CLAUDE_CONFIG_DIR
else
  CLAUDE_HOME=${HOME:-}/.claude
fi

if [ -e "$OUT_DIR" ]; then
  usage_error "--out already exists: $OUT_DIR"
fi
OUT_PARENT=$(dirname -- "$OUT_DIR")
[ -d "$OUT_PARENT" ] || usage_error "--out parent directory does not exist: $OUT_PARENT"

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claudart-backup.XXXXXX" 2>/dev/null) ||
  usage_error "cannot create a temporary directory"

# Invoked indirectly by trap.
# shellcheck disable=SC2329
cleanup() {
  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf -- "$TMP_DIR"
  fi
  # A staging dir surviving here means we failed or withheld; either way the
  # partial bundle must not be left behind for someone to mistake for output.
  if [ -n "${STAGE:-}" ] && [ -d "$STAGE" ]; then
    rm -rf -- "$STAGE"
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

# Stage beside the destination, not in $TMPDIR: same filesystem means the
# finalize is a true atomic rename rather than a cross-device copy, and a large
# --sessions all export cannot overflow a small /tmp.
STAGE=$OUT_DIR.partial
INVENTORY=$TMP_DIR/inventory
MERGEPLAN=$TMP_DIR/mergeplan
SKIPPED=$TMP_DIR/skipped
FINDINGS=$TMP_DIR/findings
HITFILES=$TMP_DIR/hitfiles
SESSION_LIST=$TMP_DIR/sessions
HSTATS=$TMP_DIR/hstats
if [ -e "$STAGE" ]; then usage_error "staging path already exists: $STAGE"; fi
mkdir -p "$STAGE" || usage_error "cannot create the staging directory"
: >"$INVENTORY"
: >"$MERGEPLAN"
: >"$SKIPPED"
: >"$FINDINGS"
: >"$HITFILES"
: >"$SESSION_LIST"
: >"$HSTATS"

# ── helpers ──────────────────────────────────────────────────────────────────

# Escape a string for embedding in a JSON string literal. Applied to EVERY
# string without exception: paths come from the filesystem and are the
# realistic break case. Reads stdin, writes the escaped body (no quotes).
json_escape() {
  awk '
    BEGIN {
      for (i = 1; i < 32; i++) ctrl[sprintf("%c", i)] = sprintf("\\u%04x", i)
      ctrl["\b"] = "\\b"; ctrl["\f"] = "\\f"
      ctrl["\t"] = "\\t"; ctrl["\r"] = "\\r"
      ctrl[sprintf("%c", 127)] = "\\u007f"
      first = 1
    }
    {
      if (!first) printf "\\n"
      first = 0
      n = length($0)
      out = ""
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == "\\") out = out "\\\\"
        else if (c == "\"") out = out "\\\""
        else if (c in ctrl) out = out ctrl[c]
        else out = out c
      }
      printf "%s", out
    }
  '
}

jstr() {
  printf '%s' "$1" | json_escape
}

jnum() {
  case "${1:-}" in
    '' | *[!0-9]*) printf '0' ;;
    *) printf '%s' "$1" ;;
  esac
}

# Mirrors install.sh:188-195 is_template_path() exactly. Import uses the
# resulting provenance to avoid downgrading a newer local template file.
is_template_path() {
  case "$1" in
    .claude/commands/* | .claude/rules/* | .claude/skills/* | .claude/agents/* | .claude/scripts/* | .claude/hooks/*) return 0 ;;
    .codex/guidelines/* | .codex/agents/* | .codex/scripts/*) return 0 ;;
    .agents/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Second belt behind the allow-list: directories whose contents are not fully
# under Claude Code's control can still acquire a credential file.
deny_path() {
  case "$1" in
    */settings.local.json | settings.local.json) return 0 ;;
    */settings.json | settings.json) return 0 ;;
    */.claude.json | .claude.json) return 0 ;;
    */.env | */.env.* | .env | .env.*) return 0 ;;
    *.key | *.pem | *.p12 | *.pfx | *.keystore) return 0 ;;
    */id_rsa | */id_dsa | */id_ecdsa | */id_ed25519) return 0 ;;
    */.credentials.json | */credentials.json) return 0 ;;
    */.netrc | */.npmrc | */.pypirc) return 0 ;;
    */.git/* | .git/*) return 0 ;;
    */node_modules/* | node_modules/*) return 0 ;;
    *.lock) return 0 ;;
    .claude/.portability/conflicts/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Assign exactly one merge class. Order matters: the most specific identity
# wins, so evaluate exact derived/router paths before the generic families.
merge_class() {
  case "$1" in
    project/.claude/tasks/index.md | project/.codex/tasks/index.md) printf 'derived-index' ;;
    project/.claude/specs/INDEX.md | project/.codex/specs/INDEX.md) printf 'derived-index' ;;
    user/memory/MEMORY.md) printf 'derived-index' ;;
    project/.claude/knowledge/INDEX.md | project/.codex/knowledge/INDEX.md) printf 'union-route' ;;
    project/.claude/knowledge/_maps/* | project/.codex/knowledge/_maps/*) printf 'union-route' ;;
    project/.claude/JOURNAL.md | project/.codex/JOURNAL.md) printf 'union-log' ;;
    user/history.jsonl) printf 'union-log' ;;
    project/.claude/HANDOFF.md | project/.codex/HANDOFF.md) printf 'singleton-state' ;;
    project/.claude/CLAUDE.md | project/AGENTS.md | project/.codex/AGENTS.md) printf 'sectioned' ;;
    project/.claude/CONTEXT.md | project/.codex/CONTEXT.md) printf 'sectioned' ;;
    project/.claude/knowledge/* | project/.codex/knowledge/*) printf 'keyed-unit' ;;
    user/memory/*) printf 'keyed-unit' ;;
    project/.claude/tasks/* | project/.codex/tasks/*) printf 'unique' ;;
    project/.claude/specs/* | project/.codex/specs/*) printf 'unique' ;;
    user/sessions/*) printf 'unique' ;;
    project/.claude/.portability/*) printf 'union-log' ;;
    *) printf 'template' ;;
  esac
}

# Frontmatter `name:` is the merge key for keyed-unit files; fall back to the
# filename slug when a topic carries none.
merge_key_for() {
  mk_class=$1
  mk_stagepath=$2
  mk_rel=$3
  if [ "$mk_class" != keyed-unit ]; then
    printf ''
    return 0
  fi
  mk_name=$(awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && /^name:[[:space:]]/ {
      sub(/^name:[[:space:]]*/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$mk_stagepath" 2>/dev/null)
  if [ -n "$mk_name" ]; then
    printf '%s' "$mk_name"
  else
    mk_base=${mk_rel##*/}
    printf '%s' "${mk_base%.md}"
  fi
}

record_skip() {
  printf '%s%s%s\n' "$1" "$SEP" "$2" >>"$SKIPPED"
}

# Stage one file and record it in both machine-readable indexes.
stage_file() {
  sf_src=$1
  sf_rel=$2
  sf_prov=$3
  if [ -L "$sf_src" ]; then
    record_skip "$sf_rel" "skipped:symlink"
    return 0
  fi
  if [ ! -f "$sf_src" ]; then
    record_skip "$sf_rel" "skipped:not-regular"
    return 0
  fi
  sf_dst=$STAGE/$sf_rel
  mkdir -p "$(dirname -- "$sf_dst")" 2>/dev/null || {
    record_skip "$sf_rel" "skipped:mkdir-failed"
    return 0
  }
  cp -- "$sf_src" "$sf_dst" 2>/dev/null || {
    record_skip "$sf_rel" "skipped:copy-failed"
    return 0
  }
  sf_class=$(merge_class "$sf_rel")
  sf_key=$(merge_key_for "$sf_class" "$sf_dst" "$sf_rel")
  printf '%s%s%s%s%s\n' "$sf_rel" "$SEP" "$sf_class" "$SEP" "$sf_key" >>"$MERGEPLAN"
  printf '%s%s%s\n' "$sf_rel" "$SEP" "$sf_prov" >>"$TMP_DIR/provenance"
  return 0
}

# Refuse any tree containing a path with a newline: cksum output is
# line-oriented and POSIX find has no -print0, so such a path would silently
# corrupt INVENTORY. Detect by comparing file count to line count.
assert_no_newline_paths() {
  ap_dir=$1
  [ -d "$ap_dir" ] || return 0
  ap_files=$(find "$ap_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
  ap_lines=$(find "$ap_dir" -type f -exec printf 'x\n' \; 2>/dev/null | wc -l | tr -d ' ')
  if [ "$ap_files" != "$ap_lines" ]; then
    usage_error "refusing to export: a path under $ap_dir contains a newline"
  fi
  return 0
}

# ── resolve the user-scope project directory ─────────────────────────────────

# The mangling is lossy (every "/" becomes "-", and "-" is legal in a path), so
# the computed name is a hint, not ground truth. Prefer observing a transcript
# whose cwd matches this root. NOTE: line 1 of a transcript is a "mode" record
# with no cwd -- the first cwd lands on line 3 or 4, so probe ~50 lines.
MANGLED=$(printf '%s' "$ROOT" | tr '/' '-')
PROJECTS_DIR=
PROJECTS_RESOLUTION=absent

if [ -d "$CLAUDE_HOME/projects/$MANGLED" ]; then
  PROJECTS_DIR=$MANGLED
  PROJECTS_RESOLUTION=mangled
elif [ -d "$CLAUDE_HOME/projects" ]; then
  find "$CLAUDE_HOME/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
    LC_ALL=C sort >"$TMP_DIR/candidates"
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    find "$cand" -mindepth 1 -maxdepth 1 -name '*.jsonl' -type f 2>/dev/null |
      LC_ALL=C sort >"$TMP_DIR/cand-jsonl"
    while IFS= read -r cj; do
      [ -n "$cj" ] || continue
      if head -n 50 "$cj" 2>/dev/null | ROOTV="$ROOT" awk '
          index($0, "\"cwd\":\"" ENVIRON["ROOTV"] "\"") > 0 { found = 1; exit }
          END { exit(found ? 0 : 1) }
        '; then
        PROJECTS_DIR=${cand##*/}
        PROJECTS_RESOLUTION=cwd-probe
        break
      fi
    done <"$TMP_DIR/cand-jsonl"
    [ -n "$PROJECTS_DIR" ] && break
  done <"$TMP_DIR/candidates"
fi

PROJECT_SRC=
if [ -n "$PROJECTS_DIR" ]; then
  PROJECT_SRC=$CLAUDE_HOME/projects/$PROJECTS_DIR
fi

# ── collect: project layer ───────────────────────────────────────────────────

assert_no_newline_paths "$ROOT/.claude"
assert_no_newline_paths "$ROOT/.codex"
assert_no_newline_paths "$ROOT/.agents"
[ -n "$PROJECT_SRC" ] && assert_no_newline_paths "$PROJECT_SRC"

: >"$TMP_DIR/provenance"

collect_layer_dir() {
  cl_dir=$1
  cl_prefix=$2
  [ -d "$ROOT/$cl_dir" ] || return 0
  find "$ROOT/$cl_dir" -type f 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/layer-files"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel=${f#"$ROOT/"}
    if deny_path "$rel"; then
      record_skip "$rel" "deny:config"
      continue
    fi
    if [ "$PROJECT_SCOPE" = graft ]; then
      case "$rel" in
        .claude/knowledge/* | .claude/rules/* | .codex/knowledge/* | .codex/guidelines/*) ;;
        *)
          record_skip "$rel" "skipped:project-scope-graft"
          continue
          ;;
      esac
    fi
    if is_template_path "$rel"; then
      prov=template
    else
      prov=state
    fi
    stage_file "$f" "$cl_prefix/$rel" "$prov"
  done <"$TMP_DIR/layer-files"
  return 0
}

collect_layer_dir ".claude" "project"
collect_layer_dir ".codex" "project"
collect_layer_dir ".agents" "project"

# ── collect: user-scope memory ───────────────────────────────────────────────

MEMORY_COUNT=0
if [ -n "$PROJECT_SRC" ] && [ -d "$PROJECT_SRC/memory" ]; then
  find "$PROJECT_SRC/memory" -type f 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/memory-files"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel=${f#"$PROJECT_SRC/memory/"}
    if deny_path "$rel"; then
      record_skip "memory/$rel" "deny:config"
      continue
    fi
    stage_file "$f" "user/memory/$rel" "state"
    MEMORY_COUNT=$((MEMORY_COUNT + 1))
  done <"$TMP_DIR/memory-files"
fi

# ── collect: sessions ────────────────────────────────────────────────────────

SESSIONS_AVAILABLE=0
SESSIONS_SELECTED=0
SUBAGENT_COUNT=0
TOOLRESULT_COUNT=0

if [ -n "$PROJECT_SRC" ] && [ "$SESSIONS_MODE" != none ]; then
  find "$PROJECT_SRC" -mindepth 1 -maxdepth 1 -name '*.jsonl' -type f 2>/dev/null |
    LC_ALL=C sort >"$TMP_DIR/all-sessions"
  SESSIONS_AVAILABLE=$(wc -l <"$TMP_DIR/all-sessions" | tr -d ' ')

  if [ "$SESSIONS_MODE" = all ]; then
    cp "$TMP_DIR/all-sessions" "$SESSION_LIST"
  else
    # Newest first by mtime. The glob is passed as separate arguments, so a
    # project path containing spaces survives; ls -t avoids parsing dates.
    ls -t -- "$PROJECT_SRC"/*.jsonl 2>/dev/null | head -n "$RECENT_N" >"$SESSION_LIST"
  fi

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sid=${f##*/}
    sid=${sid%.jsonl}
    stage_file "$f" "user/sessions/$sid.jsonl" "state"
    SESSIONS_SELECTED=$((SESSIONS_SELECTED + 1))
    if [ -d "$PROJECT_SRC/$sid" ]; then
      find "$PROJECT_SRC/$sid" -type f 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/sidecars"
      while IFS= read -r sc; do
        [ -n "$sc" ] || continue
        screl=${sc#"$PROJECT_SRC/"}
        if deny_path "$screl"; then
          record_skip "sessions/$screl" "deny:config"
          continue
        fi
        stage_file "$sc" "user/sessions/$screl" "state"
        case "$screl" in
          */subagents/*) SUBAGENT_COUNT=$((SUBAGENT_COUNT + 1)) ;;
          */tool-results/*) TOOLRESULT_COUNT=$((TOOLRESULT_COUNT + 1)) ;;
        esac
      done <"$TMP_DIR/sidecars"
    fi
  done <"$SESSION_LIST"
fi

# ── collect: history slice ───────────────────────────────────────────────────

HISTORY_TOTAL=0
HISTORY_KEPT=0
HISTORY_PASTED=0
HISTORY_SUSPECT=false

if [ "$HISTORY_MODE" = yes ] && [ -f "$CLAUDE_HOME/history.jsonl" ]; then
  # Anchor the needle with the FOLLOWING key so a project path that is a prefix
  # of another cannot match, and so an occurrence inside `display` (where the
  # quotes are backslash-escaped) cannot match either.
  ESCAPED=$(printf '%s' "$ROOT" | sed -e 's|\\|\\\\|g' -e 's|"|\\"|g')
  NEEDLE="\"project\":\"$ESCAPED\",\"sessionId\":\""
  mkdir -p "$STAGE/user"
  NEEDLE="$NEEDLE" OUTF="$STAGE/user/history.jsonl" STATF="$HSTATS" awk '
    BEGIN { needle = ENVIRON["NEEDLE"]; out = ENVIRON["OUTF"]; kept = 0; pasted = 0 }
    { total++ }
    index($0, needle) > 0 {
      kept++
      if (index($0, "\"pastedContents\":{}") == 0) pasted++
      print > out
    }
    END { printf "%d %d %d\n", total + 0, kept + 0, pasted + 0 > ENVIRON["STATF"] }
  ' "$CLAUDE_HOME/history.jsonl"

  read -r HISTORY_TOTAL HISTORY_KEPT HISTORY_PASTED <"$HSTATS"

  if [ "$HISTORY_KEPT" -eq 0 ]; then
    rm -f "$STAGE/user/history.jsonl"
    # Canary: the path is present but the anchored needle failed => the record
    # format changed. Zero matches on its own is legitimate (never used here).
    if [ "$HISTORY_TOTAL" -gt 0 ] && grep -aFq -- "$ROOT" "$CLAUDE_HOME/history.jsonl" 2>/dev/null; then
      HISTORY_SUSPECT=true
      printf '%s: warning: history.jsonl mentions this project but no line matched the expected record format; the schema may have changed\n' \
        "$PROGRAM" >&2
    fi
  else
    printf '%s%s%s%s%s\n' "user/history.jsonl" "$SEP" "union-log" "$SEP" "timestamp+sessionId" >>"$MERGEPLAN"
    printf '%s%s%s\n' "user/history.jsonl" "$SEP" "state" >>"$TMP_DIR/provenance"
  fi
fi

# ── quarantine derived indexes ───────────────────────────────────────────────

# Routers and index caches move OUT of project/ and user/ so that a naive
# `cp -R bundle/project/. dest/` cannot clobber one. They still ship: import
# needs them to detect drift and to seed a regeneration on a bare destination.
: >"$TMP_DIR/mergeplan.new"
while IFS="$SEP" read -r rel class key; do
  [ -n "$rel" ] || continue
  case "$class" in
    derived-index | union-route)
      case "$rel" in
        project/*) newrel="project-derived/${rel#project/}" ;;
        user/*) newrel="user-derived/${rel#user/}" ;;
        *) newrel=$rel ;;
      esac
      if [ -f "$STAGE/$rel" ]; then
        mkdir -p "$(dirname -- "$STAGE/$newrel")" 2>/dev/null
        mv -- "$STAGE/$rel" "$STAGE/$newrel" 2>/dev/null
      fi
      printf '%s%s%s%s%s\n' "$newrel" "$SEP" "$class" "$SEP" "$key" >>"$TMP_DIR/mergeplan.new"
      ;;
    *)
      printf '%s%s%s%s%s\n' "$rel" "$SEP" "$class" "$SEP" "$key" >>"$TMP_DIR/mergeplan.new"
      ;;
  esac
done <"$MERGEPLAN"
mv "$TMP_DIR/mergeplan.new" "$MERGEPLAN"

# Provenance paths must follow the same relocation.
: >"$TMP_DIR/provenance.new"
while IFS="$SEP" read -r rel prov; do
  [ -n "$rel" ] || continue
  if [ -f "$STAGE/$rel" ]; then
    printf '%s%s%s\n' "$rel" "$SEP" "$prov" >>"$TMP_DIR/provenance.new"
  else
    case "$rel" in
      project/*) alt="project-derived/${rel#project/}" ;;
      user/*) alt="user-derived/${rel#user/}" ;;
      *) alt=$rel ;;
    esac
    if [ -f "$STAGE/$alt" ]; then
      printf '%s%s%s\n' "$alt" "$SEP" "$prov" >>"$TMP_DIR/provenance.new"
    fi
  fi
done <"$TMP_DIR/provenance"
mv "$TMP_DIR/provenance.new" "$TMP_DIR/provenance"

# ── secret scan ──────────────────────────────────────────────────────────────

# Every rule carries a minimum trailing length. Measured over ~100 MB of real
# transcripts: unconstrained `sk-ant-` yields 24 false positives (the corpus
# discusses secret scanning); with length constraints, zero -- while still
# catching real Google keys and JWTs. Do not relax these.
scan_rules() {
  cat <<'EOF'
ANTHROPIC_KEY sk-ant-[A-Za-z0-9_-]{20,}
OPENAI_KEY sk-(proj-)?[A-Za-z0-9]{40,}
AWS_ACCESS_KEY_ID (AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}
GITHUB_TOKEN gh[pousr]_[A-Za-z0-9]{36,}
GITHUB_PAT_FINE github_pat_[A-Za-z0-9_]{60,}
SLACK_TOKEN xox[baprs]-[0-9A-Za-z-]{20,}
GOOGLE_API_KEY AIza[0-9A-Za-z_-]{35}
NPM_TOKEN npm_[A-Za-z0-9]{36}
STRIPE_LIVE_KEY (sk|rk)_live_[0-9A-Za-z]{24,}
PRIVATE_KEY_PEM -----BEGIN ([A-Z]+ )?PRIVATE KEY-----
JWT eyJ[A-Za-z0-9_-]{15,}\.eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{20,}
BEARER [Bb]earer [A-Za-z0-9._~+/-]{32,}={0,2}
EOF
}

RULE_COUNT=$(scan_rules | wc -l | tr -d ' ')
scan_rules >"$TMP_DIR/rules"
while read -r rule_id rule_re; do
  [ -n "$rule_id" ] || continue
  grep -arlE -- "$rule_re" "$STAGE" 2>/dev/null >"$TMP_DIR/rule-hits" || :
  while IFS= read -r hf; do
    [ -n "$hf" ] || continue
    hrel=${hf#"$STAGE/"}
    # awk -F: takes only the line number; the matched bytes never enter a
    # variable, a file, or a pipe again.
    grep -anE -- "$rule_re" "$hf" 2>/dev/null | awk -F: -v r="$rule_id" -v p="$hrel" '
      { printf "%s\034%s\034%s\n", r, p, $1 }
    ' >>"$FINDINGS"
    printf '%s\n' "$hrel" >>"$HITFILES"
  done <"$TMP_DIR/rule-hits"
done <"$TMP_DIR/rules"

FINDING_COUNT=$(wc -l <"$FINDINGS" | tr -d ' ')
FILES_WITH_HITS=$(LC_ALL=C sort -u "$HITFILES" 2>/dev/null | wc -l | tr -d ' ')

# ── path-token discovery ─────────────────────────────────────────────────────

# Export DESCRIBES paths; it never rewrites them. Shipping a token map instead
# of pre-rewritten bytes keeps the bundle read-only-derived and deterministic,
# lets one bundle target many destinations, and gives import a count invariant:
# rewrite, recount against PATHMAP.files, abort on any mismatch.
#
# Paths appear in six measured encodings. Raw and mangled are the obvious two;
# tilde, file://, JSON-escaped \/ and percent-encoded %2F are all present in
# real transcripts and are invisible to a raw-byte substitution.
PATHMAP=$TMP_DIR/pathmap
PATHMAP_FILES=$TMP_DIR/pathmap-files
CWDS=$TMP_DIR/cwds
: >"$PATHMAP"
: >"$PATHMAP_FILES"
: >"$CWDS"

# Tokens are registered first, then counted in ONE disjoint pass. Counting each
# token with its own independent grep double-counts every overlapping pair --
# HOME is a strict prefix of both PROJECT_ROOT and CLAUDE_HOME, so a naive sum
# over-reports by the full size of the nested tokens. Import rewrites
# disjointly, so its recount would never reconcile with an overlapping map.
TOKENS=$TMP_DIR/tokens
: >"$TOKENS"

register_token() {
  [ -n "$2" ] || return 0
  printf '%s%s%s%s%s\n' "$1" "$SEP" "$2" "$SEP" "$3" >>"$TOKENS"
  return 0
}

# Register every encoding of one absolute path. The escaped and percent forms
# are measured to occur in real transcripts and are invisible to a raw scan.
register_path_all_encodings() {
  register_token "$1" "$2" raw
  register_token "$1" "file://$2" uri
  register_token "$1" "$(printf '%s' "$2" | sed 's|/|\\/|g')" escaped
  register_token "$1" "$(printf '%s' "$2" | sed 's|/|%2F|g')" percent
  return 0
}

HOME_DIR=${HOME:-}

# Harvest every distinct cwd from the staged transcripts. cwd is a per-record
# field that follows the working directory into subdirectories, so a project
# legitimately carries several -- measured up to 7 in one real project.
if [ -d "$STAGE/user/sessions" ]; then
  find "$STAGE/user/sessions" -type f -name '*.jsonl' 2>/dev/null \
    -exec grep -aoh '"cwd":"[^"]*"' {} + 2>/dev/null |
    sed -e 's|"cwd":"||' -e 's|"$||' | LC_ALL=C sort -u >"$CWDS"
fi

register_path_all_encodings PROJECT_ROOT "$ROOT"
register_token PROJECTS_DIR "$MANGLED" mangled
register_path_all_encodings CLAUDE_HOME "$CLAUDE_HOME"
register_token CLAUDE_HOME "~/.claude" tilde

ALIAS_ROOTS=$TMP_DIR/alias-roots
: >"$ALIAS_ROOTS"
if [ -n "$ALIAS_ROOT_RAW" ]; then
  printf '%s' "$ALIAS_ROOT_RAW" | LC_ALL=C sort -u >"$ALIAS_ROOTS"
fi

FOREIGN_COUNT=0
while IFS= read -r cw; do
  [ -n "$cw" ] || continue
  [ "$cw" = "$ROOT" ] && continue
  case "$cw" in
    "$ROOT"/*)
      register_path_all_encodings PROJECT_SUBPATH "$cw"
      ;;
    *)
      # A cwd that is not a descendant of the project root: either the project
      # was moved/renamed (ALIAS_ROOT) or it belongs to another project
      # (FOREIGN). FOREIGN is never rewritten to the project root -- doing so
      # would be data corruption, not a translation.
      if grep -aFxq -- "$cw" "$ALIAS_ROOTS" 2>/dev/null; then
        register_path_all_encodings ALIAS_ROOT "$cw"
      else
        register_path_all_encodings FOREIGN "$cw"
        FOREIGN_COUNT=$((FOREIGN_COUNT + 1))
      fi
      ;;
  esac
done <"$CWDS"

# Declared alias roots that never appear as a cwd still need mapping.
while IFS= read -r ar; do
  [ -n "$ar" ] || continue
  if ! grep -aFxq -- "$ar" "$CWDS" 2>/dev/null; then
    register_path_all_encodings ALIAS_ROOT "$ar"
  fi
done <"$ALIAS_ROOTS"

# Foreign roots come from the sibling project directories in the Claude home,
# probed for their own cwd -- NOT from a regex over transcript prose. A prose
# scan looks appealing but over-matches badly: an earlier attempt returned 83
# "roots", most of them JSON config keys captured in tool output such as
# ".../devcontainer.lastModelUsage.claude-opus-4-7.inputTokens". Sibling dirs
# are ground truth, so this has no false positives.
if [ -d "$CLAUDE_HOME/projects" ]; then
  find "$CLAUDE_HOME/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
    LC_ALL=C sort >"$TMP_DIR/sibling-dirs"
  while IFS= read -r sib; do
    [ -n "$sib" ] || continue
    [ "${sib##*/}" = "$PROJECTS_DIR" ] && continue
    find "$sib" -mindepth 1 -maxdepth 1 -name '*.jsonl' -type f 2>/dev/null |
      LC_ALL=C sort | head -n 1 >"$TMP_DIR/sib-jsonl"
    while IFS= read -r sj; do
      [ -n "$sj" ] || continue
      sib_cwd=$(head -n 50 "$sj" 2>/dev/null | grep -aoh '"cwd":"[^"]*"' 2>/dev/null |
        head -n 1 | sed -e 's|"cwd":"||' -e 's|"$||')
      if [ -n "$sib_cwd" ] && [ "$sib_cwd" != "$ROOT" ]; then
        register_path_all_encodings FOREIGN "$sib_cwd"
        register_token FOREIGN "${sib##*/}" mangled
        FOREIGN_COUNT=$((FOREIGN_COUNT + 1))
      fi
    done <"$TMP_DIR/sib-jsonl"
  done <"$TMP_DIR/sibling-dirs"
fi

if [ -n "$HOME_DIR" ] && [ "$HOME_DIR" != "$ROOT" ]; then
  register_token HOME "$HOME_DIR" raw
fi

# One disjoint pass over every staged file. Tokens are tried longest-first at
# each position, so a nested token can never be counted inside its container.
# NUL is translated to \001 on the way in: grep silently treats a NUL-bearing
# file as binary and can skip it entirely (measured: every real transcript
# contains NUL), and some awks truncate strings at NUL. The substitution is
# byte-for-byte length preserving and \001 appears in no path token, so offsets
# and counts are unaffected.
# Raw per-file counts first: grep is C and fast, where a character-by-character
# awk scan over 10 MB x N tokens is not. Overlap is then removed arithmetically
# below, which is exact because containment among these tokens is substring
# containment: every occurrence of a longer token B contains a fixed number of
# occurrences of any shorter token A, so disjoint(A) = raw(A) - SUM k(A,B) *
# disjoint(B) over longer B. That needs only the token strings, not the corpus.
: >"$TMP_DIR/scan-rawcounts"
find "$STAGE" -type f 2>/dev/null | LC_ALL=C sort >"$TMP_DIR/scan-files"
while IFS= read -r sf; do
  [ -n "$sf" ] || continue
  srel=${sf#"$STAGE/"}
  tr '\000' '\001' <"$sf" 2>/dev/null >"$TMP_DIR/scan-body"
  while IFS="$SEP" read -r tclass ttok tenc; do
    [ -n "$ttok" ] || continue
    tn=$(grep -aoF -e "$ttok" -- "$TMP_DIR/scan-body" 2>/dev/null | wc -l | tr -d ' ')
    [ -n "$tn" ] || tn=0
    if [ "$tn" -gt 0 ]; then
      printf '%s%s%s%s%s%s%s%s%s\n' \
        "$srel" "$SEP" "$tclass" "$SEP" "$ttok" "$SEP" "$tenc" "$SEP" "$tn" >>"$TMP_DIR/scan-rawcounts"
    fi
  done <"$TOKENS"
done <"$TMP_DIR/scan-files"

# Remove nested double-counting, per file, longest token first.
awk -F'\034' -v OFS='\034' '
  function occ_in(a, b,   n, p, i) {
    if (length(a) == 0 || length(a) > length(b)) return 0
    n = 0; p = 1
    while ((i = index(substr(b, p), a)) > 0) { n++; p = p + i + length(a) - 1 }
    return n
  }
  { rel[NR] = $1; cls[NR] = $2; tok[NR] = $3; enc[NR] = $4; raw[NR] = $5; nrec = NR }
  END {
    for (r = 1; r <= nrec; r++) files[rel[r]] = 1
    for (f in files) {
      n = 0
      for (r = 1; r <= nrec; r++) if (rel[r] == f) { n++; idx[n] = r }
      for (i = 1; i <= n; i++)
        for (j = i + 1; j <= n; j++)
          if (length(tok[idx[j]]) > length(tok[idx[i]])) { t = idx[i]; idx[i] = idx[j]; idx[j] = t }
      for (i = 1; i <= n; i++) {
        d = raw[idx[i]]
        for (j = 1; j < i; j++) d -= occ_in(tok[idx[i]], tok[idx[j]]) * dis[idx[j]]
        if (d < 0) d = 0
        dis[idx[i]] = d
      }
    }
    for (r = 1; r <= nrec; r++)
      if (dis[r] > 0) print rel[r], cls[r], tok[r], enc[r], dis[r]
  }
' "$TMP_DIR/scan-rawcounts" >"$TMP_DIR/scan-raw"

[ -f "$TMP_DIR/scan-raw" ] || : >"$TMP_DIR/scan-raw"

awk -F'\034' -v OFS='\034' '{ print $1, $3, $5 }' "$TMP_DIR/scan-raw" >"$PATHMAP_FILES"
awk -F'\034' '
  { key = $2 "\034" $3 "\034" $4; occ[key] += $5; files[key]++ }
  END { for (k in occ) printf "%s\034%d\034%d\n", k, occ[k], files[k] }
' "$TMP_DIR/scan-raw" | LC_ALL=C sort >"$PATHMAP"

# A declared alias root that matched nothing is a silently-ineffective flag.
while IFS= read -r ar; do
  [ -n "$ar" ] || continue
  if ! awk -F'\034' -v a="$ar" '$2 == a || $2 == "file://" a { found = 1 } END { exit(found ? 0 : 1) }' "$PATHMAP"; then
    usage_error "--alias-root has no occurrences in the bundle: $ar"
  fi
done <"$ALIAS_ROOTS"

PATH_TOKEN_COUNT=$(wc -l <"$PATHMAP" | tr -d ' ')
PATH_OCCURRENCES=$(awk -F'\034' '{ t += $4 } END { printf "%d", t + 0 }' "$PATHMAP")
CWD_DISTINCT=$(wc -l <"$CWDS" | tr -d ' ')

REWRITE_ORDER="PROJECT_SUBPATH,ALIAS_ROOT,PROJECT_ROOT,CLAUDE_HOME,PROJECTS_DIR,HOME"

# ── inventory + bundle id ────────────────────────────────────────────────────

build_inventory() {
  (cd "$STAGE" && find . -type f 2>/dev/null -exec cksum {} \;) |
    sed -e 's| \./| |' | LC_ALL=C sort
}

build_inventory >"$INVENTORY"
INV_FILES=$(wc -l <"$INVENTORY" | tr -d ' ')
INV_BYTES=$(awk '{ total += $2 } END { printf "%d", total + 0 }' "$INVENTORY")

# Content-derived, so re-exporting identical data yields the same id. Import
# embeds this in sidecar filenames, so it must be a valid kebab slug and must
# be stable -- a random or timestamp id would break import idempotency.
BUNDLE_CRC=$(cksum <"$INVENTORY" | awk '{print $1}')
BUNDLE_ID=$(printf '%08x' "$BUNDLE_CRC" 2>/dev/null) || BUNDLE_ID=00000000

CREATED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')
CREATED_EPOCH=$(date -u +%s 2>/dev/null || printf '0')
SOURCE_OS=$(uname -s 2>/dev/null || printf 'unknown')

GIT_HEAD=
GIT_BRANCH=
GIT_DIRTY=false
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  GIT_HEAD=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)
  GIT_BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
    GIT_DIRTY=true
  fi
fi

CLI_VERSION=
if [ "$SESSIONS_SELECTED" -gt 0 ]; then
  CLI_VERSION=$(head -n 50 "$STAGE/user/sessions/"*.jsonl 2>/dev/null |
    grep -oE '"version":"[0-9][0-9.]*"' 2>/dev/null | head -n 1 |
    sed -e 's|"version":"||' -e 's|"||')
fi

PARENT_BUNDLE_ID=
LEDGER=$ROOT/.claude/.portability/ledger.tsv
if [ -f "$LEDGER" ]; then
  PARENT_BUNDLE_ID=$(awk -F'\034' 'NF >= 1 { last = $1 } END { print last }' "$LEDGER" 2>/dev/null)
fi

# ── emit MANIFEST.json ───────────────────────────────────────────────────────

MANIFEST=$TMP_DIR/manifest.json

emit_manifest() {
  {
    printf '{\n'
    printf '  "schema": "%s",\n' "$(jstr "$SCHEMA")"
    printf '  "generator": "claudart-backup.sh",\n'
    printf '  "bundle_id": "%s",\n' "$(jstr "$BUNDLE_ID")"
    printf '  "created_utc": "%s",\n' "$(jstr "$CREATED_UTC")"
    printf '  "created_epoch": %s,\n' "$(jnum "$CREATED_EPOCH")"
    printf '  "lineage": {\n'
    if [ -n "$PARENT_BUNDLE_ID" ]; then
      printf '    "parent_bundle_id": "%s"\n' "$(jstr "$PARENT_BUNDLE_ID")"
    else
      printf '    "parent_bundle_id": null\n'
    fi
    printf '  },\n'
    printf '  "source": {\n'
    printf '    "os": "%s",\n' "$(jstr "$SOURCE_OS")"
    printf '    "project_root": "%s",\n' "$(jstr "$ROOT")"
    printf '    "claude_home": "%s",\n' "$(jstr "$CLAUDE_HOME")"
    printf '    "projects_dir": "%s",\n' "$(jstr "$PROJECTS_DIR")"
    printf '    "projects_dir_resolution": "%s",\n' "$(jstr "$PROJECTS_RESOLUTION")"
    printf '    "cli_version_seen": "%s",\n' "$(jstr "$CLI_VERSION")"
    printf '    "git_head": "%s",\n' "$(jstr "$GIT_HEAD")"
    printf '    "git_branch": "%s",\n' "$(jstr "$GIT_BRANCH")"
    printf '    "git_dirty": %s\n' "$GIT_DIRTY"
    printf '  },\n'
    printf '  "classes": {\n'
    printf '    "project": "included:%s",\n' "$(jstr "$PROJECT_SCOPE")"
    if [ "$MEMORY_COUNT" -gt 0 ]; then
      printf '    "memory": "included",\n'
    else
      printf '    "memory": "absent",\n'
    fi
    printf '    "sessions": "%s",\n' "$(jstr "$SESSIONS_MODE")"
    printf '    "history": "%s",\n' "$(jstr "$HISTORY_MODE")"
    printf '    "plans": "excluded:unreliable-attribution",\n'
    printf '    "file_history": "excluded:redundant-with-git",\n'
    printf '    "config": "excluded:out-of-scope",\n'
    printf '    "credentials": "excluded:never-read"\n'
    printf '  },\n'
    printf '  "selection": { "sessions_available": %s, "sessions_selected": %s, "recent_n": %s },\n' \
      "$(jnum "$SESSIONS_AVAILABLE")" "$(jnum "$SESSIONS_SELECTED")" "$(jnum "$RECENT_N")"
    printf '  "history": { "source_lines": %s, "selected_lines": %s, "lines_with_pasted_content": %s, "suspect_format": %s },\n' \
      "$(jnum "$HISTORY_TOTAL")" "$(jnum "$HISTORY_KEPT")" "$(jnum "$HISTORY_PASTED")" "$HISTORY_SUSPECT"
    printf '  "skipped": [\n'
    first=1
    while IFS="$SEP" read -r srel sreason; do
      [ -n "$srel" ] || continue
      if [ "$first" -eq 1 ]; then first=0; else printf ',\n'; fi
      printf '    {"path": "%s", "reason": "%s"}' "$(jstr "$srel")" "$(jstr "$sreason")"
    done <"$SKIPPED"
    [ "$first" -eq 1 ] || printf '\n'
    printf '  ],\n'
    printf '  "secret_scan": {\n'
    printf '    "performed": true,\n'
    printf '    "rule_count": %s,\n' "$(jnum "$RULE_COUNT")"
    printf '    "hit_count": %s,\n' "$(jnum "$FINDING_COUNT")"
    printf '    "files_with_hits": %s,\n' "$(jnum "$FILES_WITH_HITS")"
    printf '    "acknowledged": %s,\n' "$ALLOW_SECRETS"
    printf '    "findings": [\n'
    first=1
    while IFS="$SEP" read -r frule fpath fline; do
      [ -n "$frule" ] || continue
      if [ "$first" -eq 1 ]; then first=0; else printf ',\n'; fi
      # Rule id, path, and line only -- never the matched bytes, so this file
      # stays safe to paste into a bug report.
      printf '      {"rule": "%s", "path": "%s", "line": %s}' \
        "$(jstr "$frule")" "$(jstr "$fpath")" "$(jnum "$fline")"
    done <"$FINDINGS"
    [ "$first" -eq 1 ] || printf '\n'
    printf '    ],\n'
    printf '    "note": "Heuristic. Absence of findings does not mean the bundle is free of secrets."\n'
    printf '  },\n'
    printf '  "paths": {\n'
    printf '    "project_root": "%s",\n' "$(jstr "$ROOT")"
    printf '    "claude_home": "%s",\n' "$(jstr "$CLAUDE_HOME")"
    printf '    "projects_dir": "%s",\n' "$(jstr "$MANGLED")"
    printf '    "home": "%s",\n' "$(jstr "$HOME_DIR")"
    printf '    "cwd_distinct": %s,\n' "$(jnum "$CWD_DISTINCT")"
    printf '    "token_count": %s,\n' "$(jnum "$PATH_TOKEN_COUNT")"
    printf '    "occurrence_total": %s,\n' "$(jnum "$PATH_OCCURRENCES")"
    printf '    "foreign_roots": %s,\n' "$(jnum "$FOREIGN_COUNT")"
    printf '    "encodings": ["raw", "mangled", "tilde", "uri", "escaped", "percent"],\n'
    printf '    "rewrite_order": ['
    printf '%s' "$REWRITE_ORDER" | tr ',' '\n' | awk '
      { if (NR > 1) printf ", "; printf "\"%s\"", $0 }
    '
    printf '],\n'
    printf '    "cwd_histogram": [\n'
    first=1
    while IFS= read -r cwv; do
      [ -n "$cwv" ] || continue
      if [ "$first" -eq 1 ]; then first=0; else printf ',\n'; fi
      printf '      {"cwd": "%s"}' "$(jstr "$cwv")"
    done <"$CWDS"
    [ "$first" -eq 1 ] || printf '\n'
    printf '    ],\n'
    printf '    "tokens": [\n'
    first=1
    while IFS="$SEP" read -r pclass ptok penc pocc pfc; do
      [ -n "$pclass" ] || continue
      if [ "$first" -eq 1 ]; then first=0; else printf ',\n'; fi
      printf '      {"class": "%s", "token": "%s", "encoding": "%s", "occurrences": %s, "files": %s}' \
        "$(jstr "$pclass")" "$(jstr "$ptok")" "$(jstr "$penc")" "$(jnum "$pocc")" "$(jnum "$pfc")"
    done <"$PATHMAP"
    [ "$first" -eq 1 ] || printf '\n'
    printf '    ]\n'
    printf '  },\n'
    printf '  "inventory_totals": { "files": %s, "bytes": %s },\n' \
      "$(jnum "$INV_FILES")" "$(jnum "$INV_BYTES")"
    printf '  "inventory": [\n'
    first=1
    while read -r icrc isize ipath; do
      [ -n "$ipath" ] || continue
      iprov=$(awk -F'\034' -v p="$ipath" '$1 == p { print $2; exit }' "$TMP_DIR/provenance")
      [ -n "$iprov" ] || iprov=state
      iclass=$(awk -F'\034' -v p="$ipath" '$1 == p { print $2; exit }' "$MERGEPLAN")
      [ -n "$iclass" ] || iclass=unique
      ikey=$(awk -F'\034' -v p="$ipath" '$1 == p { print $3; exit }' "$MERGEPLAN")
      if [ "$first" -eq 1 ]; then first=0; else printf ',\n'; fi
      printf '    {"path": "%s", "bytes": %s, "cksum": "%s", "provenance": "%s", "merge": "%s", "merge_key": "%s"}' \
        "$(jstr "$ipath")" "$(jnum "$isize")" "$(jstr "$icrc")" \
        "$(jstr "$iprov")" "$(jstr "$iclass")" "$(jstr "$ikey")"
    done <"$INVENTORY"
    [ "$first" -eq 1 ] || printf '\n'
    printf '  ]\n'
    printf '}\n'
  }
}

emit_manifest >"$MANIFEST"

# ── README + SECRETS ─────────────────────────────────────────────────────────

emit_readme() {
  cat <<EOF
CLAUDART portable bundle
========================

schema:     $SCHEMA
bundle id:  $BUNDLE_ID
created:    $CREATED_UTC
source:     $ROOT

WHAT IS IN HERE
  project/           the project .claude/ layer (and .codex/, .agents/ if present)
  project-derived/   index caches and knowledge routers, quarantined so a naive
                     copy cannot clobber a router on the destination
  user/memory/       per-project memory notes
  user/sessions/     session transcripts and their subagent / tool-result sidecars
  user/history.jsonl this project's slice of the prompt history
  INVENTORY          cksum + size + path for every payload file
  MERGEPLAN          per-file merge class and merge key, consumed by restore
  PATHMAP            every path token, its class and encoding, with counts
  PATHMAP.files      per-file occurrence counts -- restore's count invariant
  MANIFEST.json      provenance, policy, and the full inventory

PATHS ARE DESCRIBED, NOT REWRITTEN
  This bundle contains the ORIGINAL paths. Restore translates them into the
  destination's coordinates using PATHMAP, then recounts every token against
  PATHMAP.files and aborts if a single occurrence is unaccounted for. That is
  why one bundle can be restored into many different locations.

DISCLOSURE
  Session transcripts record the paths of other projects you worked on from the
  same machine. This bundle references $FOREIGN_COUNT other project root(s); their names
  are visible in PATHMAP. They are not credentials, so the secret scan does not
  flag them, and they are not scrubbed -- but you should know they are here
  before sharing this bundle.

WHAT IS DELIBERATELY NOT IN HERE
  Claude Code settings, ~/.claude.json, OAuth and API credentials, session keys,
  IDE lock files, paste cache, plugins, installed agents and skills, file-history
  snapshots, and ~/.claude/plans. Collection is an allow-list, so those paths are
  never opened at all.

  ~/.claude/plans is excluded because plan files carry no project field and
  attribution by content grep is unreliable. Durable plans belong in
  .claude/tasks/ via /plan, and those are exported losslessly.

HOW TO USE IT
  bash .claude/scripts/claudart-restore.sh --bundle <this dir> --mode full
  Add --apply once the reported plan looks right. Restore never overwrites an
  existing file; anything it cannot merge mechanically is parked for review.

NOTE: the secret scan is heuristic. It matches known credential shapes only. It
      will not catch a password written in prose, a base64 blob, or a private key
      pasted without its header. Transcripts contain raw tool output and file
      contents. Review MANIFEST.json before sharing this bundle.
EOF
}

emit_secrets() {
  while IFS="$SEP" read -r frule fpath fline; do
    [ -n "$frule" ] || continue
    printf '%-18s %s:%s\n' "$frule" "$fpath" "$fline"
  done <"$FINDINGS"
}

# ── report ───────────────────────────────────────────────────────────────────

human_bytes() {
  awk -v b="${1:-0}" 'BEGIN {
    if (b >= 1048576) printf "%.1f MiB", b / 1048576
    else if (b >= 1024) printf "%.1f KiB", b / 1024
    else printf "%d B", b
  }'
}

PROJECT_FILES=$(awk -F'\034' '$1 ~ /^project(-derived)?\// { n++ } END { printf "%d", n + 0 }' "$MERGEPLAN")
SKIP_COUNT=$(wc -l <"$SKIPPED" | tr -d ' ')

print_report() {
  if [ "$DRY_RUN" = true ]; then
    printf 'bundle:        (dry run, nothing written)\n'
  else
    printf 'bundle:        %s\n' "$OUT_DIR"
  fi
  printf 'schema:        %s\n' "$SCHEMA"
  printf 'bundle id:     %s\n' "$BUNDLE_ID"
  printf 'source:        %s\n' "$ROOT"
  if [ -n "$PROJECTS_DIR" ]; then
    printf 'user data:     %s/projects/%s (%s)\n' "$CLAUDE_HOME" "$PROJECTS_DIR" "$PROJECTS_RESOLUTION"
  else
    printf 'user data:     none found for this project\n'
  fi
  printf 'project layer: %s files (scope: %s)\n' "$PROJECT_FILES" "$PROJECT_SCOPE"
  printf 'memory:        %s files\n' "$MEMORY_COUNT"
  printf 'sessions:      %s of %s (%s)\n' "$SESSIONS_SELECTED" "$SESSIONS_AVAILABLE" "$SESSIONS_MODE"
  printf '  subagents:   %s files\n' "$SUBAGENT_COUNT"
  printf '  tool-results:%s files\n' "$TOOLRESULT_COUNT"
  printf 'history:       %s of %s lines (%s with pasted content)\n' \
    "$HISTORY_KEPT" "$HISTORY_TOTAL" "$HISTORY_PASTED"
  printf 'skipped:       %s paths\n' "$SKIP_COUNT"
  printf 'path tokens:   %s tokens, %s occurrences, %s distinct cwd\n' \
    "$PATH_TOKEN_COUNT" "$PATH_OCCURRENCES" "$CWD_DISTINCT"
  printf 'foreign paths: %s other project root(s) referenced (see PATHMAP)\n' "$FOREIGN_COUNT"
  printf 'secret scan:   %s rules, %s findings\n' "$RULE_COUNT" "$FINDING_COUNT"
  printf 'total:         %s files, %s\n' "$INV_FILES" "$(human_bytes "$INV_BYTES")"
  printf '\n'
  printf 'NOTE: this scan is heuristic. It matches known credential shapes only. It will\n'
  printf '      not catch a password written in prose, a base64 blob, or a private key\n'
  printf '      pasted without its header. Transcripts contain raw tool output and file\n'
  printf '      contents. Review MANIFEST.json before sharing this bundle.\n'
}

# ── commit ───────────────────────────────────────────────────────────────────

if [ "$FINDING_COUNT" -gt 0 ]; then
  printf '%s: secret scan found %s match(es) in %s file(s):\n' \
    "$PROGRAM" "$FINDING_COUNT" "$FILES_WITH_HITS" >&2
  emit_secrets >&2
  if [ "$ALLOW_SECRETS" != true ]; then
    printf '%s: bundle withheld. Re-run with --allow-secrets to write it anyway.\n' "$PROGRAM" >&2
    print_report
    exit 1
  fi
fi

if [ "$DRY_RUN" = true ]; then
  print_report
  if [ "$FINDING_COUNT" -gt 0 ]; then
    exit 1
  fi
  exit 0
fi

cp "$MANIFEST" "$STAGE/MANIFEST.json" || usage_error "cannot stage MANIFEST.json"
cp "$INVENTORY" "$STAGE/INVENTORY" || usage_error "cannot stage INVENTORY"
cp "$MERGEPLAN" "$STAGE/MERGEPLAN" || usage_error "cannot stage MERGEPLAN"
# cksum agreement between macOS and Linux is assumed, never verified here.
# Shipping known content plus its checksum lets restore prove its own cksum
# matches the exporter's before it trusts INVENTORY at all.
printf 'claudart selftest v1\n' >"$STAGE/SELFTEST" || usage_error "cannot stage SELFTEST"
cksum <"$STAGE/SELFTEST" | awk '{ print $1, $2 }' >"$STAGE/SELFTEST.cksum" ||
  usage_error "cannot stage SELFTEST.cksum"
cp "$PATHMAP" "$STAGE/PATHMAP" || usage_error "cannot stage PATHMAP"
cp "$PATHMAP_FILES" "$STAGE/PATHMAP.files" || usage_error "cannot stage PATHMAP.files"
emit_readme >"$STAGE/README.txt" || usage_error "cannot stage README.txt"
if [ "$FINDING_COUNT" -gt 0 ]; then
  emit_secrets >"$STAGE/SECRETS.txt" || usage_error "cannot stage SECRETS.txt"
fi

# The bundle appears in exactly one operation. Staging is a sibling of the
# destination, so this is a same-filesystem rename: complete, or absent.
mv -- "$STAGE" "$OUT_DIR" 2>/dev/null ||
  usage_error "cannot finalize the bundle at $OUT_DIR"

if [ "$ARCHIVE" = true ]; then
  (cd "$OUT_PARENT" && find "$(basename -- "$OUT_DIR")" -type f 2>/dev/null | LC_ALL=C sort) \
    >"$TMP_DIR/tarlist"
  if ! (cd "$OUT_PARENT" && tar -c -f - -T "$TMP_DIR/tarlist" 2>/dev/null | gzip -n -9 >"$OUT_DIR.tar.gz"); then
    printf '%s: warning: could not write %s.tar.gz\n' "$PROGRAM" "$OUT_DIR" >&2
  fi
fi

print_report

if [ "$FINDING_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
