#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="@openai/codex"
PREFIX="${HOME}/.local"
TARBALL_PATH=""
SKIP_NETWORK=0

usage() {
  cat <<'EOT'
Usage:
  ./install_codex_local.sh [--tarball <path.tgz>] [--prefix <dir>] [--skip-network]

Options:
  --tarball <path.tgz>  Install from a local npm tarball (offline recommended).
  --prefix <dir>        npm global prefix for install target (default: ~/.local).
  --skip-network        Do not attempt network install; require --tarball.

Examples:
  ./install_codex_local.sh
  ./install_codex_local.sh --tarball ./codex.tgz
  ./install_codex_local.sh --tarball ./codex.tgz --prefix /opt/codex-local
EOT
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tarball) TARBALL_PATH="${2:-}"; shift 2 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --skip-network) SKIP_NETWORK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v npm >/dev/null 2>&1; then
  echo "[error] npm not found. Install Node.js/npm first." >&2
  exit 2
fi

mkdir -p "$PREFIX"

echo "[step] npm prefix: $PREFIX"

do_install_tarball() {
  local tarball="$1"
  if [[ ! -f "$tarball" ]]; then
    echo "[error] tarball not found: $tarball" >&2
    exit 2
  fi
  echo "[step] installing codex from local tarball: $tarball"
  npm install -g --prefix "$PREFIX" "$tarball"
}

do_install_network() {
  echo "[step] installing codex from npm registry: $PACKAGE_NAME"
  npm install -g --prefix "$PREFIX" "$PACKAGE_NAME"
}

if [[ -n "$TARBALL_PATH" ]]; then
  do_install_tarball "$TARBALL_PATH"
elif [[ $SKIP_NETWORK -eq 1 ]]; then
  echo "[error] --skip-network requires --tarball <path.tgz>" >&2
  exit 2
else
  set +e
  out="$(do_install_network 2>&1)"
  rc=$?
  set -e
  echo "$out"
  if [[ $rc -ne 0 ]]; then
    if echo "$out" | rg -qi "403|E403|tunnel|connect|ECONN|network"; then
      cat <<'EOT'
[warn] network install failed due to restricted outbound access.
[action] Use offline tarball install instead:
  1) On a machine with internet:
     npm pack @openai/codex
  2) Copy the resulting *.tgz to this machine.
  3) Run:
     ./install_codex_local.sh --tarball ./openai-codex-<version>.tgz --skip-network
EOT
      exit 1
    fi
    exit "$rc"
  fi
fi

BIN_PATH="$PREFIX/bin/codex"
if [[ -x "$BIN_PATH" ]]; then
  echo "[ok] codex installed: $BIN_PATH"
  echo "[next] add to PATH: export PATH=\"$PREFIX/bin:\$PATH\""
  "$BIN_PATH" --version || true
else
  echo "[warn] install finished but codex binary not found at $BIN_PATH"
  echo "[hint] check npm global bin path for prefix: $PREFIX"
fi
