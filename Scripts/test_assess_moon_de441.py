import importlib.util
import json
import math
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_assessment():
    path = ROOT / "Scripts/assess-moon-de441.py"
    spec = importlib.util.spec_from_file_location("moon_de441_assessment", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MoonDE441AssessmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.assessment = load_assessment()

    def test_archived_horizons_vectors_are_all_geometric_icrf_de441_states(self):
        source = ROOT / "Scripts/reference-data/sources/horizons/moon-vector.json"
        vectors = self.assessment.parse_horizons_vectors(source.read_bytes())
        self.assertEqual(30, len(vectors))
        self.assertEqual(990_546.0, vectors[0].julian_date_tdb)
        self.assertEqual(3_912_544.0, vectors[-1].julian_date_tdb)
        self.assertTrue(all(len(vector.position_au) == 3 for vector in vectors))
        self.assertTrue(all(len(vector.velocity_au_per_day) == 3 for vector in vectors))

    def test_chebyshev_evaluation_returns_the_analytic_rate_per_day(self):
        value, rate = self.assessment.chebyshev_value_and_rate((1.0, 2.0, 3.0), 0.25, 4.0)
        self.assertEqual(-1.125, value)
        self.assertEqual(2.5, rate)

    def test_float32_conversion_reports_component_position_and_rate_bounds(self):
        coefficients = (0.1, -0.2, 0.3, -0.4)
        converted, position_bound, rate_bound = self.assessment.float32_with_bounds(coefficients, 4.0)
        errors = [abs(source - result) for source, result in zip(coefficients, converted)]
        self.assertEqual(sum(errors), position_bound)
        self.assertEqual(sum(error * degree * degree / 2 for degree, error in enumerate(errors)), rate_bound)
        for value in converted:
            self.assertEqual(struct.pack("<f", value), struct.pack("<f", struct.unpack("<f", struct.pack("<f", value))[0]))

    def test_record_window_covers_the_half_open_requested_span(self):
        metadata = self.assessment.RecordMetadata(start_jd_tdb=100.0, record_days=4.0, record_words=41, record_count=10)
        self.assertEqual((0, 1), self.assessment.record_window(metadata, 100.0, 104.0))
        self.assertEqual((0, 2), self.assessment.record_window(metadata, 100.0, 104.000_001))
        self.assertEqual((1, 2), self.assessment.record_window(metadata, 104.0, 112.0))
        with self.assertRaisesRegex(ValueError, "outside segment"):
            self.assessment.record_window(metadata, 99.0, 104.0)

    def test_summary_record_preserves_duplicate_target_segments(self):
        record = bytearray(1024)
        struct.pack_into("<3d", record, 0, 9.0, 0.0, 2.0)
        rows = [
            (-20.0, 0.0, 301, 3, 1, 2, 100, 200),
            (0.0, 20.0, 301, 3, 1, 2, 300, 400),
        ]
        for index, row in enumerate(rows):
            struct.pack_into("<2d6i", record, 24 + index * 40, *row)
        following, segments = self.assessment.parse_summary_record(bytes(record))
        self.assertEqual(9, following)
        self.assertEqual(2, len(segments))
        self.assertEqual((100, 200), (segments[0].first_word, segments[0].last_word))
        self.assertEqual((300, 400), (segments[1].first_word, segments[1].last_word))

    def test_saved_evidence_identifies_sparse_checks_as_incomplete_qualification(self):
        evidence = json.loads((ROOT / "Scripts/moon-data/de441-direct-evidence.json").read_text())
        self.assertEqual("NASA/JPL DE441", evidence["source"]["solution"])
        self.assertEqual(30, evidence["independentReference"]["sampleCount"])
        self.assertFalse(evidence["assessment"]["fullRangeQualified"])
        self.assertIn("compact", evidence["assessment"]["nextStep"].lower())


if __name__ == "__main__":
    unittest.main()
