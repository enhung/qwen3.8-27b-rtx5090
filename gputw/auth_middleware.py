"""Fail-closed public API surface for the GPUtw vLLM container."""

import hmac
import os


_ALLOWED = {
    ("GET", "/health"),
    ("GET", "/v1/models"),
    ("POST", "/v1/chat/completions"),
}


class AuthMiddleware:
    def __init__(self, app):
        key = os.environ.get("VLLM_API_KEY", "")
        if not key or any(char.isspace() for char in key):
            raise RuntimeError("VLLM_API_KEY must contain one non-empty token")
        self.app = app
        self._expected = b"Bearer " + key.encode("utf-8")

    async def __call__(self, scope, receive, send):
        kind = scope["type"]
        if kind == "lifespan":
            await self.app(scope, receive, send)
            return
        if kind == "websocket":
            await send({"type": "websocket.close", "code": 1008})
            return
        if kind != "http":
            return

        route = (scope["method"], scope["path"])
        if route not in _ALLOWED:
            await self._reject(send, 404, b'{"error":"Not found"}')
            return

        authorization = [
            value for name, value in scope.get("headers", [])
            if name.lower() == b"authorization"
        ]
        if len(authorization) != 1 or not hmac.compare_digest(
            authorization[0], self._expected
        ):
            await self._reject(send, 401, b'{"error":"Unauthorized"}')
            return
        await self.app(scope, receive, send)

    @staticmethod
    async def _reject(send, status, body):
        await send({
            "type": "http.response.start",
            "status": status,
            "headers": [(b"content-type", b"application/json")],
        })
        await send({"type": "http.response.body", "body": body})
