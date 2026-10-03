import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("sun_pilot", Path(__file__).with_name("sun_pilot.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ComparisonTests(unittest.TestCase):
    def sample(self):
        return dict(status="success", ut=0.0, tt=0.0, x=1.0, y=0.0, z=0.0,
                    gx=1.0, gy=0.0, gz=0.0, ra=0.0, dec=0.0, distance=1.0,
                    altitude=45.0, fallback=True, iterations=3, fallbackEvaluations=3)

    def test_identical_samples_pass(self):
        self.assertEqual(MODULE.differences(self.sample(), self.sample()), [])

    def test_angles_wrap_and_fixed_budgets_remain_strict(self):
        expected = self.sample()
        actual = dict(expected, ra=24.0)
        self.assertEqual(MODULE.differences(expected, actual), [])
        for field, value in [("x", 1.0 + 2e-12), ("altitude", 45 + 2e-8),
                             ("ra", 2e-8 / 15), ("distance", 1 + 2e-12),
                             ("ut", 1e-14), ("iterations", 2), ("fallback", False)]:
            with self.subTest(field=field):
                self.assertTrue(MODULE.differences(expected, dict(expected, **{field: value})))

    def test_nonfinite_and_missing_numbers_fail(self):
        for value in [float("nan"), float("inf"), None]:
            self.assertTrue(MODULE.differences(self.sample(), dict(self.sample(), x=value)))

    def test_error_status_is_exact(self):
        self.assertEqual(MODULE.differences({"status": "bad-time"}, {"status": "bad-time"}), [])
        self.assertTrue(MODULE.differences({"status": "bad-time"}, {"status": "invalid-parameter"}))

    def test_corpus_has_every_earth_seam_and_adjacent_values(self):
        cases = MODULE.corpus()
        seams = [item for item in cases if item["category"] == "seam"]
        self.assertEqual(len(seams), (9177 + 1) * 3 * 2)
        self.assertTrue(any(item["category"] == "delta-t" for item in cases))
        self.assertTrue(any(item["category"] == "invalid" for item in cases))


if __name__ == "__main__":
    unittest.main()
