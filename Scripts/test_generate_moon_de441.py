import importlib.util
import hashlib
import json
import unittest
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


class MoonDE441GenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("generate_de441", Path(__file__).with_name("generate-moon-de441.py"))
        cls.tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.tool)

    def test_binary_identity_rejects_changed_payload_even_with_correct_length(self):
        with self.assertRaisesRegex(ValueError, "digest"):
            self.tool.validate(b"abcdefgh", {"encodedBytes": 8, "sha256": "0" * 64})

    def test_binary_identity_rejects_wrong_length(self):
        with self.assertRaisesRegex(ValueError, "length"):
            self.tool.validate(b"abc", {"encodedBytes": 8, "sha256": "0" * 64})

    def test_generated_payload_roundtrips_offline(self):
        payload = bytes(range(256)) * 2
        rendered = self.tool.render(payload, -100.5, 10)
        self.assertEqual(payload, self.tool.extract(rendered))
        self.assertIn("static let start = -100.5", rendered)
        self.assertIn("static let recordCount = 10", rendered)

    def test_moon_generators_coexist_through_checks_and_regeneration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = json.loads((self.tool.ROOT / "Scripts/moon-data/manifest.json").read_text())
            generated = self.tool.ROOT / "Sources/AstronomyKit/Engine/Moon/Generated"
            relative_files = ["Scripts/generate-moon-tables.py", "Scripts/generate-moon-de441.py",
                              "Scripts/moon-data/manifest.json", "Scripts/moon-data/de441-compact-evidence.json"]
            relative_files += list(manifest["files"])
            relative_files += [str(path.relative_to(self.tool.ROOT)) for path in generated.rglob("*.swift")]
            for relative in relative_files:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(self.tool.ROOT / relative, target)
            output = root / self.tool.OUTPUT.relative_to(self.tool.ROOT)
            binary = root / "qualified.bin"
            binary.write_bytes(self.tool.extract(output.read_text()))
            expected = {path.relative_to(root): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in (root / generated.relative_to(self.tool.ROOT)).rglob("*.swift")}
            commands = [("generate-moon-tables.py", "--check"), ("generate-moon-tables.py",),
                        ("generate-moon-de441.py", "--check"),
                        ("generate-moon-de441.py", "--binary", str(binary)),
                        ("generate-moon-tables.py", "--check"), ("generate-moon-de441.py", "--check")]
            for command in commands:
                with self.subTest(command=command):
                    if "--binary" in command:
                        output.unlink(missing_ok=True)
                        if output.parent != root / generated.relative_to(self.tool.ROOT):
                            output.parent.rmdir()
                    result = subprocess.run([sys.executable, str(root / "Scripts" / command[0]), *command[1:]],
                                            capture_output=True, text=True)
                    self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                    actual = {path.relative_to(root): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in (root / generated.relative_to(self.tool.ROOT)).rglob("*.swift")}
                    self.assertEqual(expected, actual)

    def test_reference_fixtures_pin_the_source_evidence_and_include_interior_rates(self):
        data = json.loads((self.tool.ROOT / "Scripts/moon-data/de441-native-fixtures.json").read_bytes())
        self.assertEqual(hashlib.sha256(self.tool.MANIFEST.read_bytes()).hexdigest(), data["sourceEvidenceSHA256"])
        self.assertEqual(273, data["recordCount"])
        self.assertEqual(1365, len(data["rows"]))
        self.assertEqual({-1, -.5, 0, .5, 1}, {row["x"] for row in data["rows"]})


if __name__ == "__main__":
    unittest.main()
