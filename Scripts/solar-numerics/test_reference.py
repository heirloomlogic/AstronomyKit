from fractions import Fraction as Q
import unittest

import reference


class DefinitionTests(unittest.TestCase):
    def test_era_j2000_and_turn(self):
        mp = reference.mp
        self.assertLess(abs(reference.era(mp.mpf(0)) - mp.mpf("280.46061837504")), mp.mpf("1e-65"))
        step = mp.mpf(1) / mp.mpf("1.00273781191135448")
        self.assertLess(abs(reference.era(step) - reference.era(mp.mpf(0))), mp.mpf("1e-65"))

    def test_nasa_polynomial_values_and_calendar_boundary(self):
        mp = reference.mp
        for year, delta in [(1900, "-2.79"), (1920, "21.20"), (2000, "63.86"), (2050, "93")]:
            self.assertLess(abs(reference.delta_t(reference.year_start(year)) - mp.mpf(delta)), mp.mpf("1e-65"))
        before = reference.year_start(2000) - mp.mpf("1e-20")
        self.assertLess(reference.decimal_year(before), 2000)
        self.assertEqual(reference.decimal_year(reference.year_start(2000)), 2000)

    def test_exact_binary_input_is_not_decimal_shortening(self):
        mp = reference.mp
        self.assertEqual(reference.exact(0.1), mp.mpf(Q(0.1).numerator) / Q(0.1).denominator)
        self.assertNotEqual(reference.exact(0.1), mp.mpf("0.1"))

    def test_sofa_published_nutation(self):
        mp = reference.mp
        dpsi, deps = reference.nutation(mp.mpf("2191.5"))
        self.assertLess(abs(dpsi * mp.pi / 180 - mp.mpf("-0.9632552291148362783e-5")), mp.mpf("1e-13"))
        self.assertLess(abs(deps * mp.pi / 180 - mp.mpf("0.4063197106621159367e-4")), mp.mpf("1e-13"))

    def test_imcce_published_earth_at_j2000(self):
        mp = reference.mp
        x, y, z = reference.Earth().series(mp.mpf(0))
        radius = mp.sqrt(x*x + y*y + z*z)
        self.assertLess(abs(mp.atan2(y, x) - mp.mpf("1.7519238637")), mp.mpf("1e-10"))
        self.assertLess(abs(mp.asin(z/radius) - mp.mpf("-0.0000039656")), mp.mpf("1e-10"))
        self.assertLess(abs(radius - mp.mpf("0.9833276823")), mp.mpf("1e-10"))

    def test_extended_precision_converges_for_the_sampled_primitives(self):
        mp = reference.mp
        earth = reference.Earth()
        for value in [-36524.5, 0.0, 36889.5]:
            with mp.workdps(80):
                lower = [reference.era(reference.exact(value)), reference.delta_t(reference.exact(value)),
                         *reference.nutation(reference.exact(value)), *earth.position(reference.exact(value))]
            with mp.workdps(110):
                higher = [reference.era(reference.exact(value)), reference.delta_t(reference.exact(value)),
                          *reference.nutation(reference.exact(value)), *earth.position(reference.exact(value))]
                self.assertLess(max(abs(a-b) for a, b in zip(lower, higher)), mp.mpf("1e-70"))

    def test_chebyshev_definition(self):
        mp = reference.mp
        coefficients = [mp.mpf(2), mp.mpf(-3), mp.mpf(5)]
        self.assertEqual(reference.polynomial(coefficients, mp.mpf(1)), 4)
        self.assertEqual(reference.polynomial(coefficients, mp.mpf(-1)), 10)
        self.assertEqual(reference.polynomial(coefficients, mp.mpf(0)), -3)


if __name__ == "__main__":
    unittest.main()
