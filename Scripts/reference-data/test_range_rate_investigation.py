import importlib.util
import math
import unittest
from pathlib import Path

PATH = Path(__file__).with_name("investigate-range-rate.py")
SPEC = importlib.util.spec_from_file_location("range_rate", PATH)
RATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RATE)


class RangeRateInvestigationTests(unittest.TestCase):
    def test_signed_projection_and_si_units(self):
        self.assertEqual(RATE.radial([3, 4, 0], [1, -2, 0]), -1)
        self.assertEqual(RATE.to_kms(1), 149597870.7 / 86400)
        self.assertEqual(RATE.radial([3, 4, 0], [-1, 2, 0]), 1)

    def test_projection_rejects_invalid_states(self):
        for position, velocity in [([0, 0, 0], [1, 0, 0]), ([1, 0], [1, 0, 0]),
                                   ([1, 0, 0], [math.nan, 0, 0]), ([math.inf, 0, 0], [1, 0, 0])]:
            with self.subTest(position=position):
                with self.assertRaises(ValueError):
                    RATE.radial(position, velocity)

    def test_raw_projection_controls_reject_wrong_sign_and_units(self):
        row = dict(positionAU=[3, 4, 0], velocityAUPerDay=[1, -2, 0], rangeRateAUPerDay=-1)
        RATE.validate_projection(row)
        for wrong in [1, RATE.to_kms(-1), -86400]:
            with self.subTest(wrong=wrong):
                with self.assertRaises(ValueError):
                    RATE.validate_projection(dict(row, rangeRateAUPerDay=wrong))

    def test_convention_match_requires_geometric_tt_state(self):
        self.assertEqual(RATE.classification("Moon", "geocentric", "NONE", "TT"), "geometric-state-matched")
        self.assertEqual(RATE.classification("Mercury", "heliocentric", "NONE", "TT"), "geometric-state-matched")
        self.assertEqual(RATE.classification("Mars", "geocentric", "LT", "TT"), "received-light-unmatched-derivative-and-origin")
        for body, mode, correction, scale in [("Moon", "geocentric", "LT", "TT"),
                                              ("Mars", "heliocentric", "LT", "TT"),
                                              ("Mars", "heliocentric", "NONE", "TDB")]:
            with self.subTest(scale=scale, correction=correction):
                with self.assertRaises(ValueError):
                    RATE.classification(body, mode, correction, scale)

    def test_light_time_chain_factor_has_distinct_sign_and_velocity(self):
        velocity, factor = RATE.received_velocity([1, 0, 0], [2, 0, 0], [1, 0, 0], 10)
        self.assertAlmostEqual(factor, 11 / 12)
        self.assertAlmostEqual(velocity[0], 5 / 6)
        self.assertNotEqual(RATE.radial([1, 0, 0], velocity), 1)
        self.assertNotEqual(velocity, [1, 0, 0])

    def test_moving_sun_bridge_requires_emission_chain_factor(self):
        position, velocity = RATE.fixed_sun_bridge([10, 0, 0], [2, 0, 0],
                                                   [3, 0, 0], [1, 0, 0], [4, 0, 0], [2, 0, 0], .5)
        self.assertEqual(position, [8, 0, 0])
        self.assertEqual(velocity, [2, 0, 0])
        self.assertNotEqual(velocity, RATE.fixed_sun_bridge([10, 0, 0], [2, 0, 0],
                                                          [3, 0, 0], [1, 0, 0], [4, 0, 0], [2, 0, 0], 1)[1])

    def test_frozen_archive_projection_and_sun_convention_evidence(self):
        records, _ = RATE.references()
        self.assertEqual(len(records), 5035)
        self.assertEqual(sum(r["classification"] == "geometric-state-matched" for r in records), 2650)
        proof = RATE.sun_velocity_evidence()
        self.assertEqual(len(proof["cases"]), 265)
        # Distinguish algebraic reconstruction rounding from the reception-chain convention change.
        self.assertLess(proof["maximumRawVelocityResidualKmPerSecond"], 1e-12)
        self.assertGreater(proof["maximumChainVelocityResidualKmPerSecond"], 1e-8)

    def test_report_rejects_detached_source_hashes_and_missing_population(self):
        report = {"status": RATE.STATUS, "accuracyAllowance": None, "inputSHA256": {}}
        with self.assertRaisesRegex(ValueError, "stale"):
            RATE.validate_report(report)
        report["inputSHA256"] = RATE.input_hashes()
        report["results"] = []
        with self.assertRaisesRegex(ValueError, "population"):
            RATE.validate_report(report)

    def test_report_never_adopts_an_accuracy_threshold(self):
        with self.assertRaises(ValueError):
            RATE.validate_report({"status": "accuracy-passed"})


if __name__ == "__main__":
    unittest.main()
