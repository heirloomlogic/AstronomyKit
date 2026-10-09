import importlib.util
from fractions import Fraction
import hashlib
import json
import random
import tempfile
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('pluto', Path(__file__).with_name('assess-pluto-de441.py'))
p = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(p)


class PlutoAssessmentTests(unittest.TestCase):
    def test_cubic_reproduces_position_and_physical_derivatives(self):
        axes = [(4., 2., -3., .5)] * 3
        left, right = p.nodes(axes, 32.)
        recovered = p.cubic(left, right, 32.)
        self.assertEqual(axes, recovered)
        for x in (-1., -.3, 0., .8, 1.):
            self.assertEqual(p.evaluate(axes, x, 32.), p.evaluate(recovered, x, 32.))

    def test_interval_reconstruction_contains_exact_rational_coefficients(self):
        left = [1e10 + .1, -.2, 17., 1e-7, 23., -20.]
        right = [1e10 - .2, .3, -13., 2e-7, 24., -21.]
        intervals = p.cubic_intervals(left, right, 16.)
        exact = p.cubic(list(map(Fraction, left)), list(map(Fraction, right)), Fraction(16))
        for axis, coefficients in zip(intervals, exact):
            for interval, value in zip(axis, coefficients):
                self.assertLessEqual(Fraction(interval[0]), value)
                self.assertGreaterEqual(Fraction(interval[1]), value)

    def test_bounds_cover_interior_and_endpoints_for_position_and_derivative(self):
        source = [(1e9, 2., -3., 4., .07, -.003)] * 3
        left, right = p.nodes(source, 32.)
        decoded = p.cubic(left, right, 32.)
        bounds = p.error_bounds(source, p.cubic_intervals(left, right, 32.), 32.)
        for i in range(101):
            actual = p.evaluate(source, i / 50 - 1, 32.)
            compact = p.evaluate(decoded, i / 50 - 1, 32.)
            for index in (0, 1):
                self.assertLessEqual(p.norm(p.subtract(actual[index], compact[index])), bounds[index] + 1e-6)

    def test_layout_rejects_missing_coverage_and_wrong_center(self):
        segment = p.direct.Segment(0., 32 * 86400., 9, 0, 1, 2, 1, 24)
        metadata = p.direct.RecordMetadata(p.direct.J2000, 32., 20, 1)
        self.assertEqual(1, len(p.windows([(segment, metadata)], 9, p.direct.J2000, p.direct.J2000 + 32)))
        with self.assertRaisesRegex(ValueError, 'coverage'):
            p.windows([(segment, metadata)], 9, p.direct.J2000 - 1, p.direct.J2000 + 32)
        with self.assertRaisesRegex(ValueError, 'coverage'):
            p.windows([(segment._replace(center=10), metadata)], 9, p.direct.J2000, p.direct.J2000 + 32)

    def test_reference_parser_rejects_center_and_time_substitution(self):
        path = p.ROOT / 'Scripts/reference-data/sources/horizons/pluto-vector.json'
        self.assertEqual(29, len(p.references(path.read_bytes(), 999, 'plu060_merged')))
        with self.assertRaises(ValueError):
            p.references(path.read_bytes(), 9, 'DE441')
        with self.assertRaises(ValueError):
            p.references(path.read_bytes().replace(b'JDTDB', b'JDUTC'), 999, 'plu060_merged')

    def test_packed_candidates_decode_boundaries_and_interior(self):
        rows = [(100. + 32*i, 32., [(1e9 + i, 2., 3., 4., .03, .004)]*3) for i in range(2)]
        with tempfile.TemporaryDirectory() as directory:
            for name in p.CANDIDATES:
                path = Path(directory) / name
                decoded, evidence = p.scan(rows, name, path)
                for jd in (100., 101., 116., 132., 164.):
                    self.assertEqual(p.record_at(decoded, jd), p.packed_state(path.read_bytes(), (100., 32., 2, 6), name, jd))
                width = 8 if name.endswith('64') else 4
                expected = 3*6*width if name.startswith('cubic') else 2*18*width
                self.assertEqual(expected, evidence['encodedBytes'])
                with self.assertRaises(ValueError):
                    p.packed_state(path.read_bytes(), (100., 32., 2, 6), name, 99.)

    def test_random_cubic_intervals_enclose_exact_rational_reconstruction(self):
        rng = random.Random(190)
        for _ in range(200):
            left = [rng.uniform(-1e10, 1e10) for _ in range(6)]
            right = [rng.uniform(-1e10, 1e10) for _ in range(6)]
            for days in (16, 32):
                exact = p.cubic(list(map(Fraction, left)), list(map(Fraction, right)), Fraction(days))
                enclosed = p.cubic_intervals(left, right, days)
                for axis, intervals in zip(exact, enclosed):
                    for value, (lo, hi) in zip(axis, intervals):
                        self.assertLessEqual(Fraction(lo), value)
                        self.assertGreaterEqual(Fraction(hi), value)

    def test_saved_evidence_pins_inputs_and_keeps_center_qualification_open(self):
        evidence = json.loads(p.OUTPUT.read_text())
        for path, expected in {**evidence['sourceCodeSHA256'], **evidence['referenceArchivesSHA256']}.items():
            self.assertEqual(expected, hashlib.sha256((p.ROOT/path).read_bytes()).hexdigest(), path)
        self.assertEqual(set(p.CANDIDATES), set(evidence['candidates']))
        self.assertEqual(44, len(evidence['archivedReferences']))
        self.assertEqual(72, len(evidence['fixedSamples']))
        self.assertEqual(48698, evidence['centerOffset']['recordCount'])
        self.assertFalse(evidence['centerOffset']['fullAcceptedRangeQualified'])
        self.assertFalse(evidence['assessment']['absoluteFullRangeAccuracyQualified'])
        self.assertFalse(evidence['assessment']['productionIntegrated'])
        for candidate in evidence['candidates'].values():
            self.assertEqual(47909, candidate['bodies']['9']['recordCount'])
            self.assertEqual(95817, candidate['bodies']['10']['recordCount'])
            self.assertLess(candidate['angularRepresentationBoundArcminutes'], 1.)
            self.assertEqual(sum(b['encodedBytes'] for b in candidate['bodies'].values()), candidate['encodedBytes'])

    def test_shared_nodes_enforce_c1_despite_source_seam(self):
        source1 = [(1e9, 2., 3., 4.)] * 3
        source2 = [(1e9 + 1., 5., 6., 7.)] * 3
        left, seam = p.nodes(source1, 32.)
        _, right = p.nodes(source2, 32.)
        a = p.cubic(left, seam, 32.)
        b = p.cubic(seam, right, 32.)
        self.assertEqual(p.evaluate(a, 1., 32.), p.evaluate(b, -1., 32.))
        self.assertGreater(p.error_bounds(source2, p.cubic_intervals(seam, right, 32.), 32.)[0], 1.)


if __name__ == '__main__':
    unittest.main()
