#!/usr/bin/env bash
set -euo pipefail

APP_ID=""
APP_SECRET=""
DETACH=0
DIAG_ONLY=0
LOCAL_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id) APP_ID="${2:-}"; shift 2 ;;
    --app-secret) APP_SECRET="${2:-}"; shift 2 ;;
    --detach) DETACH=1; shift ;;
    --diag-only) DIAG_ONLY=1; shift ;;
    --local-only) LOCAL_ONLY=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

APP_ID="${APP_ID:-${FEISHU_APP_ID:-}}"
APP_SECRET="${APP_SECRET:-${FEISHU_APP_SECRET:-}}"

if [[ -z "$APP_ID" || -z "$APP_SECRET" ]]; then
  echo "[error] missing app credentials; pass --app-id/--app-secret or env vars" >&2
  exit 2
fi

cd "$(dirname "$0")"
export FEISHU_APP_ID="$APP_ID"
export FEISHU_APP_SECRET="$APP_SECRET"

mkdir -p .runtime
ENV_FILE=".runtime/feishu.env"
cat >"$ENV_FILE" <<EOT
FEISHU_APP_ID='$APP_ID'
FEISHU_APP_SECRET='$APP_SECRET'
EOT
chmod 600 "$ENV_FILE"
echo "[ok] wrote credentials to $ENV_FILE"

if [[ $LOCAL_ONLY -eq 1 ]]; then
  echo "[step] install local plugins only (skip network precheck)"
  ./install_local_plugins.sh
  echo "[done] local-only setup completed"
  echo "[next] run ./manage_feishu_bot.sh doctor"
  exit 0
fi

if [[ $DIAG_ONLY -eq 1 ]]; then
  ./diagnose_feishu_network.sh
  exit 0
fi

echo "[step] precheck token..."
set +e
PRECHECK_OUTPUT="$(python feishu_long_connection_client.py --check-only 2>&1)"
PRECHECK_RC=$?
set -e
echo "$PRECHECK_OUTPUT"

if [[ $PRECHECK_RC -ne 0 ]]; then
  if echo "$PRECHECK_OUTPUT" | rg -q "Tunnel connection failed: 403 Forbidden"; then
    cat <<'EOT'
[action-required] 当前网络拦截了飞书出网，代码侧无法继续绕过。
已自动生成网络诊断报告：.runtime/feishu_network_report.txt
你有 2 条可立刻执行的路径：
1) 放通网络（推荐）
   - 目标域名: open.feishu.cn
   - 目标端口: 443
   - 协议: HTTPS / WSS
2) 换一台可出网机器运行长连接（例如你的笔记本或云主机）
   - 把本仓库拷过去后执行：
     FEISHU_APP_ID='你的app_id' FEISHU_APP_SECRET='你的secret' python feishu_long_connection_client.py
EOT
    ./diagnose_feishu_network.sh
    cat <<'EOT'
[action-now] 你可以立即执行下面命令，把客户端部署到一台可出网机器：
  ./deploy_feishu_runner.sh --app-id "$FEISHU_APP_ID" --app-secret "$FEISHU_APP_SECRET" --target <user@host>
EOT
  fi
  exit "$PRECHECK_RC"
fi

if [[ $DETACH -eq 1 ]]; then
  LOG_FILE=".runtime/feishu_long_connection.log"
  PID_FILE=".runtime/feishu_long_connection.pid"
  nohup python feishu_long_connection_client.py >"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"
  echo "[ok] started in background"
  echo "[info] pid=$(cat "$PID_FILE") log=$LOG_FILE"
else
  echo "[step] start foreground long-connection client..."
  exec python feishu_long_connection_client.py
fi
