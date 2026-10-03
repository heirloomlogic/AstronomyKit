import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_diagnostic():
    path = ROOT / "Scripts/reference-data/diagnose-polar-sunrise.py"
    spec = importlib.util.spec_from_file_location("polar_sunrise_diagnostic", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PolarSunriseDiagnosticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.diagnostic = load_diagnostic()

    def test_source_transformations_change_only_requested_model_boundary(self):
        current = self.diagnostic.read_verified_source(self.diagnostic.CURRENT_SOURCE, self.diagnostic.CURRENT_SOURCE_SHA256)
        pinned = self.diagnostic.read_verified_source(self.diagnostic.PINNED_SOURCE, self.diagnostic.PINNED_SOURCE_SHA256)

        no_polynomial = self.diagnostic.disable_polynomial(current)
        pinned_nutation = self.diagnostic.exchange_nutation(current, pinned)
        pinned_vsop = self.diagnostic.exchange_vsop(current, pinned)

        self.assertEqual(3, no_polynomial.count("DIAGNOSTIC_POLYNOMIAL_DISABLED"))
        self.assertIn("Truncated and hand-optimized nutation model", pinned_nutation)
        self.assertNotIn('#include "generated/vsop87b_full.h"', pinned_vsop)
        self.assertIn("static const vsop_term_t vsop_lon_Mercury_0[]", pinned_vsop)
        self.assertIn("{ 12, vsop_rad_Neptune_0 }", pinned_vsop)

    def test_report_validation_requires_all_controls_and_the_archived_failure(self):
        report = {
            "variants": {
                name: {"events": [
                    {"sourceLine": line, "ttErrorSeconds": 75.985957542, "eventAltitudeResidualDegrees": 0.0}
                    for line in (2922, 2923, 5908, 5909)
                ]}
                for name in self.diagnostic.VARIANT_NAMES
            }
        }
        self.diagnostic.validate_report(report)
        del report["variants"]["current-no-polynomial-pinned-vsop"]
        with self.assertRaisesRegex(RuntimeError, "variant set"):
            self.diagnostic.validate_report(report)

    def test_check_rejects_a_changed_recorded_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "report.json"
            path.write_text(json.dumps({"wrong": True}) + "\n")
            with self.assertRaisesRegex(RuntimeError, "report is stale"):
                self.diagnostic.check_report(path, {"correct": True})

    def test_recorded_report_matches_compiled_controls(self):
        report = self.diagnostic.build_report()
        self.diagnostic.check_report(self.diagnostic.REPORT, report)

    def test_source_hash_verification_rejects_drift(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "source.c"
            path.write_text("changed")
            with self.assertRaisesRegex(RuntimeError, "source hash changed"):
                self.diagnostic.read_verified_source(path, "0" * 64)


if __name__ == "__main__":
    unittest.main()
