#!/usr/bin/env bash
# CLAUDART Installer
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash
#
# Options (pass after --):
#   (no flags)   Install the Claude Code layer (.claude/)
#   --claude     Install the Claude Code layer (explicit, same as default)
#   --codex      Install the Codex layer (.codex/ + .agents/ + AGENTS.md route)
#   --deepseek   Install the DeepSeek layer (.deepseek/ + .agents/ + AGENTS.md route)
#   --pi         Install the Pi layer (.pi/ + .agents/ + AGENTS.md route)
#   --both       Install both Claude and Codex layers
#   --all        Install the Claude, Codex, DeepSeek, and Pi layers
#   --force      Overwrite existing files
#   --help       Show this help text

set -euo pipefail

REPO="vankhaivn/Claudart"
BRANCH="main"
TARBALL_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

INSTALL_CLAUDE=true
INSTALL_CODEX=false
INSTALL_DEEPSEEK=false
INSTALL_PI=false
FORCE=false

# ── helpers ──────────────────────────────────────────────────────────────────

bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }
red()   { printf '\033[31m%s\033[0m' "$*"; }

show_help() {
  cat <<EOF2
$(bold "CLAUDART Installer")

USAGE
  curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- [OPTIONS]
  bash install.sh [OPTIONS]

OPTIONS
  (no flags)   Install the Claude Code layer (default)
  --claude     Install the Claude Code layer (explicit)
  --codex      Install the Codex layer instead
  --deepseek   Install the DeepSeek layer instead
  --pi         Install the Pi layer instead
  --both       Install both Claude Code and Codex layers
  --all        Install the Claude Code, Codex, DeepSeek, and Pi layers
  --force      Overwrite files that already exist
  --help       Show this help text

LAYERS
  Claude Code (default)   .claude/     (loaded through .claude/CLAUDE.md)
  Codex                   .codex/      +  .agents/
  DeepSeek                .deepseek/   +  .agents/
  Pi                      .pi/         +  .agents/
  Both                    Claude Code + Codex
  All                     Claude Code + Codex + DeepSeek + Pi

Codex, DeepSeek and Pi all auto-load AGENTS.md at the project root, so the
installer keeps one shared router there and splices a route line per layer
inside a managed marker block. Content outside that block is never modified.
EOF2
}

# ── arg parsing ───────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --claude)   INSTALL_CLAUDE=true;  INSTALL_CODEX=false; INSTALL_DEEPSEEK=false; INSTALL_PI=false ;;
    --codex)    INSTALL_CLAUDE=false; INSTALL_CODEX=true;  INSTALL_DEEPSEEK=false; INSTALL_PI=false ;;
    --deepseek) INSTALL_CLAUDE=false; INSTALL_CODEX=false; INSTALL_DEEPSEEK=true;  INSTALL_PI=false ;;
    --pi)       INSTALL_CLAUDE=false; INSTALL_CODEX=false; INSTALL_DEEPSEEK=false; INSTALL_PI=true ;;
    --both)     INSTALL_CLAUDE=true;  INSTALL_CODEX=true;  INSTALL_DEEPSEEK=false; INSTALL_PI=false ;;
    --all)      INSTALL_CLAUDE=true;  INSTALL_CODEX=true;  INSTALL_DEEPSEEK=true;  INSTALL_PI=true ;;
    --force)  FORCE=true ;;
    --help|-h) show_help; exit 0 ;;
    *) printf '%s Unknown option: %s\n' "$(red "error")" "$arg" >&2; exit 1 ;;
  esac
done

# ── download ──────────────────────────────────────────────────────────────────

DEST="${PWD}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

printf '\n%s  Downloading CLAUDART from %s …\n' "$(bold "→")" "$REPO"

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

# Copy a single file, skipping if it already exists (unless --force).
copy_file() {
  local rel="$1"          # path relative to repo root, e.g. ".claude/CLAUDE.md"
  local src="$TMPDIR/$rel"
  local dst="$DEST/$rel"

  if [[ -f "$dst" && "$FORCE" == false ]]; then
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
    copy_file "$rel"
  done < <(find "$src_root" -type f | sort)
}

# Copy only the skills belonging to one layer. .agents/skills/ is discovered by
# the Codex, DeepSeek and Pi harnesses alike, so an unfiltered copy would install
# skills that route into a layer directory the user did not ask for.
copy_skills() {
  local prefix="$1"       # e.g. "codex", "deepseek" or "pi"
  local src_root="$TMPDIR/.agents/skills"

  if [[ ! -d "$src_root" ]]; then
    return
  fi

  while IFS= read -r src_file; do
    local rel="${src_file#"$TMPDIR/"}"
    copy_file "$rel"
  done < <(find "$src_root" -type f -path "$src_root/${prefix}-*" | sort)
}

# Root AGENTS.md is the one file Codex, dsh and Pi all auto-load, so it is shared
# rather than owned by any single layer. Add this layer's route line inside the
# managed marker block, creating the file from the template when absent. Anything
# outside the markers is project-authored and is never read, moved or rewritten.
ROUTES_START="<!-- claudart:routes:start -->"
ROUTES_END="<!-- claudart:routes:end -->"

splice_route() {
  local route="$1"        # the full route line, e.g. "- Codex CLI → follow \`.codex/AGENTS.md\`"
  local dst="$DEST/AGENTS.md"

  if [[ ! -f "$dst" ]]; then
    cp "$TMPDIR/.agents/AGENTS.md" "$dst"
    printf '  %s  AGENTS.md (shared harness router)\n' "$(green "copy")"
    (( COPIED++ )) || true
  fi

  if ! grep -Fq "$ROUTES_START" "$dst"; then
    # A project-authored AGENTS.md with no CLAUDART block: append one, leaving
    # every existing line intact.
    printf '\n%s\n%s\n' "$ROUTES_START" "$ROUTES_END" >>"$dst"
    printf '  %s  AGENTS.md (added CLAUDART route block)\n' "$(green "merge")"
  fi

  # -e is required: the route line starts with "-" and would otherwise be
  # parsed as grep options.
  if grep -Fq -e "$route" "$dst"; then
    printf '  %s  AGENTS.md route (already present)\n' "$(yellow "skip")"
    (( SKIPPED++ )) || true
    return
  fi

  # Insert immediately before the end marker so route order follows install order.
  local tmp_file
  tmp_file="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *"$ROUTES_END"* ]]; then
      printf '%s\n' "$route"
    fi
    printf '%s\n' "$line"
  done <"$dst" >"$tmp_file"
  mv "$tmp_file" "$dst"
  printf '  %s  AGENTS.md route → %s\n' "$(green "merge")" "$route"
}

# ── install ───────────────────────────────────────────────────────────────────

printf '\n%s  Installing into %s\n' "$(bold "→")" "$DEST"

if [[ "$INSTALL_CLAUDE" == true ]]; then
  printf '\n%s\n' "$(bold "Claude Code layer (.claude/)")"
  copy_tree ".claude"
fi

if [[ "$INSTALL_CODEX" == true ]]; then
  printf '\n%s\n' "$(bold "Codex layer")"

  copy_tree ".codex"
  copy_skills "codex"
  splice_route "- Codex CLI → follow \`.codex/AGENTS.md\`"

  # .codex/CODEX.md is deprecated when present; the template uses AGENTS.md as
  # the sole Codex memory index. Remove the stale path during reconciliation.
  if [[ -f "$DEST/.codex/CODEX.md" ]]; then
    rm "$DEST/.codex/CODEX.md"
    printf '  %s  .codex/CODEX.md (deprecated; content consolidated into AGENTS.md)\n' "$(green "clean")"
  fi
fi

if [[ "$INSTALL_DEEPSEEK" == true ]]; then
  printf '\n%s\n' "$(bold "DeepSeek layer")"

  copy_tree ".deepseek"
  copy_skills "deepseek"
  splice_route "- DeepSeek Harness (dsh) → follow \`.deepseek/DEEPSEEK.md\`"
fi

if [[ "$INSTALL_PI" == true ]]; then
  printf '\n%s\n' "$(bold "Pi layer")"

  copy_tree ".pi"
  copy_skills "pi"
  splice_route "- Pi → follow \`.pi/PI.md\`"
fi

# ── summary ───────────────────────────────────────────────────────────────────

printf '\n%s  Done. %d copied, %d skipped.\n\n' "$(bold "✓")" "$COPIED" "$SKIPPED"

if [[ "$SKIPPED" -gt 0 ]]; then
  printf '%s  Skipped files already exist in your project. Run with --force to overwrite them.\n\n' "$(yellow "note")"
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
if [[ "$INSTALL_DEEPSEEK" == true ]]; then
  # The dollar-prefixed skill names are intentional literals.
  # shellcheck disable=SC2016
  printf '  DeepSeek     →  open project, run /deepseek-doctor → /deepseek-refactor-memory → /deepseek-doctor once\n'
fi
if [[ "$INSTALL_PI" == true ]]; then
  printf '  Pi           →  open project, run /skill:pi-doctor → /skill:pi-refactor-memory → /skill:pi-doctor once\n'
fi
printf '\n'
