from fractions import Fraction as Q
from pathlib import Path
import unittest
from unittest.mock import patch

from intervals import Interval as I
import precession_bounds as bounds
import solar_reference as solar


class LongTermBoundsTests(unittest.TestCase):
    def test_trigonometric_intervals_include_high_precision_values(self):
        mp = solar.mp
        for value in ['-1.7', '-0.4', '0', '0.4', '1.7']:
            point = I(Q(value))
            for cosine in [False, True]:
                enclosure = bounds.trig(point, cosine)
                expected = (mp.cos if cosine else mp.sin)(mp.mpf(value))
                exact = lambda v: mp.mpf(v.numerator)/v.denominator
                self.assertLessEqual(exact(enclosure.lo), expected)
                self.assertGreaterEqual(exact(enclosure.hi), expected)

    def test_changed_native_coefficients_are_rejected(self):
        original = Path.read_text
        def changed(path, *args, **kwargs):
            text = original(path, *args, **kwargs)
            if path.name == 'Vondrak2011Terms.swift':
                return text.replace('5851.607687', '5852.607687')
            return text
        with patch.object(Path, 'read_text', changed):
            with self.assertRaisesRegex(ValueError, 'differ from pinned source'):
                bounds.tables()

    def test_invalid_pole_radicand_is_rejected(self):
        data = bounds.tables()['equator']
        data[0][0][0] += 1000000
        with self.assertRaisesRegex(ValueError, 'radicand'):
            bounds.pole(I(0), data, bounds.pi_interval())

    def test_small_domain_derivative_bounds_cover_independent_model(self):
        mp = solar.mp
        result = bounds.enclose(Q('0.1'), Q('0.2'))
        self.assertGreater(result['crossNormLower'], Q('.39'))
        self.assertGreater(result['equatorRadicandLower'], Q('.99'))
        for t in ['-3652.5', '0', '3652.5']:
            tt = mp.mpf(t)
            rate = mp.diff(solar.precession, tt)
            frobenius = mp.sqrt(sum(x*x for x in rate))*180/mp.pi
            obliquity = abs(mp.diff(solar.obliquity, tt))*180/mp.pi
            self.assertLess(float(frobenius), float(result['precession']))
            self.assertLess(float(obliquity), float(result['meanObliquity']))


if __name__ == '__main__':
    unittest.main()
