import copy
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "Scripts/migration/performance_baseline.py"


def load_module():
    spec = importlib.util.spec_from_file_location("performance_baseline", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PerformanceBudgetTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()
        self.measurements = {
            "latencyNanosecondsPerOperation": [100, 104, 98, 102, 101],
            "coldThroughputOperationsPerSecond": [1_000, 980, 1_020, 990, 1_010],
            "warmThroughputOperationsPerSecond": [10_000, 9_800, 10_200, 9_900, 10_100],
            "peakResidentBytes": [1_000_000, 1_010_000, 990_000, 1_005_000, 1_000_000],
            "strippedBinaryBytes": 2_000_000,
            "cleanBuildSeconds": [10.0, 10.2, 9.9],
            "incrementalBuildSeconds": [2.0, 2.1, 1.9],
        }

    def test_derives_fixed_budgets_from_measured_baseline(self):
        budgets = self.module.derive_budgets(self.measurements)
        self.assertEqual(budgets["latencyNanosecondsPerOperation"], 152)
        self.assertEqual(budgets["coldThroughputOperationsPerSecond"], 800)
        self.assertEqual(budgets["warmThroughputOperationsPerSecond"], 8_000)
        self.assertEqual(budgets["peakResidentBytes"], 1_262_500)
        self.assertEqual(budgets["strippedBinaryBytes"], 2_200_000)
        self.assertEqual(budgets["cleanBuildSeconds"], 15.3)
        self.assertEqual(budgets["incrementalBuildSeconds"], 3.15)

    def test_candidate_at_baseline_passes_every_budget(self):
        baseline = {"budgets": self.module.derive_budgets(self.measurements)}
        result = self.module.evaluate_candidate(baseline, self.measurements)
        self.assertTrue(result["passed"])
        self.assertEqual(result["failures"], [])

    def test_each_regression_is_rejected(self):
        baseline = {"budgets": self.module.derive_budgets(self.measurements)}
        regressions = {
            "latencyNanosecondsPerOperation": [154] * 5,
            "coldThroughputOperationsPerSecond": [799] * 5,
            "warmThroughputOperationsPerSecond": [7_999] * 5,
            "peakResidentBytes": [1_262_501] * 5,
            "strippedBinaryBytes": 2_200_001,
            "cleanBuildSeconds": [15.31] * 3,
            "incrementalBuildSeconds": [3.16] * 3,
        }
        for metric, value in regressions.items():
            with self.subTest(metric=metric):
                candidate = copy.deepcopy(self.measurements)
                candidate[metric] = value
                result = self.module.evaluate_candidate(baseline, candidate)
                self.assertFalse(result["passed"])
                self.assertEqual(result["failures"], [metric])

    def test_record_requires_five_runtime_and_memory_trials(self):
        record = self.module.make_record_for_test(self.measurements)
        record["measurements"]["peakResidentBytes"].pop()
        with self.assertRaisesRegex(ValueError, "peakResidentBytes must contain five trials"):
            self.module.validate_record(record)

    def test_record_rejects_budgets_that_do_not_match_measurements(self):
        record = self.module.make_record_for_test(self.measurements)
        record["budgets"]["strippedBinaryBytes"] += 1
        with self.assertRaisesRegex(ValueError, "budgets do not match"):
            self.module.validate_record(record)


if __name__ == "__main__":
    unittest.main()
