#!/usr/bin/env bash
# CLAUDART Installer
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash
#
# Options (pass after --):
#   (no flags)   Install the Claude Code layer (.claude/)
#   --claude     Install the Claude Code layer (explicit, same as default)
#   --codex      Install the Codex layer (.codex/ + .agents/ + AGENTS.md at root)
#   --both       Install both Claude and Codex layers
#   --council    Also install Council of High Intelligence (/council) to user scope
#   --upgrade    Upgrade an existing install: overwrite template-owned files
#                (commands, rules, agents, skills, scripts) but never live
#                state (CONTEXT, JOURNAL, tasks, specs, knowledge) or the
#                user-evolved CLAUDE.md / AGENTS.md
#   --force      Overwrite ALL existing template/index files, including your
#                own live state, with the repo's copy. CLAUDART's own
#                dogfooded CONTEXT/JOURNAL/tasks/specs/knowledge are never
#                sourced from the repo at all, --force included — see
#                is_live_state_path below.
#   --repo=<o/n> Download from another GitHub repo (fork-friendly); also
#                CLAUDART_REPO env; a local run auto-detects its checkout origin
#   --branch=<b> Branch to download (default main; CLAUDART_BRANCH env)
#   --help       Show this help text

#set -euo pipefail

# Repo resolution — precedence: --repo= flag > CLAUDART_REPO env > the script's
# own checkout origin (when run as a local file from a Claudart clone) > the
# canonical fallback below. The fallback is the ONLY owner-specific line in this
# script; forks running via curl|bash override it with --repo= or CLAUDART_REPO
# instead of patching source, and a local `bash install.sh` in any fork just
# works because the checkout's origin wins.
FALLBACK_REPO="lapnd/Claudart"
REPO="${CLAUDART_REPO:-}"
REPO_SOURCE="CLAUDART_REPO env"
BRANCH="${CLAUDART_BRANCH:-main}"

COUNCIL_REPO="${CLAUDART_COUNCIL_REPO:-0xNyk/council-of-high-intelligence}"
COUNCIL_TARBALL_URL="https://github.com/${COUNCIL_REPO}/archive/refs/heads/main.tar.gz"

INSTALL_CLAUDE=true
INSTALL_CODEX=false
INSTALL_COUNCIL=false
UPGRADE=true
FORCE=false

# ── helpers ──────────────────────────────────────────────────────────────────

bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }

# Fill REPO if neither --repo= nor CLAUDART_REPO set it: when this script runs
# as a local file inside a git checkout whose origin is a GitHub repo named
# like Claudart, use that origin (fork-friendly); otherwise use the fallback.
resolve_repo() {
  if [[ -n "$REPO" ]]; then return; fi
  local script="${BASH_SOURCE[0]:-}" sdir url rest name
  if [[ -f "$script" ]]; then
    sdir="$(cd "$(dirname "$script")" 2>/dev/null && pwd)" || sdir=""
    if [[ -n "$sdir" ]] && url="$(git -C "$sdir" remote get-url origin 2>/dev/null)"; then
      rest="${url#*github.com}"
      if [[ "$rest" != "$url" ]]; then
        rest="${rest#[:/]}"; rest="${rest%.git}"; rest="${rest%/}"
        name="$(basename "$rest" | tr '[:upper:]' '[:lower:]')"
        if [[ "$rest" == */* && "$name" == claudart* ]]; then
          REPO="$rest"; REPO_SOURCE="checkout origin"
          return
        fi
      fi
    fi
  fi
  REPO="$FALLBACK_REPO"; REPO_SOURCE="default"
}

show_help() {
  cat <<EOF2
$(bold "CLAUDART Installer")

USAGE
  curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- [OPTIONS]
  bash install.sh [OPTIONS]

OPTIONS
  (no flags)   Install the Claude Code layer (default)
  --claude     Install the Claude Code layer (explicit)
  --codex      Install the Codex layer instead
  --both       Install both Claude Code and Codex layers
  --council    Also install Council of High Intelligence — the /council
               deliberation command (0xNyk/council-of-high-intelligence) —
               into your USER scope (~/.claude, ~/.codex), matching the
               layers selected above
  --upgrade    Upgrade an existing CLAUDART install in place. Overwrites
               TEMPLATE-OWNED files only (commands/, rules/, skills/,
               agents/, scripts/, guidelines/, .agents/ skills). NEVER
               touches live state (CONTEXT.md, JOURNAL.md, HANDOFF.md,
               tasks/, specs/, knowledge/) or user-evolved indexes
               (CLAUDE.md, AGENTS.md,
               config.toml) — reconcile those via INTEGRATE.md. Layers are
               auto-detected from the existing install unless you pass
               --claude/--codex/--both; with no install present it falls
               back to a fresh install. Run from a clean git tree so the
               upgrade is reviewable with git diff, then run /doctor.
  --force      Overwrite ALL existing template/index files with the repo's
               copy. Use --upgrade instead unless you really mean this.
               CLAUDART's own dogfooded CONTEXT/JOURNAL/tasks/specs/knowledge
               are never installed regardless of this flag.
  --repo=<owner/name>
               Download from this GitHub repo instead of the default —
               fork-friendly, no source patching. Precedence: --repo= >
               CLAUDART_REPO env > the checkout's own git origin (when run
               as a local file from a Claudart clone) > the built-in default.
  --branch=<name>
               Branch to download (default: main; env: CLAUDART_BRANCH).
  --help       Show this help text

LAYERS
  Claude Code (default)   .claude/
  Codex                   .codex/  +  .agents/  +  AGENTS.md at project root
  Both                    all of the above
EOF2
}

# ── arg parsing ───────────────────────────────────────────────────────────────

LAYER_EXPLICIT=false

for arg in "$@"; do
  case "$arg" in
    --claude) INSTALL_CLAUDE=true;  INSTALL_CODEX=false; LAYER_EXPLICIT=true ;;
    --codex)  INSTALL_CLAUDE=false; INSTALL_CODEX=true;  LAYER_EXPLICIT=true ;;
    --both)   INSTALL_CLAUDE=true;  INSTALL_CODEX=true;  LAYER_EXPLICIT=true ;;
    --council) INSTALL_COUNCIL=true ;;
    --upgrade) UPGRADE=true ;;
    --force)  FORCE=true ;;
    --repo=*)   REPO="${arg#--repo=}";   REPO_SOURCE="--repo flag" ;;
    --branch=*) BRANCH="${arg#--branch=}" ;;
    --help|-h) show_help; exit 0 ;;
    *) printf '%s Unknown option: %s\n' "$(red "error")" "$arg" >&2; exit 1 ;;
  esac
done

resolve_repo
TARBALL_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

# ── layer auto-detection (upgrade without explicit layer flags) ───────────────

DEST="${PWD}"

if [[ "$UPGRADE" == true && "$LAYER_EXPLICIT" == false ]]; then
  HAS_CLAUDE=false; HAS_CODEX=false
  [[ -d "$DEST/.claude" ]] && HAS_CLAUDE=true
  { [[ -d "$DEST/.codex" ]] || [[ -d "$DEST/.agents" ]]; } && HAS_CODEX=true

  if [[ "$HAS_CLAUDE" == true || "$HAS_CODEX" == true ]]; then
    INSTALL_CLAUDE=$HAS_CLAUDE
    INSTALL_CODEX=$HAS_CODEX
    layers="$( [[ "$HAS_CLAUDE" == true ]] && printf 'claude ' )$( [[ "$HAS_CODEX" == true ]] && printf 'codex' )"
    printf '\n%s  Detected existing layers: %s — upgrading those.\n' "$(bold "→")" "${layers% }"
  else
    UPGRADE=false
    printf '\n%s  No existing CLAUDART install detected here — doing a fresh install instead.\n' "$(yellow "note")"
  fi
fi

# ── download ──────────────────────────────────────────────────────────────────
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

printf '\n%s  Downloading CLAUDART from %s@%s (%s) …\n' "$(bold "→")" "$REPO" "$BRANCH" "$REPO_SOURCE"

if command -v curl &>/dev/null; then
  curl -fsSL "$TARBALL_URL" | tar -xz -C "$TMPDIR" --strip-components=1
elif command -v wget &>/dev/null; then
  wget -qO- "$TARBALL_URL" | tar -xz -C "$TMPDIR" --strip-components=1
else
  printf '%s curl or wget is required.\n' "$(red "error")" >&2
  exit 1
fi

# ── copy helpers ──────────────────────────────────────────────────────────────

SKIPPED=0
COPIED=0
UPGRADED=0
UNCHANGED=0
EXCLUDED=0

# Template-owned paths: safe to overwrite on --upgrade. Everything else —
# live state (CONTEXT, JOURNAL, HANDOFF, tasks/, specs/, knowledge/) and
# user-evolved indexes (CLAUDE.md, AGENTS.md, config.toml) — is never
# overwritten by an upgrade; reconcile those via INTEGRATE.md.
is_template_path() {
  case "$1" in
    .claude/commands/*|.claude/rules/*|.claude/skills/*|.claude/agents/*|.claude/scripts/*|.claude/hooks/*) return 0 ;;
    .codex/guidelines/*|.codex/agents/*|.codex/scripts/*) return 0 ;;
    .agents/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Live-state paths: CLAUDART dogfoods itself (it uses CLAUDART to improve
# CLAUDART), so this repo's own checked-in tree always carries real CONTEXT/
# JOURNAL/tasks/specs/knowledge content for THIS repo's sessions. That content
# must never be installed into anyone else's project — not on a fresh install,
# not on --upgrade, not even under --force. copy_tree skips these entirely so
# they are never considered for copying in the first place; the various
# CLAUDART commands already tolerate these files being absent and create them
# on first use.
is_live_state_path() {
  case "$1" in
    .claude/CONTEXT.md|.claude/JOURNAL.md|.claude/HANDOFF.md) return 0 ;;
    .claude/tasks/*|.claude/specs/*|.claude/knowledge/*) return 0 ;;
    .codex/CONTEXT.md|.codex/JOURNAL.md|.codex/HANDOFF.md) return 0 ;;
    .codex/tasks/*|.codex/specs/*|.codex/knowledge/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Copy a single file. Existing files are skipped, unless --force (overwrite
# everything) or --upgrade (overwrite template-owned paths only).
copy_file() {
  local rel="$1"          # path relative to repo root, e.g. ".claude/CLAUDE.md"
  local src="$TMPDIR/$rel"
  local dst="$DEST/$rel"

  if [[ -f "$dst" ]]; then
    if [[ "$FORCE" == true ]] || { [[ "$UPGRADE" == true ]] && is_template_path "$rel"; }; then
      if cmp -s "$src" "$dst"; then
        (( UNCHANGED++ )) || true
        return
      fi
      cp "$src" "$dst"
      printf '  %s  %s\n' "$(green "up  ")" "$rel"
      (( UPGRADED++ )) || true
      return
    fi
    printf '  %s  %s\n' "$(yellow "skip")" "$rel"
    (( SKIPPED++ )) || true
    return
  fi

  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  printf '  %s  %s\n' "$(green "copy")" "$rel"
  (( COPIED++ )) || true
}

# Copy a file from an arbitrary src path to an arbitrary dst path (different rel names).
copy_file_from_src() {
  local src_rel="$1"
  local dst_rel="$2"
  local src="$TMPDIR/$src_rel"
  local dst="$DEST/$dst_rel"

  if [[ -f "$dst" && "$FORCE" == false ]]; then
    printf '  %s  %s\n' "$(yellow "skip")" "$dst_rel"
    (( SKIPPED++ )) || true
    return
  fi

  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  printf '  %s  %s\n' "$(green "copy")" "$dst_rel"
  (( COPIED++ )) || true
}

# Walk every file inside a source tree and call copy_file for each one.
copy_tree() {
  local root="$1"         # e.g. ".claude"
  local src_root="$TMPDIR/$root"

  if [[ ! -d "$src_root" ]]; then
    return
  fi

  while IFS= read -r src_file; do
    local rel="${src_file#"$TMPDIR/"}"
    if is_live_state_path "$rel"; then
      (( EXCLUDED++ )) || true
      continue
    fi
    copy_file "$rel"
  done < <(find "$src_root" -type f | sort)
}

# ── install ───────────────────────────────────────────────────────────────────

if [[ "$UPGRADE" == true ]]; then
  printf '\n%s  Upgrading CLAUDART in %s\n' "$(bold "→")" "$DEST"
  if command -v git &>/dev/null && git -C "$DEST" rev-parse --is-inside-work-tree &>/dev/null; then
    if [[ -n "$(git -C "$DEST" status --porcelain 2>/dev/null)" ]]; then
      printf '%s  Working tree is not clean — consider committing first so the upgrade is reviewable with git diff.\n' "$(yellow "note")"
    fi
  fi
else
  printf '\n%s  Installing into %s\n' "$(bold "→")" "$DEST"
fi

if [[ "$INSTALL_CLAUDE" == true ]]; then
  printf '\n%s\n' "$(bold "Claude Code layer (.claude/)")"
  copy_tree ".claude"
fi

if [[ "$INSTALL_CODEX" == true ]]; then
  printf '\n%s\n' "$(bold "Codex layer")"

  # Snapshot AGENTS.md state BEFORE copying so we know what the user already had.
  AGENTS_AT_ROOT=false
  AGENTS_IN_CODEX=false
  [[ -f "$DEST/AGENTS.md" ]]        && AGENTS_AT_ROOT=true
  [[ -f "$DEST/.codex/AGENTS.md" ]] && AGENTS_IN_CODEX=true

  copy_tree ".codex"
  copy_tree ".agents"

  # AGENTS.md must live at project root for Codex to auto-load it.
  # • User already had it at root OR in .codex/ → leave everything untouched.
  # • Neither existed → install at root and remove the .codex/ copy that
  #   copy_tree just created (avoid having two conflicting copies).
  if [[ "$AGENTS_AT_ROOT" == false && "$AGENTS_IN_CODEX" == false ]]; then
    copy_file_from_src ".codex/AGENTS.md" "AGENTS.md"
    if [[ -f "$DEST/.codex/AGENTS.md" ]]; then
      rm "$DEST/.codex/AGENTS.md"
      printf '  %s  .codex/AGENTS.md (removed; canonical copy is at root)\n' "$(green "clean")"
    fi
  else
    location="$( [[ "$AGENTS_AT_ROOT" == true ]] && echo "root" || echo ".codex/" )"
    printf '  %s  AGENTS.md (already present at %s, skipping)\n' "$(yellow "skip")" "$location"
    (( SKIPPED++ )) || true
    # copy_tree above may have just re-created .codex/AGENTS.md on a reinstall
    # or upgrade; when the user's canonical copy lives at root and .codex/ had
    # none before this run, remove the duplicate it left behind.
    if [[ "$AGENTS_AT_ROOT" == true && "$AGENTS_IN_CODEX" == false && -f "$DEST/.codex/AGENTS.md" ]]; then
      rm "$DEST/.codex/AGENTS.md"
      (( COPIED-- )) || true
      printf '  %s  .codex/AGENTS.md (removed duplicate; canonical copy is at root)\n' "$(green "clean")"
    fi
  fi

  # .codex/CODEX.md is deprecated when present; the template uses AGENTS.md as
  # the sole Codex memory index. Remove the stale path during reconciliation.
  if [[ -f "$DEST/.codex/CODEX.md" ]]; then
    rm "$DEST/.codex/CODEX.md"
    printf '  %s  .codex/CODEX.md (deprecated; content consolidated into AGENTS.md)\n' "$(green "clean")"
  fi
fi

# ── optional companion: Council of High Intelligence ─────────────────────────

if [[ "$INSTALL_COUNCIL" == true ]]; then
  printf '\n%s\n' "$(bold "Council of High Intelligence (/council)")"
  COUNCIL_TMP="$TMPDIR/council"
  mkdir -p "$COUNCIL_TMP"

  # Council is a third-party companion (a separate repo, separate maintainer).
  # A failure here must never abort the CLAUDART install that already
  # succeeded — degrade to a warning instead, even under set -e/pipefail.
  council_ok=true
  if command -v curl &>/dev/null; then
    curl -fsSL "$COUNCIL_TARBALL_URL" | tar -xz -C "$COUNCIL_TMP" --strip-components=1 || council_ok=false
  else
    wget -qO- "$COUNCIL_TARBALL_URL" | tar -xz -C "$COUNCIL_TMP" --strip-components=1 || council_ok=false
  fi

  if [[ "$council_ok" == true ]]; then
    # Map CLAUDART layer selection onto the council installer's flags.
    council_flags=()
    if [[ "$INSTALL_CLAUDE" == true && "$INSTALL_CODEX" == true ]]; then
      council_flags+=(--codex)
    elif [[ "$INSTALL_CODEX" == true ]]; then
      council_flags+=(--codex-only)
    fi

    # Council installs to USER scope (~/.claude, ~/.codex) — shared across projects.
    if bash "$COUNCIL_TMP/install.sh" ${council_flags[@]+"${council_flags[@]}"}; then
      printf '  %s  /council available in your user scope. Integration recipe: docs/GUIDE.md → Deliberating a hard decision.\n' "$(green "done")"
    else
      council_ok=false
    fi
  fi

  if [[ "$council_ok" == false ]]; then
    printf '  %s  Could not install Council of High Intelligence (network or upstream issue) — skipped. The rest of CLAUDART installed normally; retry with --council later, or see https://github.com/%s.\n' "$(yellow "warn")" "$COUNCIL_REPO"
  fi
fi

# ── summary ───────────────────────────────────────────────────────────────────

printf '\n%s  Done. %d copied, %d upgraded, %d unchanged, %d skipped, %d excluded.\n\n' "$(bold "✓")" "$COPIED" "$UPGRADED" "$UNCHANGED" "$SKIPPED" "$EXCLUDED"

if [[ "$EXCLUDED" -gt 0 ]]; then
  printf "%s  %d file(s) from CLAUDART's own dogfooded session state (CONTEXT/JOURNAL/tasks/specs/knowledge) were never installed — that content belongs to the CLAUDART repo, not your project. Those files are created fresh by CLAUDART commands as you use them.\n" "$(yellow "note")" "$EXCLUDED"
fi

if [[ "$UPGRADE" == true ]]; then
  printf '%s  Your own live state (CONTEXT, JOURNAL, tasks, specs, knowledge) and user-evolved indexes (CLAUDE.md, AGENTS.md) were left untouched.\n' "$(yellow "note")"
  printf '%s  Review with git diff, reconcile customized indexes via INTEGRATE.md, then run /doctor.\n\n' "$(yellow "note")"
elif [[ "$SKIPPED" -gt 0 ]]; then
  printf '%s  Skipped files already exist in your project. Rerun with --upgrade to refresh template files safely, or --force to overwrite everything.\n\n' "$(yellow "note")"
fi

printf '%s\n' "$(bold "Next steps:")"
if [[ "$INSTALL_CLAUDE" == true ]]; then
  printf '  Claude Code  →  open project, run /doctor → /refactor-memory → /doctor once\n'
fi
if [[ "$INSTALL_CODEX" == true ]]; then
  # The dollar-prefixed skill names are intentional literals.
  # shellcheck disable=SC2016
  printf '  Codex        →  open project, run $codex-doctor → $codex-refactor-memory → $codex-doctor once\n'
fi
printf '\n'
