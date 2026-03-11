#!/usr/bin/env bash
set -euo pipefail

APP_ID=""
APP_SECRET=""
TARGET=""
REMOTE_DIR="~/feishu-runner"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id) APP_ID="${2:-}"; shift 2 ;;
    --app-secret) APP_SECRET="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --remote-dir) REMOTE_DIR="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

APP_ID="${APP_ID:-${FEISHU_APP_ID:-}}"
APP_SECRET="${APP_SECRET:-${FEISHU_APP_SECRET:-}}"

if [[ -z "$APP_ID" || -z "$APP_SECRET" ]]; then
  echo "[error] missing app credentials" >&2
  echo "usage: $0 --app-id <id> --app-secret <secret> [--target user@host]" >&2
  exit 2
fi

cd "$(dirname "$0")"
mkdir -p .runtime/feishu-runner

cat > .runtime/feishu-runner/requirements.txt <<'EOF'
lark-oapi
EOF

cp feishu_long_connection_client.py .runtime/feishu-runner/

cat > .runtime/feishu-runner/run.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
export FEISHU_APP_ID='${APP_ID}'
export FEISHU_APP_SECRET='${APP_SECRET}'
python feishu_long_connection_client.py
EOF
chmod +x .runtime/feishu-runner/run.sh

tar -C .runtime -czf .runtime/feishu-runner.tgz feishu-runner

echo "[ok] bundle generated: .runtime/feishu-runner.tgz"

if [[ -z "$TARGET" ]]; then
  cat <<'EOF'
[next] 在可出网机器执行：
  tar -xzf feishu-runner.tgz
  cd feishu-runner
  python3 -m pip install -r requirements.txt
  ./run.sh
EOF
  exit 0
fi

echo "[step] upload bundle to $TARGET ..."
scp .runtime/feishu-runner.tgz "$TARGET:/tmp/feishu-runner.tgz"

echo "[step] start runner on remote host ..."
ssh "$TARGET" "bash -lc 'mkdir -p $REMOTE_DIR && tar -xzf /tmp/feishu-runner.tgz -C $REMOTE_DIR --strip-components=1 && cd $REMOTE_DIR && python3 -m pip install -r requirements.txt && nohup ./run.sh > feishu.log 2>&1 & echo \\$! > feishu.pid && echo started pid=\$(cat feishu.pid) log=$REMOTE_DIR/feishu.log'"

echo "[ok] remote runner started on $TARGET"
