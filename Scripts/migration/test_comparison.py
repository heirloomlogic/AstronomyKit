import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/migration/run-comparison.py"
CORPUS = ROOT / "Tools/Migration/Comparison/corpus.json"
ARTIFACTS = ROOT / "Tools/Migration/Comparison/Artifacts/reference"


def load_comparison():
    spec = importlib.util.spec_from_file_location("migration_comparison", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ComparisonProtocolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.comparison = load_comparison()
        cls.corpus = json.loads(CORPUS.read_text())

    def test_corpus_covers_required_surfaces_and_modes(self):
        self.comparison.validate_corpus(self.corpus)
        tags = {tag for case in self.corpus["cases"] for tag in case["coverage"]}
        self.assertTrue(
            {
                "positions",
                "derivatives",
                "events",
                "cold-warm",
                "delta-t-espenak-meeus",
                "delta-t-jpl-horizons",
                "stars",
                "pluto",
                "gravity",
                "chiron",
                "errors",
            }.issubset(tags)
        )

    def test_numeric_negative_control_is_detected(self):
        expected = {"status": "success", "value": {"x": 1.0, "y": 2.0}}
        actual = {"status": "success", "value": {"x": 1.0, "y": 2.000001}}
        paths = {item["path"] for item in self.comparison.canonical_differences(expected, actual)}
        self.assertEqual({"$.value.y"}, paths)

    def test_status_negative_control_is_detected(self):
        expected = {"status": "success", "value": None}
        actual = {"status": "bad-time", "value": None}
        paths = {item["path"] for item in self.comparison.canonical_differences(expected, actual)}
        self.assertEqual({"$.status"}, paths)

    def test_time_model_negative_control_is_detected(self):
        expected = {"model": "espenak-meeus", "ut": 0.0, "tt": 0.0}
        actual = {"model": "jpl-horizons", "ut": 0.0, "tt": 0.0}
        paths = {item["path"] for item in self.comparison.canonical_differences(expected, actual)}
        self.assertEqual({"$.model"}, paths)

    def test_event_order_negative_control_is_detected(self):
        expected = {"events": [{"name": "march"}, {"name": "june"}]}
        actual = {"events": [{"name": "june"}, {"name": "march"}]}
        paths = {item["path"] for item in self.comparison.canonical_differences(expected, actual)}
        self.assertEqual({"$.events[0].name", "$.events[1].name"}, paths)

    def test_checked_in_archive_is_complete_and_content_addressed(self):
        manifest = json.loads((ARTIFACTS / "manifest.json").read_text())
        self.comparison.validate_archive(ARTIFACTS, manifest)
        self.assertEqual(
            {
                "c-output.json",
                "diffs.json",
                "downstream-populations.json",
                "inputs.json",
                "metadata.json",
                "swift-output.json",
            },
            set(manifest["files"]),
        )

    def test_archive_names_the_exact_candidate_sources(self):
        metadata = json.loads((ARTIFACTS / "metadata.json").read_text())
        self.assertEqual(self.comparison.source_hashes(), metadata["sourceHashes"])

    def test_executable_fingerprint_ignores_build_paths_but_detects_code_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executables = []
            for name, result in (("first", 0), ("second", 0), ("changed", 1)):
                directory = root / name
                directory.mkdir()
                source = directory / "probe.c"
                executable = directory / "probe"
                source.write_text(f"int main(void) {{ return {result}; }}\n")
                subprocess.run(["clang", "-g", str(source), "-o", str(executable)], check=True)
                executables.append(executable)
            first, second, changed = map(self.comparison.executable_fingerprint, executables)
            self.assertEqual(first, second)
            self.assertNotEqual(first, changed)

    def test_executable_fingerprint_rejects_signature_removal_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / "probe"
            executable.write_bytes(b"unsigned")
            def run(command, **kwargs):
                if command[0] == "codesign" and kwargs["check"]:
                    raise subprocess.CalledProcessError(1, command)
                return subprocess.CompletedProcess(command, 0)

            with mock.patch.object(self.comparison.platform, "system", return_value="Darwin"):
                with mock.patch.object(self.comparison.subprocess, "run", side_effect=run) as run_mock:
                    with self.assertRaises(subprocess.CalledProcessError):
                        self.comparison.executable_fingerprint(executable)
            self.assertTrue(run_mock.call_args_list[0].kwargs["check"])

    def test_downstream_populations_match_pinned_git_objects(self):
        lock = json.loads((ROOT / "Tools/Migration/Comparison/downstream-populations-lock.json").read_text())
        recovered, cases = self.comparison.recover_populations(lock)
        archived = json.loads((ARTIFACTS / "downstream-populations.json").read_text())
        self.assertEqual(archived, recovered)
        self.assertEqual(8, len(cases))
        self.assertEqual(7_746_010, sum(item["recordCount"] for item in recovered["populations"]))

    def test_archive_check_rejects_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary)
            for source in ARTIFACTS.iterdir():
                destination.joinpath(source.name).write_bytes(source.read_bytes())
            destination.joinpath("inputs.json").write_text("{}\n")
            manifest = json.loads(destination.joinpath("manifest.json").read_text())
            with self.assertRaisesRegex(ValueError, "inputs.json"):
                self.comparison.validate_archive(destination, manifest)


if __name__ == "__main__":
    unittest.main()
