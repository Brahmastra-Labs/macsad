"""Explicit real-LOGOS integration tier; no mocks and no skips.

LOGOS_WORKSPACE must identify the exact admitted checkout.
python3 -m unittest host_adapters.tests.proof_demo_contract -v
"""

import hashlib
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase

from host_adapters.proof_demo import REPOSITORY, run_demo


class NativeProofLoopContract(TestCase):
    def run_fixture(self, name, targets, expected_status):
        fixture = REPOSITORY / "tests/fixtures/proofs" / (name + ".lg")
        with TemporaryDirectory(prefix="macsad-proof-contract-") as temporary:
            result = run_demo(fixture, targets, Path(temporary), Path(os.environ["LOGOS_WORKSPACE"]))
            self.assertEqual([row["logos_status"] for row in result["observations"]], [expected_status] * 2)
            self.assertTrue(result["raw_reports_identical"])
            evidence = Path(result["evidence_directory"])
            self.assertEqual((evidence / "input.lg").read_bytes(), fixture.read_bytes())
            manifest = json.loads((evidence / "manifest.json").read_text())
            for name, record in manifest["files"].items():
                content = (evidence / name).read_bytes()
                self.assertEqual(hashlib.sha256(content).hexdigest(), record["sha256"])
                self.assertEqual(len(content), record["bytes"])
            first = (evidence / "first/prove.stdout").read_bytes()
            return result, first

    def test_three_geometric_results_are_checked_and_source_rerun(self):
        result, raw = self.run_fixture("tarski", ["reflexivity", "symmetry", "transitivity"], "checked")
        self.assertEqual(json.loads(raw)["axioms"], 2)
        self.assertIn("not preserved-certificate replay", result["replay"])
        self.assertEqual(result["trace_process"], {"exit_code": 0, "termination": "exited"})

    def test_removing_needed_geometric_assumption_is_not_proved(self):
        _, raw = self.run_fixture("weak_tarski", ["reflexivity"], "not-proved")
        self.assertFalse(json.loads(raw)["all_verified"])

    def test_english_given_assumptions_change_the_result_and_source_identity(self):
        positive, first = self.run_fixture("socrates", ["Socrates"], "checked")
        negative, second = self.run_fixture("unfounded_socrates", ["Socrates"], "not-proved")
        self.assertNotEqual(positive["request"]["source_sha256"], negative["request"]["source_sha256"])
        self.assertEqual(json.loads(first)["axioms"], 0)
        self.assertEqual(json.loads(second)["axioms"], 0)

    def test_wrong_requested_target_cannot_reuse_a_successful_report(self):
        self.run_fixture("socrates", ["unrelated-goal"], "rejected")

    def test_reordered_targets_are_rejected(self):
        self.run_fixture("tarski", ["symmetry", "reflexivity", "transitivity"], "rejected")

    def test_no_theorems_cannot_be_vacuously_checked(self):
        self.run_fixture("no_theorems", ["missing"], "rejected")

    def test_malformed_source_cannot_be_checked(self):
        self.run_fixture("malformed", ["missing"], "rejected")
