#!/bin/bash

# Installer behavior tests. Two mechanisms are covered because both fail
# silently: per-layer skill scoping (.agents/skills/ is shared by the Codex,
# DeepSeek and Pi harnesses) and the root AGENTS.md router splice, which must
# never disturb project-authored content.

set -u

LC_ALL=C
export LC_ALL

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 2
REPO_ROOT=$(CDPATH='' cd -- "$TEST_DIR/../.." 2>/dev/null && pwd -P) || exit 2
INSTALLER=$REPO_ROOT/install.sh
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claudart-install-tests.XXXXXX" 2>/dev/null) ||
  exit 2

# Invoked indirectly by trap.
# shellcheck disable=SC2329
cleanup() {
  if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf -- "$TMP_ROOT"
  fi
}
trap cleanup EXIT HUP INT TERM

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

assert_equals() {
  label=$1
  expected=$2
  actual=$3
  if [ "$expected" = "$actual" ]; then
    pass "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_file_contains() {
  label=$1
  file=$2
  needle=$3
  # -e guards needles that start with "-".
  if [ -f "$file" ] && grep -Fq -e "$needle" "$file"; then
    pass "$label"
  else
    fail "$label (missing '$needle' in ${file##*/})"
  fi
}

assert_missing() {
  label=$1
  path=$2
  if [ ! -e "$path" ]; then
    pass "$label"
  else
    fail "$label (unexpectedly present: $path)"
  fi
}

# The real installer downloads a tarball from GitHub. Rewrite that one block to
# copy this working tree instead, so the tests exercise the local changes.
LOCAL_INSTALLER=$TMP_ROOT/install-local.sh
/usr/bin/env python3 - "$INSTALLER" "$LOCAL_INSTALLER" "$REPO_ROOT" <<'PY'
import sys

source, destination, repo_root = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(source).read()
download = '''if command -v curl &>/dev/null; then
  curl -fsSL "$TARBALL_URL" | tar -xz -C "$TMPDIR" --strip-components=1
elif command -v wget &>/dev/null; then
  wget -qO- "$TARBALL_URL" | tar -xz -C "$TMPDIR" --strip-components=1
else
  printf '%s curl or wget is required.\\n' "$(red "error")" >&2
  exit 1
fi'''
if download not in text:
    sys.exit("install.sh download block not found; update tests/install/run.sh")
open(destination, "w").write(text.replace(download, 'cp -R %s/. "$TMPDIR/"' % repo_root))
PY

install_into() {
  target=$1
  shift
  mkdir -p "$target"
  (cd "$target" && /bin/bash "$LOCAL_INSTALLER" "$@") >"$TMP_ROOT/install.out" 2>&1
}

skill_prefixes() {
  # Distinct name prefixes present under .agents/skills/, space separated.
  find "$1/.agents/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
    sed 's|.*/||; s|-.*||' | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//'
}

route_block_count() {
  grep -c 'claudart:routes:start' "$1/AGENTS.md" 2>/dev/null || printf '0\n'
}

if /bin/bash -n "$INSTALLER" "$TEST_DIR/run.sh"; then
  pass "Bash syntax is valid"
else
  fail "Bash syntax is valid"
fi

# ── per-layer skill scoping ───────────────────────────────────────────────────

for layer in codex deepseek pi; do
  target=$TMP_ROOT/scope-$layer
  install_into "$target" "--$layer"
  assert_equals "--$layer installs only $layer- skills" "$layer" "$(skill_prefixes "$target")"
done

target=$TMP_ROOT/scope-claude
install_into "$target" --claude
assert_missing "--claude installs no .agents/skills" "$target/.agents/skills"

target=$TMP_ROOT/scope-all
install_into "$target" --all
assert_equals "--all installs every harness skill set" \
  "codex deepseek pi" "$(skill_prefixes "$target")"

# ── root AGENTS.md router ─────────────────────────────────────────────────────

target=$TMP_ROOT/router-single
install_into "$target" --pi
assert_file_contains "router names the Pi layer body" "$target/AGENTS.md" '.pi/PI.md'
assert_equals "router block appears exactly once" 1 "$(route_block_count "$target")"
assert_missing "no stray root PI.md loader" "$target/PI.md"
assert_missing "no stray root DEEPSEEK.md loader" "$target/DEEPSEEK.md"
assert_file_contains "layer body stays inside its own directory" \
  "$target/.pi/PI.md" 'CLAUDART Pi Instructions'

# Installing a second layer adds one route to the same block.
install_into "$target" --deepseek
assert_equals "second layer reuses the single route block" 1 "$(route_block_count "$target")"
assert_file_contains "router still names the Pi layer" "$target/AGENTS.md" '.pi/PI.md'
assert_file_contains "router now names the DeepSeek layer" \
  "$target/AGENTS.md" '.deepseek/DEEPSEEK.md'

# Re-running the same layer must not duplicate its route.
before=$(grep -c 'PI.md' "$target/AGENTS.md")
install_into "$target" --pi
after=$(grep -c 'PI.md' "$target/AGENTS.md")
assert_equals "re-running a layer does not duplicate its route" "$before" "$after"

# ── router must preserve project-authored content ─────────────────────────────

target=$TMP_ROOT/router-authored
mkdir -p "$target"
cat >"$target/AGENTS.md" <<'AUTHORED'
# Our House Rules

Always run `make verify` before pushing.

## Conventions

- Use tabs, not spaces.
AUTHORED
cp "$target/AGENTS.md" "$TMP_ROOT/authored-original"

install_into "$target" --codex
install_into "$target" --pi

if grep -Fq -e 'Always run `make verify` before pushing.' "$target/AGENTS.md" &&
  grep -Fq -e '- Use tabs, not spaces.' "$target/AGENTS.md" &&
  grep -Fq -e '# Our House Rules' "$target/AGENTS.md"; then
  pass "project-authored AGENTS.md content survives two installs"
else
  fail "project-authored AGENTS.md content survives two installs"
  sed 's/^/  /' "$target/AGENTS.md" >&2
fi

# Removing the managed block must return the file to exactly what was authored.
# Trailing blank lines are normalized away because the block is appended after one.
sed '/claudart:routes:start/,/claudart:routes:end/d' "$target/AGENTS.md" |
  sed -e :a -e '/^$/{$d;N;ba' -e '}' >"$TMP_ROOT/authored-stripped"
if diff -u "$TMP_ROOT/authored-original" "$TMP_ROOT/authored-stripped" \
  >"$TMP_ROOT/authored.diff"; then
  pass "stripping the managed block restores the authored file byte for byte"
else
  fail "stripping the managed block restores the authored file byte for byte"
  sed 's/^/  /' "$TMP_ROOT/authored.diff" >&2
fi

assert_equals "authored file receives exactly one route block" 1 "$(route_block_count "$target")"
assert_file_contains "authored file gains the Codex route" "$target/AGENTS.md" '.codex/AGENTS.md'
assert_file_contains "authored file gains the Pi route" "$target/AGENTS.md" '.pi/PI.md'

# ── installed layers validate ─────────────────────────────────────────────────

for layer in codex deepseek pi; do
  target=$TMP_ROOT/scope-$layer
  if /bin/bash "$target/.$layer/scripts/knowledge-check.sh" \
    --root "$target" --layer "$layer" >"$TMP_ROOT/check-$layer.out" 2>&1; then
    pass "installed $layer layer passes its own knowledge checker"
  else
    fail "installed $layer layer passes its own knowledge checker"
    sed 's/^/  /' "$TMP_ROOT/check-$layer.out" >&2
  fi
done

printf '1..%s\n' "$PASS_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf 'FAIL: %s assertion(s) failed\n' "$FAIL_COUNT" >&2
  exit 1
fi
printf 'PASS: %s assertions\n' "$PASS_COUNT"
