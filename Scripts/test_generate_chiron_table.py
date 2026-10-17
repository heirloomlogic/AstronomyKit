#!/usr/bin/env python3
"""Contract tests for the Chiron table generator."""

import copy
import gzip
import importlib.util
import json
import math
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SPEC = importlib.util.spec_from_file_location("chiron_table", Path(__file__).resolve().parent / "generate-chiron-table.py")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)
ROOT = GENERATOR.ROOT


class ChironTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.receipt = json.loads(GENERATOR.RECEIPTS.read_bytes())
        cls.replayed = GENERATOR.replay()

    def test_committed_table_replays(self):
        with mock.patch.object(GENERATOR, "replay", return_value=self.replayed):
            GENERATOR.check()

    def test_check_rejects_a_changed_swift_table(self):
        source = GENERATOR.SWIFT.read_bytes()
        marker = source.index(b'"""\n') + 4
        flipped = b"B" if source[marker:marker + 1] != b"B" else b"C"
        with tempfile.TemporaryDirectory() as directory:
            changed = Path(directory) / "ChironCoefficients.swift"
            changed.write_bytes(source[:marker] + flipped + source[marker + 1:])
            with mock.patch.object(GENERATOR, "SWIFT", changed), mock.patch.object(GENERATOR, "replay", return_value=self.replayed):
                with self.assertRaises(GENERATOR.TableError):
                    GENERATOR.check()

    def test_epoch_sets_are_complete_disjoint_and_cover_boundaries(self):
        fit = GENERATOR.fit_epochs()
        heldout = GENERATOR.holdout_epochs()
        self.assertEqual(GENERATOR.RECORD_COUNT * GENERATOR.FIT_POINTS_PER_RECORD, len(fit))
        self.assertEqual(GENERATOR.RECORD_COUNT * (len(GENERATOR.HOLDOUT_X) - 1) + 1, len(heldout))
        self.assertFalse(set(fit) & set(heldout))
        self.assertEqual(GENERATOR.START_JD_TDB, heldout[0])
        self.assertEqual(GENERATOR.END_JD_TDB, heldout[-1])

    def test_receipt_rejects_wrong_top_level_and_nested_types(self):
        mutations = []
        for value in (0, [], "receipt"):
            mutations.append(lambda data, value=value: value)
        for value in (None, [], "sources"):
            mutations.append(lambda data, value=value: {**data, "sources": value})
        for value in (None, [], "query"):
            mutations.append(lambda data, value=value: self._nested(data, "query", value))
        for value in (None, [], "response"):
            mutations.append(lambda data, value=value: self._nested(data, "response", value))
        for mutation in mutations:
            data = mutation(copy.deepcopy(self.receipt))
            with self.assertRaises(GENERATOR.TableError):
                GENERATOR.read_sources(data)

    def test_receipt_rejects_missing_members_and_path_escape(self):
        for key in self.receipt:
            data = copy.deepcopy(self.receipt)
            del data[key]
            with self.assertRaises(GENERATOR.TableError):
                GENERATOR.read_sources(data)
        for field in ("query", "response"):
            data = copy.deepcopy(self.receipt)
            data["sources"][0][field]["path"] = "../outside"
            with self.assertRaises(GENERATOR.TableError):
                GENERATOR.read_sources(data)

    def test_query_rejects_changed_conventions_and_cadence(self):
        entry = self.receipt["sources"][0]
        query = (ROOT / entry["query"]["path"]).read_bytes()
        for source, replacement in ((b"TIME_TYPE='TDB'", b"TIME_TYPE='TT'"), (b"CENTER='500@10'", b"CENTER='500@0'"), (b"VEC_CORR='NONE'", b"VEC_CORR='LT'"), (b"REF_PLANE='FRAME'", b"REF_PLANE='ECLIPTIC'")):
            with self.assertRaises(GENERATOR.TableError):
                GENERATOR.parse_query(query.replace(source, replacement))
        changed = query.replace(b"STEP_SIZE='1 d'", b"STEP_SIZE='2 d'", 1)
        with self.assertRaises(GENERATOR.TableError):
            GENERATOR.parse_query(changed)

    def test_response_rejects_wrong_identity_truncation_and_nonfinite(self):
        entry = self.receipt["sources"][0]
        query = (ROOT / entry["query"]["path"]).read_bytes()
        response = gzip.decompress((ROOT / entry["response"]["path"]).read_bytes())
        epochs = GENERATOR.parse_query(query)
        for source, replacement in ((b"JPL#171", b"JPL#170"), (b"{source: DE441}", b"{source: DE440}"), (b"Reference frame : ICRF", b"Reference frame : ECLIPTIC"), (b"Output type     : GEOMETRIC", b"Output type     : APPARENT")):
            with self.assertRaises(GENERATOR.TableError):
                GENERATOR.parse_response(response.replace(source, replacement), epochs)
        with self.assertRaises(GENERATOR.TableError):
            GENERATOR.parse_response(response.split(b"$$EOE", 1)[0], epochs)
        prefix, rest = response.split(b"$$SOE", 1)
        body, suffix = rest.split(b"$$EOE", 1)
        lines = body.splitlines(keepends=True)
        vector = next(index for index, line in enumerate(lines) if len(line.split(b",")) >= 8)
        with self.assertRaises(GENERATOR.TableError):
            GENERATOR.parse_response(prefix + b"$$SOE" + b"".join(lines[:vector] + lines[vector + 1:]) + b"$$EOE" + suffix, epochs)
        prefix, vectors = response.split(b"$$SOE", 1)
        match = next(value for value in re_float_tokens(vectors) if math.isfinite(float(value)))
        with self.assertRaises(GENERATOR.TableError):
            GENERATOR.parse_response(prefix + b"$$SOE" + vectors.replace(match, b"NaN", 1), epochs)

    def test_screen_rejects_position_and_velocity_outside_limits(self):
        fit, heldout, consistency, archive = GENERATOR.read_sources()
        coefficients = GENERATOR.fit_coefficients(fit)
        changed_position = [list(row) for row in heldout]
        changed_position[len(changed_position) // 2][1] += 2
        with self.assertRaises(GENERATOR.TableError):
            GENERATOR.assessment(coefficients, fit, changed_position, consistency, archive)
        changed_velocity = [list(row) for row in heldout]
        changed_velocity[len(changed_velocity) // 2][4] += 2 / 86_400
        with self.assertRaises(GENERATOR.TableError):
            GENERATOR.assessment(coefficients, fit, changed_velocity, consistency, archive)

    def test_receipt_rejects_wrong_inner_types_and_hashes(self):
        mutations = (
            lambda data: data["sources"][0]["query"].__setitem__("sha256", None),
            lambda data: data["sources"][0]["response"].__setitem__("uncompressedSHA256", None),
            lambda data: data["sources"][0].__setitem__("vectorCount", True),
            lambda data: data["sources"][0].__setitem__("index", True),
            lambda data: data["sources"][0].__setitem__("retrievedAtHTTPDate", None),
        )
        for mutation in mutations:
            data = copy.deepcopy(self.receipt)
            mutation(data)
            with self.assertRaises(GENERATOR.TableError):
                GENERATOR.read_sources(data)

    def test_capture_refreshes_cached_response_and_records_new_http_date(self):
        entry = self.receipt["sources"][0]
        recipe = GENERATOR.source_recipes()[0]
        query = (ROOT / entry["query"]["path"]).read_bytes()
        raw_response = gzip.decompress((ROOT / entry["response"]["path"]).read_bytes())
        fresh_date = "Tue, 13 Oct 2026 12:00:00 GMT"
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            temporary_sources = temporary_root / "sources"
            temporary_sources.mkdir()
            (temporary_root / entry["query"]["path"]).write_bytes(query)
            (temporary_root / entry["response"]["path"]).write_bytes(gzip.compress(raw_response + b"\n", mtime=0))
            temporary_receipts = temporary_root / "source-receipts.json"
            temporary_receipts.write_bytes(GENERATOR.encoded({"sources": [entry]}))
            download = mock.Mock(return_value=(raw_response, fresh_date))
            with mock.patch.object(GENERATOR, "ROOT", temporary_root), mock.patch.object(GENERATOR, "SOURCES", temporary_sources), mock.patch.object(GENERATOR, "RECEIPTS", temporary_receipts), mock.patch.object(GENERATOR, "source_recipes", return_value=[recipe]), mock.patch.object(GENERATOR, "download", download):
                GENERATOR.capture_sources()
            download.assert_called_once_with(query)
            captured = json.loads(temporary_receipts.read_bytes())
            self.assertEqual(fresh_date, captured["sources"][0]["retrievedAtHTTPDate"])
            self.assertEqual(raw_response, gzip.decompress((temporary_root / entry["response"]["path"]).read_bytes()))

    def test_source_inventory_rejects_directories_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            temporary_sources = temporary_root / "sources"
            temporary_sources.mkdir()
            expected = temporary_sources / "expected.query.txt"
            expected.write_bytes(b"query")
            inventory = {"sources/expected.query.txt"}
            with mock.patch.object(GENERATOR, "ROOT", temporary_root), mock.patch.object(GENERATOR, "SOURCES", temporary_sources):
                GENERATOR.require_source_inventory(inventory)
                extra_directory = temporary_sources / "unrecorded"
                extra_directory.mkdir()
                with self.assertRaises(GENERATOR.TableError):
                    GENERATOR.require_source_inventory(inventory)
                extra_directory.rmdir()
                target = temporary_root / "target"
                target.write_bytes(b"target")
                extra_link = temporary_sources / "unrecorded-link"
                extra_link.symlink_to(target)
                with self.assertRaises(GENERATOR.TableError):
                    GENERATOR.require_source_inventory(inventory)
                extra_link.unlink()
                expected.unlink()
                expected.symlink_to(target)
                with self.assertRaises(GENERATOR.TableError):
                    GENERATOR.require_source_inventory(inventory)

    def test_replay_rejects_unrecorded_directory(self):
        with tempfile.TemporaryDirectory(prefix="unrecorded-", dir=GENERATOR.SOURCES):
            with self.assertRaises(GENERATOR.TableError):
                GENERATOR.check()

    @staticmethod
    def _nested(data, field, value):
        data["sources"][0][field] = value
        return data


def re_float_tokens(data):
    import re
    return re.findall(rb"(?<![A-Za-z])[-+]?\d+\.\d+(?:E[-+]?\d+)?", data)


if __name__ == "__main__":
    unittest.main()
