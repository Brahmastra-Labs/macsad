"""One-shot evidence capture around admitted LOGOS; not a proof acceptance service.

Run from the MaCSad root: python3 -m host_adapters.proof_demo --help.
Python validates transport and preserves bytes; LOGOS classifies proof reports.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
import tomllib
import uuid
from datetime import datetime, timezone
from pathlib import Path

from host_adapters.proof_process import (
    ProcessObservation, proof_policy_arguments, read_source, run_bounded,
)
from host_adapters.local_cas import LocalCAS
from host_adapters.worker_artifacts import capture_published_evidence


REPOSITORY = Path(__file__).resolve().parents[1]
PROJECT_FILES = (
    "Largo.toml", "src/main.lg", "src/proof_worker.lg",
    "src/proof_result_policy.lg", "src/proof_wire_encoding.lg",
)


class EvidencePublicationError(RuntimeError):
    """Published bytes are visible, but final directory durability is uncertain."""


class EvidenceCaptureError(RuntimeError):
    """Local evidence exists; CAS capture did not return a durable index."""


def prepare_submission(source, expected):
    content = read_source(Path(source))
    proof_policy_arguments(ProcessObservation(1, b"{}", b"", "exited"), expected)
    if len(set(expected)) != len(expected):
        raise ValueError("target names must be unique")
    return content, list(expected)


def write_new(path, content):
    """Create, flush and sync a private artifact; never replace an old file."""
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "wb") as output:
        output.write(content)
        output.flush()
        os.fsync(output.fileno())


def _json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def _sync_directory(directory):
    descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(65536):
            digest.update(block)
    return digest.hexdigest()


def publish_evidence(pending, run_name, metadata):
    """Reserve a unique run directory, then publish a complete bundle inside it.

    A reserved directory without bundle/manifest.json is NOT a completed run.
    Files are private local evidence, not a tamper-proof append-only database.
    """
    if not re.fullmatch(r"run-[a-zA-Z0-9-]{1,80}", run_name):
        raise ValueError("run name must be a single bounded run identifier")
    if pending.is_symlink() or not pending.is_dir():
        raise ValueError("pending evidence must be an owned directory")
    files = {}
    directories = []
    for path in sorted(pending.rglob("*")):
        if path.is_symlink():
            raise ValueError("evidence must not contain symbolic links")
        if path.is_dir():
            directories.append(path)
        elif path.is_file():
            files[path.relative_to(pending).as_posix()] = {
                "sha256": _digest_file(path), "bytes": path.stat().st_size,
            }
        else:
            raise ValueError("evidence must contain only regular files and directories")
    manifest = dict(metadata, files=files)
    write_new(pending / "manifest.json", _json_bytes(manifest))
    for directory in reversed(directories):
        _sync_directory(directory)
    _sync_directory(pending)
    reservation = pending.parent / run_name
    reservation.mkdir(mode=0o700)  # Exclusive reservation, including empty existing directories.
    destination = reservation / "bundle"
    pending.rename(destination)
    try:
        _sync_directory(reservation)
        _sync_directory(reservation.parent)
    except OSError as error:
        raise EvidencePublicationError("evidence visible at " + str(destination) + "; final directory durability unconfirmed") from error
    return destination


def _save_observation(directory, name, observation):
    write_new(directory / (name + ".stdout"), observation.stdout)
    write_new(directory / (name + ".stderr"), observation.stderr)
    value = {"exit_code": observation.exit_code, "termination": observation.termination}
    write_new(directory / (name + ".process.json"), _json_bytes(value))
    return value


def _admitted_inputs(workspace):
    environment = {"PATH": os.defpath, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "LOGOS_WORKSPACE": str(workspace)}
    wrapper = ["/bin/bash", str(REPOSITORY / "scripts/logos.sh")]
    lock_bytes = read_source(REPOSITORY / ".macsad/toolchains/logos.lock.toml")
    lock = tomllib.loads(lock_bytes.decode("utf-8"))
    wrapper_bytes = read_source(REPOSITORY / "scripts/logos.sh")
    preflight = run_bounded(wrapper + ["--version"], cwd=REPOSITORY, environment=environment)
    expected_version = ("largo " + lock["source"]["version"] + "\n").encode()
    if preflight.termination != "exited" or preflight.exit_code != 0 or preflight.stdout != expected_version:
        raise ValueError("admitted LOGOS preflight failed; no problem was submitted")
    if read_source(REPOSITORY / "scripts/logos.sh") != wrapper_bytes or read_source(REPOSITORY / ".macsad/toolchains/logos.lock.toml") != lock_bytes:
        raise ValueError("admission inputs changed during preflight")
    project = {name: read_source(REPOSITORY / "logos/proof-worker" / name) for name in PROJECT_FILES}
    return environment, wrapper, lock, lock_bytes, wrapper_bytes, project


def run_demo(source, expected, output_directory, workspace, *, cas_directory=None,
             cas_max_object_bytes=8 * 1024 * 1024, cas_max_total_bytes=64 * 1024 * 1024):
    content, expected = prepare_submission(source, expected)
    output_directory = Path(output_directory)
    if output_directory.is_symlink() or not output_directory.is_dir():
        raise ValueError("output directory must already exist and must not be a symlink")
    output_directory = output_directory.resolve(strict=True)
    workspace = Path(workspace).resolve(strict=True)
    environment, wrapper, lock, lock_bytes, wrapper_bytes, project = _admitted_inputs(workspace)
    adapter_names = ["proof_demo.py", "proof_process.py"]
    if cas_directory is not None:
        adapter_names += ["local_cas.py", "worker_artifacts.py"]
    adapter_sources = {name: read_source(REPOSITORY / "host_adapters" / name) for name in adapter_names}

    def invoke(arguments, directory):
        def verify_identity():
            if read_source(REPOSITORY / "scripts/logos.sh") != wrapper_bytes or read_source(REPOSITORY / ".macsad/toolchains/logos.lock.toml") != lock_bytes:
                raise RuntimeError("admission inputs changed during the proof run")
        verify_identity()
        observation = run_bounded(wrapper + arguments, cwd=directory, environment=environment)
        verify_identity()
        return observation
    pending = Path(tempfile.mkdtemp(prefix=".partial-proof-", dir=output_directory))
    run_name = "run-" + str(uuid.uuid4())
    try:
        write_new(pending / "input.lg", content)
        write_new(pending / "logos.lock.toml", lock_bytes)
        adapter_directory = pending / "mechanical-adapter"
        adapter_directory.mkdir(mode=0o700)
        write_new(adapter_directory / "logos.sh", wrapper_bytes)
        for name, payload in adapter_sources.items():
            write_new(adapter_directory / name, payload)
        worker = pending / "policy"
        (worker / "src").mkdir(parents=True, mode=0o700)
        for name, payload in project.items():
            write_new(worker / name, payload)
        request = {"schema": "macsad-proof-request/1", "targets": expected, "source_sha256": hashlib.sha256(content).hexdigest()}
        write_new(pending / "request.json", _json_bytes(request))
        observations = []
        prove_reports = []
        for attempt in ("first", "rerun"):
            # Each source run gets a fresh directory but the same relative filename.
            directory = pending / attempt
            directory.mkdir(mode=0o700)
            write_new(directory / "input.lg", content)
            proof = invoke(["prove", "input.lg", "--json", "--color", "never"], directory)
            proof_process = _save_observation(directory, "prove", proof)
            arguments = proof_policy_arguments(proof, expected)
            policy = invoke(
                ["run", "--interpret", "--seed", "7", "--max-steps", "1000000", "--timeout", "5s", "--"] + arguments,
                worker,
            )
            policy_process = _save_observation(directory, "policy", policy)
            status = None
            if policy.termination == "exited" and policy.exit_code == 0 and policy.stdout in (b"checked\n", b"not-proved\n", b"rejected\n"):
                status = policy.stdout.decode("ascii").strip()
            observations.append({"attempt": attempt, "logos_status": status, "prove_process": proof_process, "policy_process": policy_process})
            prove_reports.append(proof.stdout)
        trace = invoke(["prove", "input.lg", "--trace", "--color", "never"], pending / "first")
        trace_process = _save_observation(pending / "first", "trace", trace)
        if read_source(REPOSITORY / ".macsad/toolchains/logos.lock.toml") != lock_bytes:
            raise RuntimeError("toolchain lock changed during the proof run")
        summary = {
            "schema": "macsad-proof-demo/1", "created_utc": datetime.now(timezone.utc).isoformat(),
            "request": request, "toolchain_commit": lock["source"]["commit"],
            "toolchain_binary_sha256": lock["runtime"]["observed_binary_sha256"],
            "observations": observations, "raw_reports_identical": prove_reports[0] == prove_reports[1],
            "trace_process": trace_process,
            "scope": "LOGOS reports under supplied assumptions; no case acceptance or publication",
            "replay": "same-tool source rerun, not preserved-certificate replay or independent checking",
            "assumptions": "Inspect input.lg. The reported axiom count excludes English Given premises.",
            "automation": "No model invoked; input must already be a self-contained LOGOS development.",
            "coverage": "Baseline prove handles its supported theorem blocks; no whole-program or import-closure proof claim.",
        }
        write_new(pending / "result.json", _json_bytes(summary))
        destination = publish_evidence(pending, run_name, {"schema": "macsad-proof-evidence/1", "request": request})
        if cas_directory is not None:
            try:
                with LocalCAS(cas_directory, max_bytes=cas_max_object_bytes) as store:
                    index = capture_published_evidence(destination, store, max_total_bytes=cas_max_total_bytes)
                return dict(summary, evidence_directory=str(destination),
                            cas_file_set={"sha256": index.sha256, "bytes": index.bytes})
            except (OSError, ValueError, RuntimeError) as error:
                raise EvidenceCaptureError("CAS capture incomplete; published evidence retained at " + str(destination)) from error
        return dict(summary, evidence_directory=str(destination))
    except (EvidencePublicationError, EvidenceCaptureError):
        raise
    except Exception as error:
        # Retain partial evidence for diagnosis; never present it as a completed run.
        raise RuntimeError("proof run incomplete; partial evidence retained at " + str(pending)) from error


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="self-contained UTF-8 LOGOS file (maximum 32768 bytes)")
    parser.add_argument("--target", action="append", required=True, help="exact theorem name, repeated in declaration order")
    parser.add_argument("--output-directory", type=Path, required=True, help="existing private directory for new evidence bundles")
    parser.add_argument("--cas-directory", type=Path, help="optional existing private CAS; persistence only, not proof acceptance")
    parser.add_argument("--cas-max-object-bytes", type=int, default=8 * 1024 * 1024)
    parser.add_argument("--cas-max-total-bytes", type=int, default=64 * 1024 * 1024)
    parser.add_argument("--logos-workspace", type=Path, default=os.environ.get("LOGOS_WORKSPACE"), help="checkout matching the repository's admitted toolchain lock")
    options = parser.parse_args(argv)
    if options.logos_workspace is None:
        parser.error("--logos-workspace or LOGOS_WORKSPACE is required")
    try:
        result = run_demo(options.source, options.target, options.output_directory, options.logos_workspace,
                          cas_directory=options.cas_directory, cas_max_object_bytes=options.cas_max_object_bytes,
                          cas_max_total_bytes=options.cas_max_total_bytes)
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(2, "error: " + str(error) + "\n")
    print(_json_bytes(result).decode("utf-8"), end="")
    # Exit zero means evidence captured; read LOGOS statuses, not this process exit.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
