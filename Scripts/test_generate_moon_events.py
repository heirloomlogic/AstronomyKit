import importlib.util
import unittest
from pathlib import Path


class MoonEventFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("moon_events", Path(__file__).with_name("generate-moon-events.py"))
        cls.tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.tool)

    def test_frozen_windows_cover_both_ends_blends_and_source_transition(self):
        windows = self.tool.windows()
        self.assertEqual(20, len(windows))
        self.assertEqual(-1460999.75, windows[0]["startTT"])
        self.assertEqual(1460999.75, windows[16]["endTT"])
        self.assertEqual({"blend-1900", "blend-2131", "source-segment"}, {w["id"] for w in windows[17:]})
        for window in windows:
            self.assertLess(window["startTT"], window["endTT"])
            self.assertGreaterEqual(window["startTT"], -1461000)
            self.assertLessEqual(window["endTT"], 1461000)

    def test_committed_fixture_is_pinned_and_rejects_corruption(self):
        data = self.tool.OUTPUT.read_bytes()
        self.tool.check(data)
        with self.assertRaisesRegex(ValueError, "digest"):
            self.tool.check(data + b" ")

    def test_required_records_include_time_conversion_margin(self):
        chosen = self.tool.required_records([{"startTT": -0.5, "endTT": 3.5}], -0.5)
        self.assertEqual({-1, 0, 1}, chosen)

    def test_apparent_phase_references_are_source_bound(self):
        references = self.tool.apparent_phase_references()
        self.assertEqual(["firstQuarter", "full", "lastQuarter", "new"], [row["phase"] for row in references])
        self.assertTrue(all(row["samplingAllowanceSeconds"] == 1.0 for row in references))
        self.tool.check_apparent_phase_sources()


if __name__ == "__main__":
    unittest.main()
