import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import measure


class MeasurementProvenanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.saved = json.loads(Path(__file__).with_name("evidence").joinpath("macos-arm64-debug.json").read_text())

    def recheck(self, report):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "report.json"
            path.write_text(json.dumps(report))
            with patch("sys.argv", ["measure.py", "--recheck", "--output", str(path)]), contextlib.redirect_stdout(io.StringIO()):
                measure.main()

    def test_recheck_requires_the_complete_canonical_request_sequence(self):
        for mutation in ["delete", "reorder", "rename", "duplicate"]:
            with self.subTest(mutation=mutation):
                changed = copy.deepcopy(self.saved)
                for field in ["requests", "rows"]:
                    if mutation == "delete":
                        del changed[field][0]
                    elif mutation == "reorder":
                        changed[field][0], changed[field][1] = changed[field][1], changed[field][0]
                    elif mutation == "rename":
                        changed[field][0]["id"] = "different-request"
                    else:
                        changed[field][0] = copy.deepcopy(changed[field][1])
                with self.assertRaisesRegex(SystemExit, "canonical request grid"):
                    self.recheck(changed)

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
