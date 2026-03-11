#!/usr/bin/env python3
"""Open Claw -> Feishu adapter.

Supports two official Feishu delivery modes:
1) Custom bot webhook: set FEISHU_WEBHOOK_URL
2) App credentials + chat API: set FEISHU_APP_ID / FEISHU_APP_SECRET / FEISHU_CHAT_ID
"""

from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib import request

HOST = os.getenv("ADAPTER_HOST", "0.0.0.0")
PORT = int(os.getenv("ADAPTER_PORT", "8787"))

FEISHU_WEBHOOK_URL = os.getenv("FEISHU_WEBHOOK_URL", "").strip()
FEISHU_APP_ID = os.getenv("FEISHU_APP_ID", "").strip()
FEISHU_APP_SECRET = os.getenv("FEISHU_APP_SECRET", "").strip()
FEISHU_CHAT_ID = os.getenv("FEISHU_CHAT_ID", "").strip()


def _extract_text(raw: dict) -> str:
    event = raw.get("event") if isinstance(raw.get("event"), dict) else raw
    title = event.get("title") or event.get("type") or "Open Claw 事件"
    detail = event.get("message") or event.get("content") or json.dumps(event, ensure_ascii=False)
    return f"[Open Claw] {title}\n{detail}"


def _post_json(url: str, payload: dict, headers: dict | None = None) -> tuple[int, str]:
    req = request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", **(headers or {})},
        method="POST",
    )
    with request.urlopen(req, timeout=10) as resp:
        return resp.status, resp.read().decode("utf-8", errors="ignore")


def _send_by_webhook(text: str) -> tuple[int, str]:
    payload = {"msg_type": "text", "content": {"text": text}}
    return _post_json(FEISHU_WEBHOOK_URL, payload)


def _tenant_access_token() -> str:
    _, body = _post_json(
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
        {"app_id": FEISHU_APP_ID, "app_secret": FEISHU_APP_SECRET},
    )
    parsed = json.loads(body)
    token = parsed.get("tenant_access_token", "")
    if not token:
        raise RuntimeError(f"Failed to get tenant_access_token: {body}")
    return token


def _send_by_app_credential(text: str) -> tuple[int, str]:
    token = _tenant_access_token()
    payload = {
        "receive_id": FEISHU_CHAT_ID,
        "msg_type": "text",
        "content": json.dumps({"text": text}, ensure_ascii=False),
    }
    return _post_json(
        "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id",
        payload,
        headers={"Authorization": f"Bearer {token}"},
    )


def _send_to_feishu(text: str) -> tuple[int, str]:
    if FEISHU_WEBHOOK_URL:
        return _send_by_webhook(text)
    if FEISHU_APP_ID and FEISHU_APP_SECRET and FEISHU_CHAT_ID:
        return _send_by_app_credential(text)
    raise RuntimeError(
        "Missing Feishu config. Set FEISHU_WEBHOOK_URL or FEISHU_APP_ID+FEISHU_APP_SECRET+FEISHU_CHAT_ID"
    )


class Handler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/openclaw/events":
            self.send_error(404, "Not Found")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = self.rfile.read(length).decode("utf-8")
            data = json.loads(payload) if payload else {}
            text = _extract_text(data)
            status, body = _send_to_feishu(text)
        except Exception as exc:  # noqa: BLE001
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"ok": False, "error": str(exc)}).encode("utf-8"))
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"ok": True, "feishu_status": status, "feishu_body": body}).encode("utf-8"))

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
            return
        self.send_error(404, "Not Found")


if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), Handler)
    print(f"open-claw-feishu-adapter listening on {HOST}:{PORT}")
    server.serve_forever()
