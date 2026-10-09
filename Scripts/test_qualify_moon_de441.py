import importlib.util
import math
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch


def load_qualification():
    path = Path(__file__).with_name("qualify-moon-de441.py")
    spec = importlib.util.spec_from_file_location("qualification", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CompactMoonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.q = load_qualification()

    def test_projection_bounds_enclose_position_and_analytic_rate(self):
        source = [[300000.0, 12000.123, -1600.456, 80.02, 3.001, -.31, .08, -.002, .001, 0, 0, 0, 0]] * 3
        for candidate in self.q.CANDIDATES:
            decoded, encoded = self.q.project(source, candidate)
            self.assertEqual(candidate.get("recordBytes", 3 * (candidate["degree"] + 1) * candidate.get("bytesPerCoefficient", 0)), len(encoded))
            position, rate = self.q.error_bounds(source, decoded)
            for x in (-1, -.876, -.1, 0, .37, .99, 1):
                actual_p, actual_v = self.q.evaluate(source, x)
                compact_p, compact_v = self.q.evaluate(decoded, x)
                self.assertLessEqual(math.dist(actual_p, compact_p), position)
                self.assertLessEqual(math.dist(actual_v, compact_v), rate)

    def test_source_distance_bound_covers_cancellation(self):
        source = [[100.0, 20.0, -5.0], [40.0, -3.0, 4.0], [10.0, 1.0, 2.0]]
        lower = self.q.distance_lower_bound(source)
        self.assertGreater(lower, 0)
        for x in (-1, -.2, 0, .7, 1):
            self.assertLessEqual(lower, math.dist((0, 0, 0), self.q.evaluate(source, x)[0]))
        self.assertLessEqual(self.q.distance_lower_bound([[1, 100], [0, 0], [0, 0]]), 0)

    def test_fixed_point_rejects_overflow_instead_of_wrapping(self):
        candidate = next(c for c in self.q.CANDIDATES if c["encoding"] == "int16")
        with self.assertRaisesRegex(ValueError, "overflow"):
            self.q.project([[1e20] + [0] * 12] * 3, candidate)

    def test_projection_is_binary_roundtrip_and_retains_axis_order(self):
        candidate = self.q.CANDIDATES[0]
        source = [[100 * axis + degree + .1 for degree in range(13)] for axis in range(3)]
        decoded, data = self.q.project(source, candidate)
        flat = struct.unpack("<" + "f" * (len(data) // 4), data)
        self.assertEqual(tuple(value for axis in decoded for value in axis), flat)

    def test_record_grid_rejects_wrong_epoch_radius_nonfinite_and_shape(self):
        row = (86400.0, 172800.0) + (1.0,) * 39
        self.q.validate_record(row, row, 86400.0)
        for bad in ((0.0,) + row[1:], row[:1] + (1.0,) + row[2:], row[:2] + (math.nan,) + row[3:], row[:-1]):
            with self.assertRaises(ValueError):
                self.q.validate_record(bad, row, 86400.0)

    def test_cached_range_rejects_changed_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            data = b"abcdef"
            digest = self.q.hashlib.sha256(data).hexdigest()
            (cache / "0-5.bin").write_bytes(b"abcdeg")
            reader = self.q.CachedReader(cache, {"0-5": digest})
            with self.assertRaisesRegex(ValueError, "digest"):
                reader.read(0, 6)

    def test_tail_bound_cannot_cancel_opposing_coefficients(self):
        source = [[300000, 0, 0, 0, 100, -100] + [0] * 7, [0] * 13, [0] * 13]
        compact = [[300000, 0, 0, 0], [0] * 4, [0] * 4]
        position, rate = self.q.error_bounds(source, compact)
        self.assertGreaterEqual(position, 200)
        self.assertGreaterEqual(rate, 2050)

    def test_http_identity_is_checked_before_caching_a_new_range(self):
        with tempfile.TemporaryDirectory() as directory:
            reader = self.q.CachedReader(Path(directory))
            with patch.object(self.q.direct, "RangeReader") as remote:
                remote.return_value.read.return_value = b"abcdef"
                remote.return_value.total_bytes = 6
                remote.return_value.etag = "different"
                remote.return_value.last_modified = "different"
                with self.assertRaisesRegex(ValueError, "HTTP identity"):
                    reader.read(0, 6)
                self.assertFalse((Path(directory) / "0-5.bin").exists())

    def test_an_unpinned_cache_entry_requires_its_original_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "0-5.bin").write_bytes(b"abcdef")
            with self.assertRaisesRegex(ValueError, "digest or identity"):
                self.q.CachedReader(Path(directory)).read(0, 6)


class SharedEndpointTests(unittest.TestCase):
    def test_neighboring_records_reuse_identical_position_and_rate_nodes(self):
        q = load_qualification()
        candidate = next(c for c in q.CANDIDATES if c["encoding"] == "hermite-float32")
        first = [[300000 + a * 100, 12000, -800, 30, -1, .05, -.003] + [0] * 6 for a in range(3)]
        second = [[400000 + a * 200, -12000, 800, -30, 1, -.05, .003] + [0] * 6 for a in range(3)]
        left, _ = q.project(first, candidate)
        right, payload = q.project(second, candidate, q.endpoints(first)[1])
        p_left, v_left = q.endpoints(left)[1]
        p_right, v_right = q.endpoints(right)[0]
        self.assertLess(q.math.dist(p_left, p_right), 1e-8)
        self.assertLess(q.math.dist(v_left, v_right), 1e-8)
        self.assertEqual(48, len(payload))


class SavedCompactEvidenceTests(unittest.TestCase):
    def test_manifest_covers_all_records_and_retains_failed_candidates(self):
        q = load_qualification()
        evidence = json.loads(q.OUTPUT.read_bytes())
        coverage = evidence["coverage"]
        self.assertEqual(730501, coverage["recordCount"])
        self.assertEqual(730500, coverage["sourceBoundaryDiagnostics"]["boundaryCount"])
        self.assertEqual(730501, sum(segment["recordCount"] for segment in coverage["segments"]))
        self.assertTrue(evidence["assessment"]["fullSourceRangeScanned"])
        self.assertFalse(evidence["assessment"]["endToEndAccuracyQualified"])
        self.assertEqual({c["name"] for c in q.CANDIDATES}, {c["name"] for c in evidence["candidates"]})
        self.assertTrue(any(c["failedRecordCount"] > 0 for c in evidence["candidates"]))
        for candidate in evidence["candidates"]:
            self.assertEqual(730501, candidate["recordCount"])
            self.assertEqual(30, len(candidate["archivedHorizons"]))
            self.assertEqual(candidate["failedRecordCount"] == 0, candidate["passesRepresentationTarget"])
            size = candidate.get("recordBytes", 3 * (candidate["degree"] + 1) * candidate.get("bytesPerCoefficient", 0)) * 730501
            if candidate["encoding"] == "hermite-float32":
                size += 24
            self.assertEqual(size, candidate["encodedBytes"])
            self.assertRegex(candidate["sha256"], r"^[0-9a-f]{64}$")

    def test_recheck_ignores_host_timings_but_detects_numerical_drift(self):
        q = load_qualification()
        evidence = json.loads(q.OUTPUT.read_bytes())
        copy = json.loads(q.OUTPUT.read_bytes())
        copy["observations"]["host"] = "different host"
        copy["observations"]["runtime"]["direct-float64"]["seconds"] = -1
        self.assertEqual(q.comparable(evidence), q.comparable(copy))
        copy["candidates"][0]["maximumPositionBoundKm"] += 1
        self.assertNotEqual(q.comparable(evidence), q.comparable(copy))


if __name__ == "__main__":
    unittest.main()
