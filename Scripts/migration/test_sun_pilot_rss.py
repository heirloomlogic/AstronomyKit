import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("sun_pilot_rss", Path(__file__).with_name("sun_pilot_rss.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SunPilotRSSControlTests(unittest.TestCase):
    def samples(self, *values):
        return [{"peakResidentBytes": value, "stdout": "0.0\n"} for value in values]

    def test_control_inventory_separates_runtime_foundation_model_and_runner(self):
        self.assertEqual(
            tuple(MODULE.CONTROLS),
            ("minimalSwift", "foundationOnly", "modelLinked", "unchangedRunner"),
        )
        self.assertEqual(MODULE.CONTROLS["unchangedRunner"]["arguments"], ["--rss-stage", "startup"])
        self.assertEqual(MODULE.TRIALS, 5)

    def test_validate_measurements_requires_five_fresh_process_samples(self):
        valid = {name: self.samples(10, 11, 12, 13, 14) for name in MODULE.CONTROLS}
        self.assertIs(MODULE.validate_measurements(valid), valid)
        with self.assertRaisesRegex(ValueError, "five fresh-process trials"):
            MODULE.validate_measurements({**valid, "modelLinked": self.samples(10, 11, 12, 13)})
        with self.assertRaisesRegex(ValueError, "positive peak resident bytes"):
            MODULE.validate_measurements({**valid, "foundationOnly": self.samples(10, 11, 0, 13, 14)})

    def test_conclusion_rejects_candidate_remediation_when_foundation_floor_fails(self):
        measurements = {
            "minimalSwift": self.samples(120, 121, 122, 123, 124),
            "foundationOnly": self.samples(130, 131, 132, 133, 134),
            "modelLinked": self.samples(140, 141, 142, 143, 144),
            "unchangedRunner": self.samples(150, 151, 152, 153, 154),
        }
        result = MODULE.summarize_measurements(measurements, ceiling=100)
        self.assertFalse(result["candidateRemovalCanMeetCeiling"])
        self.assertTrue(result["modelLinkageRangeSeparatedFromFoundation"])
        self.assertEqual(result["decision"], "runtime-floor-exceeds-ceiling")

    def test_conclusion_detects_bounded_candidate_linkage_cost(self):
        measurements = {
            "minimalSwift": self.samples(70, 71, 72, 73, 74),
            "foundationOnly": self.samples(80, 81, 82, 83, 84),
            "modelLinked": self.samples(110, 111, 112, 113, 114),
            "unchangedRunner": self.samples(120, 121, 122, 123, 124),
        }
        result = MODULE.summarize_measurements(measurements, ceiling=100)
        self.assertTrue(result["candidateRemovalCanMeetCeiling"])
        self.assertTrue(result["modelLinkageRangeSeparatedFromFoundation"])
        self.assertEqual(result["decision"], "candidate-linkage-cost-detected")

    def test_overlapping_ranges_do_not_claim_attribution(self):
        measurements = {
            "minimalSwift": self.samples(70, 71, 72, 73, 74),
            "foundationOnly": self.samples(80, 82, 84, 86, 88),
            "modelLinked": self.samples(86, 88, 90, 92, 94),
            "unchangedRunner": self.samples(87, 89, 91, 93, 95),
        }
        result = MODULE.summarize_measurements(measurements, ceiling=100)
        self.assertFalse(result["modelLinkageRangeSeparatedFromFoundation"])
        self.assertEqual(result["decision"], "no-separated-candidate-linkage-cost")


if __name__ == "__main__":
    unittest.main()
