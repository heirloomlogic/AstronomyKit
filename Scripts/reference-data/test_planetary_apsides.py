"""Fault controls for finite independent planetary apsis evidence."""
import importlib.util
import json
import math
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).with_name("qualify-planetary-apsides.py")
if SCRIPT.exists():
    SPEC = importlib.util.spec_from_file_location("planetary_apsides", SCRIPT)
    A = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(A)
else:
    A = types.SimpleNamespace()


def rows(rates, distances=None):
    distances = distances or [1 + (index - 2) ** 2 / 100 for index in range(len(rates))]
    return [
        {"julianDateTT": 100 + index, "rangeRateAUPerDay": rate, "rangeAU": distance}
        for index, (rate, distance) in enumerate(zip(rates, distances))
    ]


class PlanetaryApsisTests(unittest.TestCase):
    def test_plan_binds_policy_source_domain_and_nine_body_controls(self):
        plan = A.load_plan()
        self.assertEqual(9, len(plan["bodies"]))
        self.assertEqual("TT", plan["referenceSource"]["timeScale"])
        self.assertEqual("Sun body center 500@10", plan["referenceSource"]["origin"])
        self.assertEqual("NONE geometric state", plan["referenceSource"]["aberrationCorrection"])
        self.assertEqual("none", plan["referenceSource"]["smoothing"])
        self.assertEqual(60.0, plan["publicPairing"]["timingTargetSeconds"])
        self.assertEqual("strictlyLessThan", plan["publicPairing"]["timingComparison"])
        self.assertEqual(["opening-1900", "future-2101-2130", "closing-2130"], [row["id"] for row in plan["diagnosticSlices"]])

    def test_reference_recipe_rejects_target_center_frame_time_correction_unit_and_table_changes(self):
        plan = A.load_plan()
        body = plan["bodies"]["Mars"]
        recipe = A.reference_recipe(body, [2451545.0])
        A.validate_reference_recipe(recipe, body)
        faults = {
            "COMMAND": "'399'",
            "CENTER": "'500@0'",
            "REF_SYSTEM": "'B1950'",
            "TIME_TYPE": "'TDB'",
            "VEC_CORR": "'LT'",
            "OUT_UNITS": "'KM-S'",
            "VEC_TABLE": "'2'",
        }
        for key, value in faults.items():
            with self.subTest(key=key):
                changed = dict(recipe)
                changed[key] = value
                with self.assertRaisesRegex(ValueError, "reference recipe"):
                    A.validate_reference_recipe(changed, body)

    def test_coarse_schedule_has_opening_guard_stop_bracket_and_api_safe_population(self):
        plan = A.load_plan()
        start = plan["domain"]["startInclusiveJulianDateTT"]
        stop = plan["domain"]["stopExclusiveJulianDateTT"]
        for name, body in plan["bodies"].items():
            with self.subTest(body=name):
                dates = A.coarse_dates(plan, body)
                self.assertEqual(start - body["coarseStepDays"], dates[0])
                self.assertEqual(stop, dates[-1])
                self.assertLessEqual(len(dates), 10_000)
                self.assertTrue(all(a < b for a, b in zip(dates, dates[1:])))

    def test_stage_root_resolves_a_unique_monotonic_crossing_and_preserves_samples(self):
        result = A.stage_root(rows([-2, -1, 0.2, 1, 2]))
        self.assertEqual("resolved", result["status"])
        self.assertEqual("pericenter", result["kind"])
        self.assertEqual(5, len(result["samples"]))
        self.assertTrue(math.isfinite(result["julianDateTT"]))
        self.assertTrue(math.isfinite(result["rangeAU"]))

    def test_stage_root_retains_flat_double_nonfinite_and_nonpositive_range_failures(self):
        failures = [
            rows([0, 0, 0, 0, 0]),
            rows([-1, 1, -1, 1, 2]),
            rows([-2, -1, math.nan, 1, 2]),
            rows([-2, -1, 0.2, 1, 2], [1, 1, 0, 1, 1]),
        ]
        for samples in failures:
            with self.subTest(samples=samples):
                result = A.stage_root(samples)
                self.assertEqual("inconclusive", result["status"])
                self.assertEqual(samples, result["samples"])
                self.assertTrue(result["reason"])

    def test_final_root_rejects_sign_kind_change_and_excess_numerical_uncertainty(self):
        pericenter = {"status": "resolved", "kind": "pericenter", "julianDateTT": 102.0, "rangeAU": 1.0, "quadraticDifferenceSeconds": 0.1, "samples": []}
        apocenter = {**pericenter, "kind": "apocenter"}
        changed = A.finalize_root(pericenter, apocenter, pericenter, 1.0)
        self.assertEqual("inconclusive", changed["status"])
        uncertain = A.finalize_root(pericenter, pericenter, {**pericenter, "quadraticDifferenceSeconds": 1.000001}, 1.0)
        self.assertEqual("inconclusive", uncertain["status"])
        resolved = A.finalize_root(pericenter, pericenter, pericenter, 1.0)
        self.assertEqual("resolved", resolved["status"])

    def test_report_root_retains_stage_results_and_sample_identities_without_copying_rows(self):
        stage = {"status": "resolved", "kind": "pericenter", "julianDateTT": 102.0, "rangeAU": 1.0, "quadraticDifferenceSeconds": 0.1, "samples": rows([-2, -1, 0.2, 1, 2])}
        root = A.finalize_root(stage, stage, stage, 1.0)
        receipt = A.root_receipt(root)
        self.assertEqual("resolved", receipt["status"])
        self.assertEqual([100, 101, 102, 103, 104], receipt["stages"]["fine"]["sampleJulianDatesTT"])
        self.assertNotIn("samples", receipt["stages"]["fine"])

    def test_orbit_scale_clusters_retain_additional_extrema_and_boundary_ambiguity(self):
        roots = [
            {"status": "resolved", "julianDateTT": 130.0, "kind": "pericenter", "rangeAU": 1.0},
            {"status": "resolved", "julianDateTT": 135.0, "kind": "apocenter", "rangeAU": 1.1},
            {"status": "resolved", "julianDateTT": 140.0, "kind": "pericenter", "rangeAU": 0.9},
            {"status": "resolved", "julianDateTT": 200.0, "kind": "apocenter", "rangeAU": 2.0},
        ]
        result = A.classify_orbit_scale_roots(roots, period_days=100.0, start=100.0, stop=300.0)
        self.assertEqual([140.0, 200.0], [row["julianDateTT"] for row in result["orbitScaleCandidates"]])
        self.assertEqual([130.0, 135.0], [row["julianDateTT"] for row in result["additionalLocalExtrema"]])
        boundary = A.classify_orbit_scale_roots([{**roots[0], "julianDateTT": 105.0}], 100.0, 100.0, 300.0)
        self.assertEqual([], boundary["orbitScaleCandidates"])
        self.assertEqual(1, len(boundary["ambiguousClusters"]))
        even = A.classify_orbit_scale_roots(roots[:2], 100.0, 0.0, 300.0)
        self.assertEqual([], even["orbitScaleCandidates"])

    def test_pairing_reports_count_kind_order_reuse_and_strict_sixty_second_failure(self):
        references = [
            {"julianDateTT": 110.0, "kind": "pericenter", "rangeAU": 1.0},
            {"julianDateTT": 160.0, "kind": "apocenter", "rangeAU": 2.0},
        ]
        public = [
            {"julianDateTT": 110.0 + 59.999 / 86400, "kind": "pericenter", "distanceAU": 1.0},
            {"julianDateTT": 160.0 + 60.001 / 86400, "kind": "apocenter", "distanceAU": 2.0},
        ]
        result = A.pair_public_events(public, references, period_days=400.0, numerical_allowance_seconds=1.0, distance_limit=1e-6)
        self.assertTrue(result["countMatches"])
        self.assertTrue(result["kindSequenceMatches"])
        self.assertTrue(result["publicOrderValid"])
        self.assertTrue(result["pairs"][0]["nominalWithinTimingTarget"])
        self.assertFalse(result["pairs"][1]["nominalWithinTimingTarget"])
        self.assertEqual("inconclusive-numerical-envelope", result["pairs"][1]["timingNumericalEnvelopeClassification"])
        self.assertFalse(A.nominal_within_timing_target(60.0, 60.0))
        broken = A.pair_public_events([public[0], {**public[1], "kind": "pericenter"}], references, 400.0, 1.0, 1e-6)
        self.assertFalse(broken["kindSequenceMatches"])
        self.assertTrue(broken["pairingFailures"])

    def test_runner_operation_uses_public_search_and_next_apis(self):
        source = (ROOT / "Tools/Migration/AccuracyQualificationRunner/main.swift").read_text()
        self.assertIn('case "planetary-apsides"', source)
        self.assertIn("searchApsis(after:", source)
        self.assertIn("nextApsis(after:", source)

    def test_plan_bytes_are_valid_json_and_every_archive_query_binds_them(self):
        plan_path = ROOT / "Documentation/Migration/planetary-apsis-sampling-plan.json"
        self.assertEqual(1, json.loads(plan_path.read_bytes())["schemaVersion"])
        plan_hash = A.digest(plan_path.read_bytes())
        queries = sorted((ROOT / "Scripts/reference-data/sources/planetary-apsides").glob("*.query.json"))
        self.assertEqual(24, len(queries))
        for query in queries:
            self.assertEqual(plan_hash, json.loads(query.read_bytes())["planSHA256"])


if __name__ == "__main__":
    unittest.main()
