#!/usr/bin/env python3

import argparse
import http.server
import pathlib
import sys


class StaticHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".html": "text/html; charset=utf-8",
        ".js": "text/javascript; charset=utf-8",
        ".mjs": "text/javascript; charset=utf-8",
        ".wasm": "application/wasm",
    }

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def list_directory(self, path: str):  # type: ignore[override]
        self.send_error(404, "Directory listings are disabled")
        return None


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve one emitted LOGOS bundle on loopback.")
    parser.add_argument("--directory", required=True)
    parser.add_argument("--port-file", required=True)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    directory_input = pathlib.Path(arguments.directory)
    if directory_input.is_symlink():
        raise SystemExit("bundle directory must be a real directory")
    directory = directory_input.resolve(strict=True)
    port_file = pathlib.Path(arguments.port_file).resolve(strict=False)
    if not directory.is_dir():
        raise SystemExit("bundle directory must be a real directory")
    if port_file.exists() or port_file.is_symlink():
        raise SystemExit("port file must not already exist")
    if not port_file.parent.is_dir() or port_file.parent.is_symlink():
        raise SystemExit("port-file parent must be a real existing directory")

    handler = lambda *args, **kwargs: StaticHandler(  # noqa: E731
        *args, directory=str(directory), **kwargs
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    server.daemon_threads = True
    port_file.write_text(f"{server.server_port}\n", encoding="ascii")
    port_file.chmod(0o600)
    print(f"serving {directory.name} on 127.0.0.1:{server.server_port}", file=sys.stderr, flush=True)
    try:
        server.serve_forever(poll_interval=0.1)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
