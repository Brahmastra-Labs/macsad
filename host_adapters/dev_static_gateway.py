#!/usr/bin/env python3
"""Serve an exact LOGOS bundle, health route, and optional demo snapshot.

This local-only adapter validates and serves a bounded read-only projection but
contains no MaCSad domain policy. Production assets are served by Cloudflare
Static Assets, not this process.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from uuid import UUID
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
DEMO_PATH = "/api/v1/demo/snapshot"
MAX_DEMO_BYTES = 1024 * 1024
DEMO_ROOT_FIELDS = {"schema", "fixture", "read_only", "workspace_id", "records"}
CASE_BOARD_FIELDS = {
    "workspace_id",
    "research_case_id",
    "title",
    "research_kind",
    "case_state",
    "control_state",
    "priority",
    "process_key",
    "live_task_id",
    "live_task_sequence",
    "live_node_key",
    "board_phase",
    "task_state",
    "accepted_assignment_id",
    "assigned_actor_id",
    "assigned_profile_key",
    "deadline_at",
}
KANBAN_PHASES = {"inbox", "ready", "running", "verify", "review", "closed"}
TASK_STATES = {"offered", "ready", "running", "waiting", "completed", "cancelled"}


@dataclass(frozen=True)
class DemoSnapshot:
    document: dict
    body: bytes
    etag: str


def _reject_json_constant(value: str):
    raise ValueError(f"unsupported JSON constant: {value}")


def _object_without_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _require_exact_fields(value: dict, expected: set[str], label: str):
    if not isinstance(value, dict) or set(value) != expected:
        raise ValueError(f"{label} has an unexpected field set")


def _require_uuid(value, label: str, nullable: bool = False):
    if value is None and nullable:
        return
    if not isinstance(value, str):
        raise ValueError(f"{label} must be a canonical UUID string")
    try:
        parsed = UUID(value)
    except ValueError as error:
        raise ValueError(f"{label} must be a canonical UUID string") from error
    if str(parsed) != value:
        raise ValueError(f"{label} must be a lowercase canonical UUID string")


def _require_nullable_text(value, label: str):
    if value is not None and (not isinstance(value, str) or not value):
        raise ValueError(f"{label} must be null or nonempty text")


def _require_enum(value, allowed: set[str], label: str):
    if not isinstance(value, str) or value not in allowed:
        raise ValueError(f"{label} is unsupported")


def _require_nullable_enum(value, allowed: set[str], label: str):
    if value is not None and (not isinstance(value, str) or value not in allowed):
        raise ValueError(f"{label} is unsupported")


def _require_nullable_integer_string(value, label: str):
    if value is not None and (
        not isinstance(value, str) or not re.fullmatch(r"-?(?:0|[1-9][0-9]*)", value)
    ):
        raise ValueError(f"{label} must be null or a canonical integer string")


def _require_deadline(value):
    _require_nullable_text(value, "case-board deadline_at")
    if value is None:
        return
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z", value):
        raise ValueError("case-board deadline_at must use UTC RFC3339 microseconds")
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%S.%fZ")
    except ValueError as error:
        raise ValueError("case-board deadline_at is not a real timestamp") from error


def _validate_case_board_row(row: dict, workspace_id: str):
    _require_exact_fields(row, CASE_BOARD_FIELDS, "case-board row")
    if row["workspace_id"] != workspace_id:
        raise ValueError("case-board row belongs to a different workspace")
    _require_uuid(row["workspace_id"], "case-board workspace_id")
    _require_uuid(row["research_case_id"], "case-board research_case_id")
    if not isinstance(row["title"], str) or not row["title"].strip():
        raise ValueError("case-board title must be nonempty text")
    _require_enum(
        row["research_kind"],
        {"mathematics", "computer_science"},
        "case-board research_kind",
    )
    _require_enum(row["case_state"], {"open", "closed"}, "case-board case_state")
    _require_enum(
        row["control_state"],
        {"normal", "paused", "blocked"},
        "case-board control_state",
    )
    if not isinstance(row["priority"], str) or not re.fullmatch(
        r"-?(?:0|[1-9][0-9]*)", row["priority"]
    ):
        raise ValueError("case-board priority must be a canonical integer string")
    if not isinstance(row["process_key"], str) or not re.fullmatch(
        r"[a-z][a-z0-9._-]*", row["process_key"]
    ):
        raise ValueError("case-board process_key is unsupported")

    _require_uuid(row["live_task_id"], "case-board live_task_id", nullable=True)
    _require_nullable_integer_string(
        row["live_task_sequence"], "case-board live_task_sequence"
    )
    _require_nullable_text(row["live_node_key"], "case-board live_node_key")
    if row["live_node_key"] is not None and not re.fullmatch(
        r"[a-z][a-z0-9._-]*", row["live_node_key"]
    ):
        raise ValueError("case-board live_node_key is unsupported")
    _require_nullable_enum(row["board_phase"], KANBAN_PHASES, "case-board board_phase")
    _require_nullable_enum(row["task_state"], TASK_STATES, "case-board task_state")
    _require_uuid(
        row["accepted_assignment_id"], "case-board accepted_assignment_id", nullable=True
    )
    _require_uuid(row["assigned_actor_id"], "case-board assigned_actor_id", nullable=True)
    _require_nullable_text(row["assigned_profile_key"], "case-board assigned_profile_key")
    if row["assigned_profile_key"] is not None and not re.fullmatch(
        r"[a-z][a-z0-9._-]*", row["assigned_profile_key"]
    ):
        raise ValueError("case-board assigned_profile_key is unsupported")
    _require_deadline(row["deadline_at"])


def load_demo_snapshot(path: Path) -> DemoSnapshot:
    if path.is_symlink():
        raise ValueError("demo snapshot must not be a symbolic link")
    path = path.resolve(strict=True)
    if not path.is_file():
        raise ValueError("demo snapshot must be one regular file")
    if path.stat().st_size <= 0 or path.stat().st_size > MAX_DEMO_BYTES:
        raise ValueError("demo snapshot size is outside the admitted bound")
    try:
        document = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_object_without_duplicates,
            parse_constant=_reject_json_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("demo snapshot is not valid UTF-8 JSON") from error

    _require_exact_fields(document, DEMO_ROOT_FIELDS, "demo snapshot")
    if document["schema"] != "macsad-demo-snapshot/1":
        raise ValueError("demo snapshot schema is unsupported")
    if not isinstance(document["fixture"], str) or not re.fullmatch(
        r"[a-z][a-z0-9-]*", document["fixture"]
    ):
        raise ValueError("demo snapshot fixture identity is unsupported")
    if document["read_only"] is not True:
        raise ValueError("demo snapshot must be explicitly read-only")
    _require_uuid(document["workspace_id"], "demo snapshot workspace_id")
    records = document["records"]
    if not isinstance(records, list) or not 1 <= len(records) <= 5000:
        raise ValueError("demo snapshot records must be one bounded nonempty list")

    seen_cases = set()
    for record in records:
        _require_exact_fields(
            record, {"record_type", "record_schema", "row"}, "demo snapshot record"
        )
        if record["record_type"] != "case_board" or record["record_schema"] != (
            "macsad.case-board-view/1"
        ):
            raise ValueError("demo snapshot contains an unsupported record contract")
        _validate_case_board_row(record["row"], document["workspace_id"])
        case_id = record["row"]["research_case_id"]
        if case_id in seen_cases:
            raise ValueError("demo snapshot repeats a research case")
        seen_cases.add(case_id)

    body = (
        json.dumps(
            document,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        + b"\n"
    )
    return DemoSnapshot(
        document=document,
        body=body,
        etag=f'"{hashlib.sha256(body).hexdigest()}"',
    )


def classify_request(method: str, path: str, demo_enabled: bool = False) -> str:
    """Classify only the reviewed development surface."""
    if method == "GET" and path == HEALTH_PATH:
        return "health"
    if method == "GET" and path == DEMO_PATH and demo_enabled:
        return "demo"
    if method == "GET" and path in STATIC_PATHS:
        return "static"
    return "reject"


def make_handler(
    root: Path, logos_health_url: str, demo_snapshot: DemoSnapshot | None = None
):
    root = root.resolve(strict=True)

    class Handler(SimpleHTTPRequestHandler):
        server_version = "MaCSadDevelopmentGateway/1"

        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(root), **kwargs)

        def do_GET(self):  # noqa: N802 - required by BaseHTTPRequestHandler
            action = classify_request("GET", self.path, demo_enabled=demo_snapshot is not None)
            if action == "health":
                self._proxy_health()
                return
            if action == "demo":
                self._serve_demo_snapshot()
                return
            if action == "static":
                self.path = f"/{STATIC_PATHS[self.path]}"
                super().do_GET()
                return
            self.send_error(404, "Not found")

        def _reject_unsupported_method(self):
            self.send_error(405, "Only allowlisted GET routes are available")

        do_HEAD = _reject_unsupported_method
        do_OPTIONS = _reject_unsupported_method
        do_POST = _reject_unsupported_method
        do_PUT = _reject_unsupported_method
        do_PATCH = _reject_unsupported_method
        do_DELETE = _reject_unsupported_method

        def _serve_demo_snapshot(self):
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(demo_snapshot.body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("ETag", demo_snapshot.etag)
            self.end_headers()
            self.wfile.write(demo_snapshot.body)

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
    parser.add_argument("--demo-snapshot", type=Path)
    return parser.parse_args()


def main():
    args = parse_args()
    if not 1 <= args.port <= 65535:
        raise SystemExit("port must be between 1 and 65535")
    root = args.root.resolve(strict=True)
    missing = sorted(set(STATIC_PATHS.values()) - {path.name for path in root.iterdir()})
    if missing:
        raise SystemExit(f"bundle is incomplete: {', '.join(missing)}")
    try:
        demo_snapshot = (
            load_demo_snapshot(args.demo_snapshot) if args.demo_snapshot is not None else None
        )
    except (OSError, ValueError) as error:
        raise SystemExit(f"invalid demo snapshot: {error}") from error
    server = ThreadingHTTPServer(
        ("127.0.0.1", args.port),
        make_handler(root, args.logos_health_url, demo_snapshot),
    )
    print(f"MaCSad development site: http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
