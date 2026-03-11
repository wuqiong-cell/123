#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

python -m py_compile feishu_long_connection_client.py open_claw_feishu_adapter.py

set +e
python feishu_long_connection_client.py --check-only >/tmp/feishu-no-env.out 2>&1
rc=$?
set -e
if [[ $rc -eq 2 ]]; then
  echo "OK_MISSING_ENV"
else
  echo "expected rc=2 when env missing" >&2
  cat /tmp/feishu-no-env.out >&2
  exit 1
fi

bash -n setup_feishu_mode.sh diagnose_feishu_network.sh deploy_feishu_runner.sh install_local_plugins.sh manage_feishu_bot.sh

FEISHU_APP_ID='x' FEISHU_APP_SECRET='y' ./setup_feishu_mode.sh --diag-only
[[ -f .runtime/feishu_network_report.txt ]]
echo "OK_DIAG_REPORT"

tmp_codex="$(mktemp -d)"
CODEX_HOME="$tmp_codex" FEISHU_APP_ID='x' FEISHU_APP_SECRET='y' ./setup_feishu_mode.sh --local-only
[[ -f .runtime/feishu.env ]]
[[ -f "$tmp_codex/skills/open-claw/SKILL.md" ]]
[[ -f "$tmp_codex/skills/open-claw-feishu/SKILL.md" ]]
echo "OK_LOCAL_ONLY"

FEISHU_APP_ID='x' FEISHU_APP_SECRET='y' ./deploy_feishu_runner.sh
[[ -f .runtime/feishu-runner.tgz ]]
echo "OK_RUNNER_BUNDLE"

set +e
./manage_feishu_bot.sh status >/tmp/feishu-status.out 2>&1
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "OK_STATUS_NOT_RUNNING"
else
  echo "expected non-zero when not running" >&2
  exit 1
fi

set +e
./manage_feishu_bot.sh doctor >/tmp/feishu-doctor.out 2>&1
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "OK_DOCTOR_DIAG"
else
  echo "doctor should be non-zero in blocked env test context" >&2
  exit 1
fi

set +e
./manage_feishu_bot.sh check-openclaw-api >/tmp/openclaw-api-no-key.out 2>&1
rc=$?
set -e
if [[ $rc -eq 2 ]]; then
  echo "OK_OPENCLAW_API_MISSING_KEY"
else
  echo "expected rc=2 when api key missing" >&2
  exit 1
fi

set +e
OPENAI_API_KEY='sk-test' ./manage_feishu_bot.sh check-openclaw-api >/tmp/openclaw-api-check.out 2>&1
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "OK_OPENCLAW_API_CHECK_FAIL_IN_RESTRICTED_ENV"
else
  echo "expected non-zero in restricted env with fake key" >&2
  exit 1
fi
