"""Additive forward staging controls; no PostgreSQL needed."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import lean_attempt_pg16 as cohort


class ForwardStaging(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'root'
        self.stage = Path(self.temp.name) / 'stage'
        self.inputs = list(cohort.CURRENT_MIGRATIONS) + ['database/workers/control.sh']
        self.patch = patch.object(cohort, 'INPUTS', self.inputs)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        for relative in self.inputs:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(relative + '\n')

    def test_v1_then_v2_then_v3_preserves_exact_independent_migration_bytes(self):
        sources = cohort.source_manifest(self.root, cohort.CURRENT_MIGRATIONS)
        cohort.stage_v1(self.root, self.stage, sources)
        self.assertEqual([p.name for p in (self.stage/'database/migrations').iterdir()],
                         ['0001_initial_schema.sql'])
        for relative in cohort.CURRENT_MIGRATIONS[1:]:
            cohort.copy_pinned(self.root, self.stage, relative, sources)
            self.assertEqual((self.root/relative).read_bytes(), (self.stage/relative).read_bytes())
            self.assertNotEqual((self.root/relative).stat().st_ino, (self.stage/relative).stat().st_ino)
            self.assertEqual((self.stage/relative).stat().st_nlink, 1)

    def test_missing_forward_migration_is_not_silently_v2_success(self):
        (self.root/cohort.FORWARD_MIGRATION).unlink()
        with self.assertRaisesRegex(ValueError, 'exactly migrations'):
            cohort.source_manifest(self.root, cohort.CURRENT_MIGRATIONS)

    def test_changed_forward_bytes_refuse_before_copy(self):
        sources = cohort.source_manifest(self.root, cohort.CURRENT_MIGRATIONS)
        cohort.stage_v1(self.root, self.stage, sources)
        (self.root/cohort.FORWARD_MIGRATION).write_text('changed')
        with self.assertRaisesRegex(ValueError, 'source changed before staging'):
            cohort.copy_pinned(self.root, self.stage, cohort.FORWARD_MIGRATION, sources)
        self.assertFalse((self.stage/cohort.FORWARD_MIGRATION).exists())

    def test_unknown_fourth_migration_is_not_silently_omitted(self):
        (self.root/'database/migrations/0004_unreviewed.sql').write_text('SELECT 1;')
        with self.assertRaisesRegex(ValueError, 'exactly migrations'):
            cohort.source_manifest(self.root, cohort.CURRENT_MIGRATIONS)
