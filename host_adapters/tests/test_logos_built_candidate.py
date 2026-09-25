"""NEW local built-candidate controls; original directory assertions unchanged."""
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

from host_adapters import logos_directory as connector


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class BuiltCandidateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / 'macsad'
        self.repo.mkdir()
        self.candidate = self.root / 'candidate'
        self.source = self.candidate / 'repo'
        self.evidence = self.candidate / 'evidence'
        self.source.mkdir(parents=True)
        self.evidence.mkdir()
        files = {
            'Cargo.toml': '[workspace]\nmembers=["app"]\n',
            'app/Cargo.toml': '[package]\nname="fixture"\nversion="0.1.0"\n',
            'app/src/main.rs': 'fn main() {}\n',
            'Cargo.lock': 'version = 4\n', 'README.md': 'fixture\n',
            'LICENSE.md': 'fixture\n', 'AGENTS.md': 'fixture\n', 'CLAUDE.md': 'fixture\n',
            'LOGOS_QUICKGUIDE.md': 'fixture\n', 'docs/readme': 'fixture\n',
            '.cargo/config.toml': '', '.config/nextest.toml': '',
            'scripts/lean-demo.sh': '# inert\n', 'scripts/lean-contract-fixtures.sh': '# inert\n',
            'reference-kernels/lean4export/lean-toolchain': 'leanprover/lean4:v4.14.0\n',
            'work/alejandro/contract/readme': 'fixture\n',
        }
        for relative, text in files.items():
            path = self.source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.inventory = {rel: {'sha256': sha(self.source/rel), 'bytes': (self.source/rel).stat().st_size,
                               'mode': stat.S_IMODE((self.source/rel).stat().st_mode)} for rel in files}
        write_json(self.evidence/'source-inputs.json', self.inventory)
        self.inventory_sha = sha(self.evidence/'source-inputs.json')
        executable = b'#!/bin/sh\nprintf "local candidate fixture\\n"\n'
        self.binary_sha = hashlib.sha256(executable).hexdigest()
        self.binary = self.evidence/('largo-'+self.binary_sha)
        self.binary.write_bytes(executable)
        self.binary.chmod(0o555)
        self.copy = {'schema':'logos-demo-copy/1', 'completed_utc':'2026-09-25T00:00:00+00:00',
                     'source':str(self.root/'original'), 'repo':str(self.source), 'members':['app'],
                     'files':len(self.inventory), 'bytes':sum(x['bytes'] for x in self.inventory.values()),
                     'source_inventory_sha256':self.inventory_sha, 'hardlinks':False, 'symlinks':False,
                     'shared_dependencies':'installed toolchains and caches'}
        self.binary_record = {'path':str(self.binary), 'sha256':self.binary_sha, 'bytes':len(executable),
                              'source_inventory_sha256':self.inventory_sha, 'built_from':str(self.source)}
        self.command = {'argv':['/fixture/cargo','build','--offline','--locked','--release','-p','logicaffeine-cli','--bin','largo'],
                        'cwd':str(self.source),'exit_code':0, 'started_utc':'2026-09-25T00:01:00+00:00',
                        'finished_utc':'2026-09-25T00:02:00+00:00',
                        'environment_overrides':{'CARGO_TARGET_DIR':str(self.candidate/'build'), 'CARGO_BUILD_JOBS':'6',
                                                 'ELAN_TOOLCHAIN':'leanprover/lean4:v4.14.0', 'PATH':'/fixture'}}
        write_json(self.evidence/'copy.json',self.copy)
        write_json(self.evidence/'binary.json',self.binary_record)
        write_json(self.evidence/'largo-build.command.json',self.command)

    def connect(self):
        return connector.connect_built_candidate(self.repo,self.candidate,self.binary_sha,self.inventory_sha)

    def test_candidate_without_git_is_verified_as_local_evidence_only(self):
        (self.evidence/"candidate.py").write_text("raise AssertionError('must never run evidence code')\n")
        with patch("subprocess.run",side_effect=AssertionError("built mode must not invoke git/evidence code")):
            record = self.connect()
        self.assertEqual(record['schema'],'macsad-logos-built-candidate/1')
        self.assertEqual(record['mode'],'development-built-candidate')
        self.assertFalse(record['release_admitted'])
        self.assertEqual(record['source_binary_correspondence'],'local-build-evidence')
        snapshot = Path(record['snapshot_binary'])
        self.assertEqual(snapshot.read_bytes(),self.binary.read_bytes())
        self.assertNotEqual((snapshot.stat().st_dev,snapshot.stat().st_ino),(self.binary.stat().st_dev,self.binary.stat().st_ino))
        self.assertEqual(snapshot.stat().st_nlink,1)
        self.assertEqual(connector.inspect_connection(self.repo)['source_now'],record['source_at_connection'])

    def test_source_change_size_mode_and_hash_each_refused(self):
        self.connect()
        path=self.source/'app/src/main.rs'
        original=path.read_bytes(); mode=path.stat().st_mode
        for change in ('size','same-size','mode'):
            with self.subTest(change=change):
                path.write_bytes(original);path.chmod(stat.S_IMODE(mode))
                if change=='size':path.write_bytes(original+b'x')
                elif change=='same-size':path.write_bytes(b'X'+original[1:])
                else:path.chmod(stat.S_IMODE(mode)^stat.S_IXUSR)
                with self.assertRaises(ValueError):connector.inspect_connection(self.repo)

    def test_selected_extra_file_missing_file_and_workspace_member_refused(self):
        self.connect()
        extra=self.source/'app/src/extra.rs';extra.write_text('new')
        with self.assertRaises(ValueError):connector.inspect_connection(self.repo)
        extra.unlink()
        removed=self.source/'docs/readme';saved=removed.read_bytes();removed.unlink()
        with self.assertRaises(ValueError):connector.inspect_connection(self.repo)
        removed.write_bytes(saved)
        (self.source/'new').mkdir();(self.source/'new/Cargo.toml').write_text('[package]\nname="new"\nversion="0.1.0"\n')
        (self.source/'Cargo.toml').write_text('[workspace]\nmembers=["app","new"]\n')
        with self.assertRaises(ValueError):connector.inspect_connection(self.repo)

    def test_frozen_binary_or_any_evidence_change_refused(self):
        self.connect()
        for name in ('copy.json','binary.json','source-inputs.json','largo-build.command.json'):
            with self.subTest(name=name):
                p=self.evidence/name;old=p.read_bytes();p.write_bytes(old+b' ')
                with self.assertRaises(ValueError):connector.inspect_connection(self.repo)
                p.write_bytes(old)
        self.binary.chmod(0o755);self.binary.write_bytes(b'changed')
        with self.assertRaises(ValueError):connector.inspect_connection(self.repo)

    def test_failed_wrong_command_and_cross_link_evidence_refused(self):
        for kind in ('failed','command','cwd','target-dir','binary-source','copy-inventory'):
            with self.subTest(kind=kind):
                command=json.loads(json.dumps(self.command));binary=dict(self.binary_record);copy=dict(self.copy)
                if kind=='failed':command['exit_code']=1
                elif kind=='command':command['argv'][1]='test'
                elif kind=='cwd':command['cwd']=str(self.root)
                elif kind=='target-dir':command['environment_overrides']['CARGO_TARGET_DIR']=str(self.source/'target')
                elif kind=='binary-source':binary['built_from']=str(self.root)
                else:copy['source_inventory_sha256']='0'*64
                write_json(self.evidence/'largo-build.command.json',command);write_json(self.evidence/'binary.json',binary);write_json(self.evidence/'copy.json',copy)
                with self.assertRaises(ValueError):self.connect()
        write_json(self.evidence/'largo-build.command.json',self.command);write_json(self.evidence/'binary.json',self.binary_record);write_json(self.evidence/'copy.json',self.copy)

    def test_symlink_hardlink_git_and_inventory_escape_refused(self):
        path=self.source/'docs/readme';old=path.read_bytes();path.unlink();path.symlink_to(self.source/'README.md')
        with self.assertRaises(ValueError):self.connect()
        path.unlink();path.write_bytes(old)
        linked=self.root/'linked';os.link(path,linked)
        with self.assertRaises(ValueError):self.connect()
        linked.unlink();(self.source/'.git').mkdir()
        with self.assertRaises(ValueError):self.connect()
        (self.source/'.git').rmdir()
        self.inventory['../outside']=self.inventory['README.md'];write_json(self.evidence/'source-inputs.json',self.inventory)
        self.inventory_sha=sha(self.evidence/'source-inputs.json');self.copy['source_inventory_sha256']=self.inventory_sha;self.binary_record['source_inventory_sha256']=self.inventory_sha
        write_json(self.evidence/'copy.json',self.copy);write_json(self.evidence/'binary.json',self.binary_record)
        with self.assertRaises(ValueError):self.connect()

    def test_wrong_external_pins_and_duplicate_json_are_refused(self):
        with self.assertRaises(ValueError):connector.connect_built_candidate(self.repo,self.candidate,'0'*64,self.inventory_sha)
        with self.assertRaises(ValueError):connector.connect_built_candidate(self.repo,self.candidate,self.binary_sha,'0'*64)
        p=self.evidence/'binary.json';p.write_text(p.read_text().rstrip()[:-1]+',"sha256":"duplicate"}')
        with self.assertRaises(ValueError):self.connect()

    def test_existing_snapshot_with_other_hardlink_is_refused(self):
        record=self.connect();os.link(record['snapshot_binary'],self.root/'snapshot-link')
        with self.assertRaises(ValueError):connector.inspect_connection(self.repo)
        with self.assertRaises(ValueError):self.connect()

    def test_invalid_candidate_never_reaches_exec(self):
        self.connect();(self.source/'README.md').write_text('changed')
        with (patch.object(connector,'__file__',str(self.repo/'host_adapters/logos_directory.py')),
              patch('sys.argv',['logos_directory.py','run','--','--version']),patch('os.execve') as execute):
            with self.assertRaises(SystemExit):connector.main()
            execute.assert_not_called()

    def test_path_dependencies_and_literal_include_assets_are_required(self):
        (self.source/'app/Cargo.toml').write_text('[package]\nname="fixture"\nversion="0.1.0"\n[dependencies]\nsupport={path="../support"}\n')
        (self.source/'support/src').mkdir(parents=True)
        (self.source/'support/Cargo.toml').write_text('[package]\nname="support"\nversion="0.1.0"\n')
        (self.source/'support/src/lib.rs').write_text('pub fn helper() {}\n')
        (self.source/'app/src/main.rs').write_text('const DATA: &str = include_str!("../../asset.txt");\nfn main() {}\n')
        (self.source/'asset.txt').write_text('compile-time asset\n')
        self.inventory={p.relative_to(self.source).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size,'mode':stat.S_IMODE(p.stat().st_mode)}
                        for p in self.source.rglob('*') if p.is_file()}
        def refresh():
            write_json(self.evidence/'source-inputs.json',self.inventory)
            self.inventory_sha=sha(self.evidence/'source-inputs.json')
            self.copy.update(source_inventory_sha256=self.inventory_sha,files=len(self.inventory),bytes=sum(x['bytes'] for x in self.inventory.values()),members=['app','support'])
            self.binary_record['source_inventory_sha256']=self.inventory_sha
            write_json(self.evidence/'copy.json',self.copy);write_json(self.evidence/'binary.json',self.binary_record)
        refresh()
        self.assertEqual(self.connect()['source_at_connection']['members'],['app','support'])
        del self.inventory['support/src/lib.rs']
        refresh()
        with self.assertRaises(ValueError):self.connect()

    def test_cli_new_mode_and_run_keep_explicit_workspace(self):
        argv=['logos_directory.py','connect-built-candidate','--candidate',str(self.candidate),
              '--expected-binary-sha256',self.binary_sha,'--expected-source-inventory-sha256',self.inventory_sha]
        with (patch.object(connector,'__file__',str(self.repo/'host_adapters/logos_directory.py')),
              patch('sys.argv',argv),patch('sys.stdout',new_callable=io.StringIO) as output):
            connector.main()
        record=json.loads(output.getvalue())
        with (patch.object(connector,'__file__',str(self.repo/'host_adapters/logos_directory.py')),
              patch('sys.argv',['logos_directory.py','run','--','--version']),patch('os.execve') as execute):
            connector.main()
        self.assertEqual(execute.call_args.args[0],record['snapshot_binary'])
        self.assertEqual(execute.call_args.args[1],[record['snapshot_binary'],'--version'])
        self.assertEqual(execute.call_args.args[2]['LOGOS_WORKSPACE'],str(self.source))
        invocation=json.loads((self.repo/'.runtime/logos-directory/last-invocation.json').read_text())
        self.assertFalse(invocation['release_admitted'])
        self.assertEqual(invocation['source_binary_correspondence'],'local-build-evidence')
