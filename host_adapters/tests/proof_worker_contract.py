"""Explicit integration tier: 31 argv cases and 11 JSON response fixtures.

From the MaCSad root, with LOGOS_WORKSPACE pointing to the admitted checkout:
    python3 -m unittest host_adapters.tests.proof_worker_contract -v

This is intentionally not named test_*.py: ordinary host tests must not launch
LOGOS. The cases verify the native worker's transport and report classification;
they neither generate proofs nor establish mathematical acceptance or replay.
"""

from __future__ import annotations

import os
from pathlib import Path
import unittest

from host_adapters.proof_process import ProcessObservation, proof_policy_arguments, run_bounded


REPOSITORY = Path(__file__).resolve().parents[2]
BASE = (
    "macsad-proof-facts/1", "1", "120", "0", "0", "1",
    "536f637261746573", "536f637261746573", "1", "1",
)


def changed(label, updates, verdict="rejected"):
    arguments = list(BASE)
    for index, value in updates.items():
        arguments[index] = value
    return label, tuple(arguments), verdict


CASES = (
    ("checked", BASE, "checked"),
    changed("not-proved", {3: "1", 5: "0", 8: "0", 9: "0"}, "not-proved"),
    changed("not-proved-null-error", {3: "1", 5: "0", 8: "0"}, "not-proved"),
    ("missing-arguments", BASE[:-1], "rejected"),
    ("extra-arguments", BASE + ("extra",), "rejected"),
    ("no-arguments", (), "rejected"),
    changed("wrong-schema", {0: "macsad-proof-facts/2"}),
    changed("invalid-envelope", {1: "0"}),
    changed("malformed-valid-bit", {1: "true"}),
    changed("malformed-summary-bit", {5: "true"}),
    changed("leading-zero-number", {2: "0120"}),
    changed("signed-number", {4: "-1"}),
    changed("oversize-number", {2: "100000"}),
    changed("byte-bound", {2: "32769"}),
    changed("non-success-exit", {3: "124"}),
    changed("uppercase-hex", {6: "536F637261746573"}),
    changed("odd-hex", {6: "5"}),
    changed("invalid-hex", {6: "zz"}),
    changed("invalid-utf8", {6: "ff", 7: "ff"}),
    changed("overlong-utf8", {6: "c080", 7: "c080"}),
    changed("empty-name", {6: ""}),
    changed("trailing-name-separator", {6: "536f637261746573,"}),
    changed("name-mismatch", {7: "41"}),
    changed("malformed-verdict-bit", {8: "2"}),
    changed("trailing-bit-separator", {8: "1,"}),
    changed("non-null-success-error", {9: "0"}),
    changed("summary-mismatch", {5: "0"}),
    changed("name-byte-bound-ok", {6: "c3a9" * 128, 7: "c3a9" * 128}, "checked"),
    changed("name-byte-bound-excess", {6: "c3a9" * 129, 7: "c3a9" * 129}),
    changed("duplicate-targets", {6: "41,41", 7: "41,41", 8: "1,1", 9: "1,1"}),
    changed("aggregate-bound", {6: "61" * 33000}),
)


RESPONSE_CASES = (
    ("valid-proved.json", 0, "1", "checked"),
    ("valid-not-proved.json", 1, "1", "not-proved"),
    ("invalid-axiom-type.json", 0, "0", "rejected"),
    ("invalid-boolean-type.json", 0, "0", "rejected"),
    ("invalid-duplicate-key.json", 0, "0", "rejected"),
    ("invalid-duplicate-target.json", 0, "1", "rejected"),
    ("invalid-empty-targets.json", 0, "1", "rejected"),
    ("invalid-error-success.json", 0, "1", "rejected"),
    ("invalid-extra-field.json", 0, "0", "rejected"),
    ("invalid-summary.json", 1, "1", "rejected"),
    ("invalid-trailing-data.json", 0, "0", "rejected"),
)


class ProofWorkerContract(unittest.TestCase):
    def setUp(self):
        configured_workspace = os.environ.get("LOGOS_WORKSPACE")
        self.assertTrue(configured_workspace, "LOGOS_WORKSPACE must select the admitted checkout")
        workspace = Path(configured_workspace).resolve(strict=True)
        self.assertTrue(workspace.is_dir())
        self.environment = {
            "PATH": os.defpath,
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "LOGOS_WORKSPACE": str(workspace),
        }
        self.command = [
            "/bin/bash", str(REPOSITORY / "scripts/logos.sh"),
            "run", "--interpret", "--max-steps", "1000000", "--timeout", "5s",
            "--seed", "7", "--quiet", "--color", "never", "--",
        ]

    def assert_worker_verdict(self, arguments, expected):
        observed = run_bounded(
            self.command + list(arguments),
            cwd=REPOSITORY / "logos/proof-worker",
            environment=self.environment,
            timeout_seconds=15.0,
            output_limit=4096,
        )
        self.assertEqual(observed.termination, "exited")
        self.assertEqual(observed.exit_code, 0, observed.stderr)
        self.assertEqual(observed.stdout, (expected + "\n").encode("ascii"))
        self.assertEqual(observed.stderr, b"")

    def test_fixed_thirty_one_argument_cases(self):
        self.assertEqual(len(CASES), 31)
        self.assertEqual(len({case[0] for case in CASES}), 31)
        for label, arguments, expected in CASES:
            with self.subTest(case=label):
                self.assert_worker_verdict(arguments, expected)

    def test_eleven_response_fixtures_through_native_policy(self):
        directory = REPOSITORY / "tests/fixtures/proofs/responses"
        self.assertEqual(len(RESPONSE_CASES), 11)
        self.assertEqual({path.name for path in directory.glob("*.json")}, {row[0] for row in RESPONSE_CASES})
        for filename, exit_code, valid_bit, expected in RESPONSE_CASES:
            with self.subTest(fixture=filename):
                observation = ProcessObservation(exit_code, (directory / filename).read_bytes(), b"", "exited")
                arguments = proof_policy_arguments(observation, ["Socrates"])
                self.assertEqual(arguments[1], valid_bit)
                self.assertEqual(arguments[6], "536f637261746573")
                self.assert_worker_verdict(arguments, expected)


if __name__ == "__main__":
    unittest.main()
