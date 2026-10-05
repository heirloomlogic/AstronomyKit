"""Controls for the bounded paired allocation comparison."""
import copy
import importlib.util
import math
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("allocations", Path(__file__).with_name("compare_sun_pilot_allocations.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def report(rss):
    workloads = {mode: {"operations": count, "checksum": float(index), "elapsedNanoseconds": 1}
                 for index, (mode, count) in enumerate(MODULE.OPERATIONS.items())}
    configuration = {"comparison": {"passed": True, "count": 67240, "failures": [], "fallbackSamples": 8},
                     "perturbationDetected": True, "perturbationFailures": [1],
                     "runtime": [{"peakResidentBytes": value, "workloads": copy.deepcopy(workloads)} for value in rss]}
    return {"status": "complete-evidence", "diagnostic": False, "candidateDirty": False,
            "numericalPassed": True, "environment": {"system": "Linux", "swift": "fixture"},
            "sourceSHA256": {"Sources/generated.swift": "bits"}, "protocolSHA256": "protocol",
            "aggregateRSSProtocolSHA256": "aggregate", "oracle": {"sha256": "oracle"},
            "effectivePackage": {"manifestSHA256": "manifest", "evaluatedManifestSHA256": "graph"},
            "fixedBudgetObservations": {"baselineSHA256": "budget", "budgets": {"peakResidentBytes": 11182080}},
            "configurations": {name: copy.deepcopy(configuration) for name in ("debug", "release")}}


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.baseline = report([12500000] * 5)
        self.candidate = report([12000000] * 5)

    def test_separated_trials_support_retention_without_passing_ceiling(self):
        result = MODULE.validate_reports(self.baseline, self.candidate)
        self.assertTrue(result["rssRetentionConditionPassed"])
        self.assertFalse(result["candidateWithinOriginalCeiling"])

    def test_only_isolated_manifest_root_paths_are_normalized(self):
        for record, root in ((self.baseline, "/tmp/first"), (self.candidate, "/tmp/second")):
            record["effectivePackage"]["evaluatedManifest"] = {"packageKind": {"root": [root]}, "targets": []}
            record["effectivePackage"]["evaluatedManifestSHA256"] = root
        self.assertTrue(MODULE.validate_reports(self.baseline, self.candidate)["rssRetentionConditionPassed"])
        self.candidate["effectivePackage"]["evaluatedManifest"]["targets"] = ["changed"]
        with self.assertRaises(ValueError):
            MODULE.validate_reports(self.baseline, self.candidate)

    def test_overlap_is_retained_as_a_negative_observation(self):
        self.candidate["configurations"]["release"]["runtime"][4]["peakResidentBytes"] = 12500000
        self.assertFalse(MODULE.validate_reports(self.baseline, self.candidate)["rssRetentionConditionPassed"])

    def test_changed_workloads_and_nonfinite_values_are_rejected(self):
        for field, value in (("operations", 199), ("checksum", 1.25), ("checksum", math.nan)):
            with self.subTest(field=field, value=value):
                candidate = copy.deepcopy(self.candidate)
                candidate["configurations"]["release"]["runtime"][0]["workloads"]["freshFallback"][field] = value
                with self.assertRaises(ValueError):
                    MODULE.validate_reports(self.baseline, candidate)

    def test_missing_trials_failed_controls_and_drift_are_rejected(self):
        mutations = [lambda r: r["configurations"]["release"]["runtime"].pop(),
                     lambda r: r["configurations"]["debug"].update(perturbationDetected=False),
                     lambda r: r["sourceSHA256"].update({"Sources/generated.swift": "changed"}),
                     lambda r: r["environment"].update(swift="different"),
                     lambda r: r.update(candidateDirty=True),
                     lambda r: r.update(diagnostic=True),
                     lambda r: r["fixedBudgetObservations"]["budgets"].update(peakResidentBytes=99999999)]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                candidate = copy.deepcopy(self.candidate)
                mutation(candidate)
                with self.assertRaises(ValueError):
                    MODULE.validate_reports(self.baseline, candidate)


if __name__ == "__main__":
    unittest.main()
