#!/usr/bin/env bash
# okf-install.sh — builds the pinned `okf` binary (okf-agent-memory CLI) into
# <repo>/.claude/scripts/bin/okf, per D13.
#
# Idempotent: if the target binary already exists and is executable, this is a no-op (exit 0).
# Otherwise it clones the pinned commit into a temp dir, builds it, and cleans up the temp dir on
# both success and failure. Exits 2 with a message when `go` is not on PATH.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${HERE}/../.." && pwd)

OKF_REPO_URL="https://github.com/okf-memory/okf-agent-memory"
OKF_PINNED_COMMIT="c05ce5d"
OKF_BIN_DIR="${REPO_ROOT}/.claude/scripts/bin"
OKF_BIN_PATH="${OKF_BIN_DIR}/okf"

if [ -x "${OKF_BIN_PATH}" ]; then
  printf 'okf-install: %s already present — nothing to do\n' "${OKF_BIN_PATH}"
  exit 0
fi

if ! command -v go >/dev/null 2>&1; then
  printf 'okf-install: go is required to build okf and was not found on PATH.\n' >&2
  printf 'okf-install: on a machine without Go, set CLAUDART_OKF_BIN to a prebuilt okf binary instead.\n' >&2
  exit 2
fi

WORKDIR=$(mktemp -d)
cleanup() {
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

# A shallow `git fetch --depth 1 origin <short-sha>` cannot reach an arbitrary commit on GitHub's
# smart-HTTP transport (it rejects a short SHA as an unknown "remote ref", and even the full 40-char
# SHA is only reachable when the host explicitly allows fetch-by-SHA). A full clone followed by a
# local checkout of the pinned commit works unconditionally and is the alternative this script's
# owning task explicitly sanctions.
git -C "${WORKDIR}" clone --quiet "${OKF_REPO_URL}" checkout
git -C "${WORKDIR}/checkout" checkout --quiet "${OKF_PINNED_COMMIT}"

CHECKED_OUT_SHA=$(git -C "${WORKDIR}/checkout" rev-parse HEAD)
case "${CHECKED_OUT_SHA}" in
  "${OKF_PINNED_COMMIT}"*) ;;
  *)
    printf 'okf-install: checked-out commit %s does not match pinned commit %s\n' \
      "${CHECKED_OUT_SHA}" "${OKF_PINNED_COMMIT}" >&2
    exit 2
    ;;
esac

mkdir -p "${OKF_BIN_DIR}"
( cd "${WORKDIR}/checkout" && go build -o "${OKF_BIN_PATH}" ./cmd/okf )

if [ ! -x "${OKF_BIN_PATH}" ]; then
  printf 'okf-install: build reported success but %s is not executable\n' "${OKF_BIN_PATH}" >&2
  exit 2
fi

printf 'okf-install: built %s at commit %s\n' "${OKF_BIN_PATH}" "${CHECKED_OUT_SHA}"
