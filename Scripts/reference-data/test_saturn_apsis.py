"""Fault controls for the failure-selected Saturn diagnosis."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

SCRIPT = Path(__file__).with_name("diagnose-saturn-apsides.py")
SPEC = importlib.util.spec_from_file_location("saturn_diagnosis", SCRIPT)
D = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(D)


class SaturnDiagnosisTests(unittest.TestCase):
    def test_plan_preserves_six_failures_and_center_acceptance(self):
        plan = D.load_plan()
        self.assertEqual(len(plan["cases"]), 6)
        self.assertEqual(plan["acceptanceTargetID"], "699")
        self.assertEqual(plan["diagnosticTargetID"], "6")
        self.assertEqual(plan["timingTargetSeconds"], 60)
        for key, value in [("acceptanceTargetID", "6"), ("timingTargetSeconds", 61), ("timeScale", "UT")]:
            changed = copy.deepcopy(plan)
            changed[key] = value
            with self.assertRaises(ValueError):
                D.validate_plan(changed)

    def test_source_pair_rejects_target_hash_and_plan_changes(self):
        plan = D.load_plan()
        data, receipt = D.archive_pair("699", "centers", plan)
        for key, value in [("responseSHA256", "bad"), ("planSHA256", "bad")]:
            changed = copy.deepcopy(receipt)
            changed[key] = value
            with self.assertRaises(ValueError):
                D.validate_archive(data, changed, "699", "centers", plan)
        for key, value in [("COMMAND", "'6'"), ("CENTER", "'500@0'"), ("TIME_TYPE", "'TDB'"), ("REF_SYSTEM", "'B1950'"), ("VEC_CORR", "'LT'"), ("OUT_UNITS", "'KM-S'")]:
            changed = copy.deepcopy(receipt)
            changed["parameters"][key] = value
            with self.assertRaises(ValueError):
                D.validate_archive(data, changed, "699", "centers", plan)

    def test_root_identity_rejects_absent_extra_or_wrong_kind_crossing(self):
        rows = [{"julianDateTT": 10 + i * 0.125, "rangeAU": 9, "rangeRateAUPerDay": (i - 2) * 1e-6} for i in range(5)]
        result = D.resolve(rows, "pericenter")
        self.assertEqual(result["kind"], "pericenter")
        self.assertAlmostEqual(result["julianDateTT"], 10.25)
        with self.assertRaises(ValueError):
            D.resolve(rows, "apocenter")
        for values in [[1, 2, 3, 4, 5], [-1, 1, -1, 1, -1]]:
            changed = copy.deepcopy(rows)
            for row, value in zip(changed, values):
                row["rangeRateAUPerDay"] = value
            with self.assertRaises(ValueError):
                D.resolve(changed, "pericenter")

    def test_model_control_rejects_direction_precision_units_and_missing_method(self):
        plan = D.load_plan()
        case = plan["cases"][0]
        probe = {"publicKind": case["kind"], "publicJulianDateTT": case["publicJulianDateTT"], "roots": []}
        for evaluator in ["production", "full-series"]:
            for step in [0, *plan["finiteDifferenceStepsDays"]]:
                probe["roots"].append({"evaluator": evaluator, "stepDays": step, "method": "finite-difference" if step else "analytic", "kind": case["kind"], "julianDateTT": case["publicJulianDateTT"], "offsetFromArchivedPublicSeconds": 0, "bracketWidthSeconds": 0.00001, "rateAtArchivedPublicAUPerDay": 0, "rateAtArchivedReferenceAUPerDay": 1e-7})
        D.validate_probe(probe, case, plan)
        for key, value in [("kind", "pericenter"), ("bracketWidthSeconds", 0.1), ("stepDays", 86.4), ("rateAtArchivedPublicAUPerDay", float("nan")), ("method", "finite-difference"), ("offsetFromArchivedPublicSeconds", 86400)]:
            changed = copy.deepcopy(probe)
            changed["roots"][0][key] = value
            with self.assertRaises(ValueError):
                D.validate_probe(changed, case, plan)
        changed = copy.deepcopy(probe)
        changed["roots"].pop()
        with self.assertRaises(ValueError):
            D.validate_probe(changed, case, plan)

    def test_center_grid_retains_all_extra_crossings(self):
        plan = D.load_plan()
        data, receipt = D.archive_pair("699", "centers", plan)
        rows, metadata = D.validate_archive(data, receipt, "699", "centers", plan)
        result = D.center_roots(rows, plan["cases"][0], plan)
        self.assertEqual(result["sampleCount"], 161)
        self.assertEqual(result["directedCrossingCount"], 3)
        self.assertEqual([root["kind"] for root in result["roots"]], ["apocenter", "pericenter", "apocenter"])
        self.assertEqual([root["withinOriginalNumericalAllowance"] for root in result["roots"]], [False, False, True])

    def test_report_comparison_ignores_only_commit_time_receipt(self):
        report = {"candidateRevision": "before", "candidateDirty": True, "qualified": False, "cases": [1], "inputSHA256": {"probe": "a"}, "probeExecutable": {"sha256": "original"}}
        changed = copy.deepcopy(report)
        changed.update(candidateRevision="after", candidateDirty=False)
        self.assertEqual(D.scientific_report(report), D.scientific_report(changed))
        for key, value in [("qualified", True), ("cases", []), ("inputSHA256", {}), ("probeExecutable", {})]:
            changed = copy.deepcopy(report)
            changed[key] = value
            self.assertNotEqual(D.scientific_report(report), D.scientific_report(changed))

    def test_original_archived_assessment_remains_unqualified(self):
        baseline = json.loads(D.BASELINE.read_bytes())
        self.assertFalse(baseline["qualified"])
        pairs = baseline["bodies"]["Saturn"]["comparison"]["pairs"]
        self.assertEqual(len(pairs), 6)
        self.assertTrue(all(not pair["nominalWithinTimingTarget"] for pair in pairs))


if __name__ == "__main__":
    unittest.main()
