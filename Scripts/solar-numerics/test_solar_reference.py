import unittest
import solar_reference as solar


class SolarDefinitionTests(unittest.TestCase):
    def test_exact_public_scalar_and_civil_epoch(self):
        mp = solar.mp
        for model in ['espenakMeeus', 'jplHorizons']:
            ut, tt = solar.input_pair(0.1, 'ut', model, 0.1)
            self.assertEqual(ut, solar.ref.exact(0.1))
            self.assertEqual(tt, ut+solar.ref.delta_t(ut,model)/86400)
            civil_ut, civil_tt = solar.input_pair(0.0, 'date', model, 365.5)
            self.assertEqual(civil_tt, mp.mpf('365.5')+mp.mpf('64.184')/86400)
            self.assertLess(abs(civil_ut+solar.ref.delta_t(civil_ut,model)/86400-civil_tt), mp.mpf('1e-65'))

    def test_positive_gap_has_no_mathematical_inverse(self):
        mp = solar.mp
        boundary = solar.ref.year_start(1941)
        left = boundary+solar.ref.delta_t(boundary-mp.mpf('1e-30'))/86400
        right = boundary+solar.ref.delta_t(boundary)/86400
        value = float((left+right)/2)
        self.assertGreater(solar.ref.exact(value), left)
        self.assertLess(solar.ref.exact(value), right)
        for model in ['espenakMeeus', 'jplHorizons']:
            self.assertIsNone(solar.input_pair(value, 'tt', model, float(boundary)))

    def test_sofa_precession_matrix(self):
        mp = solar.mp
        actual = solar.precession(mp.mpf('50123.9999') - mp.mpf('51544.5'))
        expected = [
            ['0.9999995504864960278', '0.8696112578855404832e-3', '0.3778929293341390127e-3'],
            ['-0.8696112560510186244e-3', '0.9999996218880458820', '-0.1691646168941896285e-6'],
            ['-0.3778929335557603418e-3', '-0.1594554040786495076e-6', '0.9999999285984501222'],
        ]
        # EnginePrecessionTests uses 1e-13 for this Fukushima-Williams route;
        # its documented difference from the IERS angle product is about 3e-14.
        for i in range(3):
            for j in range(3):
                self.assertLess(abs(actual[i,j] - mp.mpf(expected[i][j])), mp.mpf('1e-13'))

    def test_sofa_complementary_terms(self):
        mp = solar.mp
        self.assertLess(abs(solar.complementary(mp.mpf('2191.5')) - mp.mpf('0.2046085004885125264e-8')), mp.mpf('1e-20'))

    def test_sofa_mean_sidereal_time(self):
        mp = solar.mp
        self.assertLess(abs(solar.mean_sidereal(mp.mpf('2191.5'), mp.mpf('2191.5')) * mp.pi / 180 - mp.mpf('1.754174971870091203')), mp.mpf('1e-12'))

    def test_full_altitude_converges_at_the_backdated_step(self):
        mp = solar.mp
        altitudes = []
        for precision in [80, 110]:
            with mp.workdps(precision):
                u = solar.ref.exact(1826.5056790659519)
                tt = u + solar.ref.delta_t(u) / 86400
                result = solar.Solar().altitude(u, tt, 'espenakMeeus', [-33.87, 151.21, -10000.0])
                self.assertEqual(len(result['trace']), 3)
                altitudes.append(result['altitude'])
        with mp.workdps(110):
            self.assertLess(abs(altitudes[0] - altitudes[1]), mp.mpf('1e-65'))

    def test_backdate_crosses_the_2005_step_at_extended_precision(self):
        mp = solar.mp
        values = []
        for precision in [80, 110]:
            with mp.workdps(precision):
                u = solar.ref.exact(1826.5056790659519)
                result = solar.Solar().geocentric(u, u + solar.ref.delta_t(u) / 86400, 'espenakMeeus')
                self.assertEqual(len(result['trace']), 3)
                self.assertLess(result['trace'][1]['nextUT'], mp.mpf('1826.5'))
                values.append(result['vector'])
        with mp.workdps(110):
            self.assertLess(max(abs(a-b) for a,b in zip(*values)), mp.mpf('1e-70'))


if __name__ == '__main__':
    unittest.main()
