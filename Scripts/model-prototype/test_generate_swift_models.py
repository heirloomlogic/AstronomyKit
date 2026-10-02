"""Tests for the complete development-only Swift model generator."""

import hashlib
import importlib.util
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "generate_models", ROOT / "Scripts/generate-models.py"
)
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


def decoded_payload_arrays(content):
    """Decode emitted literals independently through bytes, rather than the production word codec."""
    arrays = []
    for symbol, literal, count in re.findall(r'let (\w+): \[UInt64\] = decodeModelBits\("(.*)", count: (\d+)\)', content):
        codes = bytearray()
        for token in re.findall(r'\\u\{[0-9a-f]+\}|\\["\\]|[^\\]', literal):
            codes.append(int(token[3:-1], 16) if token.startswith("\\u{") else ord(token[1]) if token.startswith("\\") else ord(token))
        count = int(count)
        if len(codes) != (count * 64 + 6) // 7:
            raise AssertionError(f"{symbol}: encoded length mismatch")
        raw = bytearray()
        pending = available = 0
        for code in codes:
            if code >= 128:
                raise AssertionError(f"{symbol}: non-ASCII payload")
            pending |= code << available
            available += 7
            while available >= 8:
                raw.append(pending & 255)
                pending >>= 8
                available -= 8
        if pending:
            raise AssertionError(f"{symbol}: nonzero padding")
        values = tuple(int.from_bytes(raw[offset:offset + 8], "little") for offset in range(0, count * 8, 8))
        arrays.append((symbol, values))
    return arrays


class SwiftModelGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.outputs = GENERATOR.render_swift_model()
        cls.model = GENERATOR.load_swift_model()
        cls.payloads = {name: decoded_payload_arrays(content) for name, content in cls.outputs.items()}

    def test_ascii7_encoder_preserves_hand_checked_words(self):
        encoder = getattr(GENERATOR, "encode_ascii7_bits", None)
        self.assertTrue(callable(encoder), "Lossless ASCII7 encoder is missing")
        cases = [
            ((0,), bytes(10)),
            ((0xffffffffffffffff,), bytes([127] * 9 + [1])),
            ((0x8000000000000000,), bytes([0] * 9 + [1])),
            ((0x7f00000000000000,), bytes([0] * 8 + [127, 0])),
            ((0xffffffffffffffff, 0), bytes([127] * 9 + [1] + [0] * 9)),
        ]
        for values, expected in cases:
            self.assertEqual(encoder(values), expected)

    def test_ascii7_literal_escaping_covers_controls_quotes_and_backslashes(self):
        escape = getattr(GENERATOR, "escape_ascii7", None)
        self.assertTrue(callable(escape), "ASCII7 Swift literal escaping is missing")
        self.assertEqual(escape(bytes([0, 10, 13, 34, 92, 127])), '\\u{0}\\u{a}\\u{d}\\"\\\\\\u{7f}')

    def test_static_payloads_roundtrip_the_complete_frozen_archive(self):
        self.assertTrue(any(self.payloads.values()), "Encoded model storage is missing")
        actual = {symbol: values for arrays in self.payloads.values() for symbol, values in arrays}
        expected = {}
        for body in self.model.polynomials:
            for number, start in enumerate(range(0, len(body.coefficient_bits), GENERATOR.SWIFT_CHUNK_SIZE)):
                expected[f"polynomial{body.name}Bits{number}"] = body.coefficient_bits[start:start + GENERATOR.SWIFT_CHUNK_SIZE]
        vsop = tuple(value for term in self.model.vsop_terms for value in term)
        for number, start in enumerate(range(0, len(vsop), GENERATOR.SWIFT_CHUNK_SIZE)):
            expected[f"vsopTermBits{number}"] = vsop[start:start + GENERATOR.SWIFT_CHUNK_SIZE]
        expected["nutationIntegerBits"] = tuple(value & 0xffffffffffffffff for row in self.model.nutation_rows for value in row[0])
        expected["nutationCoefficientBits"] = tuple(value for row in self.model.nutation_rows for value in row[1])
        self.assertEqual(set(actual), set(expected))
        for symbol, values in expected.items():
            self.assertEqual(actual[symbol], values, symbol)
        self.assertEqual(sum(map(len, actual.values())), 1_537_855)
    def test_complete_archive_inventory(self):
        model = self.model
        self.assertEqual(sum(len(body.coefficient_bits) for body in model.polynomials), 1_431_768)
        self.assertEqual(sum(bit == 0 for body in model.polynomials for bit in body.validity), 413)
        self.assertEqual(len(model.nutation_rows), 77)
        self.assertGreater(len(model.vsop_terms), 0)
        self.assertEqual(sum(series.count for series in model.vsop_series), len(model.vsop_terms))

    def test_binary64_and_validity_hashes_match_frozen_manifest(self):
        model = self.model
        for body in model.polynomials:
            coefficient_bytes = b"".join(value.to_bytes(8, "little") for value in body.coefficient_bits)
            self.assertEqual(hashlib.sha256(coefficient_bytes).hexdigest(), body.coefficient_sha256)
            self.assertEqual(hashlib.sha256(body.validity).hexdigest(), body.validity_sha256)

    def test_render_is_deterministic_and_manifest_covers_every_output(self):
        first = self.outputs
        second = GENERATOR.render_swift_model()
        self.assertEqual(first, second)
        manifest = GENERATOR.swift_output_manifest(first)
        self.assertEqual(set(manifest["outputs"]), set(first))
        for name, content in first.items():
            self.assertEqual(manifest["outputs"][name], hashlib.sha256(content.encode()).hexdigest())

    def test_generated_metadata_includes_exact_polynomial_grid_bounds(self):
        metadata = self.outputs["AstronomyModelPrototypeGenerated/Generated/Metadata.swift"]
        self.assertIn("startTT: Double(bitPattern: 0xc0e1d59000000000)", metadata)
        self.assertIn("stopTT: Double(bitPattern: 0x40e2033000000000)", metadata)

    def test_polynomial_payloads_are_bounded(self):
        outputs = self.outputs
        polynomial_sources = {
            name: content
            for name, content in outputs.items()
            if "/Generated/Polynomial" in name
        }
        self.assertTrue(polynomial_sources)
        self.assertLessEqual(GENERATOR.SWIFT_CHUNK_SIZE, 16_384)
        for name, content in polynomial_sources.items():
            arrays = self.payloads[name]
            self.assertTrue(arrays, name)
            for _, values in arrays:
                self.assertLessEqual(len(values), 16_384, name)
        for body in self.model.polynomials:
            access = outputs[
                f"AstronomyPolynomial{body.name}Prototype/Generated/Access.swift"
            ]
            self.assertIn(f"switch index / {GENERATOR.SWIFT_CHUNK_SIZE}", access)

    def test_input_manifest_covers_every_archive_file(self):
        manifest = GENERATOR.swift_input_manifest()
        expected = {
            path.relative_to(ROOT).as_posix()
            for directory in (ROOT / "Scripts/model-data", ROOT / "Scripts/performance/polynomial/data")
            for path in directory.rglob("*")
            if path.is_file() and path != GENERATOR.SWIFT_MANIFEST
        }
        self.assertEqual(set(manifest), expected)

    def test_vsop_payloads_are_bounded(self):
        arrays = [
            (name, values)
            for name, entries in self.payloads.items()
            if name.startswith("AstronomyVSOPPrototype/")
            for _, values in entries
        ]
        self.assertTrue(arrays)
        for name, values in arrays:
            self.assertLessEqual(len(values), 16_384, name)

    def test_rendered_vsop_bits_preserve_every_frozen_term_in_order(self):
        arrays = []
        for name, entries in self.payloads.items():
            if not name.startswith("AstronomyVSOPPrototype/"):
                continue
            for symbol, values in entries:
                arrays.append((int(symbol.removeprefix("vsopTermBits")), values))
        actual = tuple(value for _, values in sorted(arrays) for value in values)
        expected = tuple(value for term in self.model.vsop_terms for value in term)
        self.assertEqual(actual, expected)

    def test_generated_vsop_access_dispatch_preserves_chunk_boundaries(self):
        outputs = self.outputs
        access = outputs["AstronomyVSOPPrototype/Generated/VSOPTerms.swift"]
        self.assertTrue("public func vsopTermBitPattern(at index: Int) -> UInt64?" in access, "Generated VSOP bit accessor is missing")
        expected = tuple(value for term in self.model.vsop_terms for value in term)
        self.assertTrue(f"guard index >= 0 && index < {len(expected)} else {{ return nil }}" in access, "Generated VSOP bounds guard is missing")
        self.assertTrue(f"switch index / {GENERATOR.SWIFT_CHUNK_SIZE}" in access, "Generated VSOP chunk dispatch is missing")
        routes = {
            int(case): (int(chunk), int(offset))
            for case, chunk, offset in re.findall(r"case (\d+): return vsopTermBits(\d+)\[index - (\d+)\]", access)
        }
        chunks = {
            int(symbol.removeprefix("vsopTermBits")): values
            for name, entries in self.payloads.items()
            if name.startswith("AstronomyVSOPPrototype/")
            for symbol, values in entries
        }
        indexes = {0, len(expected) - 1}
        for seam in range(GENERATOR.SWIFT_CHUNK_SIZE, len(expected), GENERATOR.SWIFT_CHUNK_SIZE):
            indexes.update((seam - 1, seam, seam + 1))
        self.assertEqual(set(routes), set(range(len(chunks))))
        for index in sorted(indexes):
            number, offset = routes[index // GENERATOR.SWIFT_CHUNK_SIZE]
            self.assertEqual(chunks[number][index - offset], expected[index], index)

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
