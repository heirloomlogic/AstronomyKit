from fractions import Fraction as Q
import contextlib
import io
import json
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

import certify_light_time as certify
from intervals import Interval as I, DeltaT, Earth


class FiniteConvergenceTests(unittest.TestCase):
    def test_check_reconstructs_coverage_after_a_saved_strip_is_deleted(self):
        saved = json.loads(Path(__file__).with_name('derived-light-convergence.json').read_text())
        del saved['records'][0]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'omitted-strip.json'
            path.write_text(json.dumps(saved))
            with patch('sys.argv', ['certify_light_time.py', '--check', '--output', str(path)]), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(SystemExit, 'canonical coverage'):
                    certify.main()

    def test_float_lattice_endpoints_are_exact(self):
        # Decimal 0.1 lies strictly below its closest binary64 number.
        exact = Q('0.1')
        self.assertEqual(certify.float_candidates(I(exact-Q(1,10**30), exact+Q(1,10**30))), [])
        first = 0.1
        self.assertEqual(certify.float_candidates(I(Q(first))), [first])
        self.assertEqual(certify.float_candidates(I(-Q(first))), [-first])

    def test_source_iteration_change_cannot_reuse_the_derived_certificate(self):
        original = Path.read_text
        def changed(path, *args, **kwargs):
            text = original(path, *args, **kwargs)
            if path.name == 'EngineSearch.swift':
                return text.replace('abs(next.tt - backdated.tt) < 1.0e-9', 'abs(next.tt - backdated.tt) < 1.0e-8')
            return text
        with patch.object(Path, 'read_text', changed):
            with self.assertRaisesRegex(ValueError, 'stop expression'):
                certify.constants()

    def test_real_cycle_enclosure_remains_unresolved(self):
        delta, earth = DeltaT(), Earth()
        # P94's 80/110/140-digit cycling midpoint. This is a real-input
        # diagnostic, not a representable public-input counterexample.
        value = I(Q('1826.5056790659519832235243111659781243807860857682570480399333208'))
        iteration, trace = certify.successful_return(value, delta.forward(value, 'espenakMeeus'), 'espenakMeeus', delta, earth)
        self.assertIsNone(iteration)
        self.assertEqual(len(trace), 10)

    def test_representable_neighbor_has_a_strict_interval_stop_certificate(self):
        delta, earth = DeltaT(), Earth()
        value = I(Q(1826.5056790659519))
        iteration, trace = certify.successful_return(value, delta.forward(value, 'espenakMeeus'), 'espenakMeeus', delta, earth)
        self.assertEqual(iteration, 3)
        self.assertLess(trace[-1], certify.TAU)


if __name__ == '__main__':
    unittest.main()
