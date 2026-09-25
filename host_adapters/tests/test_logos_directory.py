"""Local-directory selection must never impersonate release admission."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from host_adapters.logos_directory import connect, inspect_connection, execution_environment


class LogosDirectoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / "macsad"
        self.repo.mkdir()
        self.workspace = self.root / "private source"
        self.workspace.mkdir()
        subprocess.run(["git", "init", "-q", str(self.workspace)], check=True)
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Fixture")
        (self.workspace / "Cargo.lock").write_text("version = 4\n")
        self.git("add", "Cargo.lock")
        self.git("commit", "-qm", "fixture")
        self.binary = self.workspace / "target/debug/largo"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text("#!/bin/sh\nprintf 'largo fixture\\n'\n")
        self.binary.chmod(0o755)

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.workspace), *args], check=True, capture_output=True)

    def test_connection_records_dirty_source_separately_from_unproven_binary_origin(self):
        result = connect(self.repo, self.workspace, "target/debug/largo")
        self.assertEqual(result["mode"], "development-directory")
        self.assertFalse(result["release_admitted"])
        self.assertEqual(result["source_binary_correspondence"], "unverified")
        self.assertTrue(result["source_at_connection"]["dirty"])
        self.assertEqual(result["workspace"], str(self.workspace.resolve()))
        snapshot = Path(result["snapshot_binary"])
        self.assertEqual(snapshot.read_bytes(), self.binary.read_bytes())
        self.assertNotEqual(snapshot.stat().st_ino, self.binary.stat().st_ino)
        self.assertEqual(snapshot.stat().st_nlink, 1)
        self.assertEqual(inspect_connection(self.repo)["binary_sha256"], result["binary_sha256"])

    def test_rebuilt_binary_requires_explicit_reconnect(self):
        first = connect(self.repo, self.workspace, "target/debug/largo")
        self.binary.write_text("#!/bin/sh\nexit 7\n")
        with self.assertRaisesRegex(ValueError, "changed.*reconnect"):
            inspect_connection(self.repo)
        second = connect(self.repo, self.workspace, "target/debug/largo")
        self.assertNotEqual(first["binary_sha256"], second["binary_sha256"])

    def test_current_source_changes_are_reported_without_fabricating_build_provenance(self):
        connect(self.repo, self.workspace, "target/debug/largo")
        (self.workspace / "Cargo.lock").write_text("version = 5\n")
        report = inspect_connection(self.repo)
        self.assertNotEqual(report["source_at_connection"], report["source_now"])
        self.assertEqual(report["source_binary_correspondence"], "unverified")

    def test_snapshot_tampering_fails_closed(self):
        report = connect(self.repo, self.workspace, "target/debug/largo")
        snapshot = Path(report["snapshot_binary"])
        snapshot.chmod(0o700)
        snapshot.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "snapshot"):
            inspect_connection(self.repo)

    def test_binary_cannot_escape_or_be_symlink(self):
        outside = self.root / "outside"
        outside.write_text("#!/bin/sh\nexit 0\n")
        outside.chmod(0o755)
        link = self.workspace / "link"
        link.symlink_to(outside)
        for binary in ("../outside", str(outside), "link", "Cargo.lock"):
            with self.subTest(binary=binary), self.assertRaises(ValueError):
                connect(self.repo, self.workspace, binary)

    def test_missing_corrupt_and_unknown_config_refused(self):
        with self.assertRaises(ValueError):
            inspect_connection(self.repo)
        connect(self.repo, self.workspace, "target/debug/largo")
        config = self.repo / ".runtime/logos-directory/connection.json"
        original = config.read_text()
        for payload in ("{}", original.replace('macsad-logos-directory/1', 'macsad-logos-directory/9'), original[:-2] + ',"schema":"duplicate"}'):
            with self.subTest(payload=payload):
                config.write_text(payload)
                with self.assertRaises(ValueError):
                    inspect_connection(self.repo)

    def test_runtime_symlink_is_not_followed(self):
        (self.repo / ".runtime").symlink_to(self.root)
        with self.assertRaises(ValueError):
            connect(self.repo, self.workspace, "target/debug/largo")

    def test_development_environment_is_explicit_and_retains_workspace(self):
        connect(self.repo, self.workspace, "target/debug/largo")
        env = execution_environment(inspect_connection(self.repo), {"PATH": os.defpath})
        self.assertEqual(env["LOGOS_WORKSPACE"], str(self.workspace))
        self.assertNotIn("MACSAD_LOGOS_MODE", env)
        self.assertNotIn("DATABASE_URL", env)

    def test_git_environment_cannot_redirect_recorded_source(self):
        alternate = self.root / "other"
        subprocess.run(["git", "init", "-q", str(alternate)], check=True)
        with patch.dict(os.environ, {"GIT_DIR": str(alternate / ".git"), "GIT_WORK_TREE": str(alternate)}):
            report = connect(self.repo, self.workspace, "target/debug/largo")
        expected = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.assertEqual(report["source_at_connection"]["commit"], expected)

    def test_admitted_launcher_ignores_development_environment(self):
        wrapper = Path(__file__).resolve().parents[2] / "scripts/logos.sh"
        result = subprocess.run(["bash", str(wrapper), "--version"], capture_output=True,
                                env={**os.environ, "MACSAD_LOGOS_MODE": "development-directory",
                                     "LOGOS_WORKSPACE": str(self.workspace)})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b"largo fixture", result.stdout)
