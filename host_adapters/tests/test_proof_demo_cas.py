"""Exercise the existing demo path with real files/CAS and a fake process port.

The fake port is explicit: these controls establish byte handoff, not proofs.
"""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from host_adapters import proof_demo
from host_adapters.local_cas import LocalCAS
from host_adapters.proof_process import ProcessObservation
from host_adapters.worker_artifacts import read_file_set


class ProofDemoCASWiring(unittest.TestCase):
    def test_optional_capture_preserves_observed_statuses_and_exact_evidence(self):
        with TemporaryDirectory() as temp:
            root=Path(temp).resolve(); output=root/'out';output.mkdir();cas=root/'cas';cas.mkdir()
            source=root/'input.lg';source.write_bytes(b'source bytes')
            lock={'source':{'commit':'test-only'},'runtime':{'observed_binary_sha256':'a'*64}}
            project={'Largo.toml':b'[package]\n','src/main.lg':b'# fake worker\n'}
            admitted=({},['fake-process-port'],lock,b'lock',b'wrapper',project)
            def read(path):
                if path==source:return source.read_bytes()
                if path.name=='logos.sh':return b'wrapper'
                if path.name=='logos.lock.toml':return b'lock'
                return b'# pinned test adapter source\n'
            def observed(argv,**kwargs):
                return ProcessObservation(0,b'not-proved\n' if 'run' in argv else b'exact raw output\n',b'', 'exited')
            with patch.object(proof_demo,'_admitted_inputs',return_value=admitted), \
                 patch.object(proof_demo,'read_source',side_effect=read), \
                 patch.object(proof_demo,'proof_policy_arguments',return_value=['explicit fake facts']), \
                 patch.object(proof_demo,'run_bounded',side_effect=observed):
                result=proof_demo.run_demo(source,['T'],output,root,cas_directory=cas)
                with patch.object(proof_demo,'capture_published_evidence',side_effect=OSError('CAS unavailable')):
                    with self.assertRaises(proof_demo.EvidenceCaptureError) as failure:
                        proof_demo.run_demo(source,['T'],output,root,cas_directory=cas)
                retained=Path(str(failure.exception).split('retained at ',1)[1])
                self.assertTrue((retained/'manifest.json').is_file())
                self.assertTrue((retained/'result.json').is_file())
            self.assertEqual([x['logos_status'] for x in result['observations']],['not-proved','not-proved'])
            with LocalCAS(cas,max_bytes=8*1024*1024) as store:
                facts=read_file_set(store,result['cas_file_set']['sha256'],max_total_bytes=64*1024*1024)
                bundle=Path(result['evidence_directory'])
                for name,fact in facts.items():self.assertEqual(store.get(fact.sha256),(bundle/name).read_bytes())
                self.assertEqual(store.get(facts['input.lg'].sha256),b'source bytes')
                self.assertEqual(store.get(facts['first/prove.stdout'].sha256),b'exact raw output\n')
            self.assertNotIn('cas_file_set',json.loads((bundle/'result.json').read_text()))

    def test_cli_forwards_explicit_cas_limits_without_altering_old_required_args(self):
        with patch.object(proof_demo,'run_demo',return_value={}) as run,patch('builtins.print'):
            self.assertEqual(proof_demo.main(['input.lg','--target','T','--output-directory','out',
                '--logos-workspace','engine','--cas-directory','cas','--cas-max-object-bytes','4096',
                '--cas-max-total-bytes','8192']),0)
            self.assertEqual(run.call_args.kwargs,{'cas_directory':Path('cas'),'cas_max_object_bytes':4096,'cas_max_total_bytes':8192})


if __name__=='__main__':unittest.main()
