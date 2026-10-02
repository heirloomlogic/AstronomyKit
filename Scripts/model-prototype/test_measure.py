"""Validation tests for model-prototype measurement evidence."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


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

    def test_checkpoint_treats_empty_failure_as_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"
            MEASURE.write_checkpoint(path, "runtime-first", {}, "")
            record = json.loads(path.read_text())
            self.assertEqual(record["status"], "incomplete")
            self.assertEqual(record["failure"], "")

    def test_protocol_inputs_bind_coordinator_and_baseline(self):
        inputs = MEASURE.prototype_inputs(MEASURE.ROOT)
        self.assertIn("Scripts/model-prototype/measure.py", inputs)
        self.assertIn("Documentation/Migration/performance-baseline.json", inputs)

    def test_runner_payloads_must_prove_mode_value_and_checksum(self):
        first = [({"mode": "first", "elapsedNanoseconds": 1, "value": MEASURE.EXPECTED_FIRST_VALUE}, 10)] * MEASURE.RUNTIME_TRIALS
        sweep = [({"mode": "sweep", "elapsedNanoseconds": 2, "checksum": MEASURE.EXPECTED_WHOLE_MODEL_FNV64}, 20)] * MEASURE.RUNTIME_TRIALS
        MEASURE.validate_runner_results(first, sweep)
        first[0] = ({"mode": "first", "elapsedNanoseconds": 1, "value": 0}, 10)
        with self.assertRaisesRegex(ValueError, "first-access value"):
            MEASURE.validate_runner_results(first, sweep)
        first[0] = ({"mode": "first", "elapsedNanoseconds": 1, "value": MEASURE.EXPECTED_FIRST_VALUE}, 10)
        sweep[0] = ({"mode": "sweep", "elapsedNanoseconds": 2, "checksum": 0}, 20)
        with self.assertRaisesRegex(ValueError, "whole-model checksum"):
            MEASURE.validate_runner_results(first, sweep)

    def test_post_build_failure_finalizes_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence.json"
            release = {"cleanSeconds": [1.0, 1.0, 1.0], "incrementalSeconds": [1.0, 1.0, 1.0], "cleanPeakResidentBytes": [1, 1, 1]}
            with patch.object(MEASURE, "OUTPUT", output), patch.object(MEASURE, "prototype_inputs", return_value={"Package.swift": "0" * 64, "Tools/Migration/ModelPrototypeRunner/main.swift": "1" * 64}), patch.object(MEASURE, "copy_workspace"), patch.object(MEASURE, "build_trials", return_value=(release, Path("runner"))), patch.object(MEASURE, "bounded_debug_build", return_value={"completed": False, "elapsedSeconds": 0.01, "timeoutSeconds": 180}), patch.object(MEASURE, "timed_runner", side_effect=RuntimeError("runner failed")):
                with self.assertRaisesRegex(RuntimeError, "runner failed"):
                    MEASURE.measure()
            record = json.loads(output.read_text())
            self.assertEqual(record["status"], "incomplete")
            self.assertEqual(record["phase"], "runtime-first")
            self.assertEqual(record["failure"], "runner failed")

    def test_post_build_interrupt_finalizes_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence.json"
            release = {"cleanSeconds": [1.0, 1.0, 1.0], "incrementalSeconds": [1.0, 1.0, 1.0], "cleanPeakResidentBytes": [1, 1, 1]}
            with patch.object(MEASURE, "OUTPUT", output), patch.object(MEASURE, "prototype_inputs", return_value={"Package.swift": "0" * 64, "Tools/Migration/ModelPrototypeRunner/main.swift": "1" * 64}), patch.object(MEASURE, "copy_workspace"), patch.object(MEASURE, "build_trials", return_value=(release, Path("runner"))), patch.object(MEASURE, "bounded_debug_build", return_value={"completed": False, "elapsedSeconds": 0.01, "timeoutSeconds": 180}), patch.object(MEASURE, "timed_runner", side_effect=KeyboardInterrupt):
                with self.assertRaises(KeyboardInterrupt):
                    MEASURE.measure()
            record = json.loads(output.read_text())
            self.assertEqual(record["status"], "incomplete")
            self.assertEqual(record["phase"], "runtime-first")
            self.assertEqual(record["failure"], "KeyboardInterrupt")

    def test_measurement_records_observed_debug_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence.json"
            baseline = Path(directory) / "baseline.json"
            baseline.write_text(json.dumps({"budgets": {"cleanBuildSeconds": 2.0, "incrementalBuildSeconds": 2.0}}))
            hashes = {
                "Documentation/Migration/performance-baseline.json": "2" * 64,
                "Package.swift": "0" * 64,
                "Scripts/model-prototype/measure.py": "3" * 64,
                "Tools/Migration/ModelPrototypeRunner/main.swift": "1" * 64,
            }
            release = {"cleanSeconds": [1.0, 1.0, 1.0], "incrementalSeconds": [1.0, 1.0, 1.0], "cleanPeakResidentBytes": [1, 1, 1]}
            first = {"mode": "first", "elapsedNanoseconds": 1, "value": MEASURE.EXPECTED_FIRST_VALUE}
            sweep = {"mode": "sweep", "elapsedNanoseconds": 2, "checksum": MEASURE.EXPECTED_WHOLE_MODEL_FNV64}
            with patch.object(MEASURE, "OUTPUT", output), patch.object(MEASURE, "BASELINE", baseline), patch.object(MEASURE, "prototype_inputs", return_value=hashes), patch.object(MEASURE, "copy_workspace"), patch.object(MEASURE, "build_trials", return_value=(release, Path("runner"))), patch.object(MEASURE, "bounded_debug_build", return_value={"completed": False, "elapsedSeconds": 180.25, "timeoutSeconds": 180}) as debug, patch.object(MEASURE, "timed_runner", side_effect=[*((first, 10),) * MEASURE.RUNTIME_TRIALS, *((sweep, 20),) * MEASURE.RUNTIME_TRIALS]), patch.object(MEASURE, "stripped_size", return_value=100), patch.object(MEASURE, "environment", return_value={}):
                record = MEASURE.measure()
            debug.assert_called_once()
            self.assertFalse(record["measurements"]["cleanDebugBuildCompleted"])
            self.assertEqual(record["measurements"]["cleanDebugBuildElapsedSeconds"], 180.25)
            self.assertEqual(record["measurements"]["cleanDebugBuildTimeoutSeconds"], 180)

    def test_final_write_failure_replaces_running_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence.json"
            baseline = Path(directory) / "baseline.json"
            baseline.write_text(json.dumps({"budgets": {"cleanBuildSeconds": 2.0, "incrementalBuildSeconds": 2.0}}))
            hashes = {
                "Documentation/Migration/performance-baseline.json": "2" * 64,
                "Package.swift": "0" * 64,
                "Scripts/model-prototype/measure.py": "3" * 64,
                "Tools/Migration/ModelPrototypeRunner/main.swift": "1" * 64,
            }
            release = {"cleanSeconds": [1.0, 1.0, 1.0], "incrementalSeconds": [1.0, 1.0, 1.0], "cleanPeakResidentBytes": [1, 1, 1]}
            first = {"mode": "first", "elapsedNanoseconds": 1, "value": MEASURE.EXPECTED_FIRST_VALUE}
            sweep = {"mode": "sweep", "elapsedNanoseconds": 2, "checksum": MEASURE.EXPECTED_WHOLE_MODEL_FNV64}
            original_write_text = Path.write_text

            def fail_final_write(path, contents, *args, **kwargs):
                if '"phase": "measured-with-acceptance-gaps"' in contents:
                    raise OSError("final write failed")
                return original_write_text(path, contents, *args, **kwargs)

            with patch.object(MEASURE, "OUTPUT", output), patch.object(MEASURE, "BASELINE", baseline), patch.object(MEASURE, "prototype_inputs", return_value=hashes), patch.object(MEASURE, "copy_workspace"), patch.object(MEASURE, "build_trials", return_value=(release, Path("runner"))), patch.object(MEASURE, "bounded_debug_build", return_value={"completed": False, "elapsedSeconds": 180.25, "timeoutSeconds": 180}), patch.object(MEASURE, "timed_runner", side_effect=[*((first, 10),) * MEASURE.RUNTIME_TRIALS, *((sweep, 20),) * MEASURE.RUNTIME_TRIALS]), patch.object(MEASURE, "stripped_size", return_value=100), patch.object(MEASURE, "environment", return_value={}), patch.object(Path, "write_text", new=fail_final_write):
                with self.assertRaisesRegex(OSError, "final write failed"):
                    MEASURE.measure()
            record = json.loads(output.read_text())
            self.assertEqual(record["status"], "incomplete")
            self.assertEqual(record["phase"], "final-write")
            self.assertEqual(record["failure"], "final write failed")


if __name__ == "__main__":
    unittest.main()
