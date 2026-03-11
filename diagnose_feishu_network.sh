#!/usr/bin/env bash
set -euo pipefail

OUT_FILE="${1:-.runtime/feishu_network_report.txt}"
mkdir -p "$(dirname "$OUT_FILE")"

{
  echo "# Feishu network diagnostic report"
  echo "time=$(date -Iseconds)"
  echo
  echo "## proxy env"
  env | rg -i 'proxy|no_proxy' || true
  echo

  echo "## dns via system (proxy context)"
  getent hosts open.feishu.cn || true
  getent hosts open.larksuite.com || true
  echo

  echo "## curl via current proxy env"
  curl -I --max-time 10 https://open.feishu.cn 2>&1 | sed -n '1,12p' || true
  echo

  echo "## curl direct(no proxy/no all_proxy)"
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy \
    curl -I --noproxy '*' --max-time 10 https://open.feishu.cn 2>&1 | sed -n '1,12p' || true
  echo

  echo "## expected allowlist"
  echo "open.feishu.cn:443 (HTTPS/WSS)"
} >"$OUT_FILE"

echo "[ok] diagnostic report saved: $OUT_FILE"
