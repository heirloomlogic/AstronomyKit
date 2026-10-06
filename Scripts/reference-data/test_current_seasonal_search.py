import copy
import importlib.util
import json
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("current_seasons", Path(__file__).with_name("check-current-seasonal-search.py"))
C = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(C)


class CurrentSeasonalInputs(unittest.TestCase):
    def test_api_comment_classification_rejects_actual_coordinate_code_change(self):
        from unittest import mock
        saved = json.loads(C.S.REPORT.read_text())
        read = Path.read_bytes
        coordinate = C.ROOT / 'Sources/AstronomyKit/Coordinates.swift'
        def changed(path):
            return read(path) + b'\nfunc unexpectedExecutableChange() {}\n' if path == coordinate else read(path)
        with mock.patch.object(Path, 'read_bytes', changed):
            current = {'inputSHA256': C.S.source_hashes()}
            with self.assertRaisesRegex(ValueError, 'coordinate implementation'):
                C.validate_inputs(saved, current)

    def test_actual_inputs_and_tampered_population_hashes(self):
        saved = json.loads(C.S.REPORT.read_text())
        current = {'inputSHA256': C.S.source_hashes()}
        C.validate_inputs(saved, current)
        for path in ['Sources/CLibAstronomy/astronomy.c', 'Scripts/reference-data/qualify-seasonal-roots.py']:
            mutated = copy.deepcopy(current)
            mutated['inputSHA256'][path] = '0' * 64
            with self.assertRaisesRegex(ValueError, 'actual files'):
                C.validate_inputs(saved, mutated)
        for mutation in ['missing', 'extra']:
            mutated = copy.deepcopy(current)
            if mutation == 'missing':
                mutated['inputSHA256'].pop('Sources/CLibAstronomy/astronomy.c')
            else:
                mutated['inputSHA256']['unapproved'] = '0' * 64
            with self.assertRaisesRegex(ValueError, 'actual files'):
                C.validate_inputs(saved, mutated)

    def test_complete_map_includes_generated_coefficients(self):
        complete = C.complete_sources()
        coefficient_paths = {str(p.relative_to(C.ROOT)) for p in (C.ROOT / 'Sources/CLibAstronomy').rglob('*.inc')}
        self.assertTrue(coefficient_paths)
        self.assertTrue(coefficient_paths <= set(complete))
        for path in coefficient_paths:
            self.assertEqual(complete[path], C.S.Q.digest((C.ROOT / path).read_bytes()))

    def test_stale_runner_cannot_claim_changed_generated_inputs(self):
        from unittest import mock
        saved = json.loads(C.S.REPORT.read_text())
        packet = copy.deepcopy(saved)
        packet['inputSHA256'] = C.S.source_hashes()
        changed = C.complete_sources()
        generated = next(p for p in changed if p.endswith('.inc'))
        changed[generated] = '0' * 64
        # The assessment is valid and unchanged, but no build authenticates the changed map.
        with mock.patch.object(C, 'complete_sources', return_value=changed), mock.patch.object(C.S, 'assess', return_value=packet), mock.patch.object(C, 'validate_inputs'), mock.patch.object(Path, 'write_text'), mock.patch.object(C.S, 'validate_replay'):
            with self.assertRaises(ValueError):
                C.check()

    def test_stale_source_binary_recipe_and_runner_are_rejected_before_use(self):
        from unittest import mock
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'runner'
            binary.write_bytes(b'authenticated executable')
            receipt = {'classification': 'fresh-current-copied-source-build', 'completeCurrentSourceSHA256': C.complete_sources(), 'runnerSourceSHA256': C.runner_sources(), 'manifestSHA256': C.S.Q.digest(C.B.MANIFEST.encode()), 'buildRecipeSHA256': C.S.Q.digest(Path(C.__file__).read_bytes()), 'manifestProviderSHA256': C.S.Q.digest(Path(C.B.__file__).read_bytes()), 'flags': [], 'binarySHA256': C.S.Q.digest(binary.read_bytes())}
            C.validate_build_link(binary, receipt)
            for field in ['completeCurrentSourceSHA256', 'runnerSourceSHA256', 'manifestSHA256', 'binarySHA256', 'buildRecipeSHA256']:
                changed = copy.deepcopy(receipt)
                changed[field] = {} if isinstance(changed[field], dict) else '0' * 64
                with self.assertRaises(ValueError):
                    C.validate_build_link(binary, changed)
            generated = next(p for p in receipt['completeCurrentSourceSHA256'] if p.endswith('.inc'))
            changed_sources = copy.deepcopy(receipt['completeCurrentSourceSHA256'])
            changed_sources[generated] = '0' * 64
            with mock.patch.object(C, 'complete_sources', return_value=changed_sources):
                with self.assertRaisesRegex(ValueError, 'stale'):
                    C.validate_build_link(binary, receipt)
            binary.write_bytes(b'replaced executable')
            with self.assertRaisesRegex(ValueError, 'executable changed'):
                C.validate_build_link(binary, receipt)

    def test_check_rejects_stale_built_source_before_assessment(self):
        from unittest import mock
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'runner'
            binary.write_bytes(b'old executable')
            receipt = {'classification': 'fresh-current-copied-source-build', 'completeCurrentSourceSHA256': C.complete_sources(), 'runnerSourceSHA256': C.runner_sources()}
            generated = next(p for p in receipt['completeCurrentSourceSHA256'] if p.endswith('.inc'))
            receipt['completeCurrentSourceSHA256'][generated] = '0' * 64
            with mock.patch.object(C, 'build_current', return_value=(binary, receipt)), mock.patch.object(C.S, 'assess') as assess:
                with self.assertRaisesRegex(ValueError, 'stale'):
                    C.check()
            assess.assert_not_called()

    def test_actual_assessor_uses_private_manifest_without_legacy_package(self):
        from unittest import mock
        import tempfile
        saved = json.loads(C.S.REPORT.read_text())
        plan = json.loads(C.S.PLAN.read_text())
        source = C.S.source_hashes()
        references = {mode: [e['reference'] for e in saved['events'] if e['mode'] == mode and e['deltaTModel'] == plan['publicDeltaTModels'][0]] for mode in ['nominal', 'matched']}
        requests, results = [], []
        for model in plan['publicDeltaTModels']:
            for year in range(plan['selection']['firstYear'], plan['selection']['lastYear'] + 1):
                request = {'operation': 'seasonal-roots', 'year': year, 'deltaTModel': model}
                requests.append(request)
                results.append({'request': request, 'status': 'success', 'events': [e['actual'] for e in saved['events'] if e['mode'] == 'nominal' and e['deltaTModel'] == model and e['year'] == year]})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def private_build(work, output):
                package = work / 'package'
                package.mkdir()
                (package / 'Package.swift').write_text(C.B.MANIFEST)
                binary = work / 'runner'
                binary.write_bytes(b'isolated test executable')
                return binary, {'manifestSHA256': C.S.Q.digest(C.B.MANIFEST.encode()), 'completeCurrentSourceSHA256': {}, 'revision': 'test revision'}
            legacy = root / '.context/accuracy-qualification/runner-package/Package.swift'
            self.assertFalse(legacy.exists())
            with mock.patch.object(C, 'ROOT', root), mock.patch.object(C.S, 'ROOT', root), mock.patch.object(C, 'build_current', side_effect=private_build), mock.patch.object(C, 'validate_build_link'), mock.patch.object(C, 'validate_inputs'), mock.patch.object(C.S, 'load_plan', return_value=plan), mock.patch.object(C.S, 'references', side_effect=lambda mode: (references[mode], [])), mock.patch.object(C.S, 'public_results', return_value=(requests, results)) as scientific, mock.patch.object(C.S, 'source_hashes', return_value=source), mock.patch.object(C.S.G, 'environment', return_value={}), mock.patch.object(C.S.subprocess, 'check_output', return_value='test identity'), mock.patch.object(C.S, 'validate_replay'):
                output = C.check()
            scientific.assert_called_once()
            measured = json.loads((output / 'assessment.json').read_text())
            self.assertEqual(len(measured['events']), 3696)
            self.assertEqual(measured['publicRunner']['isolatedManifestSHA256'], C.S.Q.digest(C.B.MANIFEST.encode()))
            self.assertTrue((output / 'execution-receipt.json').is_file())
            self.assertFalse(legacy.exists())

    def test_invalid_private_manifest_rejects_before_scientific_execution(self):
        from unittest import mock
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            def detached_build(work, output):
                package = work / 'package'
                package.mkdir()
                (package / 'Package.swift').write_text('detached manifest')
                binary = work / 'runner'
                binary.write_bytes(b'test executable')
                receipt = {'classification': 'fresh-current-copied-source-build', 'completeCurrentSourceSHA256': C.complete_sources(), 'runnerSourceSHA256': C.runner_sources(), 'manifestSHA256': C.S.Q.digest(C.B.MANIFEST.encode()), 'buildRecipeSHA256': C.S.Q.digest(Path(C.__file__).read_bytes()), 'manifestProviderSHA256': C.S.Q.digest(Path(C.B.__file__).read_bytes()), 'flags': [], 'binarySHA256': C.S.Q.digest(binary.read_bytes())}
                return binary, receipt
            with mock.patch.object(C, 'build_current', side_effect=detached_build), mock.patch.object(C.S, 'public_results') as scientific:
                with self.assertRaisesRegex(ValueError, 'private build manifest detached'):
                    C.check()
            scientific.assert_not_called()
            with mock.patch.object(C.S, 'public_results') as scientific, mock.patch.object(C.S, 'references') as reference:
                with self.assertRaises(FileNotFoundError):
                    C.S.assess(Path(directory) / 'unused runner', manifest=Path(directory) / 'missing-private-manifest')
            scientific.assert_not_called()
            reference.assert_not_called()
