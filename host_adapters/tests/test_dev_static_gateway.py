from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread
from unittest import TestCase
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from host_adapters.dev_static_gateway import STATIC_PATHS, classify_request, make_handler


class FakeHealth(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        body = b"LOGOS health fixture"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


class DevelopmentGatewayTests(TestCase):
    def test_route_allowlist_is_fail_closed(self):
        self.assertEqual(classify_request("GET", "/api/v1/health"), "health")
        for path in STATIC_PATHS:
            self.assertEqual(classify_request("GET", path), "static")
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            self.assertEqual(classify_request(method, "/api/v1/health"), "reject")
            self.assertEqual(classify_request(method, "/macsad_admin.wasm"), "reject")
        self.assertEqual(classify_request("GET", "/../private"), "reject")
        self.assertEqual(classify_request("GET", "/unknown"), "reject")

    def test_static_health_and_mutation_runtime_contract(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            for filename in set(STATIC_PATHS.values()):
                (root / filename).write_bytes(f"fixture:{filename}".encode())

            health = ThreadingHTTPServer(("127.0.0.1", 0), FakeHealth)
            health_thread = Thread(target=health.serve_forever, daemon=True)
            health_thread.start()
            health_url = f"http://127.0.0.1:{health.server_port}/api/v1/health"

            gateway = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(root, health_url))
            gateway_thread = Thread(target=gateway.serve_forever, daemon=True)
            gateway_thread.start()
            base = f"http://127.0.0.1:{gateway.server_port}"
            try:
                with urlopen(f"{base}/") as response:
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.read(), b"fixture:macsad_admin.html")
                with urlopen(f"{base}/api/v1/health") as response:
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.read(), b"LOGOS health fixture")
                with self.assertRaises(HTTPError) as rejected:
                    urlopen(Request(f"{base}/api/v1/health", method="POST", data=b"x"))
                self.assertEqual(rejected.exception.code, 405)
                with self.assertRaises(HTTPError) as missing:
                    urlopen(f"{base}/../private")
                self.assertEqual(missing.exception.code, 404)
            finally:
                gateway.shutdown()
                gateway.server_close()
                health.shutdown()
                health.server_close()
