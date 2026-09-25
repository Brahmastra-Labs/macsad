"""Small orchestration controls; no PostgreSQL server or process is started."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import lean_attempt_pg16 as cohort


class VersionedStaging(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'root'
        self.stage = Path(self.temporary.name) / 'stage'
        self.inputs = list(cohort.MIGRATIONS) + ['database/workers/control.sh']
        self.patch = patch.object(cohort, 'INPUTS', self.inputs)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        for relative in self.inputs:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(relative + '\n')
        (self.root/self.inputs[2]).chmod(0o750)

    def test_v1_excludes_upgrade_then_copies_the_exact_upgrade(self):
        sources = cohort.source_manifest(self.root)
        cohort.stage_v1(self.root, self.stage, sources)
        self.assertFalse((self.stage/cohort.MIGRATIONS[1]).exists())
        self.assertEqual((self.stage/self.inputs[2]).stat().st_mode & 0o777, 0o750)
        self.assertEqual((self.stage/cohort.MIGRATIONS[0]).read_bytes(),
                         (self.root/cohort.MIGRATIONS[0]).read_bytes())
        cohort.copy_pinned(self.root, self.stage, cohort.MIGRATIONS[1], sources)
        self.assertEqual((self.stage/cohort.MIGRATIONS[1]).read_bytes(),
                         (self.root/cohort.MIGRATIONS[1]).read_bytes())

    def test_unknown_next_migration_cannot_be_silently_omitted(self):
        (self.root/'database/migrations/0003_unreviewed.sql').write_text('SELECT 1;')
        with self.assertRaisesRegex(ValueError, 'exactly migrations'):
            cohort.source_manifest(self.root)

    def test_changed_upgrade_bytes_refuse_before_becoming_visible(self):
        sources = cohort.source_manifest(self.root)
        cohort.stage_v1(self.root, self.stage, sources)
        (self.root/cohort.MIGRATIONS[1]).write_text('changed')
        with self.assertRaisesRegex(ValueError, 'source changed before staging'):
            cohort.copy_pinned(self.root, self.stage, cohort.MIGRATIONS[1], sources)
        self.assertFalse((self.stage/cohort.MIGRATIONS[1]).exists())

    def test_prepopulated_v2_stage_cannot_host_v1_fixtures(self):
        path = self.stage/cohort.MIGRATIONS[1]
        path.parent.mkdir(parents=True)
        path.write_text('unexpected old stage')
        with self.assertRaisesRegex(ValueError, 'v1 fixture stage contains a later migration'):
            cohort.stage_v1(self.root, self.stage, cohort.source_manifest(self.root))


def load_tests(loader, tests, pattern):
    if tests.countTestCases() != 4:
        raise AssertionError('versioned staging requires exactly four controls')
    return tests


if __name__ == '__main__':
    unittest.main()
