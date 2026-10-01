import copy
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock


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

    def test_source_hashes_include_nested_swift_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative in self.module.INPUT_PATHS:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(relative)
            nested = root / "Sources/AstronomyKit/Internal/Nested.swift"
            nested.parent.mkdir(parents=True)
            nested.write_text("struct Nested {}\n")
            c_source = root / "Sources/CLibAstronomy/astronomy.c"
            c_source.parent.mkdir(parents=True)
            c_source.write_text("int astronomy;\n")
            hashes = self.module.source_hashes(root)
        self.assertIn("Sources/AstronomyKit/Internal/Nested.swift", hashes)

    def test_measurement_workspace_never_moves_the_dev_sentinel(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "source"
            destination = Path(temporary) / "measurement"
            root.mkdir()
            (root / "Package.swift").write_text("// package\n")
            (root / "Sources").mkdir()
            (root / "Tests").mkdir()
            runner = root / "Tools/Migration/PerformanceRunner"
            runner.mkdir(parents=True)
            (runner / "main.swift").write_text("print(0)\n")
            sentinel = root / ".dev-tooling"
            sentinel.write_text("")
            self.module.copy_measurement_workspace(root, destination)
            self.assertTrue(sentinel.exists())
            self.assertFalse((destination / ".dev-tooling").exists())

    def test_clean_build_fails_when_scratch_cannot_be_removed(self):
        with tempfile.TemporaryDirectory() as temporary:
            scratch = Path(temporary) / "scratch"
            scratch.mkdir()
            with mock.patch.object(self.module.shutil, "rmtree", side_effect=PermissionError("denied")):
                with self.assertRaisesRegex(PermissionError, "denied"):
                    self.module.remove_scratch(scratch)

    def test_record_rejects_missing_or_altered_provenance(self):
        record = self.module.make_record_for_test(self.measurements)
        for field in ("baseRevision", "environment", "commands", "inputSHA256", "runnerSHA256", "runnerChecksums"):
            with self.subTest(missing=field):
                malformed = copy.deepcopy(record)
                del malformed[field]
                with self.assertRaises(ValueError):
                    self.module.validate_record(malformed)
        for field in ("baseRevision", "environment", "commands", "runnerSHA256", "runnerChecksums"):
            with self.subTest(altered=field):
                malformed = copy.deepcopy(record)
                malformed[field] = "altered"
                with self.assertRaises(ValueError):
                    self.module.validate_record(malformed)

    def test_candidate_protocol_must_match_baseline(self):
        baseline = self.module.make_record_for_test(self.measurements)
        self.assertEqual(1, baseline["protocol"]["buildWarmupRuns"])
        self.assertEqual(3, baseline["protocol"]["buildTrials"])
        self.assertEqual(5, baseline["protocol"]["runtimeTrials"])
        candidate = copy.deepcopy(baseline)
        candidate["protocol"]["runnerSourceSHA256"] = "1" * 64
        candidate["provenanceSHA256"] = self.module.provenance_sha256(candidate)
        with self.assertRaisesRegex(ValueError, "measurement protocol differs"):
            self.module.validate_candidate_protocol(baseline, candidate)

    def test_measurement_rejects_a_source_change_during_trials(self):
        before = {"Package.swift": "0" * 64}
        after = {"Package.swift": "1" * 64}
        with self.assertRaisesRegex(RuntimeError, "sources changed during measurement"):
            self.module.require_unchanged_snapshot(
                {"baseRevision": "0" * 40, "inputSHA256": before},
                {"baseRevision": "0" * 40, "inputSHA256": after},
            )


if __name__ == "__main__":
    unittest.main()
