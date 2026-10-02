import copy
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_investigation():
    path = ROOT / "Scripts/reference-data/investigate-apparent-range.py"
    spec = importlib.util.spec_from_file_location("apparent_range_investigation", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ApparentRangeInvestigationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.investigation = load_investigation()
        cls.report = cls.investigation.build_report()

    def test_report_covers_every_archived_observer_sample(self):
        self.investigation.validate_report(self.report)
        self.assertEqual(12, len(self.report["results"]))
        self.assertEqual(
            "diagnostic-without-applicable-tolerance",
            self.report["status"],
        )

    def test_moon_is_not_classified_as_light_time_backdated(self):
        moon_results = [result for result in self.report["results"] if result["body"] == "moon"]
        planet_results = [result for result in self.report["results"] if result["body"] != "moon"]

        self.assertEqual(3, len(moon_results))
        self.assertTrue(all(not result["productionAppliesLightTimeBackdating"] for result in moon_results))
        self.assertEqual(
            {"unmatched-no-light-time-backdating"},
            {result["comparisonClassification"] for result in moon_results},
        )
        self.assertTrue(all(result["productionAppliesLightTimeBackdating"] for result in planet_results))
        self.assertEqual(
            {"light-time-convention-aligned"},
            {result["comparisonClassification"] for result in planet_results},
        )

    def test_input_hash_mutation_is_rejected(self):
        mutated = copy.deepcopy(self.report)
        path = next(iter(mutated["inputSHA256"]))
        mutated["inputSHA256"][path] = "0" * 64

        with self.assertRaisesRegex(ValueError, "input hashes"):
            self.investigation.validate_report(mutated)

    def test_unit_conversion_mutation_is_rejected(self):
        mutated = copy.deepcopy(self.report)
        mutated["results"][0]["configurations"][0]["absoluteDifferenceKM"] *= 1_000

        with self.assertRaisesRegex(ValueError, "unit conversion"):
            self.investigation.validate_report(mutated)


if __name__ == "__main__":
    unittest.main()
