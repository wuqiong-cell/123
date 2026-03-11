#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p .runtime
PID_FILE=".runtime/feishu_long_connection.pid"
LOG_FILE=".runtime/feishu_long_connection.log"
ENV_FILE=".runtime/feishu.env"
DIAG_FILE=".runtime/feishu_network_report.txt"

usage() {
  cat <<'EOT'
usage: ./manage_feishu_bot.sh <doctor|check|start|stop|status|check-openclaw-api> [--api-key <key>]

doctor             - full diagnosis with actionable next steps
check              - verify env and Feishu token precheck
start              - install dependency if needed and start long connection in background
stop               - stop background long connection process
status             - show whether long connection process is running
check-openclaw-api - verify OpenClaw/OpenAI API key connectivity
EOT
}

parse_api_key_arg() {
  API_KEY_ARG=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --api-key)
        API_KEY_ARG="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
}

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "[error] $ENV_FILE not found. run setup_feishu_mode.sh --local-only first" >&2
    exit 2
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  export FEISHU_APP_ID FEISHU_APP_SECRET
}

ensure_dep() {
  if python - <<'PY' >/dev/null 2>&1
import importlib
importlib.import_module('lark_oapi')
PY
  then
    return 0
  fi
  echo "[step] installing dependency: lark-oapi"
  python -m pip install --quiet lark-oapi
}

resolve_api_key() {
  if [[ -n "${API_KEY_ARG:-}" ]]; then
    echo "$API_KEY_ARG"
    return 0
  fi
  if [[ -n "${OPENCLAW_API_KEY:-}" ]]; then
    echo "$OPENCLAW_API_KEY"
    return 0
  fi
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    echo "$OPENAI_API_KEY"
    return 0
  fi
  echo ""
}

check_openclaw_api() {
  local key
  key="$(resolve_api_key)"
  if [[ -z "$key" ]]; then
    echo "[error] missing api key. pass --api-key or set OPENCLAW_API_KEY/OPENAI_API_KEY" >&2
    return 2
  fi

  local masked
  masked="${key:0:10}...${key: -6}"
  local base_url
  base_url="${OPENCLAW_BASE_URL:-https://api.openai.com}"
  local url="${base_url%/}/v1/models"

  echo "[check-openclaw-api] checking $url"
  echo "[check-openclaw-api] key=$masked"

  set +e
  local out rc
  out="$(curl -sS -i --max-time 15 -H "Authorization: Bearer $key" "$url" 2>&1)"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    if echo "$out" | rg -q "CONNECT tunnel failed, response 403|Tunnel connection failed: 403 Forbidden"; then
      echo "[error] api key request blocked by network proxy (CONNECT 403)."
      echo "[fix] allow outbound access to api.openai.com:443 (or set OPENCLAW_BASE_URL to your reachable gateway)."
      return 1
    fi
    echo "[error] api request failed: $out"
    return 1
  fi

  local code
  code="$(echo "$out" | awk 'NR==1{print $2}')"
  if [[ "$code" == "200" ]]; then
    echo "[ok] api key is reachable and valid for model listing"
    return 0
  fi
  if [[ "$code" == "401" ]]; then
    echo "[error] api key unauthorized (401). check key value and account permissions."
    return 1
  fi

  echo "[warn] unexpected http status: $code"
  echo "$out" | sed -n '1,20p'
  return 1
}

do_check() {
  load_env
  python feishu_long_connection_client.py --check-only
}

do_doctor() {
  echo "[doctor] 1/5 checking env file..."
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "[doctor:error] missing $ENV_FILE"
    echo "[doctor:fix] run: ./setup_feishu_mode.sh --app-id '<id>' --app-secret '<secret>' --local-only"
    return 2
  fi

  echo "[doctor] 2/5 checking long-connection process..."
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" >/dev/null 2>&1; then
    echo "[doctor:ok] process running pid=$(cat "$PID_FILE")"
  else
    echo "[doctor:warn] process not running"
  fi

  echo "[doctor] 3/5 checking app credentials and Feishu outbound connectivity..."
  set +e
  check_out="$(do_check 2>&1)"
  rc=$?
  set -e
  echo "$check_out"

  echo "[doctor] 4/5 checking OpenClaw/OpenAI API key connectivity (optional)..."
  set +e
  parse_api_key_arg "$@"
  api_out="$(check_openclaw_api 2>&1)"
  api_rc=$?
  set -e
  echo "$api_out"

  if [[ $rc -eq 0 ]]; then
    cat <<'EOT'
[doctor:ok] Feishu precheck passed.
[doctor:next] run: ./manage_feishu_bot.sh start
[doctor:next] after status is running, return to Feishu console and click Save.
EOT
    return 0
  fi

  echo "[doctor] 5/5 generating network report..."
  ./diagnose_feishu_network.sh "$DIAG_FILE" >/dev/null
  echo "[doctor:info] report: $DIAG_FILE"

  if echo "$check_out" | rg -q "Tunnel connection failed: 403 Forbidden"; then
    cat <<'EOT'
[doctor:root-cause] current machine is blocked by proxy/egress policy (CONNECT 403) to Feishu.
[doctor:fix-required]
  A) ask network admin to allow: open.feishu.cn:443 (HTTPS/WSS)
  B) OR run long connection on a machine with internet egress.
[doctor:when-fixed] run:
  ./manage_feishu_bot.sh start
  ./manage_feishu_bot.sh status
EOT
    return 1
  fi

  if echo "$check_out" | rg -qi "code=.*|app_id|app_secret|tenant_access_token"; then
    cat <<'EOT'
[doctor:root-cause] app credentials likely invalid or app permission not ready.
[doctor:fix-required]
  - verify App ID / App Secret in Feishu console
  - ensure app is published/installed and bot capability is enabled
EOT
    return 1
  fi

  if [[ $api_rc -ne 0 ]]; then
    cat <<'EOT'
[doctor:extra] OpenClaw/OpenAI API key check failed too.
[doctor:fix-required]
  - verify API key validity
  - allow outbound api.openai.com:443 or set OPENCLAW_BASE_URL to reachable gateway
EOT
  fi

  cat <<'EOT'
[doctor:root-cause] unknown startup failure.
[doctor:fix-required] inspect logs and diagnostics:
  - .runtime/feishu_long_connection.log
  - .runtime/feishu_network_report.txt
EOT
  return 1
}

do_start() {
  load_env
  ensure_dep
  python feishu_long_connection_client.py --check-only
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" >/dev/null 2>&1; then
    echo "[ok] already running pid=$(cat "$PID_FILE")"
    exit 0
  fi
  nohup python feishu_long_connection_client.py >"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"
  sleep 2
  if kill -0 "$(cat "$PID_FILE")" >/dev/null 2>&1; then
    echo "[ok] long connection started pid=$(cat "$PID_FILE")"
    echo "[info] log=$LOG_FILE"
  else
    echo "[error] process exited quickly, check log: $LOG_FILE" >&2
    tail -n 50 "$LOG_FILE" || true
    exit 1
  fi
}

do_stop() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" >/dev/null 2>&1; then
    kill "$(cat "$PID_FILE")"
    rm -f "$PID_FILE"
    echo "[ok] stopped"
  else
    echo "[ok] not running"
  fi
}

do_status() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" >/dev/null 2>&1; then
    echo "[ok] running pid=$(cat "$PID_FILE")"
    echo "[info] log=$LOG_FILE"
    tail -n 20 "$LOG_FILE" || true
  else
    echo "[warn] not running"
    [[ -f "$LOG_FILE" ]] && tail -n 20 "$LOG_FILE" || true
    exit 1
  fi
}

cmd="${1:-}"
case "$cmd" in
  doctor) shift; do_doctor "$@" ;;
  check) do_check ;;
  start) do_start ;;
  stop) do_stop ;;
  status) do_status ;;
  check-openclaw-api) shift; parse_api_key_arg "$@"; check_openclaw_api ;;
  *) usage; exit 2 ;;
esac
