"""Adversarial evidence-contract checks for the independent model diagnosis."""
import importlib.util
import json
import math
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

PATH = Path(__file__).with_name('outer-planet-diagnostic.py')
SPEC = importlib.util.spec_from_file_location('outer_planet_diagnostic', PATH)
DIAG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DIAG)


class OuterPlanetDiagnosticTests(unittest.TestCase):
    def test_official_check_values_match_to_printed_precision(self):
        rows = DIAG.published_checks()
        self.assertEqual(set(rows), {'Uranus', 'Neptune'})
        self.assertTrue(all(row['sampleCount'] == 10 for row in rows.values()))

    def test_frozen_epochs_reject_unregistered_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            original = json.loads((DIAG.RAW / 'epochs.json').read_bytes())
            original['julianDatesTT'][0] += 1
            (p / 'epochs.json').write_bytes(DIAG.encoded(original))
            with patch.object(DIAG, 'RAW', p), self.assertRaisesRegex(ValueError, 'epochs changed'):
                DIAG.dates()

    def test_reference_archive_hash_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            (p / 'data').write_bytes(b'changed')
            (p / 'data.recipe.json').write_bytes(DIAG.encoded({'sha256': DIAG.sha(b'original')}))
            with patch.object(DIAG, 'RAW', p), self.assertRaisesRegex(ValueError, 'hash mismatch'):
                DIAG.read_verified('data')

    def test_wrong_reference_center_is_rejected_before_measurement(self):
        data, recipe = DIAG.read_verified('uranus-barycenter.horizons.json')
        text = json.loads(data)
        text['result'] = text['result'].replace('Sun (10)', 'Earth (399)')
        with self.assertRaisesRegex(ValueError, 'target/center mismatch'):
            DIAG.parse_horizons(DIAG.encoded(text), recipe['parameters'], 'DE441')

    def test_wrong_solution_tag_is_rejected(self):
        data, recipe = DIAG.read_verified('neptune-barycenter.horizons.json')
        with self.assertRaisesRegex(ValueError, 'solution differs'):
            DIAG.parse_horizons(data, recipe['parameters'], 'DE200')

    def test_incomplete_epoch_reference_is_rejected(self):
        data, recipe = DIAG.read_verified('uranus-barycenter.horizons.json')
        envelope = json.loads(data)
        text = envelope['result']
        start, end = text.split('$$SOE', 1)
        rows, footer = end.split('$$EOE', 1)
        rows = rows.strip().splitlines()[1:]
        envelope['result'] = start + '$$SOE\n' + '\n'.join(rows) + '\n$$EOE' + footer
        with self.assertRaisesRegex(ValueError, 'epoch coverage mismatch'):
            DIAG.parse_horizons(DIAG.encoded(envelope), recipe['parameters'], 'DE441')

    def test_signed_radial_components_telescope_per_epoch(self):
        report = json.loads(DIAG.REPORT.read_bytes())
        self.assertEqual(len(report['rows']), 36)
        for row in report['rows']:
            self.assertAlmostEqual(row['rawMinusDE200RadiusKm'] + row['de200MinusDE441RadiusKm'], row['rawMinusDE441RadiusKm'], delta=1e-8)

    def check_tampered_report(self, mutate):
        expected = json.loads(DIAG.REPORT.read_bytes())
        previous = json.loads(DIAG.REPORT.read_bytes())
        mutate(previous)
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / 'report.json'
            # Use json.dumps here to permit deliberately malformed nonfinite input.
            report.write_text(json.dumps(previous))
            with patch.object(DIAG, 'REPORT', report), patch.object(DIAG, 'measure', return_value=expected), patch('sys.argv', ['diag', 'check']):
                with self.assertRaises(ValueError): DIAG.main()

    def test_tampered_summary_is_rejected(self):
        self.check_tampered_report(lambda r: r['summaries']['Uranus']['rawMinusDE200RadiusKm'].__setitem__('maxAbsolute', 0.))

    def test_tampered_frame_caveat_is_rejected(self):
        self.check_tampered_report(lambda r: r.__setitem__('vectorFrameCaveat', 'Fully aligned ICRF'))

    def test_tampered_report_epoch_is_rejected_even_below_numeric_allowance(self):
        self.check_tampered_report(lambda r: r['rows'][0].__setitem__('jdTT', r['rows'][0]['jdTT'] + .00001))

    def test_angular_summary_preserves_radian_reproduction_allowance(self):
        self.check_tampered_report(lambda r: r['summaries']['Uranus']['binary64Minus60DigitLongitudeRad'].__setitem__('maxAbsolute', .00001))

    def test_nonfinite_report_number_is_rejected(self):
        self.check_tampered_report(lambda r: r['rows'][0].__setitem__('rawMinusDE200RadiusKm', float('nan')))

    def test_de200_archive_uses_actual_native_frame_and_tdb(self):
        data, recipe = DIAG.read_verified('de200-states.json')
        refs = json.loads(data)
        self.assertEqual(recipe['nativeFrame'], 'DE-200 (14)')
        self.assertEqual(recipe['kernelTimeScale'], 'TDB')
        self.assertTrue(all(row['frame'] == 14 for row in refs['segments']))
        for row in refs['rows']:
            self.assertAlmostEqual(math.hypot(*row['positionAU']), math.hypot(*row['nativePositionAU']), delta=2e-14)
            self.assertLess(row['usingTTAsTDBVectorDifferenceKm'], .001)


if __name__ == '__main__':
    unittest.main()
