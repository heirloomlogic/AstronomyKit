"""Tests for the complete development-only Swift model generator."""

import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "generate_models", ROOT / "Scripts/generate-models.py"
)
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class SwiftModelGenerationTests(unittest.TestCase):
    def test_complete_archive_inventory(self):
        model = GENERATOR.load_swift_model()
        self.assertEqual(sum(len(body.coefficient_bits) for body in model.polynomials), 1_431_768)
        self.assertEqual(sum(bit == 0 for body in model.polynomials for bit in body.validity), 413)
        self.assertEqual(len(model.nutation_rows), 77)
        self.assertGreater(len(model.vsop_terms), 0)
        self.assertEqual(sum(series.count for series in model.vsop_series), len(model.vsop_terms))

    def test_binary64_and_validity_hashes_match_frozen_manifest(self):
        model = GENERATOR.load_swift_model()
        for body in model.polynomials:
            coefficient_bytes = b"".join(value.to_bytes(8, "little") for value in body.coefficient_bits)
            self.assertEqual(hashlib.sha256(coefficient_bytes).hexdigest(), body.coefficient_sha256)
            self.assertEqual(hashlib.sha256(body.validity).hexdigest(), body.validity_sha256)

    def test_render_is_deterministic_and_manifest_covers_every_output(self):
        first = GENERATOR.render_swift_model()
        second = GENERATOR.render_swift_model()
        self.assertEqual(first, second)
        manifest = GENERATOR.swift_output_manifest(first)
        self.assertEqual(set(manifest["outputs"]), set(first))
        for name, content in first.items():
            self.assertEqual(manifest["outputs"][name], hashlib.sha256(content.encode()).hexdigest())

    def test_generated_metadata_includes_exact_polynomial_grid_bounds(self):
        metadata = GENERATOR.render_swift_model()["AstronomyModelPrototypeGenerated/Generated/Metadata.swift"]
        self.assertIn("startTT: Double(bitPattern: 0xc0e1d59000000000)", metadata)
        self.assertIn("stopTT: Double(bitPattern: 0x40e2033000000000)", metadata)

    def test_input_manifest_covers_every_archive_file(self):
        manifest = GENERATOR.swift_input_manifest()
        expected = {
            path.relative_to(ROOT).as_posix()
            for directory in (ROOT / "Scripts/model-data", ROOT / "Scripts/performance/polynomial/data")
            for path in directory.rglob("*")
            if path.is_file() and path != GENERATOR.SWIFT_MANIFEST
        }
        self.assertEqual(set(manifest), expected)

    def test_check_rejects_stale_generated_source(self):
        outputs = {"AstronomyModelPrototype/Generated/Metadata.swift": "expected"}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            generated = root / "AstronomyModelPrototype/Generated"
            generated.mkdir(parents=True)
            (generated / "Metadata.swift").write_text("expected")
            (generated / "Stale.swift").write_text("stale")
            manifest = root / "manifest.json"
            manifest.write_text("manifest\n")
            with patch.object(GENERATOR, "SWIFT_OUTPUT", root), patch.object(GENERATOR, "SWIFT_MANIFEST", manifest), patch.object(GENERATOR, "render_swift_model", return_value=outputs), patch.object(GENERATOR, "swift_output_manifest", return_value="ignored"), patch.object(GENERATOR.json, "dumps", return_value="manifest"):
                with self.assertRaisesRegex(SystemExit, "file set differs"):
                    GENERATOR.write_swift_model(check=True)


if __name__ == "__main__":
    unittest.main()
