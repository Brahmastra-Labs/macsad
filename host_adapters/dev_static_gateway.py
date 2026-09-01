#!/usr/bin/env python3
"""Serve an exact LOGOS bundle and proxy one read-only LOGOS health route.

This local-only adapter contains no MaCSad domain policy. Production assets are
served by Cloudflare Static Assets, not this process.
"""

from __future__ import annotations

import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


STATIC_PATHS = {
    "/": "macsad_admin.html",
    "/index.html": "macsad_admin.html",
    "/macsad_admin.html": "macsad_admin.html",
    "/macsad_admin.js": "macsad_admin.js",
    "/macsad_admin.mjs": "macsad_admin.mjs",
    "/macsad_admin.wasm": "macsad_admin.wasm",
}
HEALTH_PATH = "/api/v1/health"


def classify_request(method: str, path: str) -> str:
    """Classify only the reviewed development surface."""
    if method == "GET" and path == HEALTH_PATH:
        return "health"
    if method == "GET" and path in STATIC_PATHS:
        return "static"
    return "reject"


def make_handler(root: Path, logos_health_url: str):
    root = root.resolve(strict=True)

    class Handler(SimpleHTTPRequestHandler):
        server_version = "MaCSadDevelopmentGateway/1"

        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(root), **kwargs)

        def do_GET(self):  # noqa: N802 - required by BaseHTTPRequestHandler
            action = classify_request("GET", self.path)
            if action == "health":
                self._proxy_health()
                return
            if action == "static":
                self.path = f"/{STATIC_PATHS[self.path]}"
                super().do_GET()
                return
            self.send_error(404, "Not found")

        def _reject_mutation(self):
            self.send_error(405, "Mutation methods are unavailable")

        do_POST = _reject_mutation
        do_PUT = _reject_mutation
        do_PATCH = _reject_mutation
        do_DELETE = _reject_mutation

        def _proxy_health(self):
            try:
                request = Request(logos_health_url, method="GET")
                with urlopen(request, timeout=2.0) as response:
                    body = response.read(4097)
                    if len(body) > 4096:
                        raise ValueError("health response exceeds 4096 bytes")
                    status = response.status
                    content_type = response.headers.get_content_type()
            except (HTTPError, URLError, TimeoutError, ValueError):
                body = b"MaCSad LOGOS health endpoint unavailable"
                status = 502
                content_type = "text/plain"
            self.send_response(status)
            self.send_header("Content-Type", f"{content_type}; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            return

    return Handler


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument(
        "--logos-health-url",
        default="http://127.0.0.1:18081/api/v1/health",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    if not 1 <= args.port <= 65535:
        raise SystemExit("port must be between 1 and 65535")
    root = args.root.resolve(strict=True)
    missing = sorted(set(STATIC_PATHS.values()) - {path.name for path in root.iterdir()})
    if missing:
        raise SystemExit(f"bundle is incomplete: {', '.join(missing)}")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(root, args.logos_health_url))
    print(f"MaCSad development site: http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
