import copy
import gzip
import importlib.util
import json
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("repair", Path(__file__).with_name("check_current_search.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)


class CurrentSearchTests(unittest.TestCase):
    def test_population_and_named_outcome_are_not_blanket_exceptions(self):
        original, _, _ = R.M.load_archive()
        supplement = json.loads(gzip.decompress((R.M.SUPPLEMENT / "raw-runs.json.gz").read_bytes()))
        cases = R.M.protocol()["cases"] + R.M.supplement_protocol()["cases"]
        saved = {m: original[m]["swift"] + supplement[m]["swift"] for m in R.M.protocol()["models"]}
        with self.assertRaisesRegex(ValueError, "did not reject"):
            R.compare(saved, saved, cases)
        dropped = copy.deepcopy(saved)
        dropped["espenak-meeus"].pop()
        with self.assertRaisesRegex(ValueError, "population"):
            R.compare(saved, dropped, cases)
        with self.assertRaisesRegex(ValueError, "population"):
            R.compare(saved, saved, cases[:-1])

    def test_live_source_change_population(self):
        actual = R.source_identity()
        original = R.M.protocol()["currentSourceFilesSHA256"]
        self.assertEqual([p for p in actual if actual[p] != original[p]], ["Sources/CLibAstronomy/astronomy.c"])
