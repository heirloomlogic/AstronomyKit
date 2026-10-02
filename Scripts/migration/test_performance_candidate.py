import copy
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASELINE_MODULE_PATH = ROOT / "Scripts/migration/performance_baseline.py"
CANDIDATE_MODULE_PATH = ROOT / "Scripts/migration/performance_candidate.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PerformanceCandidateTests(unittest.TestCase):
    def setUp(self):
        self.baseline_module = load_module("performance_baseline_for_candidate_test", BASELINE_MODULE_PATH)
        self.candidate_module = load_module("performance_candidate_test", CANDIDATE_MODULE_PATH)
        measurements = {
            "latencyNanosecondsPerOperation": [100, 104, 98, 102, 101],
            "coldThroughputOperationsPerSecond": [1_000, 980, 1_020, 990, 1_010],
            "warmThroughputOperationsPerSecond": [10_000, 9_800, 10_200, 9_900, 10_100],
            "peakResidentBytes": [1_000_000, 1_010_000, 990_000, 1_005_000, 1_000_000],
            "strippedBinaryBytes": 2_000_000,
            "cleanBuildSeconds": [10.0, 10.2, 9.9],
            "incrementalBuildSeconds": [2.0, 2.1, 1.9],
        }
        self.baseline = self.baseline_module.make_record_for_test(measurements)
        self.baseline["inputSHA256"] = {"Sources/AstronomyKit/Chiron.swift": "0" * 64}
        self.baseline["provenanceSHA256"] = self.baseline_module.provenance_sha256(self.baseline)
        self.candidate = copy.deepcopy(self.baseline)
        self.candidate["inputSHA256"] = {"Sources/AstronomyKit/Chiron.swift": "1" * 64}
        self.candidate["provenanceSHA256"] = self.baseline_module.provenance_sha256(self.candidate)

    def test_unchanged_baseline_inputs_need_no_candidate(self):
        result = self.candidate_module.check_evidence(
            self.baseline_module, self.baseline, None, self.baseline["inputSHA256"])
        self.assertEqual(result["source"], "frozen-baseline")

    def test_changed_inputs_require_a_matching_passing_candidate(self):
        artifact = self.candidate_module.make_artifact(
            self.baseline_module, self.baseline, self.candidate)
        result = self.candidate_module.check_evidence(
            self.baseline_module, self.baseline, artifact, self.candidate["inputSHA256"])
        self.assertEqual(result["source"], "measured-candidate")
        self.assertTrue(result["evaluation"]["passed"])

    def test_changed_inputs_without_candidate_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "candidate evidence is required"):
            self.candidate_module.check_evidence(
                self.baseline_module, self.baseline, None, self.candidate["inputSHA256"])

    def test_candidate_must_match_current_inputs(self):
        artifact = self.candidate_module.make_artifact(
            self.baseline_module, self.baseline, self.candidate)
        with self.assertRaisesRegex(ValueError, "candidate input hashes are stale"):
            self.candidate_module.check_evidence(
                self.baseline_module,
                self.baseline,
                artifact,
                {"Sources/AstronomyKit/Chiron.swift": "2" * 64},
            )

    def test_candidate_must_pass_frozen_budgets(self):
        failing = copy.deepcopy(self.candidate)
        failing["measurements"]["latencyNanosecondsPerOperation"] = [10_000] * 5
        failing["budgets"] = self.baseline_module.derive_budgets(failing["measurements"])
        failing["provenanceSHA256"] = self.baseline_module.provenance_sha256(failing)
        artifact = self.candidate_module.make_artifact(
            self.baseline_module, self.baseline, failing)
        with self.assertRaisesRegex(ValueError, "candidate fails frozen budgets"):
            self.candidate_module.check_evidence(
                self.baseline_module, self.baseline, artifact, failing["inputSHA256"])

    def test_candidate_artifact_provenance_is_verified(self):
        artifact = self.candidate_module.make_artifact(
            self.baseline_module, self.baseline, self.candidate)
        artifact["candidate"]["runnerChecksums"][0]["coldThroughput"] += 1
        with self.assertRaisesRegex(ValueError, "candidate artifact provenance"):
            self.candidate_module.check_evidence(
                self.baseline_module, self.baseline, artifact, self.candidate["inputSHA256"])


if __name__ == "__main__":
    unittest.main()
