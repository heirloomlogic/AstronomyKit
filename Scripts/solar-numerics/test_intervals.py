from fractions import Fraction as Q
import unittest

from intervals import Interval, DeltaT, Earth, expression
import solar_reference as solar


class IntervalTests(unittest.TestCase):
    def test_arithmetic_encloses_exact_rationals(self):
        a, b = Interval(Q(1, 3), Q(2, 3)), Interval(-7, -2)
        for x in [a.lo, a.hi, Q(1, 2)]:
            for y in [b.lo, b.hi, Q(-3)]:
                for result, expected in [(a+b, x+y), (a*b, x*y), (a/b, x/y), (a**2, x*x)]:
                    self.assertLessEqual(result.lo, expected)
                    self.assertGreaterEqual(result.hi, expected)
        self.assertEqual((Interval(-2, 3)**2).lo, 0)
        with self.assertRaises(ValueError):
            a / Interval(-1, 1)

    def test_square_root_enclosure_is_verified_by_integer_arithmetic(self):
        root = Interval(2, 3).sqrt()
        self.assertLessEqual(root.lo**2, 2)
        self.assertGreaterEqual(root.hi**2, 3)

    def test_swift_decimal_tokens_are_exact_and_unknown_operations_fail(self):
        result = expression('0.1 + p.u2 / 233', {'u': Interval(7)})
        self.assertLessEqual(result.lo, Q('0.1')+Q(49,233))
        self.assertGreaterEqual(result.hi, Q('0.1')+Q(49,233))
        with self.assertRaises(ValueError):
            expression('sin(u)', {'u': Interval(0)})

    def test_delta_t_hull_includes_both_sides_of_negative_step(self):
        model = DeltaT()
        value = model.seconds(Interval(Q('1826.5')-Q(1,10**30), Q('1826.5')), 'espenakMeeus')
        self.assertLess(value.lo, Q('64.671'))
        self.assertGreater(value.hi, Q('64.720'))

    def test_earth_interval_contains_independent_extended_precision_value(self):
        t = Q('1826.500748')
        actual = Earth().position(Interval(t))
        expected = solar.equatorial_earth(solar.Solar().earth.position(solar.mp.mpf(t.numerator)/t.denominator))
        for interval, value in zip(actual, expected):
            self.assertLessEqual(solar.mp.mpf(interval.lo.numerator)/interval.lo.denominator, value)
            self.assertGreaterEqual(solar.mp.mpf(interval.hi.numerator)/interval.hi.denominator, value)


if __name__ == '__main__':
    unittest.main()
