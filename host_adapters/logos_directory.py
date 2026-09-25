"""Explicit local LOGOS development connection; never release admission.

An existing executable is copied independently and hashed. Source observations
are separate: this adapter cannot prove which source produced that executable.
All machine-specific paths and observations stay in ignored .runtime state.
"""
import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

SCHEMA = "macsad-logos-directory/1"


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def regular(path, executable=False):
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        raise ValueError("required regular file is unavailable: " + str(path)) from error
    if not stat.S_ISREG(mode) or (executable and not os.access(path, os.X_OK)):
        raise ValueError("required regular executable/file is invalid: " + str(path))


def runtime(repo, create=False):
    root = repo.resolve()
    for name in (".runtime", "logos-directory"):
        root = root / name
        if create:
            try:
                root.mkdir(mode=0o700)
            except FileExistsError:
                pass
        if root.is_symlink() or not root.is_dir():
            raise ValueError("development runtime must be a real directory")
    return root


def source_observation(workspace):
    git_environment = {key: value for key, value in os.environ.items()
                       if not key.startswith("GIT_")}
    def git(*args):
        return subprocess.run(["git", "-C", str(workspace), *args],
                              check=True, capture_output=True, env=git_environment).stdout
    regular(workspace / "Cargo.lock")
    status = git("status", "--porcelain=v1", "-z", "--untracked-files=all")
    return {"commit": git("rev-parse", "HEAD").decode().strip(),
            "tree": git("rev-parse", "HEAD^{tree}").decode().strip(),
            "dirty": bool(status), "status_sha256": hashlib.sha256(status).hexdigest(),
            "cargo_lock_sha256": digest(workspace / "Cargo.lock")}


def source_binary(workspace, relative):
    relative = Path(relative)
    if relative.is_absolute() or ".." in relative.parts or relative == Path("."):
        raise ValueError("binary must be a relative path inside the workspace")
    path = workspace / relative
    regular(path, executable=True)
    if workspace not in path.resolve().parents:
        raise ValueError("binary escaped workspace")
    return path


def write_json(path, value):
    descriptor, name = tempfile.mkstemp(prefix=".record-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, sort_keys=True, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def connect(repo, workspace, relative):
    workspace = workspace.resolve(strict=True)
    binary = source_binary(workspace, relative)
    observed = source_observation(workspace)
    root = runtime(repo, create=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".binary-", dir=root)
    try:
        with os.fdopen(descriptor, "wb") as output, binary.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        copied = Path(temporary)
        sha = digest(copied)
        if sha != digest(binary):
            raise ValueError("binary changed while connecting; reconnect")
        copied.chmod(0o500)
        snapshot = root / ("largo-" + sha)
        if snapshot.exists() or snapshot.is_symlink():
            regular(snapshot, executable=True)
            if digest(snapshot) != sha:
                raise ValueError("existing development snapshot is corrupt")
            copied.unlink()
        else:
            os.replace(copied, snapshot)
        record = {"schema": SCHEMA, "mode": "development-directory",
                  "release_admitted": False, "source_binary_correspondence": "unverified",
                  "workspace": str(workspace), "binary_relative_path": str(relative),
                  "binary_sha256": sha, "snapshot_binary": str(snapshot),
                  "source_at_connection": observed}
        write_json(root / "connection.json", record)
        return record
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)



def candidate_module():
    if sys.version_info < (3, 11):
        raise ValueError("built candidate connection requires Python 3.11 or newer")
    if __package__:
        return importlib.import_module(".logos_built_candidate", __package__)
    return importlib.import_module("logos_built_candidate")


def connect_built_candidate(repo, candidate, binary_sha256, source_inventory_sha256):
    checks = candidate_module()
    verified = checks.verify(candidate, binary_sha256, source_inventory_sha256)
    root = runtime(repo, create=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".binary-", dir=root)
    try:
        with os.fdopen(descriptor, "wb") as output, Path(verified["binary"]).open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        copied = Path(temporary)
        if checks.digest(copied) != binary_sha256:
            raise ValueError("candidate binary changed while connecting")
        copied.chmod(0o500)
        snapshot = root / ("largo-" + binary_sha256)
        if snapshot.exists() or snapshot.is_symlink():
            checks.regular(snapshot, executable=True)
            if checks.digest(snapshot) != binary_sha256:
                raise ValueError("existing candidate snapshot is corrupt")
            copied.unlink()
        else:
            os.replace(copied, snapshot)
        record = {"schema": checks.SCHEMA, "mode": checks.MODE,
                  "release_admitted": False, "source_binary_correspondence": "local-build-evidence",
                  "candidate": verified["candidate"], "workspace": verified["workspace"],
                  "binary_sha256": binary_sha256, "source_inventory_sha256": source_inventory_sha256,
                  "snapshot_binary": str(snapshot), "evidence_sha256": verified["evidence_sha256"],
                  "source_at_connection": verified["source"]}
        write_json(root / "connection.json", record)
        return record
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def inspect_built_candidate(root, record):
    checks = candidate_module()
    expected = {"schema", "mode", "release_admitted", "source_binary_correspondence", "candidate", "workspace",
                "binary_sha256", "source_inventory_sha256", "snapshot_binary", "evidence_sha256", "source_at_connection"}
    if (set(record) != expected or record["schema"] != checks.SCHEMA or record["mode"] != checks.MODE
            or record["release_admitted"] is not False or record["source_binary_correspondence"] != "local-build-evidence"):
        raise ValueError("invalid built candidate connection schema")
    verified = checks.verify(Path(record["candidate"]), record["binary_sha256"], record["source_inventory_sha256"])
    if (verified["candidate"] != record["candidate"] or verified["workspace"] != record["workspace"]
            or verified["evidence_sha256"] != record["evidence_sha256"] or verified["source"] != record["source_at_connection"]):
        raise ValueError("candidate evidence changed; reconnect explicitly")
    snapshot = root / ("largo-" + record["binary_sha256"])
    if record["snapshot_binary"] != str(snapshot):
        raise ValueError("invalid candidate snapshot path")
    checks.regular(snapshot, executable=True)
    if checks.digest(snapshot) != record["binary_sha256"]:
        raise ValueError("candidate snapshot digest mismatch")
    return {**record, "source_now": verified["source"]}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate connection field")
        result[key] = value
    return result


def inspect_connection(repo):
    root = runtime(repo)
    config = root / "connection.json"
    regular(config)
    if config.stat().st_size > 16384:
        raise ValueError("oversized development connection")
    try:
        record = json.loads(config.read_text(), object_pairs_hook=unique_object)
        if isinstance(record, dict) and record.get("schema") == "macsad-logos-built-candidate/1":
            return inspect_built_candidate(root, record)
        keys = {"schema", "mode", "release_admitted", "source_binary_correspondence",
                "workspace", "binary_relative_path", "binary_sha256", "snapshot_binary",
                "source_at_connection"}
        if (not isinstance(record, dict) or set(record) != keys or record["schema"] != SCHEMA
                or record["mode"] != "development-directory" or record["release_admitted"] is not False
                or record["source_binary_correspondence"] != "unverified"):
            raise ValueError("invalid development connection schema")
        sha = record["binary_sha256"]
        if not isinstance(sha, str) or len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
            raise ValueError("invalid development binary digest")
        workspace = Path(record["workspace"]).resolve(strict=True)
        binary = source_binary(workspace, record["binary_relative_path"])
        if digest(binary) != sha:
            raise ValueError("workspace binary changed; reconnect explicitly")
        snapshot = root / ("largo-" + sha)
        if record["snapshot_binary"] != str(snapshot):
            raise ValueError("invalid development snapshot path")
        regular(snapshot, executable=True)
        if digest(snapshot) != sha:
            raise ValueError("development snapshot digest mismatch")
        return {**record, "source_now": source_observation(workspace)}
    except (OSError, TypeError, KeyError) as error:
        raise ValueError("invalid development connection") from error


def execution_environment(record, original):
    return {**original, "LOGOS_WORKSPACE": record["workspace"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    configure = commands.add_parser("connect")
    configure.add_argument("--workspace", type=Path, required=True)
    configure.add_argument("--binary", default="target/debug/largo")
    built = commands.add_parser("connect-built-candidate")
    built.add_argument("--candidate", type=Path, required=True)
    built.add_argument("--expected-binary-sha256", required=True)
    built.add_argument("--expected-source-inventory-sha256", required=True)
    commands.add_parser("inspect")
    run = commands.add_parser("run")
    run.add_argument("arguments", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    try:
        if arguments.command == "connect":
            record = connect(repo, arguments.workspace, arguments.binary)
        elif arguments.command == "connect-built-candidate":
            record = connect_built_candidate(repo, arguments.candidate, arguments.expected_binary_sha256,
                                             arguments.expected_source_inventory_sha256)
        else:
            record = inspect_connection(repo)
        if arguments.command in ("connect", "connect-built-candidate", "inspect"):
            print(json.dumps(record, sort_keys=True, indent=2))
            return
        environment = execution_environment(record, os.environ)
        write_json(runtime(repo) / "last-invocation.json", record)
        argv = arguments.arguments
        if argv[:1] == ["--"]:
            argv = argv[1:]
        if not argv:
            raise ValueError("a largo command is required")
        os.execve(record["snapshot_binary"], [record["snapshot_binary"], *argv], environment)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, "error: " + str(error) + "\n")


if __name__ == "__main__":
    main()
