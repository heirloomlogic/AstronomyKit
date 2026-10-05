import copy
import gzip
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock
import shutil
import tempfile

SPEC = importlib.util.spec_from_file_location("repair", Path(__file__).with_name("check_current_search.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)


class CurrentSearchTests(unittest.TestCase):
    def test_population_and_named_outcome_are_not_blanket_exceptions(self):
        original, _, _ = R.M.load_archive()
        supplement = R.load_supplement()
        cases = R.M.protocol()["cases"] + R.M.supplement_protocol()["cases"]
        saved = {m: original[m]["swift"] + supplement[m]["swift"] for m in R.M.protocol()["models"]}
        with self.assertRaisesRegex(ValueError, "did not reject"):
            R.compare(saved, saved, cases)
        dropped = copy.deepcopy(saved)
        dropped["espenak-meeus"].pop()
        with self.assertRaisesRegex(ValueError, "population"):
            R.compare(saved, dropped, cases)
        with self.assertRaisesRegex(ValueError, "population"):
            R.compare(saved, saved, cases[:-1])

    def test_live_source_change_population(self):
        actual = R.source_identity()
        original = R.baseline_sources()
        self.assertEqual([p for p in actual if actual[p] != original[p]], ["Sources/CLibAstronomy/astronomy.c"])

    def test_authenticated_supplement_and_rehashed_mutation(self):
        R.load_supplement()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "supplement"
            shutil.copytree(R.M.SUPPLEMENT, root)
            raw = root / "raw-runs.json.gz"
            raw.write_bytes(gzip.compress(b"{}"))
            with self.assertRaisesRegex(ValueError, "artifact detached"):
                R.load_supplement(root)
            manifest = json.loads((root / "manifest.json").read_text())
            manifest["filesSHA256"][raw.name] = R.M.sha(raw.read_bytes())
            (root / "manifest.json").write_text(R.M.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "immutable identity"):
                R.load_supplement(root)

    def test_unchanged_trace_mutations_are_rejected(self):
        events = [{"event": "callback", "time": {"ut": R.M.packet(20000.0)}, "value": R.M.packet(1.0)}, {"event": "terminal", "outcome": "absent"}]
        R.compare_events(events, copy.deepcopy(events))
        for changed in [events[::-1], events[:-1], [{"event": "callback", "time": {"ut": R.M.packet(20001.0)}, "value": R.M.packet(1.0)}, events[-1]], [events[0], {"event": "terminal", "outcome": "value"}]]:
            with self.assertRaises(ValueError):
                R.compare_events(events, changed)


    def test_generated_input_hash_missing_and_extra_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Sources/CLibAstronomy').mkdir(parents=True)
            (root / 'Sources/AstronomyKit').mkdir()
            solver = root / 'Sources/CLibAstronomy/astronomy.c'
            coefficient = root / 'Sources/CLibAstronomy/model.inc'
            solver.write_text('repaired solver')
            coefficient.write_text('immutable coefficients')
            original = {'Sources/CLibAstronomy/astronomy.c': R.M.sha(b'old solver'), 'Sources/CLibAstronomy/model.inc': R.M.sha(coefficient.read_bytes())}
            plan = R.selection()
            with mock.patch.object(R, 'ROOT', root), mock.patch.object(R, 'baseline_sources', return_value=original), mock.patch.object(R, 'selection', return_value=plan):
                R.source_identity()
                coefficient.write_text('tampered coefficients')
                with self.assertRaisesRegex(ValueError, 'source changes'):
                    R.source_identity()
                coefficient.unlink()
                with self.assertRaisesRegex(ValueError, 'source changes'):
                    R.source_identity()
                coefficient.write_text('immutable coefficients')
                (root / 'Sources/CLibAstronomy/extra.inc').write_text('extra')
                with self.assertRaisesRegex(ValueError, 'source changes'):
                    R.source_identity()
    def test_retained_repair_evidence_is_bound_and_semantically_recomputed(self):
        directory = R.ROOT / 'Tools/Migration/SearchRepair/Evidence'
        manifest_bytes = (directory / 'manifest.json').read_bytes()
        self.assertEqual(R.M.sha(manifest_bytes), 'c4ea6b4c06ad38771516c715a8274e4263516eec95816895a2b13fa679086465')
        manifest = json.loads(manifest_bytes)
        self.assertEqual({p.name for p in directory.iterdir()}, set(manifest['filesSHA256']) | {'manifest.json'})
        for name, digest in manifest['filesSHA256'].items():
            self.assertEqual(R.M.sha((directory / name).read_bytes()), digest)
        current = json.loads(gzip.decompress((directory / 'callback-raw-runs.json.gz').read_bytes()))
        original, _, _ = R.M.load_archive()
        supplement = R.load_supplement()
        cases = R.M.protocol()['cases'] + R.M.supplement_protocol()['cases']
        saved = {m: original[m]['swift'] + supplement[m]['swift'] for m in R.M.protocol()['models']}
        changes = R.compare(saved, current, cases)
        report = json.loads((directory / 'callback-assessment.json').read_text())
        self.assertEqual(report['namedChanges'], changes)
        self.assertEqual(report['processes'], 106)
        self.assertEqual(report['rawSHA256'], manifest['filesSHA256']['callback-raw-runs.json.gz'])
        receipt = json.loads((directory / 'callback-build-receipt.json').read_text())
        self.assertEqual(receipt['revision'], manifest['repairSourceRevision'])
        self.assertIs(receipt['trackedTreeDirty'], False)
        expected_population = set(R.baseline_sources())
        self.assertEqual(set(receipt['sourceSHA256']), expected_population)
        for path, digest in receipt['sourceSHA256'].items():
            self.assertEqual(R.M.sha(R.M.git_bytes(receipt['revision'], path)), digest)
        self.assertEqual(receipt['validatorSHA256'], R.M.sha(R.M.git_bytes(receipt['revision'], 'Scripts/migration/check_current_search.py')))
        self.assertEqual(receipt['adapterSHA256'], R.M.sha((R.M.HOME / 'main.swift').read_bytes()))
        self.assertEqual(receipt['manifestSHA256'], R.M.sha(R.M.MANIFEST.encode()))
        self.assertEqual(receipt['flags'], json.loads(R.M.LOCK.read_text())['build']['flags'])
        base = json.loads(gzip.decompress((directory / 'migration-base.json.gz').read_bytes()))
        candidate = json.loads(gzip.decompress((directory / 'migration-current.json.gz').read_bytes()))
        for field in ['cases', 'cOutputs', 'swiftOutputs', 'comparisons', 'failed']:
            self.assertEqual(base[field], candidate[field])
        self.assertEqual(len(base['cases']), 18)
        self.assertEqual(base['failed'], ['pluto-position-em', 'pluto-state-jpl'])

    def test_existing_destination_rejects_before_build_or_process(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / '.context/current-search-repair'
            output.mkdir(parents=True)
            sentinel = output / 'prior-packets'
            sentinel.write_text('preserved')
            with mock.patch.object(R, 'ROOT', root), mock.patch.object(R, 'selection'), mock.patch.object(R, 'load_supplement', return_value={m: {'swift': []} for m in R.M.protocol()['models']}), mock.patch.object(R.M, 'load_archive', return_value=({m: {'swift': []} for m in R.M.protocol()['models']}, None, None)), mock.patch.object(R, 'build', return_value=(root / 'binary', {})) as build, mock.patch.object(R.M, 'run_command', return_value={}) as process:
                with self.assertRaises(FileExistsError):
                    R.check()
            build.assert_not_called()
            process.assert_not_called()
            self.assertEqual(sentinel.read_text(), 'preserved')

    def test_process_exception_preserves_every_completed_packet(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.context').mkdir()
            output = root / '.context/attempt'
            models = R.M.protocol()['models']
            import sys
            partial = R.M.run_command([sys.executable, '-c', "import sys; print('partial observation'); print('process failed', file=sys.stderr); sys.exit(3)"], 5)
            self.assertEqual(partial['termination'], 'process-error')
            self.assertEqual(partial['exitCode'], 3)
            with mock.patch.object(R, 'ROOT', root), mock.patch.object(R, 'selection'), mock.patch.object(R, 'load_supplement', return_value={m: {'swift': []} for m in models}), mock.patch.object(R.M, 'load_archive', return_value=({m: {'swift': []} for m in models}, None, None)), mock.patch.object(R, 'build', return_value=(root / 'binary', {})), mock.patch.object(R.M, 'run_command', side_effect=[partial, OSError('injected process failure')]), mock.patch.object(R, 'compare') as assess:
                with self.assertRaisesRegex(OSError, 'injected'):
                    R.check(output)
            saved = json.loads(gzip.decompress((output / 'raw-runs.json.gz').read_bytes()))
            self.assertEqual(len(saved[models[0]]), 1)
            self.assertEqual(saved[models[0]][0]['stdout'], partial['stdout'])
            self.assertEqual(json.loads((output / 'acquisition-error.json').read_text())['savedProcesses'], 1)
            assess.assert_not_called()
