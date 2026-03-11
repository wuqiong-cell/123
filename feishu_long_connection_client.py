#!/usr/bin/env python3
"""Feishu long-connection client (official SDK mode)."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

TOKEN_URL = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal"


def _build_handler(lark):
    def do_p2_im_message_receive_v1(data, event):
        print("[feishu] receive message event")
        try:
            print(json.dumps(data, ensure_ascii=False))
        except Exception:  # noqa: BLE001
            print(str(data))
        return lark.ws.P2ImMessageReceiveV1Response(code=0)

    return (
        lark.EventDispatcherHandler.builder("", "")
        .register_p2_im_message_receive_v1(do_p2_im_message_receive_v1)
        .build()
    )


def _env_creds() -> tuple[str, str]:
    return os.getenv("FEISHU_APP_ID", "").strip(), os.getenv("FEISHU_APP_SECRET", "").strip()


def _check_token(app_id: str, app_secret: str, timeout: int = 12) -> tuple[bool, str]:
    payload = json.dumps({"app_id": app_id, "app_secret": app_secret}).encode("utf-8")
    req = urllib.request.Request(
        TOKEN_URL,
        data=payload,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return False, f"http {exc.code}: {body}"
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)

    if data.get("code") == 0 and data.get("tenant_access_token"):
        return True, "tenant_access_token acquired"
    return False, f"code={data.get('code')} msg={data.get('msg')}"


def _maybe_disable_proxy_once() -> tuple[bool, str]:
    keys = [
        "http_proxy",
        "https_proxy",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "all_proxy",
    ]
    old = {k: os.environ.get(k) for k in keys}
    had_proxy = any(v for v in old.values())
    if not had_proxy:
        return False, ""

    for k in keys:
        os.environ.pop(k, None)
    no_proxy = os.environ.get("NO_PROXY", "")
    want = "open.feishu.cn"
    if want not in no_proxy:
        os.environ["NO_PROXY"] = (no_proxy + "," + want).strip(",")
    return True, "proxy vars temporarily disabled for retry"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-only", action="store_true", help="only run token precheck")
    parser.add_argument("--no-proxy-fallback", action="store_true", help="don't retry with proxy disabled")
    args = parser.parse_args()

    app_id, app_secret = _env_creds()
    if not app_id or not app_secret:
        print("[error] missing FEISHU_APP_ID or FEISHU_APP_SECRET")
        return 2

    ok, detail = _check_token(app_id, app_secret)
    if not ok and ("Tunnel connection failed" in detail or "403" in detail) and not args.no_proxy_fallback:
        changed, msg = _maybe_disable_proxy_once()
        if changed:
            print(f"[warn] {msg}")
            ok2, detail2 = _check_token(app_id, app_secret)
            if ok2:
                ok, detail = ok2, detail2
            else:
                detail = f"{detail}; no-proxy-retry: {detail2}"

    if args.check_only:
        if ok:
            print(f"[ok] precheck passed: {detail}")
            return 0
        print(f"[error] precheck failed: {detail}")
        return 1

    if not ok:
        print(f"[error] precheck failed: {detail}")
        print("[hint] check app credentials or outbound access to open.feishu.cn:443")
        return 1

    try:
        import lark_oapi as lark
    except Exception as exc:  # noqa: BLE001
        print("[error] missing dependency lark_oapi. install with: pip install lark-oapi")
        print(f"[detail] {exc}")
        return 3

    event_handler = _build_handler(lark)
    client = lark.ws.Client(
        app_id,
        app_secret,
        event_handler=event_handler,
        log_level=lark.LogLevel.INFO,
    )

    print("[feishu] starting long connection client...")
    print(f"[feishu] app_id={app_id}")

    try:
        client.start()
    except KeyboardInterrupt:
        print("\n[feishu] stopped by user")
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"[error] failed to start long connection: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
