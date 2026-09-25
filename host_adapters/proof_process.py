"""Bounded mechanical process/JSON ports; no mathematical acceptance policy."""

from __future__ import annotations

import json
import math
import os
import selectors
import signal
import stat
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


MAX_BYTES = 32768


@dataclass(frozen=True)
class ProcessObservation:
    exit_code: int | None
    stdout: bytes
    stderr: bytes
    termination: str


def read_source(path: Path) -> bytes:
    """Read one regular source snapshot without following its final symlink."""
    if path.is_symlink():
        raise ValueError("source must not be a symbolic link")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode) or not 1 <= before.st_size <= MAX_BYTES:
            raise ValueError("source must be a bounded nonempty regular file")
        content = source.read(MAX_BYTES + 1)
        after = os.fstat(source.fileno())
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ValueError("source changed while being read")
    if not 1 <= len(content) <= MAX_BYTES or b"\0" in content:
        raise ValueError("source length or null byte is unsupported")
    try:
        content.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise ValueError("source must be valid UTF-8") from error
    return content


def _resource_limits(timeout_seconds):
    import resource

    limits = (
        (resource.RLIMIT_CPU, math.ceil(timeout_seconds) + 1),
        (resource.RLIMIT_AS, 2 * 1024 * 1024 * 1024),
        (resource.RLIMIT_NOFILE, 128),
        (resource.RLIMIT_NPROC, 256),
        (resource.RLIMIT_CORE, 0),
    )
    for kind, desired in limits:
        _, inherited_hard = resource.getrlimit(kind)
        value = desired if inherited_hard == resource.RLIM_INFINITY else min(desired, inherited_hard)
        resource.setrlimit(kind, (value, value))


def terminate_owned_process(process):
    """Never signal special IDs, the caller, or an unverified process group."""
    pid = process.pid
    if type(pid) is not int or pid <= 1 or pid in (os.getpid(), os.getpgrp()):
        raise RuntimeError("unsafe process identity refused during cleanup")
    try:
        # A session leader is not necessarily our child. Never signal a PID
        # obtained from a forged/stale process object or a reaped child.
        os.waitid(os.P_PID, pid, os.WEXITED | os.WNOWAIT | os.WNOHANG)
    except ChildProcessError as error:
        raise RuntimeError("unowned child identity refused during cleanup") from error
    try:
        if os.getpgid(pid) != pid or os.getsid(pid) != pid:
            raise RuntimeError("unowned process group refused during cleanup")
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        # No signal is sent when ownership cannot be re-established.
        pass
    try:
        process.wait(timeout=2.0)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("owned process cleanup could not be confirmed") from error


def run_bounded(argv, *, cwd, environment, timeout_seconds=15.0, output_limit=MAX_BYTES):
    """Execute trusted fixed argv, capture both pipes, terminate the owned group.

    This single-threaded CLI port is not a security sandbox or a server queue.
    The caller supplies only admitted commands, never commands from problem text.
    """
    if type(output_limit) is not int or not 1 <= output_limit <= MAX_BYTES:
        raise ValueError("output limit must be an exact bounded integer")
    if type(timeout_seconds) not in (int, float) or not 0 < timeout_seconds <= 60 or not math.isfinite(timeout_seconds):
        raise ValueError("process limits are outside the supported contract")
    if os.name != "posix" or not hasattr(os, "waitid") or not hasattr(os, "WNOWAIT"):
        raise ValueError("bounded proof execution requires non-reaping POSIX wait support")
    if not argv or any(not isinstance(value, str) or "\0" in value for value in argv):
        raise ValueError("argv must contain literal null-free strings")
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    deadline = time.monotonic() + timeout_seconds
    termination = "exited"
    process = subprocess.Popen(
        argv, cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=False,
        start_new_session=True, close_fds=True,
        preexec_fn=lambda: _resource_limits(timeout_seconds),
    )
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ, "stdout")
            selector.register(process.stderr, selectors.EVENT_READ, "stderr")
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    termination = "timeout"
                    break
                for key, _ in selector.select(min(remaining, 0.1)):
                    used = sum(len(value) for value in buffers.values())
                    block = os.read(key.fileobj.fileno(), min(65536, output_limit - used + 1))
                    if not block:
                        selector.unregister(key.fileobj)
                        continue
                    available = output_limit - used
                    buffers[key.data].extend(block[:available])
                    if len(block) > available:
                        termination = "output-limit"
                        break
                if termination != "exited":
                    break
            if termination == "exited":
                # Keep the leader's PID reserved until its group is cleaned up.
                while os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOWAIT | os.WNOHANG) is None:
                    if time.monotonic() >= deadline:
                        termination = "timeout"
                        break
                    time.sleep(min(0.01, max(0, deadline - time.monotonic())))
    finally:
        try:
            terminate_owned_process(process)
        finally:
            process.stdout.close()
            process.stderr.close()
    return ProcessObservation(
        process.returncode if termination == "exited" else None,
        bytes(buffers["stdout"]), bytes(buffers["stderr"]), termination,
    )


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON field")
        result[key] = value
    return result


def _reject_constant(_):
    raise ValueError("nonfinite JSON number")


def _exact_fields(value, fields):
    if type(value) is not dict or set(value) != fields:
        raise ValueError("unexpected JSON field set")


def decode_prove_report(payload: bytes) -> dict:
    """Validate shape and primitive types only; preserve contradictory facts."""
    if not 1 <= len(payload) <= MAX_BYTES:
        raise ValueError("proof JSON exceeds its byte contract")
    try:
        report = json.loads(payload.decode("utf-8"), object_pairs_hook=_unique_object, parse_constant=_reject_constant)
    except (UnicodeError, RecursionError, ValueError) as error:
        raise ValueError("proof output is not strict bounded JSON") from error
    _exact_fields(report, {"file", "axioms", "theorems", "all_verified"})
    if report["file"] != "input.lg" or type(report["axioms"]) is not int or type(report["all_verified"]) is not bool:
        raise ValueError("proof header primitive types or source name mismatch")
    if not -(2**63) <= report["axioms"] <= 2**63 - 1:
        raise ValueError("axiom count cannot be represented by the LOGOS integer wire")
    if type(report["theorems"]) is not list or len(report["theorems"]) > 32:
        raise ValueError("theorem array violates transport bounds")
    for theorem in report["theorems"]:
        _exact_fields(theorem, {"name", "verified", "error"})
        if type(theorem["name"]) is not str or type(theorem["verified"]) is not bool:
            raise ValueError("theorem primitive types mismatch")
        if theorem["error"] is not None and type(theorem["error"]) is not str:
            raise ValueError("theorem error must be null or text")
        try:
            theorem["name"].encode("utf-8", errors="strict")
            if theorem["error"] is not None:
                theorem["error"].encode("utf-8", errors="strict")
        except UnicodeError as error:
            raise ValueError("theorem text contains an invalid Unicode scalar") from error
    return report


def proof_policy_arguments(observation, expected):
    """Lossless typed framing for the LOGOS policy, never generated LOGOS code."""
    if type(expected) not in (list, tuple) or not 1 <= len(expected) <= 32:
        raise ValueError("expected target names must be a bounded nonempty sequence")
    if any(type(name) is not str or not 1 <= len(name.encode("utf-8")) <= 256 or "\0" in name for name in expected):
        raise ValueError("expected target names violate transport bounds")
    expected_hex = ",".join(name.encode("utf-8").hex() for name in expected)
    valid = observation.termination == "exited"
    try:
        report = decode_prove_report(observation.stdout)
    except ValueError:
        valid = False
        report = {"axioms": 0, "all_verified": False, "theorems": []}
    theorems = report["theorems"]
    return [
        "macsad-proof-facts/1", "1" if valid else "0", str(len(observation.stdout)),
        str(observation.exit_code if observation.exit_code is not None else 127),
        str(report["axioms"]), "1" if report["all_verified"] else "0", expected_hex,
        ",".join(row["name"].encode("utf-8").hex() for row in theorems),
        ",".join("1" if row["verified"] else "0" for row in theorems),
        ",".join("1" if row["error"] is None else "0" for row in theorems),
    ]
