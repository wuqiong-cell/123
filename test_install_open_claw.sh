#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$ROOT_DIR/install_open_claw.sh"

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; exit 1; }

# 1) help should work
"$SCRIPT" --help >/dev/null || fail "--help should exit 0"
pass "--help exits 0"

# 2) local-dir install should work
TMP1="$(mktemp -d)"
mkdir -p "$TMP1/open-claw"
printf '# Open Claw\n' > "$TMP1/open-claw/SKILL.md"
CODEX_HOME="$TMP1/codex-home" "$SCRIPT" --local-dir "$TMP1/open-claw" >/dev/null
[[ -f "$TMP1/codex-home/skills/open-claw/SKILL.md" ]] || fail "local-dir install should create skill"
pass "--local-dir installs successfully"

# 3) existing destination should be skipped (still success)
CODEX_HOME="$TMP1/codex-home" "$SCRIPT" --local-dir "$TMP1/open-claw" >/dev/null
pass "existing destination is handled"

# 4) local-zip install should work
TMP2="$(mktemp -d)"
mkdir -p "$TMP2/skills-main/skills/.curated/open-claw"
printf '# Open Claw\n' > "$TMP2/skills-main/skills/.curated/open-claw/SKILL.md"
(
  cd "$TMP2"
  zip -qr skills-main.zip skills-main
)
CODEX_HOME="$TMP2/codex-home" "$SCRIPT" --local-zip "$TMP2/skills-main.zip" >/dev/null
[[ -f "$TMP2/codex-home/skills/open-claw/SKILL.md" ]] || fail "local-zip install should create skill"
pass "--local-zip installs successfully"

# 5) invalid local-dir should fail
TMP3="$(mktemp -d)"
mkdir -p "$TMP3/not-a-skill"
if CODEX_HOME="$TMP3/codex-home" "$SCRIPT" --local-dir "$TMP3/not-a-skill" >/dev/null 2>&1; then
  fail "invalid local-dir should fail"
fi
pass "invalid local-dir fails as expected"

pass "all installer tests passed"
