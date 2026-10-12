import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


class MoonEventFixtureTests(unittest.TestCase):
    evidence_files = (
        "Scripts/moon-data/de441-event-evidence.json",
    )

    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("moon_events", Path(__file__).with_name("generate-moon-events.py"))
        cls.tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.tool)

    def write_evidence(self, root, evidence_name, source_hashes):
        evidence = root / evidence_name
        evidence.parent.mkdir(parents=True)
        evidence.write_text(json.dumps({"sourceSHA256": source_hashes}))
        return evidence

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

    def test_committed_event_and_native_evidence_bind_all_named_sources(self):
        counts = [self.tool.check_source_hashes(self.tool.ROOT / name) for name in self.evidence_files]
        self.assertGreater(counts[0], 15)

    def test_apparent_event_evidence_binds_composition_clock_and_orientation(self):
        evidence = json.loads((self.tool.ROOT / self.evidence_files[0]).read_bytes())
        for name in [
            "Sources/AstronomyKit/Engine/Positions/EngineApparentComposition.swift",
            "Sources/AstronomyKit/Engine/Moon/EngineTDB.swift",
            "Sources/AstronomyKit/Engine/Orientation/EnginePrecession.swift",
        ]:
            with self.subTest(source=name):
                self.assertIn(name, evidence["sourceSHA256"])

    def test_event_replay_rejects_omitted_composition_binding(self):
        value = json.loads((self.tool.ROOT / self.evidence_files[0]).read_bytes())
        value["sourceSHA256"].pop("Sources/AstronomyKit/Engine/Positions/EngineApparentComposition.swift", None)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"
            path.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError, "source binding coverage differs"):
                self.tool.check_source_hashes(path, required_sources=self.tool.event_source_paths())

    def test_event_and_native_evidence_reject_stale_source_digest(self):
        for evidence_name in self.evidence_files:
            with self.subTest(evidence=evidence_name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = root / "Sources/current.swift"
                source.parent.mkdir(parents=True)
                source.write_text("current")
                evidence = self.write_evidence(root, evidence_name, {"Sources/current.swift": "0" * 64})
                with self.assertRaisesRegex(ValueError, "source digest differs for Sources/current.swift"):
                    self.tool.check_source_hashes(evidence, root)

    def test_event_and_native_evidence_reject_missing_named_source(self):
        for evidence_name in self.evidence_files:
            with self.subTest(evidence=evidence_name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                evidence = self.write_evidence(
                    root, evidence_name, {"Sources/missing.swift": hashlib.sha256(b"").hexdigest()}
                )
                with self.assertRaisesRegex(ValueError, "named source is missing: Sources/missing.swift"):
                    self.tool.check_source_hashes(evidence, root)

    def test_event_and_native_evidence_reject_malformed_source_map(self):
        for evidence_name in self.evidence_files:
            with self.subTest(evidence=evidence_name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                evidence = self.write_evidence(root, evidence_name, [])
                with self.assertRaisesRegex(ValueError, "sourceSHA256 must be a non-empty object"):
                    self.tool.check_source_hashes(evidence, root)


if __name__ == "__main__":
    unittest.main()
