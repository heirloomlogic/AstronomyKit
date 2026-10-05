import copy
import importlib.util
import math
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "constellation", Path(__file__).with_name("constellation-corpus.py")
)
C = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(C)


class ConstellationCorpusTests(unittest.TestCase):
    def test_source_names_records_and_notices(self):
        source = C.sources()
        tables = C.parse_tables(source["lockedText"])
        self.assertEqual(len(tables["names"]), 88)
        self.assertEqual(len(tables["records"]), 357)
        self.assertIn("Copyright (c) 2019-2025 Don Cross", source["notices"])
        self.assertEqual(source["lockedText"], source["currentText"])
        self.assertEqual(tables["names"][1]["name"], "Antila")

    def test_every_record_has_all_tie_neighbor_probes(self):
        tables = C.parse_tables(C.sources()["lockedText"])
        cases = C.table_cases(tables)
        self.assertEqual(len(cases), 7497)
        for index in range(357):
            self.assertEqual(sum(c["record"] == index for c in cases), 21)
        self.assertEqual(cases[0]["raCompact"], math.nextafter(0, -math.inf))
        self.assertEqual(cases[1]["raCompact"], math.nextafter(0, -math.inf))
        self.assertEqual(C.match_record(tables, 0, 2112), 0)
        self.assertIsNone(C.match_record(tables, 8640, -2160))

    def test_representatives_cover_all_source_names(self):
        tables = C.parse_tables(C.sources()["lockedText"])
        samples = C.representatives(tables)
        self.assertEqual(len(samples), 88)
        self.assertEqual(
            {C.match_record(tables, c["raCompact"], c["decCompact"]) for c in samples},
            set(c["matchedRecord"] for c in samples),
        )
        self.assertEqual(
            {tables["records"][c["matchedRecord"]]["index"] for c in samples},
            set(range(88)),
        )

    def test_directed_table_mutations_change_results(self):
        tables = C.parse_tables(C.sources()["lockedText"])
        cases = C.table_cases(tables)
        for mode in ["reverse", "lower-exclusive", "upper-inclusive", "name"]:
            self.assertTrue(
                any(
                    C.table_result(tables, c, mode) != C.table_result(tables, c)
                    for c in cases
                ),
                mode,
            )

    def test_result_semantics_reject_missing_wrong_name_and_nonfinite_success(self):
        tables = C.parse_tables(C.sources()["lockedText"])
        request = {
            "id": "anchor",
            "operation": "lookup",
            "raHours": "2.53",
            "decDegrees": "89.26",
        }
        result = {
            "id": "anchor",
            "status": "success",
            "symbol": "UMi",
            "name": "Ursa Minor",
            "ra1875": 2.5,
            "dec1875": 89.3,
        }
        C.validate_results([request], [result], tables)
        for edit in ["missing", "duplicate", "id", "name", "nan", "inf"]:
            changed = copy.deepcopy(result)
            rows = [changed]
            if edit == "missing":
                rows = []
            if edit == "duplicate":
                rows *= 2
            if edit == "id":
                changed["id"] = "wrong"
            if edit == "name":
                changed["name"] = "changed"
            if edit == "nan":
                changed["ra1875"] = float("nan")
            if edit == "inf":
                changed["dec1875"] = float("inf")
            with self.subTest(edit=edit), self.assertRaises(ValueError):
                C.validate_results([request], rows, tables)


class ReplayIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tables = C.parse_tables(C.sources()["lockedText"])
        cls.public = C.read_rows(C.DATA / "public-inputs.json")
        cls.transforms = {
            m: [
                {
                    "id": r["id"],
                    "status": "success",
                    "raHours": float(r["raHours"]),
                    "decDegrees": float(r["decDegrees"]),
                }
                for r in rows[1:-41]
            ]
            for m, rows in cls.public.items()
        }

    def test_public_selection_frame_and_nonfinite_controls(self):
        C.validate_public_selection(self.tables, self.public, self.transforms)
        for mode in [
            "missing",
            "duplicate",
            "order",
            "source",
            "frame",
            "nan",
            "inf",
            "model",
        ]:
            public = copy.deepcopy(self.public)
            model = next(iter(public))
            rows = public[model]
            if mode == "missing":
                rows.pop(3)
            if mode == "duplicate":
                rows[3] = copy.deepcopy(rows[2])
            if mode == "order":
                rows[2], rows[3] = rows[3], rows[2]
            if mode == "source":
                rows[2]["tableExpected"]["symbol"] = "Ori"
            if mode == "frame":
                rows[2]["raHours"] = str(float(rows[2]["raHours"]) + 1)
            if mode == "nan":
                rows[2]["raHours"] = "nan"
            if mode == "inf":
                rows[2]["decDegrees"] = "inf"
            if mode == "model":
                public["wrong-model"] = public.pop(model)
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                C.validate_public_selection(self.tables, public, self.transforms)

    def test_response_status_shape_and_coordinate_ownership(self):
        request = {
            "id": "anchor",
            "operation": "lookup",
            "raHours": "2.53",
            "decDegrees": "89.26",
        }
        result = {
            "id": "anchor",
            "status": "success",
            "symbol": "UMi",
            "name": "Ursa Minor",
            "ra1875": 2.5,
            "dec1875": 89.3,
        }
        for mode in [
            "unknown",
            "stale-error",
            "wrong-constellation",
            "missing-coordinate",
            "bool",
            "invalid-success",
        ]:
            row = copy.deepcopy(result)
            r = copy.deepcopy(request)
            if mode == "unknown":
                row = {"id": "anchor", "status": "invented"}
            if mode == "stale-error":
                row["status"] = "invalid-parameter"
            if mode == "wrong-constellation":
                row.update(symbol="Ori", name="Orion")
            if mode == "missing-coordinate":
                row.pop("ra1875")
            if mode == "bool":
                row["ra1875"] = True
            if mode == "invalid-success":
                r["kind"] = "invalid"
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                C.validate_results([r], [row], self.tables)

    def test_original_raw_binding_and_rehashed_empty_payload(self):
        import gzip
        import tempfile
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for path in C.DATA.iterdir():
                (directory / path.name).write_bytes(path.read_bytes())
            path = directory / "c-espenak-meeus-espenak-meeus.json.gz"
            path.write_bytes(gzip.compress(b"[]", mtime=0))
            with patch.object(C, "DATA", directory), self.assertRaises(ValueError):
                C.authenticate_archive()
            manifest = C.read_rows(directory / "manifest.json")
            manifest["artifactSHA256"][path.name] = C.digest(path.read_bytes())
            (directory / "manifest.json").write_bytes(C.encoded(manifest))
            with patch.object(C, "DATA", directory), self.assertRaises(ValueError):
                C.authenticate_archive()

    def test_archive_platform_comparison_retains_boundary_changes_only(self):
        request = {"id": "x", "kind": "table-boundary"}
        old = {"id": "x", "status": "internal-error"}
        new = {
            "id": "x",
            "status": "success",
            "symbol": "UMi",
            "name": "Ursa Minor",
            "ra1875": 2.5,
            "dec1875": 89.3,
        }
        self.assertEqual(C.compare_archive([request], [old], [new]), ["x"])
        for mode in ["interior", "id", "nan", "coordinate"]:
            r = copy.deepcopy(request)
            row = copy.deepcopy(new)
            a = copy.deepcopy(new)
            if mode == "interior":
                r["kind"] = "representative"
                a = old
            if mode == "id":
                row["id"] = "wrong"
            if mode == "nan":
                row["dec1875"] = math.nan
            if mode == "coordinate":
                row["dec1875"] += 1e-4
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                C.finite_payload(row)
                C.compare_archive([r], [a], [row])


if __name__ == "__main__":
    unittest.main()
