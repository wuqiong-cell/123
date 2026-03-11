#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

DEST_ROOT="${CODEX_HOME:-${HOME}/.codex}/skills"
mkdir -p "$DEST_ROOT"

install_one() {
  local src="$1"
  local name
  name="$(basename "$src")"
  local dest="$DEST_ROOT/$name"
  rm -rf "$dest"
  cp -R "$src" "$dest"
  echo "[ok] installed $name -> $dest"
}

install_one "local_plugins/open-claw"
install_one "local_plugins/open-claw-feishu"

echo "[done] local plugins installed"
echo "[hint] restart Codex to pick up new skills"
