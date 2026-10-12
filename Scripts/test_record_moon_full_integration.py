import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('moon_integration', Path(__file__).with_name('record-moon-full-integration.py'))
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)


class MoonIntegrationEvidenceTests(unittest.TestCase):
    def candidate(self):
        archive = json.loads((tool.ROOT / 'Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json').read_bytes())
        captures = {}
        for configuration in ('debug', 'release'):
            captures['differential-' + configuration] = dict(samples=1365, integratedSamples=1360, maximumPositionKm=0,
                maximumRateKmPerTDBDay=0, maximumIntegratedRateKmPerTTDay=0, maximumIntegratedAngleArcminutes=0,
                maximumIntegratedDistanceKm=0, maximumLongitudeArcminutes=0, maximumLatitudeArcminutes=0)
            captures['boundaries-' + configuration] = dict(boundaries=730501, maximumPositionJumpAU=0, maximumRateJumpAUPerTDBDay=0)
            captures['horizons-' + configuration] = [dict(julianDateTDB=row['julianDateTDB'], angleArcminutes=0, distanceKm=0) for row in archive['vectors'] if row['body'] == 'moon']
        captures['measurement-release'] = dict(evaluationsPerWorkload=20000, seconds=dict(outer=1, central=1), coldSeconds=0)
        return captures

    def test_complete_candidate_passes(self):
        tool.validate(self.candidate())

    def test_missing_extra_empty_and_duplicate_inventories_fail(self):
        original = self.candidate()
        changes = [lambda c: c.pop('boundaries-debug'), lambda c: c.update(extra={}),
                   lambda c: c.update({'horizons-debug': []}),
                   lambda c: c['horizons-debug'].__setitem__(1, c['horizons-debug'][0]),
                   lambda c: c['horizons-debug'][0].update(julianDateTDB=0),
                   lambda c: c['boundaries-release'].update(boundaries=730500),
                   lambda c: c['differential-debug'].update(samples=0)]
        for change in changes:
            candidate = copy.deepcopy(original); change(candidate)
            with self.assertRaises(ValueError): tool.validate(candidate)

    def test_acceptance_and_nonfinite_controls_fail(self):
        for field, value in [('angleArcminutes', 1.001), ('distanceKm', 28.690), ('angleArcminutes', float('nan'))]:
            candidate = self.candidate();candidate['horizons-release'][0][field] = value
            with self.assertRaises(ValueError): tool.validate(candidate)
        candidate = self.candidate();candidate['differential-debug']['maximumPositionKm'] = 1e-7
        with self.assertRaises(ValueError): tool.validate(candidate)

    def test_transitive_ownership_includes_actual_public_and_padding_routes(self):
        paths = tool.source_paths()
        self.assertEqual(len(paths), len(set(paths)))
        for name in ['Sources/AstronomyKit/Engine/Positions/EngineApparentComposition.swift',
                     'Sources/AstronomyKit/Engine/Moon/EngineMoonStates.swift',
                     'Sources/AstronomyKit/MoonPhase.swift',
                     'Tests/AstronomyKitTests/Engine/Moon/EngineMoonFullIntegrationTests.swift']:
            self.assertIn(name, paths)
        self.assertNotIn('Sources/AstronomyKit/Engine/Moon/EngineMoonDE441.swift', paths)

    def test_omitted_source_binding_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'evidence.json'
            path.write_text(json.dumps({'sourceSHA256': {'omitted.swift': '0' * 64}}))
            with self.assertRaisesRegex(ValueError, 'source binding coverage differs'):
                tool.events.check_source_hashes(path, required_sources=tool.source_paths())
