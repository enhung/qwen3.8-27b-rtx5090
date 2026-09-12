import asyncio
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gputw"))
from auth_middleware import AuthMiddleware
from verify_auth import checked_origin, load_key


class AuthMiddlewareTests(unittest.TestCase):
    def setUp(self):
        self.upstream_calls = 0

        async def upstream(scope, receive, send):
            self.upstream_calls += 1
            await send({"type": "http.response.start", "status": 200, "headers": []})
            await send({"type": "http.response.body", "body": b"ok"})

        with patch.dict(os.environ, {"VLLM_API_KEY": "test-key"}):
            self.middleware = AuthMiddleware(upstream)

    def request(self, method, path, headers=()):
        events = []

        async def receive():
            return {"type": "http.request", "body": b"", "more_body": False}

        async def send(event):
            events.append(event)

        asyncio.run(self.middleware(
            {"type": "http", "method": method, "path": path, "headers": headers},
            receive,
            send,
        ))
        return events[0]["status"]

    def test_approved_hermes_and_health_routes_require_key(self):
        for method, path in (
            ("GET", "/health"),
            ("GET", "/v1/models"),
            ("POST", "/v1/chat/completions"),
        ):
            with self.subTest(path=path):
                self.assertEqual(self.request(method, path), 401)
                self.assertEqual(self.request(
                    method, path, [(b"authorization", b"Bearer wrong")]
                ), 401)
                self.assertEqual(self.request(
                    method, path, [(b"authorization", b"Bearer test-key")]
                ), 200)
        self.assertEqual(self.upstream_calls, 3)

    def test_unprotected_vllm_routes_are_not_exposed(self):
        for path in ("/invocations", "/metrics", "/docs", "/v1/load_lora_adapter"):
            with self.subTest(path=path):
                self.assertEqual(self.request(
                    "POST", path, [(b"authorization", b"Bearer test-key")]
                ), 404)
        self.assertEqual(self.upstream_calls, 0)

    def test_duplicate_auth_headers_are_rejected(self):
        self.assertEqual(self.request("GET", "/health", [
            (b"authorization", b"Bearer test-key"),
            (b"authorization", b"Bearer test-key"),
        ]), 401)
        self.assertEqual(self.upstream_calls, 0)

    def test_missing_key_fails_closed(self):
        with patch.dict(os.environ, {"VLLM_API_KEY": ""}):
            with self.assertRaises(RuntimeError):
                AuthMiddleware(None)


class EntrypointTests(unittest.TestCase):
    def test_missing_or_multiline_key_file_prevents_start(self):
        script = Path(__file__).resolve().parents[1] / "gputw" / "entrypoint-auth.sh"
        with tempfile.TemporaryDirectory() as directory:
            key_file = Path(directory) / "api_key"
            env = dict(os.environ, API_KEY_FILE=str(key_file))
            invocation = ["bash", str(script), "--served-model-name", "test"]
            missing = subprocess.run(invocation, env=env, capture_output=True)
            self.assertEqual(missing.returncode, 1)
            key_file.write_text("first-line\nsecond-line\n")
            multiline = subprocess.run(invocation, env=env, capture_output=True)
            self.assertEqual(multiline.returncode, 1)
            self.assertNotIn(b"first-line", multiline.stderr)


class LiveVerifierInputTests(unittest.TestCase):
    def test_origin_must_be_exact_https_host_without_path(self):
        self.assertEqual(checked_origin("https://abc.gputw.ai/", "abc.gputw.ai"),
                         "https://abc.gputw.ai")
        for origin in ("http://abc.gputw.ai", "https://evil.example",
                       "https://abc.gputw.ai/v1", "https://user@abc.gputw.ai"):
            with self.subTest(origin=origin):
                with self.assertRaises(ValueError):
                    checked_origin(origin, "abc.gputw.ai")

    def test_key_file_must_have_one_line(self):
        with tempfile.TemporaryDirectory() as directory:
            key_file = Path(directory) / "api_key"
            key_file.write_text("test-key\n")
            self.assertEqual(load_key(str(key_file)), "test-key")
            key_file.write_text("test-key\nsecond-key\n")
            with self.assertRaises(ValueError):
                load_key(str(key_file))


if __name__ == "__main__":
    unittest.main()
