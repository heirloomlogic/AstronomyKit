import copy
import json
from pathlib import Path
import unittest

import measure


class MeasurementProvenanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.saved = json.loads(Path(__file__).with_name("evidence").joinpath("macos-arm64-debug.json").read_text())

    def test_saved_reference_is_reexecuted(self):
        rows = self.saved["rows"][:1]
        self.assertEqual(measure.comparisons(rows, self.saved["requests"][:1]), rows)
        changed = copy.deepcopy(rows)
        changed[0]["reference"]["earthX"] = "0"
        self.assertNotEqual(measure.comparisons(changed, self.saved["requests"][:1]), changed)

    def test_altered_summary_is_rejected(self):
        changed = copy.deepcopy(self.saved)
        changed["sampledMaximumAbsoluteError"]["earthX"] = "0"
        with self.assertRaisesRegex(ValueError, "maxima"):
            measure.verify_summary(changed)

    def test_wrong_request_association_is_rejected(self):
        row = copy.deepcopy(self.saved["rows"][:1])
        row[0]["id"] = "wrong-epoch"
        with self.assertRaisesRegex(ValueError, "wrong request"):
            measure.comparisons(row, self.saved["requests"][:1])

    def test_lost_input_bits_are_rejected(self):
        row = copy.deepcopy(self.saved["rows"][:1])
        row[0]["values"]["input"] = "0"
        with self.assertRaisesRegex(ValueError, "input bits"):
            measure.comparisons(row, self.saved["requests"][:1])

    def test_missing_or_duplicate_output_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Missing or duplicate"):
            measure.comparisons([], self.saved["requests"][:1])
        with self.assertRaisesRegex(ValueError, "Missing or duplicate"):
            measure.comparisons(self.saved["rows"][:1] * 2, self.saved["requests"][:2])


if __name__ == "__main__":
    unittest.main()
