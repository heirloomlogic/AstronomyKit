from fractions import Fraction as Q
import contextlib
import io
import json
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

import certify_light_time as certify
import apparent_bounds


class FiniteConvergenceTests(unittest.TestCase):
    def test_check_reconstructs_every_iteration_after_a_saved_record_is_deleted(self):
        saved = json.loads(Path(__file__).with_name('derived-light-convergence.json').read_text())
        del saved['records'][0]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'omitted-iteration.json'
            path.write_text(json.dumps(saved))
            with patch('sys.argv', ['certify_light_time.py', '--check', '--output', str(path)]), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(SystemExit, 'canonical coverage'):
                    certify.main()

    def test_source_iteration_change_cannot_reuse_the_derived_certificate(self):
        original = Path.read_text
        def changed(path, *args, **kwargs):
            text = original(path, *args, **kwargs)
            if path.name == 'EngineApparentPlace.swift':
                return text.replace('4 * nextDelay.ulp', '8 * nextDelay.ulp')
            return text
        with patch.object(Path, 'read_text', changed):
            with self.assertRaisesRegex(ValueError, 'stop expression'):
                certify.constants()

    def test_contraction_reaches_the_delay_ulp_floor_within_the_native_cap(self):
        bounds = certify.constants()
        iteration = int(bounds['exactReturnEvaluations'])
        self.assertGreater(iteration, 1)
        self.assertLessEqual(iteration, 20)
        self.assertLess(bounds['T'] * bounds['k']**(iteration-1), bounds['stopFloorDays'])
        self.assertGreaterEqual(bounds['T'] * bounds['k']**(iteration-2), bounds['stopFloorDays'])
        self.assertGreater(bounds['successfulRootErrorDays'], bounds['successfulResidualDays'])

    def test_source_enclosure_rejects_exterior_not_truncated_records(self):
        with self.assertRaisesRegex(ValueError, 'coverage'):
            apparent_bounds.solar_bounds(Q(-1462000), Q(0))
        bounds = apparent_bounds.solar_bounds()
        self.assertEqual(bounds['recordCount'], bounds['lastRecord'] - bounds['firstRecord'] + 1)
        self.assertGreater(bounds['recordCount'], 4600)
        self.assertGreater(bounds['speedTT'], bounds['speedTDB'])

    def test_deleting_a_clock_term_fails_closed(self):
        original = Path.read_text
        def changed(path, *args, **kwargs):
            text = original(path, *args, **kwargs)
            if path.name == 'TDBTerms.swift':
                import re
                return re.sub(r'Term\([^)]*\),?', '', text, count=1)
            return text
        with patch.object(Path, 'read_text', changed):
            with self.assertRaisesRegex(ValueError, 'coefficient layout'):
                apparent_bounds.clock_bounds()


if __name__ == '__main__':
    unittest.main()
