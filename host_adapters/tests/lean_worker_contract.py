"""Explicit interpreter integration tier; no Lean compilation or proof claim.

Run separately under the parent's exclusive validation window. The default
admitted runner uses LOGOS_WORKSPACE through unchanged scripts/logos.sh.
MACSAD_LEAN_WORKER_RUNNER=development-directory explicitly selects dev.sh logos
and reports the measured connection identity; it is compatibility evidence only.
No mode is injected into the admitted launcher or old proof demo.
"""
import json
import os
from pathlib import Path
import unittest

from host_adapters.lean_result import lean_import_policy_arguments, lean_replay_policy_arguments
from host_adapters.proof_process import run_bounded
from host_adapters.tests.test_lean_result import D, report, receipt, wire

ROOT = Path(__file__).resolve().parents[2]


def import_args(value=None, code=0, **changes):
    identities = dict(expected_lean="T.example", expected_logos="T.example",
                      expected_package_path="/private/job/package",
                      observed_manifest_sha256=D, observed_package_schema="logos-lean-package/1")
    identities.update(changes)
    return lean_import_policy_arguments(wire(report() if value is None else value), exit_code=code, **identities)


def cases():
    yield "verified", import_args(), "verified"
    yield "legacy-proof", ["macsad-proof-facts/1", "1", "120", "0", "0", "1", "41", "41", "1", "1"], "checked"
    yield "verified-wrong-exit", import_args(code=1), "rejected_contract"
    value = report(); value["assumptions"] = ["propext", "Quot.sound", "Classical.choice"]
    yield "named-assumptions", import_args(value), "verified"
    for stage in report()["stages"]:
        value = report(); value["stages"][stage] = "not_run"
        yield "missing-" + stage, import_args(value), "rejected_contract"
    for assumption in (["sorryAx"], ["propext", "propext"], ["propext,Classical.choice"]):
        value = report(); value["assumptions"] = assumption
        yield repr(assumption), import_args(value), "rejected_contract"
    for changes in ({"expected_lean": "Other.target"}, {"expected_logos": "Other.target"},
                    {"expected_package_path": "/other/package"}, {"observed_manifest_sha256": "b" * 64},
                    {"observed_package_schema": "logos-lean-package/2"}):
        yield repr(changes), import_args(**changes), "rejected_contract"
    for code, outcome in enumerate(("invalid_source", "unsupported_feature", "disallowed_assumptions",
                                    "resource_limit", "infrastructure_failure"), 1):
        value = report(); value["outcome"] = outcome; value["package"] = None
        value["stages"] = dict.fromkeys(value["stages"], "not_run")
        value["target"]["logos"] = None
        yield outcome, import_args(value, code, expected_logos=None, observed_manifest_sha256=None,
                                   observed_package_schema=None), outcome
    yield "replayed", lean_replay_policy_arguments(wire(receipt()), exit_code=0,
                                                   expected_manifest_sha256=D), "replayed"
    value = receipt(); value["verified"] = True
    yield "replay-original-acceptance", lean_replay_policy_arguments(wire(value), exit_code=0,
                                                                    expected_manifest_sha256=D), "rejected_contract"
    yield "replay-wrong-digest", lean_replay_policy_arguments(wire(receipt()), exit_code=0,
                                                             expected_manifest_sha256="b" * 64), "rejected_contract"
    value = receipt(); value["stages"]["independent_recheck"]["status"] = "not_run"
    yield "replay-no-independent", lean_replay_policy_arguments(wire(value), exit_code=0,
                                                               expected_manifest_sha256=D), "rejected_contract"
    args = import_args(); args[0] = "macsad-lean-facts/2"
    yield "unknown-facts-schema", args, "rejected_contract"
    args = import_args(); args[1] = "ff"
    yield "invalid-wire-utf8", args, "rejected_contract"
    yield "wrong-arity", import_args()[:-1], "rejected_contract"
    value = receipt(); value["stages"]["lean_accepted"]["status"] = "passed"
    yield "replay-claims-lean-pass", lean_replay_policy_arguments(wire(value), exit_code=0,
                                                                expected_manifest_sha256=D), "rejected_contract"
    value = receipt(); value["replayed"] = False; value["manifest_sha256"] = None
    for stage in value["stages"].values():
        stage["status"] = "not_run"
    value["stages"]["fresh_replay"]["status"] = "failed"
    yield "replay-failed", lean_replay_policy_arguments(wire(value), exit_code=1,
                                                       expected_manifest_sha256=D), "replay_failed"


class LeanWorkerContract(unittest.TestCase):
    def test_current_results_through_logos_policy(self):
        runner = os.environ.get("MACSAD_LEAN_WORKER_RUNNER", "admitted")
        self.assertIn(runner, ("admitted", "development-directory"), "unknown explicit Lean worker runner")
        connection = None
        if runner == "development-directory":
            from host_adapters.logos_directory import inspect_connection
            connection = inspect_connection(ROOT)
            self.assertEqual(connection["mode"], "development-directory")
            self.assertIs(connection["release_admitted"], False)
            self.assertEqual(connection["source_binary_correspondence"], "unverified")
            workspace = Path(connection["workspace"])
            command = ["/bin/bash", str(ROOT / "scripts/dev.sh"), "logos"]
            # This receipt identifies inspected bytes; it does not prove their
            # source correspondence or promote an admitted toolchain.
            print(json.dumps({"schema": "macsad-lean-worker-runtime/1",
                              "runner": runner, "connection": connection}, sort_keys=True), flush=True)
        else:
            configured = os.environ.get("LOGOS_WORKSPACE")
            self.assertTrue(configured, "LOGOS_WORKSPACE must select the admitted checkout")
            workspace = Path(configured).resolve(strict=True)
            command = ["/bin/bash", str(ROOT / "scripts/logos.sh")]
        environment = {"PATH": os.defpath, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
                       "LOGOS_WORKSPACE": str(workspace)}
        command += ["run", "--interpret", "--max-steps", "1000000", "--timeout", "5s",
                    "--seed", "7", "--quiet", "--color", "never", "--"]
        for label, args, expected in cases():
            with self.subTest(case=label):
                observed = run_bounded(command + args, cwd=ROOT / "logos/proof-worker",
                                       environment=environment, timeout_seconds=15.0, output_limit=4096)
                self.assertEqual(observed.termination, "exited")
                self.assertEqual(observed.exit_code, 0, observed.stderr)
                self.assertEqual(observed.stdout, (expected + "\n").encode())
                self.assertEqual(observed.stderr, b"")
        if connection is not None:
            after = inspect_connection(ROOT)
            self.assertEqual(after["binary_sha256"], connection["binary_sha256"],
                             "development binary identity changed during the controls")
            self.assertEqual(after["snapshot_binary"], connection["snapshot_binary"])


if __name__ == "__main__":
    unittest.main()
