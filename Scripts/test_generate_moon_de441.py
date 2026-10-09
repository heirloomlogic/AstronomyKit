import importlib.util
import hashlib
import json
import unittest
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

    def test_reference_fixtures_pin_the_source_evidence_and_include_interior_rates(self):
        data = json.loads((self.tool.ROOT / "Scripts/moon-data/de441-native-fixtures.json").read_bytes())
        self.assertEqual(hashlib.sha256(self.tool.MANIFEST.read_bytes()).hexdigest(), data["sourceEvidenceSHA256"])
        self.assertEqual(273, data["recordCount"])
        self.assertEqual(1365, len(data["rows"]))
        self.assertEqual({-1, -.5, 0, .5, 1}, {row["x"] for row in data["rows"]})


if __name__ == "__main__":
    unittest.main()
