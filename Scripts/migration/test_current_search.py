import copy
import gzip
import importlib.util
import json
from pathlib import Path
import unittest
import shutil
import tempfile

SPEC = importlib.util.spec_from_file_location("repair", Path(__file__).with_name("check_current_search.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)


class CurrentSearchTests(unittest.TestCase):
    def test_population_and_named_outcome_are_not_blanket_exceptions(self):
        original, _, _ = R.M.load_archive()
        supplement = R.load_supplement()
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

    def test_authenticated_supplement_and_rehashed_mutation(self):
        R.load_supplement()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "supplement"
            shutil.copytree(R.M.SUPPLEMENT, root)
            raw = root / "raw-runs.json.gz"
            raw.write_bytes(gzip.compress(b"{}"))
            with self.assertRaisesRegex(ValueError, "artifact detached"):
                R.load_supplement(root)
            manifest = json.loads((root / "manifest.json").read_text())
            manifest["filesSHA256"][raw.name] = R.M.sha(raw.read_bytes())
            (root / "manifest.json").write_text(R.M.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "immutable identity"):
                R.load_supplement(root)

    def test_unchanged_trace_mutations_are_rejected(self):
        events = [{"event": "callback", "time": {"ut": R.M.packet(20000.0)}, "value": R.M.packet(1.0)}, {"event": "terminal", "outcome": "absent"}]
        R.compare_events(events, copy.deepcopy(events))
        for changed in [events[::-1], events[:-1], [{"event": "callback", "time": {"ut": R.M.packet(20001.0)}, "value": R.M.packet(1.0)}, events[-1]], [events[0], {"event": "terminal", "outcome": "value"}]]:
            with self.assertRaises(ValueError):
                R.compare_events(events, changed)
