"""Mechanical proof-worker contracts; scientific decisions belong to LOGOS."""

import json
import os
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase
from unittest.mock import Mock, patch

from host_adapters import proof_process

from host_adapters.proof_process import (
    ProcessObservation,
    decode_prove_report,
    proof_policy_arguments,
    read_source,
    run_bounded,
)


def report_bytes(**changes):
    report = {
        "file": "input.lg",
        "axioms": 0,
        "theorems": [{"name": "Socrates", "verified": True, "error": None}],
        "all_verified": True,
    }
    report.update(changes)
    return json.dumps(report, ensure_ascii=False).encode("utf-8")


class ProofReportTransportTests(TestCase):
    def test_exact_structural_report_is_not_a_scientific_decision(self):
        payload = report_bytes()
        decoded = decode_prove_report(payload)
        self.assertEqual(decoded["file"], "input.lg")
        # Intentionally inconsistent semantics: only LOGOS may classify this.
        inconsistent = report_bytes(all_verified=False)
        self.assertFalse(decode_prove_report(inconsistent)["all_verified"])
        empty = report_bytes(theorems=[])
        self.assertEqual(decode_prove_report(empty)["theorems"], [])

    def test_duplicate_unknown_missing_and_nonfinite_fields_are_rejected(self):
        original = report_bytes().decode()
        malformed = [
            original.replace('"axioms": 0', '"axioms": 0, "axioms": 1'),
            original.replace('"error": null', '"error": null, "error": null'),
            original.replace('"axioms": 0', '"axioms": NaN'),
            original.replace('"axioms": 0', '"axioms": true'),
            original.replace('"verified": true', '"verified": 1'),
            original.replace('"name": "Socrates"', '"name": null'),
            original.replace('"error": null', '"error": {}'),
            original.replace('"all_verified": true', '"all_verified": "true"'),
            original.replace('"file": "input.lg"', '"file": "other.lg"'),
            original.replace('"axioms": 0, ', ''),
            original[:-1] + ', "certificate": "pretend"}',
            original.replace('"error": null', '"error": null, "extra": 1'),
        ]
        for value in malformed:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    decode_prove_report(value.encode())

    def test_encoding_depth_and_byte_limits_fail_before_interpretation(self):
        for value in (b"", b"\xff", b"[" * 1200, b" " * 32769):
            with self.subTest(length=len(value)):
                with self.assertRaises(ValueError):
                    decode_prove_report(value)
        bad_scalar = report_bytes().replace(b'Socrates', b'\\ud800')
        with self.assertRaises(ValueError):
            decode_prove_report(bad_scalar)
        for value in (2**63, -(2**63) - 1):
            with self.assertRaises(ValueError):
                decode_prove_report(report_bytes(axioms=value))

    def test_fields_are_framed_as_data_not_generated_program_source(self):
        payload = report_bytes(theorems=[{"name": "A|B\nC", "verified": False, "error": "none"}], all_verified=False)
        observation = ProcessObservation(1, payload, b"not proved", "exited")
        values = proof_policy_arguments(observation, ["A|B\nC"])
        self.assertEqual(values[0], "macsad-proof-facts/1")
        self.assertEqual(values[1:6], ["1", str(len(payload)), "1", "0", "0"])
        self.assertEqual(values[6:10], ["417c420a43", "417c420a43", "0", "0"])
        self.assertNotIn("## Main", " ".join(values))

    def test_malformed_or_interrupted_reports_have_explicit_invalid_facts(self):
        for observation in (
            ProcessObservation(0, b"{}", b"", "exited"),
            ProcessObservation(None, report_bytes(), b"", "timeout"),
            ProcessObservation(None, report_bytes(), b"", "output-limit"),
        ):
            fields = proof_policy_arguments(observation, ["Socrates"])
            self.assertEqual(fields[1], "0")

    def test_expected_targets_have_unambiguous_sequence_framing(self):
        observation = ProcessObservation(0, report_bytes(), b"", "exited")
        for names in ("AB", [], [""], ["nul\0name"], ["x" * 257], ["x"] * 33):
            with self.assertRaises(ValueError):
                proof_policy_arguments(observation, names)

    def test_source_read_is_bounded_utf8_and_refuses_symlinks(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.lg"
            source.write_bytes(b"## Theorem: Example\n")
            self.assertEqual(read_source(source), source.read_bytes())
            for payload in (b"", b"\xff", b"x\0y", b"x" * 32769):
                source.write_bytes(payload)
                with self.assertRaises(ValueError):
                    read_source(source)
            source.write_bytes(b"valid text")
            link = root / "link.lg"
            link.symlink_to(source)
            with self.assertRaises(ValueError):
                read_source(link)

    def test_source_fifo_without_writer_does_not_block_validation(self):
        with TemporaryDirectory() as temporary:
            fifo = Path(temporary) / "source.lg"
            os.mkfifo(fifo)
            code = "from pathlib import Path; from host_adapters.proof_process import read_source; import sys\ntry: read_source(Path(sys.argv[1]))\nexcept ValueError: print('rejected')"
            result = run_bounded(
                [sys.executable, "-c", code, str(fifo)],
                cwd=Path(__file__).resolve().parents[2],
                environment={"PATH": os.defpath}, timeout_seconds=0.4,
            )
            self.assertEqual(result.termination, "exited")
            self.assertEqual(result.stdout, b"rejected\n")


class BoundedProcessTests(TestCase):
    def run_python(self, code, **options):
        with TemporaryDirectory() as temporary:
            return run_bounded(
                [sys.executable, "-c", code],
                cwd=Path(temporary),
                environment={"PATH": os.defpath},
                **options,
            )

    def test_preserves_real_exit_and_both_output_streams(self):
        result = self.run_python("import sys; print('out'); print('err', file=sys.stderr); sys.exit(3)")
        self.assertEqual(result, ProcessObservation(3, b"out\n", b"err\n", "exited"))

    def test_timeout_terminates_instead_of_returning_success(self):
        result = self.run_python("import time; time.sleep(20)", timeout_seconds=0.1)
        self.assertEqual(result.termination, "timeout")
        self.assertIsNone(result.exit_code)

    def test_output_limit_is_shared_and_bounded(self):
        result = self.run_python("import sys; sys.stdout.write('x'*4096); sys.stdout.flush(); sys.stderr.write('y'*4096)", output_limit=128)
        self.assertEqual(result.termination, "output-limit")
        self.assertLessEqual(len(result.stdout) + len(result.stderr), 128)
        self.assertIsNone(result.exit_code)

    def test_arguments_are_not_interpreted_as_a_shell_command(self):
        with TemporaryDirectory() as temporary:
            result = run_bounded(
                [sys.executable, "-c", "import sys; print(sys.argv[1])", "$(touch leaked); echo unsafe"],
                cwd=Path(temporary),
                environment={"PATH": os.defpath},
            )
            self.assertEqual(result.stdout, b"$(touch leaked); echo unsafe\n")
            self.assertFalse((Path(temporary) / "leaked").exists())

    def test_invalid_limits_fail_before_start(self):
        for timeout_seconds, output_limit in ((0, 128), (1, 0), (61, 128), (1, 32769), (1, 128.5), (1, True), (True, 128), (float("nan"), 128), (10**1000, 128)):
            with self.subTest(timeout=timeout_seconds, limit=output_limit):
                with patch("host_adapters.proof_process.subprocess.Popen", side_effect=ValueError("unexpected process start")) as start:
                    with self.assertRaises(ValueError):
                        self.run_python("print('must not run')", timeout_seconds=timeout_seconds, output_limit=output_limit)
                    start.assert_not_called()

    def test_child_closing_output_does_not_escape_timeout(self):
        result = self.run_python("import os,time; os.close(1); os.close(2); time.sleep(20)", timeout_seconds=0.1)
        self.assertEqual(result.termination, "timeout")

    def test_descendant_holding_output_is_terminated_with_owned_group(self):
        import time

        code = "import os,time; child=os.fork()\nif child == 0: time.sleep(20)\nelse: os.write(1,str(child).encode()); os._exit(0)"
        result = self.run_python(code, timeout_seconds=0.1)
        self.assertEqual(result.termination, "timeout")
        child_status = Path("/proc") / result.stdout.decode("ascii") / "stat"
        deadline = time.monotonic() + 1
        state = None
        while child_status.exists() and time.monotonic() < deadline:
            try:
                state = child_status.read_text().split(") ", 1)[1].split()[0]
            except FileNotFoundError:
                break
            if state == "Z":
                break
            time.sleep(0.01)
        else:
            state = None if not child_status.exists() else "running"
        self.assertIn(state, (None, "Z"))

    def test_cleanup_failure_is_explicit_and_reap_wait_is_bounded(self):
        import subprocess

        process = Mock(pid=12345)
        process.wait.side_effect = subprocess.TimeoutExpired("owned-child", 2)
        with patch("host_adapters.proof_process.os.killpg") as kill, patch("host_adapters.proof_process.os.waitid", return_value=None), patch("host_adapters.proof_process.os.getpgid", return_value=12345), patch("host_adapters.proof_process.os.getsid", return_value=12345):
            with self.assertRaisesRegex(RuntimeError, "cleanup"):
                proof_process.terminate_owned_process(process)
            kill.assert_called_once_with(12345, 9)
            process.wait.assert_called_once_with(timeout=2.0)

    def test_cleanup_refuses_special_mocked_and_current_process_ids(self):
        for pid in (-1, 0, 1, True, Mock(), os.getpid(), os.getpgrp()):
            with self.subTest(pid=repr(pid)):
                with patch("host_adapters.proof_process.os.killpg") as kill:
                    with self.assertRaisesRegex(RuntimeError, "unsafe process identity"):
                        proof_process.terminate_owned_process(Mock(pid=pid))
                    kill.assert_not_called()

    def test_cleanup_refuses_a_process_in_another_session_or_group(self):
        with patch("host_adapters.proof_process.os.killpg") as kill, patch("host_adapters.proof_process.os.waitid", return_value=None), patch("host_adapters.proof_process.os.getpgid", return_value=54321):
            with self.assertRaisesRegex(RuntimeError, "unowned process group"):
                proof_process.terminate_owned_process(Mock(pid=12345))
            kill.assert_not_called()

    def test_cleanup_refuses_a_session_leader_that_is_not_our_child(self):
        with patch("host_adapters.proof_process.os.killpg") as kill, patch("host_adapters.proof_process.os.waitid", side_effect=ChildProcessError), patch("host_adapters.proof_process.os.getpgid", return_value=12345), patch("host_adapters.proof_process.os.getsid", return_value=12345):
            with self.assertRaisesRegex(RuntimeError, "unowned child identity"):
                proof_process.terminate_owned_process(Mock(pid=12345))
            kill.assert_not_called()
