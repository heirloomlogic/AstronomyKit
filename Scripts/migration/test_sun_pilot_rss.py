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
            ("minimalSwift", "foundationOnly", "modelLinked", "pilotRunner"),
        )
        self.assertEqual(MODULE.CONTROLS["pilotRunner"]["arguments"], ["--rss-stage", "startup"])
        self.assertEqual(MODULE.TRIALS, 5)

    def test_validate_measurements_requires_five_fresh_process_samples(self):
        valid = {name: self.samples(10, 11, 12, 13, 14) for name in MODULE.CONTROLS}
        self.assertIs(MODULE.validate_measurements(valid), valid)
        with self.assertRaisesRegex(ValueError, "five fresh-process trials"):
            MODULE.validate_measurements({**valid, "modelLinked": self.samples(10, 11, 12, 13)})
        with self.assertRaisesRegex(ValueError, "positive peak resident bytes"):
            MODULE.validate_measurements({**valid, "foundationOnly": self.samples(10, 11, 0, 13, 14)})

    def test_summary_reports_observed_ranges_without_causal_attribution(self):
        measurements = {
            "minimalSwift": self.samples(70, 71, 72, 73, 74),
            "foundationOnly": self.samples(130, 131, 132, 133, 134),
            "modelLinked": self.samples(140, 141, 142, 143, 144),
            "pilotRunner": self.samples(150, 151, 152, 153, 154),
        }
        result = MODULE.summarize_measurements(measurements, ceiling=100)
        self.assertTrue(result["foundationControlExceedsCeiling"])
        self.assertTrue(result["modelLinkedRangeDisjointAboveFoundation"])
        self.assertTrue(result["pilotRunnerRangeDisjointAboveFoundation"])
        self.assertEqual(result["modelLinkedMedianDifferenceFromFoundationBytes"], 10)
        self.assertEqual(result["pilotRunnerMedianDifferenceFromFoundationBytes"], 20)
        self.assertEqual(result["causalAttribution"], "not-established-by-independent-process-peak-rss")
        self.assertEqual(result["decision"], "foundation-control-exceeds-ceiling")
        for removed in ("candidateRemovalCanMeetCeiling", "candidateLinkageCostDetected", "modelLinkageRangeSeparatedFromFoundation"):
            self.assertNotIn(removed, result)

    def test_disjoint_ranges_do_not_claim_removable_candidate_cost(self):
        measurements = {
            "minimalSwift": self.samples(70, 71, 72, 73, 74),
            "foundationOnly": self.samples(80, 81, 82, 83, 84),
            "modelLinked": self.samples(110, 111, 112, 113, 114),
            "pilotRunner": self.samples(120, 121, 122, 123, 124),
        }
        result = MODULE.summarize_measurements(measurements, ceiling=100)
        self.assertFalse(result["foundationControlExceedsCeiling"])
        self.assertTrue(result["modelLinkedRangeDisjointAboveFoundation"])
        self.assertEqual(result["causalAttribution"], "not-established-by-independent-process-peak-rss")
        self.assertEqual(result["decision"], "all-controls-within-ceiling-or-attribution-unresolved")

    def test_overlapping_ranges_do_not_claim_attribution(self):
        measurements = {
            "minimalSwift": self.samples(70, 71, 72, 73, 74),
            "foundationOnly": self.samples(80, 82, 84, 86, 88),
            "modelLinked": self.samples(86, 88, 90, 92, 94),
            "pilotRunner": self.samples(87, 89, 91, 93, 95),
        }
        result = MODULE.summarize_measurements(measurements, ceiling=100)
        self.assertFalse(result["modelLinkedRangeDisjointAboveFoundation"])
        self.assertEqual(result["causalAttribution"], "not-established-by-independent-process-peak-rss")

    def test_blocked_stdin_read_requires_observed_read_syscall_on_fd_zero(self):
        self.assertTrue(MODULE.is_blocked_stdin_read("0 0x0 0x7fff 0x1000", "x86_64"))
        self.assertTrue(MODULE.is_blocked_stdin_read("63 0x0 0xffff 0x1000", "aarch64"))
        self.assertFalse(MODULE.is_blocked_stdin_read("running", "x86_64"))
        self.assertFalse(MODULE.is_blocked_stdin_read("0 0x1 0x7fff 0x1000", "x86_64"))
        self.assertFalse(MODULE.is_blocked_stdin_read("1 0x0 0x7fff 0x1000", "x86_64"))

    def test_mapping_snapshot_requires_expected_loaded_libraries(self):
        loaded = "\n".join(["mapping"] * 20 + ["/usr/lib/swift/linux/libFoundation.so"])
        self.assertEqual(MODULE.validate_mapping_snapshot("foundationOnly", loaded), 21)
        for name in ("minimalSwift", "modelLinked", "pilotRunner"):
            self.assertEqual(MODULE.validate_mapping_snapshot(name, "\n".join(["mapping"] * 21)), 21)
            with self.assertRaisesRegex(ValueError, "unexpectedly includes Foundation"):
                MODULE.validate_mapping_snapshot(name, loaded)
        with self.assertRaisesRegex(ValueError, "too few mappings"):
            MODULE.validate_mapping_snapshot("minimalSwift", "\n".join(["mapping"] * 12))
        with self.assertRaisesRegex(ValueError, "Foundation mapping"):
            MODULE.validate_mapping_snapshot("foundationOnly", "\n".join(["mapping"] * 21))


if __name__ == "__main__":
    unittest.main()
