"""Mechanical current Lean wire decoder. No proof or publication decision here.

Callers capture only normally exited processes, retain the original bytes, and
supply identities obtained from the requested job and actual package manifest.
This module neither runs a process nor interprets a filesystem path as a URL.
"""
import json
import math
import re

MAX_BYTES = 1024 * 1024
STAGES = ("lean_accepted", "translated", "primary_check", "independent_recheck",
          "assumption_policy", "emission_reparsed", "fresh_replay")
STATUSES = {"passed", "failed", "not_run", "unsupported"}
OUTCOMES = ("verified", "invalid_source", "unsupported_feature",
            "disallowed_assumptions", "resource_limit", "infrastructure_failure")
WIRE_SCHEMA = "macsad-lean-facts/1"


def _fail(message):
    raise ValueError(message)


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            _fail("duplicate JSON field")
        result[key] = value
    return result


def _fields(value, names):
    if type(value) is not dict or set(value) != set(names):
        _fail("unexpected JSON fields")


def _text(value, limit=4096, nullable=False):
    if nullable and value is None:
        return
    if type(value) is not str:
        _fail("expected text")
    try:
        size = len(value.encode("utf-8", errors="strict"))
    except UnicodeError as error:
        raise ValueError("invalid Unicode scalar") from error
    if size > limit or "\0" in value:
        _fail("text outside transport bounds")


def _array(value, limit):
    if type(value) is not list or len(value) > limit:
        _fail("array outside transport bounds")


def _digest(value, nullable=False):
    if nullable and value is None:
        return
    if type(value) is not str or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        _fail("expected canonical SHA256")


def _load(payload):
    if type(payload) is not bytes or not 1 <= len(payload) <= MAX_BYTES:
        _fail("Lean JSON exceeds byte contract")
    try:
        source = payload.decode("utf-8", errors="strict")
        # Bound nesting before recursive json.loads, including unused audit data.
        depth = 0
        quoted = escaped = False
        for char in source:
            if quoted:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            elif char in "[{":
                depth += 1
                if depth > 64:
                    _fail("JSON nesting exceeds transport bound")
            elif char in "]}":
                depth -= 1
        result = json.loads(source, object_pairs_hook=_unique,
                            parse_constant=lambda _: _fail("nonfinite number"))
        pending = [result]
        while pending:
            value = pending.pop()
            if type(value) is str:
                _text(value, MAX_BYTES)
            elif type(value) is dict:
                pending.extend(value.keys())
                pending.extend(value.values())
            elif type(value) is list:
                pending.extend(value)
            elif type(value) is float and not math.isfinite(value):
                _fail("nonfinite JSON number")
        return result
    except (UnicodeError, RecursionError, ValueError) as error:
        raise ValueError("invalid bounded Lean JSON") from error


def decode_import_result(payload):
    """Check transport shape/types; contradictory claims reach LOGOS unchanged."""
    result = _load(payload)
    _fields(result, ("schema", "outcome", "stages", "target", "assumptions",
                     "information_losses", "diagnostics", "audit", "package"))
    if result["schema"] != "logos-lean-result/1":
        _fail("unknown Lean import schema")
    if result["outcome"] not in OUTCOMES:
        _fail("unknown outcome")
    _fields(result["stages"], STAGES)
    for value in result["stages"].values():
        if type(value) is not str or value not in STATUSES:
            _fail("unknown stage status")
    _fields(result["target"], ("lean", "logos"))
    _text(result["target"]["lean"], 256)
    _text(result["target"]["logos"], 256, nullable=True)
    _array(result["assumptions"], 64)
    for value in result["assumptions"]:
        _text(value, 256)
    _array(result["information_losses"], 2048)
    for loss in result["information_losses"]:
        _fields(loss, ("category", "detail"))
        _text(loss["category"])
        _text(loss["detail"], MAX_BYTES)
    _array(result["diagnostics"], 2048)
    for diagnostic in result["diagnostics"]:
        _fields(diagnostic, ("code", "stage", "declaration", "line", "message"))
        for key in ("code", "stage", "message"):
            _text(diagnostic[key], MAX_BYTES)
        _text(diagnostic["declaration"], nullable=True)
        line = diagnostic["line"]
        if line is not None and (type(line) is not int or not 0 <= line <= 2**63 - 1):
            _fail("invalid diagnostic line")
    audit = result["audit"]
    if audit is not None:
        if type(audit) is not dict or audit.get("schema") != "logos-lean-import-report/1":
            _fail("unknown importer audit schema")
        # Audit contents are retained evidence, not acceptance inputs.
    package = result["package"]
    if package is not None:
        _fields(package, ("path", "manifest_sha256"))
        _text(package["path"])
        _digest(package["manifest_sha256"])
    return result


def decode_replay_receipt(payload):
    result = _load(payload)
    _fields(result, ("schema", "replayed", "verified", "manifest_sha256", "stages", "trusted_base"))
    if result["schema"] != "logos-lean-replay/1":
        _fail("unknown Lean replay schema")
    if type(result["replayed"]) is not bool or type(result["verified"]) is not bool:
        _fail("replay flags must be Boolean")
    _digest(result["manifest_sha256"], nullable=True)
    _fields(result["stages"], STAGES)
    for stage in result["stages"].values():
        _fields(stage, ("status", "code", "detail"))
        if type(stage["status"]) is not str or stage["status"] not in STATUSES:
            _fail("unknown replay stage status")
        _text(stage["code"], nullable=True)
        _text(stage["detail"], MAX_BYTES)
    _array(result["trusted_base"], 64)
    for item in result["trusted_base"]:
        _text(item)
    return result


def _exit(value):
    if type(value) is not int or not 0 <= value <= 255:
        _fail("expected normal process exit code")
    return str(value)


def _arguments(fields):
    if len(fields) != 17:
        _fail("internal facts arity")
    encoded = []
    for field in fields:
        _text(field, 32768)
        encoded.append(field.encode("utf-8").hex() if field else "-")
    arguments = [WIRE_SCHEMA, *encoded]
    if sum(len(item) for item in arguments) > 131072:
        _fail("facts exceed wire budget")
    return arguments


def lean_import_policy_arguments(payload, *, exit_code, expected_lean, expected_logos,
                                 expected_package_path, observed_manifest_sha256,
                                 observed_package_schema):
    """Observed manifest identity must come from actual bytes, never result claims.

    For a non-publishing result, pass None for all observed package facts and the
    expected output directory as usual. The policy decides consistency.
    """
    result = decode_import_result(payload)
    _text(expected_lean, 256)
    _text(expected_logos, 256, nullable=True)
    _text(expected_package_path)
    _digest(observed_manifest_sha256, nullable=True)
    _text(observed_package_schema, nullable=True)
    package = result["package"]
    return _arguments([
        "import", _exit(exit_code), result["outcome"],
        ",".join(result["stages"][name] for name in STAGES),
        result["target"]["lean"], result["target"]["logos"] or "", expected_lean, expected_logos or "",
        package["path"] if package else "", expected_package_path,
        package["manifest_sha256"] if package else "", observed_manifest_sha256 or "",
        observed_package_schema or "",
        ",".join(name.encode("utf-8").hex() for name in result["assumptions"]),
        "1" if package is not None else "0", "0", "0",
    ])


def lean_replay_policy_arguments(payload, *, exit_code, expected_manifest_sha256):
    result = decode_replay_receipt(payload)
    _digest(expected_manifest_sha256)
    return _arguments([
        "replay", _exit(exit_code), "", ",".join(result["stages"][name]["status"] for name in STAGES),
        "", "", "", "", "", "", result["manifest_sha256"] or "", expected_manifest_sha256,
        "", "", "0", "1" if result["replayed"] else "0", "1" if result["verified"] else "0",
    ])
