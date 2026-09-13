#!/bin/bash

# Read-only validator, scheduler and reporter for CLAUDART spec missions.
# Runtime dependencies are limited to Bash 3.2 and common POSIX utilities.
#
# The spec workflow states a large number of rules that a machine can decide:
# which ROADMAP dispositions are legal, what a LEDGER may record, when a status
# contradicts the plan it describes. This script supplies the enforcer for them.
# It never writes; findings only.

set -u

LC_ALL=C
export LC_ALL

PROGRAM=${0##*/}
SUBCOMMAND=lint
FAIL_ON=error
ROOT_OVERRIDE=
LAYER_OVERRIDE=
SPEC_FILTER=
SEP=$(printf '\034')

usage() {
  cat <<'EOF'
Usage: spec-check.sh [lint|next|status] [options]

Read-only validation and scheduling for CLAUDART spec missions.

Subcommands:
  lint                       Report contract findings (default)
  next                       Print the runnable task set, computed from edges
  status                     Report loop metrics for each active mission

Options:
  --root DIR                 Repository root (default: inferred from script path)
  --layer claude|codex|deepseek|pi
                             Runtime layer (default: inferred from script path)
  --spec SLUG                Restrict to one mission (folder id or short slug)
  --fail-on error|warning    Exit 1 at this severity (default: error)
  --help                     Show this help

Exit status:
  0  no finding at or above the selected threshold
  1  at least one finding at or above the selected threshold
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

case "$SCRIPT_DIR" in
  */.claude/scripts) INFERRED_LAYER=claude ;;
  */.codex/scripts) INFERRED_LAYER=codex ;;
  */.deepseek/scripts) INFERRED_LAYER=deepseek ;;
  */.pi/scripts) INFERRED_LAYER=pi ;;
  *) INFERRED_LAYER= ;;
esac

case "${1:-}" in
  lint | next | status)
    SUBCOMMAND=$1
    shift
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] || usage_error "--root requires a directory"
      ROOT_OVERRIDE=$2
      shift 2
      ;;
    --layer)
      [ "$#" -ge 2 ] || usage_error "--layer requires claude, codex, deepseek, or pi"
      LAYER_OVERRIDE=$2
      shift 2
      ;;
    --spec)
      [ "$#" -ge 2 ] || usage_error "--spec requires a mission slug"
      SPEC_FILTER=$2
      shift 2
      ;;
    --fail-on)
      [ "$#" -ge 2 ] || usage_error "--fail-on requires error or warning"
      FAIL_ON=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --*) usage_error "unknown option: $1" ;;
    *) usage_error "unexpected argument: $1" ;;
  esac
done

case "$FAIL_ON" in
  error | warning) ;;
  *) usage_error "--fail-on must be error or warning" ;;
esac

if [ -n "$LAYER_OVERRIDE" ]; then
  LAYER=$LAYER_OVERRIDE
else
  LAYER=$INFERRED_LAYER
fi
case "$LAYER" in
  claude | codex | deepseek | pi) ;;
  *) usage_error "cannot infer layer; pass --layer claude, --layer codex, --layer deepseek, or --layer pi" ;;
esac

if [ -n "$ROOT_OVERRIDE" ]; then
  [ -d "$ROOT_OVERRIDE" ] || usage_error "--root is not a directory"
  ROOT=$(CDPATH='' cd -- "$ROOT_OVERRIDE" 2>/dev/null && pwd -P) ||
    usage_error "cannot resolve --root"
else
  ROOT=$INFERRED_ROOT
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claudart-spec-check.XXXXXX" 2>/dev/null) ||
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

FINDINGS=$TMP_DIR/findings
: >"$FINDINGS"

SPECS_REL=.$LAYER/specs
SPECS=$ROOT/$SPECS_REL

STATUS_ENUM="drafting poc-review ready running blocked awaiting-final-review done cancelled"
TERMINAL_STATUS="done cancelled"
COMMITS_ENUM="user per-task per-phase"
EVENT_VOCAB="run-started task-started task-completed validation-failed phase-validated task-blocked replanned delegated circuit-breaker rotation-checkpoint scope-change final-gate"
EDGE_TYPES="IMPLEMENTATION CONTRACT PORT DATA RUNTIME TEST DEPLOYMENT EVIDENCE"
NOTES_CEILING=150

add_finding() {
  severity=$1
  code=$2
  path=$3
  line=$4
  message=$5
  case "$line" in
    '' | *[!0-9]*) line=1 ;;
  esac
  printf '%s|%s|%s:%s|%s\n' "$severity" "$code" "$path" "$line" "$message" >>"$FINDINGS"
}

in_list() {
  needle=$1
  shift
  for candidate in $1; do
    [ "$candidate" = "$needle" ] && return 0
  done
  return 1
}

frontmatter_value() {
  awk -v key="$2" '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { inside = 1; next }
    inside && $0 == "---" { exit }
    inside {
      pos = index($0, ":")
      if (pos == 0) next
      k = substr($0, 1, pos - 1)
      if (k != key) next
      v = substr($0, pos + 1)
      sub(/^[ \t]+/, "", v)
      sub(/[ \t]*#.*$/, "", v)
      sub(/[ \t]+$/, "", v)
      print v
      exit
    }
  ' "$1"
}

# ── ROADMAP parsing ───────────────────────────────────────────────────────────
#
# Emits one record per line so the shell never has to re-parse Markdown:
#   ROW  line  id  state(open|done)  struck(0|1)  blocked(0|1)  verify(0|1)  phase  earlyok(0|1)
#   REQ  line  task  node  edgetype
#   PRV  line  task  node
parse_roadmap() {
  awk -v sep="$SEP" '
    function emit(kind, line, a, b, c, d, e, f, g) {
      print kind sep line sep a sep b sep c sep d sep e sep f sep g
    }
    function flush() {
      if (cur_line == 0) return
      emit("ROW", cur_line, cur_id, cur_state, cur_struck, \
           (buf ~ /blocked:/) ? 1 : 0, \
           (buf ~ /\(verify:/) ? 1 : 0, \
           cur_phase, (buf ~ /early-ok/) ? 1 : 0)
      if (cur_struck && cur_state == "done" && buf !~ /superseded by/)
        emit("NOSUP", cur_line, cur_id, "", "", "", "", "", "")
      if (buf ~ /blocked:/ && buf !~ /unlock:/)
        emit("NOUNLOCK", cur_line, cur_id, "", "", "", "", "", "")
      cur_line = 0; buf = ""
    }
    /^##[ \t]+[Pp]hase/ {
      flush()
      decl = $0
      if (match(decl, /[Pp]hase[ \t]+[0-9]+/)) {
        num = substr(decl, RSTART, RLENGTH)
        sub(/[Pp]hase[ \t]+/, "", num)
        phase = num + 0
      } else phase++
      next
    }
    /^-[ \t]+\[[ xX]\]/ {
      flush()
      line = NR
      state = ($0 ~ /^-[ \t]+\[[xX]\]/) ? "done" : "open"
      struck = ($0 ~ /~~/) ? 1 : 0
      rest = $0
      sub(/^-[ \t]+\[[ xX]\][ \t]*/, "", rest)
      gsub(/~~/, "", rest)
      sub(/^[ \t]+/, "", rest)
      id = rest
      sub(/[ \t].*$/, "", id)
      if (id !~ /^[A-Za-z][A-Za-z0-9._-]*$/) id = "-"
      current = id
      cur_line = line; cur_id = id; cur_state = state
      cur_struck = struck; cur_phase = phase + 0; buf = $0
      next
    }
    /^[ \t]+requires:/ {
      body = $0
      sub(/^[ \t]*requires:[ \t]*/, "", body)
      n = split(body, parts, ",")
      for (i = 1; i <= n; i++) {
        item = parts[i]
        sub(/^[ \t]+/, "", item); sub(/[ \t]+$/, "", item)
        if (item == "") continue
        etype = ""
        if (match(item, /\([A-Za-z]+\)/)) {
          etype = substr(item, RSTART + 1, RLENGTH - 2)
          item = substr(item, 1, RSTART - 1)
        }
        sub(/[ \t]+$/, "", item)
        if (item == "") continue
        emit("REQ", NR, current, item, etype, "", "", "", "")
      }
      buf = buf " " $0
      next
    }
    /^[ \t]+node:/ {
      body = $0
      sub(/^[ \t]*node:[ \t]*/, "", body)
      sub(/[ \t]*\|.*$/, "", body)
      sub(/[ \t]+$/, "", body)
      if (body != "") emit("NODE", NR, current, body, "", "", "", "", "")
      buf = buf " " $0
      next
    }
    /^[ \t]+paths:/ {
      body = $0
      sub(/^[ \t]*paths:[ \t]*/, "", body)
      sub(/[ \t]+$/, "", body)
      if (body != "") emit("PATHS", NR, current, body, "", "", "", "", "")
      buf = buf " " $0
      next
    }
    /^[ \t]+proves:/ {
      body = $0
      sub(/^[ \t]*proves:[ \t]*/, "", body)
      n = split(body, parts, ",")
      for (i = 1; i <= n; i++) {
        item = parts[i]
        sub(/^[ \t]+/, "", item); sub(/[ \t]+$/, "", item)
        if (item == "") continue
        emit("PRV", NR, current, item, "", "", "", "", "")
      }
      buf = buf " " $0
      next
    }
    { if (cur_line) buf = buf " " $0 }
    END { flush() }
  ' "$1"
}

# ── per-mission checks ────────────────────────────────────────────────────────
check_mission() {
  dir=$1
  archived=$2
  rel=${dir#"$ROOT"/}
  folder=$(basename "$dir")

  spec=$dir/SPEC.md
  roadmap=$dir/ROADMAP.md
  notes=$dir/NOTES.md
  ledger=$dir/LEDGER.md

  for required in SPEC.md ROADMAP.md NOTES.md LEDGER.md; do
    if [ ! -f "$dir/$required" ]; then
      add_finding ERROR S001 "$rel" 1 "mission is missing $required"
    fi
  done
  [ -f "$spec" ] || return 0

  status=$(frontmatter_value "$spec" status)
  slug=$(frontmatter_value "$spec" slug)
  created=$(frontmatter_value "$spec" created)
  commits=$(frontmatter_value "$spec" commits)

  for key in slug status created updated agent; do
    if [ -z "$(frontmatter_value "$spec" "$key")" ]; then
      add_finding ERROR S110 "$rel/SPEC.md" 1 "SPEC frontmatter is missing required key: $key"
    fi
  done

  if [ -n "$status" ] && ! in_list "$status" "$STATUS_ENUM"; then
    add_finding ERROR S111 "$rel/SPEC.md" 1 "SPEC status is not a recognised state"
  fi
  if [ -n "$commits" ] && ! in_list "$commits" "$COMMITS_ENUM"; then
    add_finding ERROR S112 "$rel/SPEC.md" 1 "commits policy is not user, per-task or per-phase"
  fi
  if [ -n "$created" ] && [ -n "$slug" ] && [ "$folder" != "$created-$slug" ]; then
    add_finding ERROR S002 "$rel" 1 "folder name does not equal created date plus slug"
  fi

  if [ "$archived" = yes ]; then
    if [ -n "$status" ] && ! in_list "$status" "$TERMINAL_STATUS"; then
      add_finding ERROR S113 "$rel/SPEC.md" 1 "archived mission is not done or cancelled"
    fi
  else
    if [ -n "$status" ] && in_list "$status" "$TERMINAL_STATUS"; then
      add_finding WARN S114 "$rel/SPEC.md" 1 "terminal mission still sits outside the done archive"
    fi
  fi

  if [ -f "$notes" ]; then
    n=$(wc -l <"$notes" | tr -d ' ')
    if [ "$n" -gt "$NOTES_CEILING" ]; then
      add_finding WARN S003 "$rel/NOTES.md" 1 "NOTES exceeds its $NOTES_CEILING line ceiling"
    fi
  fi

  [ -f "$roadmap" ] || return 0
  records=$TMP_DIR/records
  parse_roadmap "$roadmap" >"$records"

  open_rows=0
  done_rows=0
  blocked_rows=0
  while IFS="$SEP" read -r kind line id state struck blocked verify phase early; do
    [ "$kind" = ROW ] || continue
    case "$state" in
      done) done_rows=$((done_rows + 1)) ;;
      open) open_rows=$((open_rows + 1)) ;;
    esac
    [ "$blocked" = 1 ] && blocked_rows=$((blocked_rows + 1))

    if [ "$state" = open ] && [ "$struck" = 1 ]; then
      add_finding ERROR S200 "$rel/ROADMAP.md" "$line" "unticked struck row is an invalid legacy disposition"
    fi
    if [ "$struck" = 0 ] && [ "$verify" = 0 ]; then
      add_finding WARN S203 "$rel/ROADMAP.md" "$line" "task carries no verify check"
    fi
  done <"$records"

  while IFS="$SEP" read -r kind line id _rest; do
    case "$kind" in
      NOSUP) add_finding ERROR S201 "$rel/ROADMAP.md" "$line" "superseded row does not name what replaced it" ;;
      NOUNLOCK) add_finding ERROR S202 "$rel/ROADMAP.md" "$line" "blocked row does not state its unlock condition" ;;
    esac
  done <"$records"

  total_rows=$((open_rows + done_rows))
  if [ "$total_rows" -gt 0 ]; then
    case "$status" in
      awaiting-final-review | done)
        if [ "$open_rows" -gt 0 ]; then
          add_finding ERROR S204 "$rel/SPEC.md" 1 "status claims the mission is complete while tasks remain open"
        fi
        ;;
      running)
        if [ "$open_rows" -eq 0 ]; then
          add_finding ERROR S205 "$rel/SPEC.md" 1 "status is running with no task left to run"
        fi
        ;;
      blocked)
        if [ "$blocked_rows" -eq 0 ]; then
          add_finding ERROR S206 "$rel/SPEC.md" 1 "status is blocked with no blocked task recorded"
        fi
        ;;
    esac
  fi

  # ── graph ───────────────────────────────────────────────────────────────────
  #
  # These rules describe a mission that opted into dependency edges. A ROADMAP
  # of plain rows is not defective for lacking them, and a mission that declares
  # its nodes in an external manifest puts node existence beyond this script.
  uses_graph=0
  grep -qE '^[ \t]+(requires|proves):' "$roadmap" && uses_graph=1
  first_phase=$(awk -v sep="$SEP" '$0 ~ /^ROW/ { split($0, f, sep); print f[8]; exit }' "$records")
  case "$first_phase" in '' | *[!0-9]*) first_phase=1 ;; esac
  external_nodes=0
  for manifest in architecture.yaml architecture.yml graph; do
    [ -e "$dir/$manifest" ] && external_nodes=1
  done

  proven=$TMP_DIR/proven
  provers=$TMP_DIR/provers
  : >"$proven"
  : >"$provers"
  # A node is supplied by the task declaring `node:`. `proves:` is an outgoing
  # edge, and reading it as the supplier inverted the dependency map.
  while IFS="$SEP" read -r kind line task node _rest; do
    [ "$kind" = NODE ] || continue
    printf '%s %s\n' "$node" "$task" >>"$provers"
    taskstate=$(awk -v sep="$SEP" -v t="$task" '
      $0 ~ /^ROW/ { split($0, f, sep); if (f[3] == t) { print f[4]; exit } }' "$records")
    [ "$taskstate" = done ] && printf '%s\n' "$node" >>"$proven"
  done <"$records"

  while IFS="$SEP" read -r kind line task node etype _rest; do
    [ "$kind" = REQ ] || continue
    if [ "$external_nodes" = 0 ] &&
      ! cut -d' ' -f1 "$provers" | grep -qx -- "$node"; then
      add_finding ERROR S300 "$rel/ROADMAP.md" "$line" "requires a node that no task proves"
    fi
    if [ -n "$etype" ] && ! in_list "$etype" "$EDGE_TYPES"; then
      add_finding ERROR S303 "$rel/ROADMAP.md" "$line" "edge type is not registered"
    fi
  done <"$records"

  # Cycle detection: repeatedly discharge tasks whose requires are all proven by
  # already-discharged tasks. Anything left is inside a cycle.
  settled=$TMP_DIR/settled
  : >"$settled"
  progress=1
  while [ "$progress" = 1 ]; do
    progress=0
    while IFS="$SEP" read -r kind line id state struck blocked verify phase early; do
      [ "$kind" = ROW ] || continue
      [ "$id" = "-" ] && continue
      grep -qx -- "$id" "$settled" && continue
      unmet=0
      while IFS="$SEP" read -r k2 l2 t2 n2 _r2; do
        [ "$k2" = REQ ] || continue
        [ "$t2" = "$id" ] || continue
        p=$(awk -v n="$n2" '$1 == n { print $2; exit }' "$provers")
        [ -z "$p" ] && continue
        grep -qx -- "$p" "$settled" || unmet=1
      done <"$records"
      if [ "$unmet" = 0 ]; then
        printf '%s\n' "$id" >>"$settled"
        progress=1
      fi
    done <"$records"
  done
  while IFS="$SEP" read -r kind line id state struck blocked verify phase early; do
    [ "$kind" = ROW ] || continue
    [ "$id" = "-" ] && continue
    grep -qx -- "$id" "$settled" && continue
    add_finding ERROR S301 "$rel/ROADMAP.md" "$line" "task sits inside a dependency cycle"
  done <"$records"

  # S310: a task nobody has scheduled. A root with `node:` and no `requires:` is
  # legitimate — a contract test depends on nothing — so only a task carrying
  # neither is unscheduled. An earlier phase-orphan rule fired 29 times on
  # missions that had completed successfully, which made it a statement about the
  # rule rather than about the data, and it was removed instead of tuned.
  [ "$uses_graph" = 1 ] && while IFS="$SEP" read -r kind line id state struck blocked verify phase early; do
    [ "$kind" = ROW ] || continue
    [ "$state" = done ] && continue
    [ "$struck" = 1 ] && continue
    has=$(awk -v sep="$SEP" -v t="$id" '
      ($0 ~ /^REQ/ || $0 ~ /^NODE/) { split($0, f, sep); if (f[3] == t) { print "y"; exit } }' "$records")
    [ -n "$has" ] && continue
    grep -qiE '^##[ \t]+unanalysed' "$roadmap" && continue
    add_finding WARN S310 "$rel/ROADMAP.md" "$line" "open task declares no node and no dependency, so nothing has scheduled it"
  done <"$records"

  # ── ledger ──────────────────────────────────────────────────────────────────
  [ -f "$ledger" ] || return 0
  # There is deliberately no closed vocabulary check here. One was written and
  # then deleted: it fired 109 times across the corpus because ledger headings
  # are narrative, not a typed event stream — `delegated` alone appears 89 times,
  # alongside `rotation-checkpoint`, `scope-change`, `phase-validated` and a long
  # tail of one-off names. An enforcer that fires that often is wrong about the
  # data, not the other way round. A structural `- Evidence:` requirement was
  # measured as the fallback and rejected too: 841 of 1028 entries do not carry
  # one. Re-derive both with:
  #   grep -rhoE '^### [0-9-]+ [0-9:]+Z — [a-z][a-z-]+' <repo>/.claude/specs/

  # A final gate that does not say whether it was a full baseline or a scoped
  # review lets a narrow re-run stand in for a complete one. WARN, not ERROR:
  # the convention is real but only 4 of 15 recorded gates follow it, so this
  # reports a gap rather than failing a mission that is otherwise sound.
  grep -nE '^###.*— *final-gate' "$ledger" 2>/dev/null | while IFS= read -r entry; do
    lno=${entry%%:*}
    body=${entry#*:}
    case "$body" in
      *full-baseline* | *scoped*) ;;
      *) add_finding WARN S402 "$rel/LEDGER.md" "$lno" "final gate does not record whether it was a full baseline or a scoped review" ;;
    esac
  done

  # Pair by task id, not by count. Comparing totals hid an unclosed task whenever
  # some other task had been closed without a recorded start.
  awk '
    # Cut at the FIRST em-dash. `sub(/^###.*— /, ...)` is greedy, and a heading
    # like "— task-completed P4.8 `adapter/x` — the SPA build is GREEN" made it
    # cut at the LAST one, yielding the id "SPA" and leaving P4.8 forever open.
    function payload(s,   i) {
      i = index(s, "\342\200\224")
      return i ? substr(s, i + 3) : ""
    }
    function id(s,   n) {
      n = s; sub(/^[ \t]*[a-z][a-z-]+[ \t]+/, "", n)
      sub(/[^A-Za-z0-9._-].*$/, "", n)
      return n
    }
    /^###/ {
      p = payload($0)
      if (p ~ /^[ \t]*task-started[ \t]/) { start[id(p)] = NR; next }
      # Any later event naming the same task closes the marker. Listing closers
      # by name got this wrong: `delegated` is the corpus''s second most common
      # ledger event (89 uses) and plainly resolves a started task, but was
      # absent from the list, so every delegated task looked like a crash.
      if (p ~ /^[ \t]*[a-z][a-z-]+[ \t]+[A-Za-z0-9._-]/) delete start[id(p)]
    }
    END { for (n in start) print start[n] "\t" n }
  ' "$ledger" | while IFS="$(printf '\t')" read -r lno task; do
    [ -n "$task" ] || continue
    add_finding WARN S401 "$rel/LEDGER.md" "$lno" "a task was started and never closed, the documented crash-recovery marker"
  done
}

# ── mission enumeration ───────────────────────────────────────────────────────
missions=$TMP_DIR/missions
: >"$missions"
if [ -d "$SPECS" ]; then
  for d in "$SPECS"/*/; do
    [ -d "$d" ] || continue
    b=$(basename "$d")
    [ "$b" = done ] && continue
    case "$b" in [0-9][0-9][0-9][0-9]-*) ;; *) continue ;; esac
    printf '%s\tno\n' "${d%/}" >>"$missions"
  done
  if [ -d "$SPECS/done" ]; then
    for d in "$SPECS"/done/*/; do
      [ -d "$d" ] || continue
      case "$(basename "$d")" in [0-9][0-9][0-9][0-9]-*) ;; *) continue ;; esac
      printf '%s\tyes\n' "${d%/}" >>"$missions"
    done
  fi
fi

if [ -n "$SPEC_FILTER" ]; then
  filtered=$TMP_DIR/filtered
  grep -E "/($SPEC_FILTER|[0-9-]+-$SPEC_FILTER)\b" "$missions" >"$filtered" 2>/dev/null || :
  mv "$filtered" "$missions"
fi

# ── task disposition ──────────────────────────────────────────────────────────
#
# Emits `<disposition> <id> <detail>` for every task that is not already done,
# so nothing is silently in or out of the set. The distinction that matters is
# `runnable` versus `unmodelled`: a task declaring no edges at all is not a graph
# root, it is a task nobody has scheduled. Counting those as ready is how an
# earlier version of this function reported a 39-wide wave where 13 was correct.
disposition_for() {
  dir=$1
  roadmap=$dir/ROADMAP.md
  [ -f "$roadmap" ] || return 0
  r=$TMP_DIR/r.next
  parse_roadmap "$roadmap" >"$r"

  uses_graph=0
  grep -qE '^[ \t]+(requires|node):' "$roadmap" && uses_graph=1

  # A node is supplied by the task that declares `node:`, not by one that
  # `proves:` it — `proves` is an outgoing edge. Reading it the other way round
  # inverted the whole dependency map and made implementations look ready before
  # the tests they depend on.
  pv=$TMP_DIR/pv.next
  : >"$pv"
  while IFS="$SEP" read -r kind line task node _rest; do
    [ "$kind" = NODE ] || continue
    st=$(awk -v sep="$SEP" -v t="$task" '
      $0 ~ /^ROW/ { split($0, f, sep); if (f[3] == t) { print f[4]; exit } }' "$r")
    [ "$st" = done ] && printf '%s\n' "$node" >>"$pv"
  done <"$r"

  while IFS="$SEP" read -r kind line id state struck blocked verify phase early; do
    [ "$kind" = ROW ] || continue
    [ "$state" = open ] || continue
    [ "$struck" = 1 ] && continue
    if [ "$blocked" = 1 ]; then
      printf 'blocked %s %s\n' "$id" "$(sed -n "${line}p" "$roadmap" |
        sed -n 's/.*blocked:[ \t]*\([^;]*\).*/\1/p' | cut -c1-60)"
      continue
    fi

    edges=$(awk -v sep="$SEP" -v t="$id" '
      ($0 ~ /^REQ/ || $0 ~ /^NODE/) { split($0, f, sep); if (f[3] == t) n++ }
      END { print n + 0 }' "$r")
    if [ "$uses_graph" = 1 ] && [ "$edges" -eq 0 ]; then
      printf 'unmodelled %s no edges declared\n' "$id"
      continue
    fi

    unmet=""
    while IFS="$SEP" read -r k2 l2 t2 n2 _r2; do
      [ "$k2" = REQ ] || continue
      [ "$t2" = "$id" ] || continue
      grep -qx -- "$n2" "$pv" || unmet="$unmet $n2"
    done <"$r"
    if [ -n "$unmet" ]; then
      printf 'waiting %s%s\n' "$id" "$unmet"
    else
      printf 'runnable %s -\n' "$id"
    fi
  done <"$r"
}

case "$SUBCOMMAND" in
  next)
    while IFS="$(printf '\t')" read -r dir archived; do
      [ -n "$dir" ] || continue
      [ "$archived" = yes ] && continue
      st=$(frontmatter_value "$dir/SPEC.md" status 2>/dev/null)
      case "$st" in ready | running | blocked) ;; *) continue ;; esac
      disp=$TMP_DIR/disp
      disposition_for "$dir" >"$disp"
      nr=$(grep -c '^runnable ' "$disp" || true)
      nu=$(grep -c '^unmodelled ' "$disp" || true)
      nw=$(grep -c '^waiting ' "$disp" || true)
      nb=$(grep -c '^blocked ' "$disp" || true)
      printf '%s [%s]  runnable=%s unmodelled=%s waiting=%s blocked=%s\n' \
        "$(basename "$dir")" "$st" "$nr" "$nu" "$nw" "$nb"
      sort "$disp" | sed 's/^/  /'
      printf '  --\n'
      printf '  Dependency state only. Before running any of these together, measure\n'
      printf '  file overlap (disjoint.sh); ordering and output dependency stay yours.\n'
      [ "$nu" -gt 0 ] &&
        printf '  %s task(s) declare no edges: unscheduled, not ready.\n' "$nu"
    done <"$missions"
    exit 0
    ;;
  status)
    while IFS="$(printf '\t')" read -r dir archived; do
      [ -n "$dir" ] || continue
      [ "$archived" = yes ] && continue
      roadmap=$dir/ROADMAP.md
      [ -f "$roadmap" ] || continue
      st=$(frontmatter_value "$dir/SPEC.md" status 2>/dev/null)
      d=$(grep -cE '^-[ \t]+\[[xX]\]' "$roadmap" 2>/dev/null || true)
      o=$(grep -cE '^-[ \t]+\[[ ]\]' "$roadmap" 2>/dev/null || true)
      b=$(grep -c 'blocked:' "$roadmap" 2>/dev/null || true)
      run=$(disposition_for "$dir" | grep -c '^runnable ' || true)
      unm=$(disposition_for "$dir" | grep -c '^unmodelled ' || true)
      led=$dir/LEDGER.md
      ev=0
      stall=0
      if [ -f "$led" ]; then
        ev=$(grep -cE '^###[ \t]' "$led" 2>/dev/null || true)
        # retry without progress: validation-failed entries after the last completion
        last_done=$(grep -nE 'task-completed' "$led" 2>/dev/null | tail -1 | cut -d: -f1)
        [ -z "$last_done" ] && last_done=0
        stall=$(awk -v start="$last_done" 'NR > start && /validation-failed/ { n++ } END { print n + 0 }' "$led")
      fi
      printf '%s [%s]  done=%s open=%s blocked=%s runnable=%s unmodelled=%s ledger=%s retries-since-progress=%s\n' \
        "$(basename "$dir")" "${st:-?}" "$d" "$o" "$b" "$run" "$unm" "$ev" "$stall"
    done <"$missions"
    exit 0
    ;;
esac

while IFS="$(printf '\t')" read -r dir archived; do
  [ -n "$dir" ] || continue
  check_mission "$dir" "$archived"
done <"$missions"

if ! LC_ALL=C sort "$FINDINGS"; then
  printf '%s: cannot sort checker findings\n' "$PROGRAM" >&2
  exit 2
fi

case "$FAIL_ON" in
  warning)
    if [ -s "$FINDINGS" ]; then
      exit 1
    fi
    ;;
  error)
    if grep -q '^ERROR|' "$FINDINGS"; then
      exit 1
    fi
    ;;
esac

exit 0
