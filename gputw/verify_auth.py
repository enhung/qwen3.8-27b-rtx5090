#!/usr/bin/env python3
"""Check a GPUtw P1 endpoint without printing credentials or response bodies."""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def checked_origin(value, expected_host):
    parsed = urllib.parse.urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.path not in ("", "/")
            or parsed.query or parsed.fragment):
        raise ValueError("expected an HTTPS origin without path or credentials")
    host = parsed.hostname.lower()
    allowed = expected_host.lower()
    if host != allowed:
        raise ValueError("endpoint hostname does not match --expected-host")
    return value.rstrip("/")


def load_key(filename):
    if filename:
        lines = Path(filename).read_text().splitlines()
        key = lines[0] if len(lines) == 1 else ""
    else:
        key = os.environ.get("VLLM_API_KEY", "")
    if not key or any(char.isspace() for char in key):
        raise ValueError("set VLLM_API_KEY or provide a one-line --key-file")
    return key


def request_status(origin, method, path, key=None, body=None):
    # GPUtw's Cloudflare edge rejects urllib's default Python-urllib user agent
    # with a platform-level 403 before the request reaches the container.
    headers = {"User-Agent": "qwen38-gputw-verify/1.0"}
    if key is not None:
        headers["Authorization"] = "Bearer " + key
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        origin + path, data=body, headers=headers, method=method
    )
    start = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, round(time.monotonic() - start, 3)
    except urllib.error.HTTPError as error:
        return error.code, round(time.monotonic() - start, 3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--origin", required=True, help="GPUtw HTTPS origin, without /v1")
    parser.add_argument("--expected-host", required=True,
                        help="Exact trusted GPUtw endpoint hostname")
    parser.add_argument("--key-file", help="Read one token from a local file")
    args = parser.parse_args()
    try:
        origin = checked_origin(args.origin, args.expected_host)
        key = load_key(args.key_file)
        wrong_key = key + "-wrong"
        cases = [
            ("GET", "/health", None, None, 401),
            ("GET", "/health", wrong_key, None, 401),
            ("GET", "/health", key, None, 200),
            ("GET", "/v1/models", None, None, 401),
            ("GET", "/v1/models", key, None, 200),
            ("POST", "/v1/chat/completions", None, b"{}", 401),
            ("POST", "/invocations", None, b"{}", 404),
            ("POST", "/invocations", key, b"{}", 404),
            ("GET", "/metrics", key, None, 404),
            ("GET", "/docs", key, None, 404),
        ]
        rows = []
        for method, path, credential, body, expected in cases:
            status, seconds = request_status(origin, method, path, credential, body)
            rows.append({"method": method, "path": path,
                         "credential": "valid" if credential == key else
                         ("none" if credential is None else "wrong"),
                         "status": status, "expected": expected,
                         "seconds": seconds, "pass": status == expected})
        print(json.dumps({"origin_host": urllib.parse.urlsplit(origin).hostname,
                          "cases": rows, "pass": all(row["pass"] for row in rows)},
                         indent=2))
        return 0 if all(row["pass"] for row in rows) else 1
    except (ValueError, OSError, urllib.error.URLError) as error:
        print("verification could not complete: " + type(error).__name__, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
