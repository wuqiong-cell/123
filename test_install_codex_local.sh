#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

bash -n install_codex_local.sh

# help
./install_codex_local.sh --help >/tmp/codex-help.out

tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/pkg/bin"
cat >"$tmpdir/pkg/package.json" <<'JSON'
{
  "name": "@openai/codex",
  "version": "0.0.0-test",
  "bin": {
    "codex": "bin/codex"
  }
}
JSON
cat >"$tmpdir/pkg/bin/codex" <<'SH'
#!/usr/bin/env bash
echo "codex 0.0.0-test"
SH
chmod +x "$tmpdir/pkg/bin/codex"

( cd "$tmpdir/pkg" && npm pack >/tmp/codex-pack.out )
TARBALL="$tmpdir/pkg/$(cat /tmp/codex-pack.out | tail -n 1)"

PREFIX="$tmpdir/prefix"
./install_codex_local.sh --tarball "$TARBALL" --skip-network --prefix "$PREFIX"

"$PREFIX/bin/codex" --version | rg -q '0.0.0-test'
echo "OK_FAKE_TARBALL_INSTALL"

set +e
./install_codex_local.sh --skip-network >/tmp/codex-skip.out 2>&1
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "OK_SKIP_NETWORK_REQUIRES_TARBALL"
else
  echo "expected failure for --skip-network without --tarball" >&2
  exit 1
fi
