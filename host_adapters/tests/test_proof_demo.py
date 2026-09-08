"""Evidence file mechanics, not mathematical acceptance policy."""

import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase
from unittest.mock import patch

from host_adapters.proof_demo import EvidencePublicationError, prepare_submission, write_new, publish_evidence


class ProofDemoEvidenceTests(TestCase):
    def test_submission_preserves_original_source_bytes(self):
        with TemporaryDirectory() as temporary:
            source = Path(temporary) / "example.lg"
            source.write_bytes("# café\r\n## Main\r\n".encode())
            content, names = prepare_submission(source, ["Socrates"])
            self.assertEqual(content, source.read_bytes())
            self.assertEqual(names, ["Socrates"])

    def test_invalid_submission_fails_before_any_process_or_artifact(self):
        with TemporaryDirectory() as temporary:
            source = Path(temporary) / "example.lg"
            source.write_bytes(b"bounded source")
            for names in ([], [""], ["a", "a"], ["x" * 257], ["nul\0name"], ["a"] * 33):
                with self.subTest(names=names):
                    with self.assertRaises(ValueError):
                        prepare_submission(source, names)
            self.assertEqual(list(Path(temporary).iterdir()), [source])

    def test_artifacts_never_overwrite_an_existing_file(self):
        with TemporaryDirectory() as temporary:
            destination = Path(temporary) / "input.lg"
            write_new(destination, b"original")
            with self.assertRaises(FileExistsError):
                write_new(destination, b"replacement")
            self.assertEqual(destination.read_bytes(), b"original")
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)

    def test_publication_includes_hashes_and_preserves_completed_runs(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            pending = root / ".partial-unique"
            pending.mkdir(mode=0o700)
            write_new(pending / "input.lg", b"exact source")
            destination = publish_evidence(pending, "run-unique", {"schema": "macsad-proof-demo/1"})
            self.assertEqual(destination, root / "run-unique" / "bundle")
            self.assertFalse(pending.exists())
            manifest = json.loads((destination / "manifest.json").read_text())
            self.assertEqual(manifest["files"]["input.lg"]["bytes"], 12)
            self.assertEqual(len(manifest["files"]["input.lg"]["sha256"]), 64)
            second = root / ".partial-second"
            second.mkdir()
            write_new(second / "input.lg", b"different source")
            with self.assertRaises(FileExistsError):
                publish_evidence(second, "run-unique", {})
            self.assertEqual((destination / "input.lg").read_bytes(), b"exact source")
            self.assertTrue(second.exists())

    def test_manifest_does_not_follow_symlinks_or_accept_path_escape(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            pending = root / ".partial-one"
            pending.mkdir()
            (pending / "outside").symlink_to(root)
            with self.assertRaises(ValueError):
                publish_evidence(pending, "../escaped", {})
            with self.assertRaises(ValueError):
                publish_evidence(pending, "run-one", {})

    def test_disk_failure_does_not_expose_a_completed_bundle(self):
        with TemporaryDirectory() as temporary:
            pending = Path(temporary) / ".partial-one"
            pending.mkdir()
            write_new(pending / "input.lg", b"source")
            with patch("host_adapters.proof_demo.os.fsync", side_effect=OSError("disk failure")):
                with self.assertRaises(OSError):
                    publish_evidence(pending, "run-one", {})
            self.assertFalse((pending.parent / "run-one").exists())

    def test_failure_after_rename_reports_visible_location_and_uncertain_durability(self):
        with TemporaryDirectory() as temporary:
            pending = Path(temporary) / ".partial-one"
            pending.mkdir()
            write_new(pending / "input.lg", b"source")
            destination = pending.parent / "run-one" / "bundle"
            with patch("host_adapters.proof_demo._sync_directory", side_effect=[None, OSError("disk failure")]):
                with self.assertRaisesRegex(EvidencePublicationError, "durability unconfirmed") as failure:
                    publish_evidence(pending, "run-one", {})
            self.assertIn(str(destination), str(failure.exception))
            self.assertTrue((destination / "manifest.json").is_file())
            self.assertFalse(pending.exists())
