import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread
from unittest import TestCase
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from host_adapters.dev_static_gateway import (
    DEMO_PATH,
    STATIC_PATHS,
    classify_request,
    load_demo_snapshot,
    make_handler,
)


WORKSPACE_ID = "10000000-0000-4000-8000-000000000001"
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
STORYBOARD_PATH = REPOSITORY_ROOT / "demo" / "fixtures" / "board_storyboard_v1.json"


def demo_document():
    return {
        "schema": "macsad-demo-snapshot/1",
        "fixture": "board-storyboard-v1",
        "read_only": True,
        "workspace_id": WORKSPACE_ID,
        "records": [
            {
                "record_type": "case_board",
                "record_schema": "macsad.case-board-view/1",
                "row": {
                    "workspace_id": WORKSPACE_ID,
                    "research_case_id": "14000000-0000-4000-8000-000000000001",
                    "title": "Characterize sparse verifier search",
                    "research_kind": "computer_science",
                    "case_state": "open",
                    "control_state": "normal",
                    "priority": "80",
                    "process_key": "discovery-v1",
                    "live_task_id": "18000000-0000-4000-8000-000000000001",
                    "live_task_sequence": "1",
                    "live_node_key": "investigate",
                    "board_phase": "inbox",
                    "task_state": "offered",
                    "accepted_assignment_id": None,
                    "assigned_actor_id": None,
                    "assigned_profile_key": None,
                    "deadline_at": None,
                },
            }
        ],
    }


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
    def test_checked_in_storyboard_exercises_every_board_column(self):
        snapshot = load_demo_snapshot(STORYBOARD_PATH)
        rows = [record["row"] for record in snapshot.document["records"]]
        self.assertEqual(len(rows), 6)
        self.assertEqual(
            {row["board_phase"] for row in rows if row["board_phase"] is not None},
            {"inbox", "ready", "running", "verify", "review"},
        )
        closed_rows = [row for row in rows if row["case_state"] == "closed"]
        self.assertEqual(len(closed_rows), 1)
        self.assertIsNone(closed_rows[0]["board_phase"])
        self.assertIsNone(closed_rows[0]["live_task_id"])

    def test_route_allowlist_is_fail_closed(self):
        self.assertEqual(classify_request("GET", "/api/v1/health"), "health")
        for path in STATIC_PATHS:
            self.assertEqual(classify_request("GET", path), "static")
        self.assertEqual(classify_request("GET", DEMO_PATH), "reject")
        self.assertEqual(classify_request("GET", DEMO_PATH, demo_enabled=True), "demo")
        for method in ("HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"):
            self.assertEqual(classify_request(method, "/api/v1/health"), "reject")
            self.assertEqual(classify_request(method, "/macsad_admin.wasm"), "reject")
            self.assertEqual(classify_request(method, DEMO_PATH, demo_enabled=True), "reject")
        self.assertEqual(classify_request("GET", "/../private"), "reject")
        self.assertEqual(classify_request("GET", "/unknown"), "reject")

    def test_demo_snapshot_validation_is_fail_closed(self):
        with TemporaryDirectory() as directory:
            snapshot_path = Path(directory) / "snapshot.json"
            snapshot_path.write_text(
                json.dumps(demo_document(), ensure_ascii=False), encoding="utf-8"
            )
            snapshot = load_demo_snapshot(snapshot_path)
            self.assertEqual(snapshot.document["schema"], "macsad-demo-snapshot/1")
            self.assertEqual(snapshot.document["workspace_id"], WORKSPACE_ID)
            self.assertEqual(snapshot.body, load_demo_snapshot(snapshot_path).body)
            self.assertRegex(snapshot.etag, r'^"[0-9a-f]{64}"$')

            invalid_documents = []
            wrong_schema = demo_document()
            wrong_schema["schema"] = "macsad-demo-snapshot/2"
            invalid_documents.append(wrong_schema)
            writable = demo_document()
            writable["read_only"] = False
            invalid_documents.append(writable)
            mixed_workspace = demo_document()
            mixed_workspace["records"][0]["row"]["workspace_id"] = (
                "20000000-0000-4000-8000-000000000001"
            )
            invalid_documents.append(mixed_workspace)
            unknown_record = demo_document()
            unknown_record["records"][0]["record_type"] = "raw_table"
            invalid_documents.append(unknown_record)
            invalid_timestamp = demo_document()
            invalid_timestamp["records"][0]["row"]["deadline_at"] = "tomorrow"
            invalid_documents.append(invalid_timestamp)
            unexpected_field = demo_document()
            unexpected_field["records"][0]["row"]["derived_label"] = "Inbox"
            invalid_documents.append(unexpected_field)
            noncanonical_integer = demo_document()
            noncanonical_integer["records"][0]["row"]["priority"] = "080"
            invalid_documents.append(noncanonical_integer)
            noncanonical_uuid = demo_document()
            noncanonical_uuid["records"][0]["row"]["research_case_id"] = (
                "14000000-0000-4000-8000-00000000000A"
            )
            invalid_documents.append(noncanonical_uuid)
            malformed_required_enum = demo_document()
            malformed_required_enum["records"][0]["row"]["research_kind"] = []
            invalid_documents.append(malformed_required_enum)
            malformed_nullable_enum = demo_document()
            malformed_nullable_enum["records"][0]["row"]["board_phase"] = []
            invalid_documents.append(malformed_nullable_enum)
            duplicate_case = demo_document()
            duplicate_case["records"].append(duplicate_case["records"][0].copy())
            invalid_documents.append(duplicate_case)

            for index, document in enumerate(invalid_documents):
                invalid_path = Path(directory) / f"invalid-{index}.json"
                invalid_path.write_text(json.dumps(document), encoding="utf-8")
                with self.assertRaises(ValueError):
                    load_demo_snapshot(invalid_path)

            duplicate_key_path = Path(directory) / "duplicate-key.json"
            duplicate_key_path.write_text(
                '{"schema":"macsad-demo-snapshot/1","schema":"duplicate"}',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                load_demo_snapshot(duplicate_key_path)

            nonfinite_path = Path(directory) / "nonfinite.json"
            nonfinite_path.write_text('{"value":NaN}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "unsupported JSON constant"):
                load_demo_snapshot(nonfinite_path)

            invalid_utf8_path = Path(directory) / "invalid-utf8.json"
            invalid_utf8_path.write_bytes(b"{\xff}")
            with self.assertRaisesRegex(ValueError, "not valid UTF-8 JSON"):
                load_demo_snapshot(invalid_utf8_path)

    def test_demo_validation_is_structural_not_domain_policy(self):
        with TemporaryDirectory() as directory:
            snapshot_path = Path(directory) / "snapshot.json"

            open_without_task = demo_document()
            row = open_without_task["records"][0]["row"]
            for field in (
                "live_task_id",
                "live_task_sequence",
                "live_node_key",
                "board_phase",
                "task_state",
            ):
                row[field] = None
            row["accepted_assignment_id"] = (
                "19000000-0000-4000-8000-000000000001"
            )
            snapshot_path.write_text(json.dumps(open_without_task), encoding="utf-8")
            load_demo_snapshot(snapshot_path)

            closed_with_terminal_task = demo_document()
            row = closed_with_terminal_task["records"][0]["row"]
            row["case_state"] = "closed"
            row["board_phase"] = "closed"
            row["task_state"] = "completed"
            snapshot_path.write_text(
                json.dumps(closed_with_terminal_task), encoding="utf-8"
            )
            load_demo_snapshot(snapshot_path)

    def test_static_health_and_mutation_runtime_contract(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            for filename in set(STATIC_PATHS.values()):
                (root / filename).write_bytes(f"fixture:{filename}".encode())
            snapshot_path = root / "demo.json"
            snapshot_path.write_text(
                json.dumps(demo_document(), ensure_ascii=False), encoding="utf-8"
            )
            snapshot = load_demo_snapshot(snapshot_path)

            health = ThreadingHTTPServer(("127.0.0.1", 0), FakeHealth)
            health_thread = Thread(target=health.serve_forever, daemon=True)
            health_thread.start()
            health_url = f"http://127.0.0.1:{health.server_port}/api/v1/health"

            gateway = ThreadingHTTPServer(
                ("127.0.0.1", 0), make_handler(root, health_url, snapshot)
            )
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
                with urlopen(f"{base}{DEMO_PATH}") as response:
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.headers.get_content_type(), "application/json")
                    self.assertEqual(response.headers["Cache-Control"], "no-store")
                    self.assertEqual(response.headers["ETag"], snapshot.etag)
                    self.assertEqual(response.read(), snapshot.body)
                with urlopen(f"{base}{DEMO_PATH}") as response:
                    self.assertEqual(response.read(), snapshot.body)
                with self.assertRaises(HTTPError) as rejected:
                    urlopen(Request(f"{base}/api/v1/health", method="POST", data=b"x"))
                self.assertEqual(rejected.exception.code, 405)
                with self.assertRaises(HTTPError) as rejected_demo:
                    urlopen(Request(f"{base}{DEMO_PATH}", method="POST", data=b"x"))
                self.assertEqual(rejected_demo.exception.code, 405)
                with self.assertRaises(HTTPError) as rejected_head:
                    urlopen(Request(f"{base}{DEMO_PATH}", method="HEAD"))
                self.assertEqual(rejected_head.exception.code, 405)
                with self.assertRaises(HTTPError) as disabled_demo:
                    disabled = ThreadingHTTPServer(
                        ("127.0.0.1", 0), make_handler(root, health_url)
                    )
                    try:
                        disabled_thread = Thread(
                            target=disabled.serve_forever, daemon=True
                        )
                        disabled_thread.start()
                        urlopen(
                            f"http://127.0.0.1:{disabled.server_port}{DEMO_PATH}"
                        )
                    finally:
                        disabled.shutdown()
                        disabled.server_close()
                self.assertEqual(disabled_demo.exception.code, 404)
                with self.assertRaises(HTTPError) as missing:
                    urlopen(f"{base}/../private")
                self.assertEqual(missing.exception.code, 404)
            finally:
                gateway.shutdown()
                gateway.server_close()
                health.shutdown()
                health.server_close()
