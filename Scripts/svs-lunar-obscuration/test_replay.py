#!/usr/bin/env python3
"""Regression tests for the bounded SVS lunar-obscuration replay."""

import copy
import importlib.util
import json
import unittest

from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("svs_lunar_obscuration_replay", HERE / "replay.py")
REPLAY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPLAY)


class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.receipts = REPLAY.load_json(REPLAY.RECEIPTS)

    def test_committed_result_is_reproducible(self):
        REPLAY.verify_receipts(self.receipts)
        actual = REPLAY.build_results(self.receipts)
        expected = json.loads(REPLAY.RESULTS.read_text())
        self.assertEqual(actual, expected)

    def test_source_digest_drift_is_rejected(self):
        receipts = copy.deepcopy(self.receipts)
        receipts["sources"]["svs"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(REPLAY.EvidenceError, "svs SHA-256 changed"):
            REPLAY.verify_receipts(receipts)

    def test_source_semantic_drift_is_rejected(self):
        receipts = copy.deepcopy(self.receipts)
        receipts["sources"]["svs"]["requiredText"].append("invented exact rounding rule")
        with self.assertRaisesRegex(REPLAY.EvidenceError, "required source text"):
            REPLAY.verify_receipts(receipts)

    def test_source_path_escape_is_rejected(self):
        receipts = copy.deepcopy(self.receipts)
        receipts["sources"]["svs"]["archivePath"] = "../Package.swift"
        with self.assertRaisesRegex(REPLAY.EvidenceError, "path escapes the repository"):
            REPLAY.verify_receipts(receipts)

    def test_measure_and_model_substitutions_are_negative_controls(self):
        result = REPLAY.build_results(self.receipts)
        self.assertTrue(result["negativeControls"])
        self.assertFalse(any(result["negativeControls"].values()))
        self.assertEqual(result["conventions"]["catalog"]["measure"], "umbral magnitude, a diameter fraction")
        self.assertEqual(result["conventions"]["svs"]["measure"], "Moon-disc area inside the umbra")

    def test_published_datum_interval_and_known_miss_are_preserved(self):
        result = REPLAY.build_results(self.receipts)
        comparison = result["comparison"]
        self.assertEqual(comparison["svsPrintedObscuration"], 0.963)
        self.assertEqual(comparison["conditionalNearestPrintInterval"], [0.9625, 0.9635])
        self.assertLess(comparison["nativeCapturedObscuration"], 0.9625)
        self.assertLess(comparison["horizonsDE441DanjonReplay"]["obscuration"], 0.9625)

    def test_circle_overlap_boundary_controls(self):
        self.assertEqual(REPLAY.circle_overlap_fraction(1, 1, 2), 0)
        self.assertEqual(REPLAY.circle_overlap_fraction(1, 2, 0), 1)
        self.assertEqual(REPLAY.circle_overlap_fraction(2, 1, 0), 0.25)


if __name__ == "__main__":
    unittest.main()
