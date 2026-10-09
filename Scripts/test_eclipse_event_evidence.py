#!/usr/bin/env python3
"""Negative controls for native lunar-eclipse evidence."""

import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("eclipse_evidence", ROOT / "Scripts/record-eclipse-event-evidence.py")
RECORD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECORD)


class EclipseEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.captures = json.loads(RECORD.CAPTURES.read_bytes())

    def test_recorded_captures_validate(self):
        RECORD.evidence(self.captures, RECORD.source_hashes())

    def test_peak_outside_published_allowance_is_rejected(self):
        self.captures["debug"]["published"][0]["peakResidualSeconds"] = 121
        self.captures["release"]["published"][0]["peakResidualSeconds"] = 121
        with self.assertRaisesRegex(ValueError, "peak criterion"):
            RECORD.evidence(self.captures, {})

    def test_debug_release_disagreement_is_rejected(self):
        self.captures["debug"]["published"][0]["obscuration"] += 0.01
        with self.assertRaisesRegex(ValueError, "Debug and Release"):
            RECORD.evidence(self.captures, {})

    def test_obscuration_outside_print_interval_is_rejected(self):
        for configuration in ("debug", "release"):
            self.captures[configuration]["obscurations"][0]["obscuration"] = 0.99
        with self.assertRaisesRegex(ValueError, "print interval criterion"):
            RECORD.evidence(self.captures, {})


if __name__ == "__main__":
    unittest.main()
