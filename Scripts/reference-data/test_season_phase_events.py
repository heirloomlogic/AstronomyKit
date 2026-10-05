import hashlib
import importlib.util
import json
import math
import tempfile
import types
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/reference-data/qualify-season-phase-events.py"
if SCRIPT.exists():
    spec = importlib.util.spec_from_file_location("season_phase_events", SCRIPT)
    Q = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(Q)
else:
    Q = types.SimpleNamespace()


class SeasonPhaseEventTests(unittest.TestCase):
    def test_plan_binds_policy_sources_coverage_and_strict_target(self):
        plan = Q.load_plan()
        self.assertEqual("strictlyLessThan", plan["comparison"]["timingRule"])
        self.assertEqual(60, plan["comparison"]["thresholdSeconds"])
        self.assertEqual("not-recorded", plan["comparison"]["referenceRoundingDirection"])
        self.assertEqual(804, plan["expectedRetainedCounts"]["seasons"])
        self.assertEqual(1038, plan["expectedRetainedCounts"]["lunarPhases"])
        self.assertEqual(201, len(Q.retained_years(plan, "seasons")))
        self.assertEqual(21, len(Q.retained_years(plan, "lunarPhases")))
        self.assertEqual(2100, Q.retained_years(plan, "lunarPhases")[-1])
        self.assertIn("2101 through 2130", plan["domain"]["seasons"]["omitted"])
        self.assertIn("non-decennial", plan["domain"]["lunarPhases"]["omitted"])
        self.assertIn("retains every archived season", plan["domain"]["seasons"]["omissionBasis"])
        self.assertIn("retains every archived year", plan["domain"]["lunarPhases"]["omissionBasis"])

    def test_plan_rejects_detached_policy_or_source_bytes(self):
        plan = json.loads(Q.PLAN.read_bytes())
        with self.assertRaisesRegex(ValueError, "policy"):
            Q.validate_plan({**plan, "approvedPolicy": {**plan["approvedPolicy"], "sha256": "0" * 64}})
        changed = json.loads(json.dumps(plan))
        changed["referenceSources"]["seasons"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "source"):
            Q.validate_plan(changed)

    def test_plan_discloses_prior_observation_and_preserves_initial_assessment(self):
        plan = Q.load_plan()
        self.assertEqual("prospective-replay-plan-after-prior-results-observed", plan["classification"])
        chronology = plan["measurementChronology"]
        self.assertEqual("7d577000d1062cdb034e05dd8d97ac3e2eef22d2", chronology["firstRepositoryCommit"])
        self.assertIn("results had already been observed", chronology["prospectiveReplay"])
        archive = ROOT / chronology["initialAssessment"]["path"]
        self.assertEqual(chronology["initialAssessment"]["sha256"], hashlib.sha256(archive.read_bytes()).hexdigest())

    def test_plan_pins_actual_upstream_acquisition_endpoints(self):
        plan = Q.load_plan()
        seasons = plan["referenceSources"]["seasons"]
        phases = plan["referenceSources"]["lunarPhases"]
        self.assertEqual("https://api.usno.navy.mil/seasons?year=YEAR", seasons["sourceAPI"])
        self.assertEqual("https://api.usno.navy.mil/moon/phase?year=YEAR", phases["sourceAPI"])
        self.assertEqual("27c1a14ff1184bd09e246d83d2c94a6b6ba0c2f971ef267c3fe205b4b77bb38f", seasons["acquisitionScriptSHA256"])
        self.assertEqual("c45c24ef50da3aa4439feaff6d498e084ffb3f28998c1b5643bf5b0964f30175", phases["acquisitionScriptSHA256"])

    def test_report_refuses_implicit_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "assessment.json"
            report.write_bytes(b"original\n")
            with self.assertRaisesRegex(FileExistsError, "--replace-existing"):
                Q.write_report(report, b"replacement\n", replace_existing=False)
            self.assertEqual(b"original\n", report.read_bytes())
            Q.write_report(report, b"replacement\n", replace_existing=True)
            self.assertEqual(b"replacement\n", report.read_bytes())

    def test_parsers_retain_every_predeclared_event_in_order(self):
        plan = Q.load_plan()
        seasons = Q.parse_seasons(plan)
        phases = Q.parse_lunar_phases(plan)
        self.assertEqual(804, len(seasons))
        self.assertEqual(1038, len(phases))
        self.assertEqual(["marchEquinox", "juneSolstice", "septemberEquinox", "decemberSolstice"], [row["kind"] for row in seasons[:4]])
        self.assertEqual(["new", "firstQuarter", "full", "lastQuarter"], [row["kind"] for row in phases[:4]])
        self.assertTrue(all(a["julianDateUT"] < b["julianDateUT"] for a, b in zip(seasons, seasons[1:])))
        self.assertTrue(all(a["julianDateUT"] < b["julianDateUT"] for a, b in zip(phases, phases[1:])))

    def test_pairing_preserves_count_kind_order_and_every_failure(self):
        references = [
            {"kind": "new", "julianDateTT": 100.0, "source": "a"},
            {"kind": "firstQuarter", "julianDateTT": 108.0, "source": "b"},
        ]
        candidates = [
            {"kind": "new", "julianDateTT": 100.0 + 59.999 / 86400},
            {"kind": "full", "julianDateTT": 109.0},
            {"kind": "firstQuarter", "julianDateTT": 108.0 + 60.0 / 86400},
        ]
        result = Q.compare_events(references, candidates, 60.0)
        self.assertFalse(result["countMatches"])
        self.assertFalse(result["kindSequenceMatches"])
        self.assertFalse(result["candidateOrderValid"])
        self.assertEqual(3, len(result["rows"]))
        self.assertTrue(result["rows"][0]["nominalWithinTarget"])
        self.assertFalse(result["rows"][1]["identityMatches"])
        self.assertFalse(result["rows"][2]["nominalWithinTarget"])
        self.assertTrue(result["failures"])

    def test_strict_sixty_second_and_time_scale_mutations_fail(self):
        self.assertTrue(Q.nominal_within_target(59.999, 60.0))
        self.assertFalse(Q.nominal_within_target(60.0, 60.0))
        reference = [{"kind": "new", "julianDateTT": 100.0}]
        shifted = [{"kind": "new", "julianDateTT": 100.0 + 70.0 / 86400}]
        self.assertFalse(Q.compare_events(reference, shifted, 60.0)["rows"][0]["nominalWithinTarget"])

    def test_time_scale_and_event_selection_mutation_controls_change_results(self):
        rows = [
            {
                "candidate": {"kind": "new", "julianDateTT": 100.0 + 30.0 / 86_400},
                "identityMatches": True,
                "nominalWithinTarget": True,
                "reference": {"kind": "new", "julianDateTT": 100.0, "julianDateUT": 100.0 - 90.0 / 86_400},
            },
            {
                "candidate": {"kind": "firstQuarter", "julianDateTT": 108.0},
                "identityMatches": True,
                "nominalWithinTarget": True,
                "reference": {"kind": "firstQuarter", "julianDateTT": 108.0, "julianDateUT": 108.0 - 90.0 / 86_400},
            },
        ]
        controls = Q.mutation_controls(rows, 60.0)
        self.assertTrue(controls["sourceUTMisreadAsTT"]["detected"])
        self.assertEqual(2, controls["sourceUTMisreadAsTT"]["nominalFailureCount"])
        self.assertTrue(controls["eventSelectionShift"]["detected"])
        self.assertTrue(controls["strictBoundary"]["detected"])

    def test_runner_operations_use_public_season_and_lunar_phase_apis(self):
        source = (ROOT / "Tools/Migration/AccuracyQualificationRunner/main.swift").read_text()
        self.assertIn('case "seasons"', source)
        self.assertIn("Seasons.forYear", source)
        self.assertIn('case "lunar-phases"', source)
        self.assertIn("Moon.quarters", source)

    def test_scientific_report_ignores_only_commit_receipt(self):
        expected = {"candidateRevision": "old", "candidateDirty": False, "inputSHA256": {"source": "bound"}, "families": {"seasons": {"retained": 4}}}
        later_commit = {**expected, "candidateRevision": "later", "candidateDirty": True}
        self.assertEqual(Q.scientific_report(expected), Q.scientific_report(later_commit))
        changed = {**later_commit, "families": {"seasons": {"retained": 3}}}
        self.assertNotEqual(Q.scientific_report(expected), Q.scientific_report(changed))

    def test_comparison_rejects_nonfinite_and_duplicate_candidate_epochs(self):
        reference = [{"kind": "new", "julianDateTT": 100.0}, {"kind": "firstQuarter", "julianDateTT": 108.0}]
        for candidates in [
            [{"kind": "new", "julianDateTT": math.nan}, {"kind": "firstQuarter", "julianDateTT": 108.0}],
            [{"kind": "new", "julianDateTT": 100.0}, {"kind": "firstQuarter", "julianDateTT": 100.0}],
        ]:
            with self.subTest(candidates=candidates):
                result = Q.compare_events(reference, candidates, 60.0)
                self.assertFalse(result["candidateOrderValid"])
                self.assertTrue(result["failures"])


if __name__ == "__main__":
    unittest.main()
