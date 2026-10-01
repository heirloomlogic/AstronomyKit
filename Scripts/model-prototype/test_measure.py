"""Validation tests for model-prototype measurement evidence."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


PATH = Path(__file__).with_name("measure.py")
SPEC = importlib.util.spec_from_file_location("measure", PATH)
MEASURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MEASURE)


class MeasurementTests(unittest.TestCase):
    def test_build_budget_uses_slowest_clean_and_incremental_trials(self):
        result = MEASURE.evaluate_builds(
            {"cleanReleaseSeconds": [40.0, 42.0, 41.0], "incrementalReleaseSeconds": [10.0, 13.0, 11.0]},
            {"cleanBuildSeconds": 42.9, "incrementalBuildSeconds": 12.668},
        )
        self.assertEqual(result["failures"], ["incrementalReleaseSeconds"])

    def test_evidence_requires_complete_trial_counts_and_workload_identity(self):
        with self.assertRaisesRegex(ValueError, "three clean"):
            MEASURE.validate_evidence({"cleanReleaseSeconds": [1.0], "incrementalReleaseSeconds": [1.0] * 3, "workloadSHA256": "0" * 64})
        with self.assertRaisesRegex(ValueError, "workload"):
            MEASURE.validate_evidence({"cleanReleaseSeconds": [1.0] * 3, "incrementalReleaseSeconds": [1.0] * 3, "workloadSHA256": "bad"})

    def test_checkpoint_preserves_completed_trials_and_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"
            MEASURE.write_checkpoint(path, "debug-preflight", {"cleanReleaseSeconds": [41.0, 42.0, 51.0]}, "timed out")
            record = json.loads(path.read_text())
            self.assertEqual(record["status"], "incomplete")
            self.assertEqual(record["phase"], "debug-preflight")
            self.assertEqual(record["measurements"]["cleanReleaseSeconds"], [41.0, 42.0, 51.0])
            self.assertEqual(record["failure"], "timed out")


if __name__ == "__main__":
    unittest.main()
