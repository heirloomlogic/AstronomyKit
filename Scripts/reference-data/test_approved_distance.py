import importlib.util
import json
import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("approved_distance", ROOT / "Scripts/reference-data/assess-approved-distance.py")
ASSESSMENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ASSESSMENT)


class ApprovedDistanceTests(unittest.TestCase):
    def test_distance_boundary_is_inclusive_and_sign_invariant(self):
        boundary = 149.5978707
        for sign in (1, -1):
            self.assertFalse(ASSESSMENT.assess(1, sign * boundary, 1e-6)["nominalTargetExceeded"])
            self.assertTrue(ASSESSMENT.assess(1, sign * math.nextafter(boundary, math.inf), 1e-6)["nominalTargetExceeded"])

    def test_fractional_target_uses_reference_distance_and_kilometres(self):
        for distance_km, expected_km in ((384000, 0.384), (150000000, 150.0)):
            result = ASSESSMENT.assess(distance_km / 149597870.7, expected_km / 2, 1e-6)
            self.assertAlmostEqual(expected_km, result["allowedErrorKm"], places=10)
            self.assertAlmostEqual(0.5, result["errorPPM"], places=10)

    def test_rejects_invalid_reference_values_and_targets(self):
        for values in ((0, 1, 1e-6), (-1, 1, 1e-6), (1, math.nan, 1e-6), (1, 1, 0), (math.inf, 1, 1e-6)):
            with self.assertRaises(ValueError):
                ASSESSMENT.assess(*values)

    def test_body_specific_policy_does_not_apply_a_uniform_or_fallback_limit(self):
        policy = json.loads(ASSESSMENT.POLICY.read_text())
        for body, ppm in (("Sun", 1), ("Earth", 1), ("Mercury", 1), ("Venus", 1), ("Mars", 1), ("Jupiter", 1), ("Saturn", 1), ("Uranus", 10), ("Neptune", 10), ("Moon", 100), ("Pluto", 100)):
            limit = ASSESSMENT.relative_limit(policy, body)
            self.assertAlmostEqual(ppm, limit * 1e6)
            boundary = 149597870.7 * limit
            self.assertFalse(ASSESSMENT.assess(1, boundary, limit)["nominalTargetExceeded"])
            self.assertTrue(ASSESSMENT.assess(1, math.nextafter(boundary, math.inf), limit)["nominalTargetExceeded"])
        with self.assertRaisesRegex(ValueError, "no approved"):
            ASSESSMENT.relative_limit(policy, "Chiron")


if __name__ == "__main__":
    unittest.main()
