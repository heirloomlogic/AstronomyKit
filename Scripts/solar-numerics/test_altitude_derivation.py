from fractions import Fraction as Q
import contextlib
import io
from pathlib import Path
import unittest
from unittest.mock import patch

import derive_altitude as derive


class AltitudeDerivationTests(unittest.TestCase):
    def test_generated_constants_enclose_exact_terms(self):
        result = derive.derive()
        for name, term in result['terms'].items():
            self.assertGreaterEqual(Q(term['binary64']), Q(term['rational']), name)
        self.assertLess(Q(result['classificationGuard']['derivedForwardErrorDays']), Q('5e-12'))
        self.assertLess(Q(result['nativeRadiusGuard']['delayUpperDays']), Q('.006'))

    def test_decimal_year_clamp_change_invalidates_guard(self):
        original = Path.read_text
        def changed(path, *args, **kwargs):
            text = original(path, *args, **kwargs)
            if path.name == 'EngineDeltaT.swift':
                return text.replace('min(decimal, (year + 1).nextDown)', 'decimal')
            return text
        with patch.object(Path, 'read_text', changed):
            with self.assertRaisesRegex(ValueError, 'boundary clamp'):
                derive.classification_guard()

    def test_check_rejects_altered_generated_constant(self):
        original = Path.read_text
        def changed(path, *args, **kwargs):
            text = original(path, *args, **kwargs)
            if path.name == 'SolarAltitudeBounds.swift':
                return text.replace('static let eraDegrees =', 'static let alteredEraDegrees =')
            return text
        with patch.object(Path, 'read_text', changed), patch('sys.argv', ['derive_altitude.py', '--check']), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(SystemExit, 'stale'):
                derive.main()


if __name__ == '__main__':
    unittest.main()
