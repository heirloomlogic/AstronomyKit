#!/usr/bin/env python3
"""Contract tests for the Chiron table preflight."""

import copy
import gzip
import importlib.util
import json
import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("chiron_preflight", ROOT / "preflight.py")
PREFLIGHT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREFLIGHT)


class PreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.receipt = json.loads(PREFLIGHT.RECEIPTS.read_bytes())

    def test_committed_preflight_replays(self):
        PREFLIGHT.check()

    def test_epoch_sets_are_complete_disjoint_and_cover_boundaries(self):
        fit = PREFLIGHT.fit_epochs()
        heldout = PREFLIGHT.holdout_epochs()
        self.assertEqual(PREFLIGHT.RECORD_COUNT * PREFLIGHT.FIT_POINTS_PER_RECORD, len(fit))
        self.assertEqual(PREFLIGHT.RECORD_COUNT * (len(PREFLIGHT.HOLDOUT_X) - 1) + 1, len(heldout))
        self.assertFalse(set(fit) & set(heldout))
        self.assertEqual(PREFLIGHT.START_JD_TDB, heldout[0])
        self.assertEqual(PREFLIGHT.END_JD_TDB, heldout[-1])

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
            with self.assertRaises(PREFLIGHT.PreflightError):
                PREFLIGHT.read_sources(data)

    def test_receipt_rejects_missing_members_and_path_escape(self):
        for key in self.receipt:
            data = copy.deepcopy(self.receipt)
            del data[key]
            with self.assertRaises(PREFLIGHT.PreflightError):
                PREFLIGHT.read_sources(data)
        for field in ("query", "response"):
            data = copy.deepcopy(self.receipt)
            data["sources"][0][field]["path"] = "../outside"
            with self.assertRaises(PREFLIGHT.PreflightError):
                PREFLIGHT.read_sources(data)

    def test_query_rejects_changed_conventions_and_cadence(self):
        entry = self.receipt["sources"][0]
        query = (ROOT / entry["query"]["path"]).read_bytes()
        for source, replacement in ((b"TIME_TYPE='TDB'", b"TIME_TYPE='TT'"), (b"CENTER='500@10'", b"CENTER='500@0'"), (b"VEC_CORR='NONE'", b"VEC_CORR='LT'"), (b"REF_PLANE='FRAME'", b"REF_PLANE='ECLIPTIC'")):
            with self.assertRaises(PREFLIGHT.PreflightError):
                PREFLIGHT.parse_query(query.replace(source, replacement))
        changed = query.replace(b"STEP_SIZE='1 d'", b"STEP_SIZE='2 d'", 1)
        with self.assertRaises(PREFLIGHT.PreflightError):
            PREFLIGHT.parse_query(changed)

    def test_response_rejects_wrong_identity_truncation_and_nonfinite(self):
        entry = self.receipt["sources"][0]
        query = (ROOT / entry["query"]["path"]).read_bytes()
        response = gzip.decompress((ROOT / entry["response"]["path"]).read_bytes())
        epochs = PREFLIGHT.parse_query(query)
        for source, replacement in ((b"JPL#171", b"JPL#170"), (b"{source: DE441}", b"{source: DE440}"), (b"Reference frame : ICRF", b"Reference frame : ECLIPTIC"), (b"Output type     : GEOMETRIC", b"Output type     : APPARENT")):
            with self.assertRaises(PREFLIGHT.PreflightError):
                PREFLIGHT.parse_response(response.replace(source, replacement), epochs)
        with self.assertRaises(PREFLIGHT.PreflightError):
            PREFLIGHT.parse_response(response.split(b"$$EOE", 1)[0], epochs)
        prefix, rest = response.split(b"$$SOE", 1)
        body, suffix = rest.split(b"$$EOE", 1)
        lines = body.splitlines(keepends=True)
        vector = next(index for index, line in enumerate(lines) if len(line.split(b",")) >= 8)
        with self.assertRaises(PREFLIGHT.PreflightError):
            PREFLIGHT.parse_response(prefix + b"$$SOE" + b"".join(lines[:vector] + lines[vector + 1:]) + b"$$EOE" + suffix, epochs)
        prefix, vectors = response.split(b"$$SOE", 1)
        match = next(value for value in re_float_tokens(vectors) if math.isfinite(float(value)))
        with self.assertRaises(PREFLIGHT.PreflightError):
            PREFLIGHT.parse_response(prefix + b"$$SOE" + vectors.replace(match, b"NaN", 1), epochs)

    def test_screen_rejects_position_and_velocity_outside_limits(self):
        fit, heldout, consistency, archive = PREFLIGHT.read_sources()
        coefficients = PREFLIGHT.fit_coefficients(fit)
        changed_position = [list(row) for row in heldout]
        changed_position[len(changed_position) // 2][1] += 2
        with self.assertRaises(PREFLIGHT.PreflightError):
            PREFLIGHT.assessment(coefficients, fit, changed_position, consistency, archive)
        changed_velocity = [list(row) for row in heldout]
        changed_velocity[len(changed_velocity) // 2][4] += 2 / 86_400
        with self.assertRaises(PREFLIGHT.PreflightError):
            PREFLIGHT.assessment(coefficients, fit, changed_velocity, consistency, archive)

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
            with self.assertRaises(PREFLIGHT.PreflightError):
                PREFLIGHT.read_sources(data)

    @staticmethod
    def _nested(data, field, value):
        data["sources"][0][field] = value
        return data


def re_float_tokens(data):
    import re
    return re.findall(rb"(?<![A-Za-z])[-+]?\d+\.\d+(?:E[-+]?\d+)?", data)


if __name__ == "__main__":
    unittest.main()
