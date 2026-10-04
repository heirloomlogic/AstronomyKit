import copy
import importlib.util
import json
import math
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("polar_reference", ROOT / "Scripts/reference-data/investigate-polar-reference.py")
REFERENCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REFERENCE)


class PolarReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = REFERENCE.model_report()
        cls.parameters = REFERENCE.horizons_parameters(2923, -90, cls.model)
        cls.response, _ = REFERENCE.read_pair(2923, "horizons", cls.parameters)

    def test_rejects_wrong_clock_and_observer(self):
        for old, new in (("Date__(TT)__HR:MN", "Date__(UT)__HR:MN"), ("0.0, -90.0,", "0.0, -89.0,")):
            response = copy.deepcopy(self.response)
            response["result"] = response["result"].replace(old, new)
            with self.assertRaises(ValueError):
                REFERENCE.parse_horizons(response, -90, self.parameters["TLIST"])

    def test_rejects_epoch_coverage_mismatch(self):
        with self.assertRaisesRegex(ValueError, "epoch coverage"):
            REFERENCE.parse_horizons(self.response, -90, "'2451545'")

    def test_rejects_response_query_detachment(self):
        path = REFERENCE.ARCHIVE / "2923-horizons.query.json"
        recipe = json.loads(path.read_text())
        recipe["responseSHA256"] = "0" * 64
        with patch.object(Path, "read_text", return_value=json.dumps(recipe)):
            with self.assertRaisesRegex(ValueError, "detached"):
                REFERENCE.read_pair(2923, "horizons", self.parameters)

    def test_quadratic_root_for_rising_and_setting_crossings(self):
        # Analytic root of x + x*x/1000 - 10, independent of interpolation.
        expected = (-1000 + math.sqrt(1040000)) / 2
        for direction in (1, -1):
            rows = [{"ttDays": seconds / 86400, "residual": direction * (seconds + seconds**2 / 1000 - 10)} for seconds in (-30, 0, 30, 60)]
            root = REFERENCE.interpolate_root(rows, "residual")
            self.assertAlmostEqual(expected, root["ttDays"] * 86400, places=8)

    def test_requires_a_unique_bracketed_crossing(self):
        for values in ((1, 2, 3), (-1, 1, -1)):
            rows = [{"ttDays": i * 30 / 86400, "residual": value} for i, value in enumerate(values)]
            with self.assertRaisesRegex(ValueError, "exactly one"):
                REFERENCE.interpolate_root(rows, "residual")


if __name__ == "__main__":
    unittest.main()
