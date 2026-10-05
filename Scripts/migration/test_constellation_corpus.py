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


class Fixer141RegressionTests(unittest.TestCase):
    def isolated_replay(self, edit):
        import shutil, tempfile
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as temporary:
            tool = Path(temporary) / "tool"
            shutil.copytree(C.TOOL, tool)
            data = tool / "Artifacts"
            derived = tool / "DerivedEvidence"
            original = C.read_rows(data / "manifest.json")
            matched = C.read_rows(derived / "manifest.json")
            provenance = C.read_rows(tool / "validation-provenance.json")
            edit(tool, original, matched, provenance)
            (data / "manifest.json").write_bytes(C.encoded(original))
            matched["originalManifestSHA256"] = C.digest(
                (data / "manifest.json").read_bytes()
            )
            (derived / "manifest.json").write_bytes(C.encoded(matched))
            provenance["derivedManifestSHA256"] = C.digest(
                (derived / "manifest.json").read_bytes()
            )
            (tool / "validation-provenance.json").write_bytes(C.encoded(provenance))
            with patch.object(C, "TOOL", tool), patch.object(
                C, "DATA", data
            ), patch.object(C, "DERIVED", derived), patch.object(
                C, "SNAPSHOTS", tool / "AcquisitionTools"
            ), patch.object(
                C, "build", return_value=None
            ):
                C.check()

    def test_rehashed_original_build_receipt_is_rejected(self):
        def edit(tool, original, matched, provenance):
            path = tool / "Artifacts/build-receipt.json"
            receipt = C.read_rows(path)
            receipt["c"].update(
                flags=["-ffast-math"],
                sourceRevision="not-the-oracle",
                adapterSHA256="0" * 64,
            )
            receipt["swift"]["manifestSHA256"] = "0" * 64
            path.write_bytes(C.encoded(receipt))
            original["artifactSHA256"][path.name] = C.digest(path.read_bytes())

        with self.assertRaises(ValueError):
            self.isolated_replay(edit)

    def test_rehashed_derived_receipt_without_matched_flags_is_rejected(self):
        def edit(tool, original, matched, provenance):
            path = tool / "DerivedEvidence/build-receipt.json"
            receipt = C.read_rows(path)
            receipt["swift"].pop("cCompilerFlagsAdded")
            path.write_bytes(C.encoded(receipt))
            matched["artifactSHA256"][path.name] = C.digest(path.read_bytes())

        with self.assertRaises(ValueError):
            self.isolated_replay(edit)

    def test_empty_mandatory_maps_and_changed_snapshots_are_rejected(self):
        def edit(tool, original, matched, provenance):
            original["toolSHA256"] = {}
            matched["toolSHA256"] = {}
            provenance["toolSHA256"] = {}
            for name in ["AcquisitionTools", "DerivationTools"]:
                for path in (tool / name).iterdir():
                    path.write_text("unrelated text\n")

        with self.assertRaises(ValueError):
            self.isolated_replay(edit)

    def test_macos_job_prepares_generated_lint_configuration(self):
        job = (
            (C.ROOT / ".github/workflows/test.yml")
            .read_text()
            .split("\n  constellation-corpus-replay:", 1)[1]
        )
        setup = ".build/checkouts/Persnicket/bin/ci-lint-setup"
        self.assertIn("touch .dev-tooling", job)
        self.assertIn("swift package resolve", job)
        self.assertIn(setup, job)
        self.assertLess(job.index(setup), job.index("xcrun swift-format lint"))


class BuildReceiptSemanticTests(unittest.TestCase):
    def test_recorded_receipts_reject_each_changed_condition_and_identity(self):
        edits = [
            ("c", "flags", ["-ffast-math"]),
            ("c", "sourceRevision", "not-the-oracle"),
            ("c", "oracleLockSHA256", "0" * 64),
            ("c", "sourceFilesSHA256", {}),
            ("c", "adapterSHA256", "0" * 64),
            ("c", "binarySHA256", "a" * 64),
            ("c", "compiler", "different compiler"),
            ("swift", "manifestSHA256", "0" * 64),
            ("swift", "binarySHA256", "b" * 64),
            ("swift", "compiler", "different compiler"),
        ]
        for stage, directory in [("acquisition", C.DATA), ("derivation", C.DERIVED)]:
            original = C.read_rows(directory / "build-receipt.json")
            C.validate_build_receipt(original, stage)
            for backend, field, value in edits:
                changed = copy.deepcopy(original)
                changed[backend][field] = value
                with self.subTest(stage=stage, field=field), self.assertRaises(
                    ValueError
                ):
                    C.validate_build_receipt(changed, stage)
            for field in ["platform", "architecture"]:
                changed = copy.deepcopy(original)
                changed[field] = "different environment"
                with self.subTest(stage=stage, field=field), self.assertRaises(
                    ValueError
                ):
                    C.validate_build_receipt(changed, stage)
            for backend in ["c", "swift"]:
                for field in original[backend]:
                    changed = copy.deepcopy(original)
                    changed[backend].pop(field)
                    with self.subTest(stage=stage, missing=field), self.assertRaises(
                        ValueError
                    ):
                        C.validate_build_receipt(changed, stage)
            changed = copy.deepcopy(original)
            changed["unexpected"] = True
            with self.assertRaises(ValueError):
                C.validate_build_receipt(changed, stage)
        derived = C.read_rows(C.DERIVED / "build-receipt.json")
        derived["swift"]["cCompilerFlagsAdded"] = []
        with self.assertRaises(ValueError):
            C.validate_build_receipt(derived, "derivation")

    def test_mandatory_tool_maps_reject_missing_extra_renamed_and_changed_sources(self):
        import tempfile, shutil

        for stage, directory in [
            ("acquisition", C.SNAPSHOTS),
            ("derivation", C.TOOL / "DerivationTools"),
        ]:
            valid = C.ARCHIVED_TOOL_SHA256[stage]
            C.validate_tool_population(valid, directory, stage)
            for mode in ["empty", "missing", "extra", "renamed", "hash"]:
                changed = copy.deepcopy(valid)
                first = next(iter(changed))
                if mode == "empty":
                    changed = {}
                if mode == "missing":
                    changed.pop(first)
                if mode == "extra":
                    changed["unrelated"] = "a" * 64
                if mode == "renamed":
                    changed["elsewhere/" + first] = changed.pop(first)
                if mode == "hash":
                    changed[first] = "a" * 64
                with self.subTest(stage=stage, mode=mode), self.assertRaises(
                    ValueError
                ):
                    C.validate_tool_population(changed, directory, stage)
            for mode in ["missing", "extra", "content"]:
                with tempfile.TemporaryDirectory() as temporary:
                    snapshot = Path(temporary) / "snapshots"
                    shutil.copytree(directory, snapshot)
                    first = next(snapshot.iterdir())
                    if mode == "missing":
                        first.unlink()
                    if mode == "extra":
                        (snapshot / "unrelated.txt").write_text("extra")
                    if mode == "content":
                        first.write_text("unrelated text")
                    with self.subTest(stage=stage, snapshot=mode), self.assertRaises(
                        ValueError
                    ):
                        C.validate_tool_population(valid, snapshot, stage)
        valid = {name: C.digest((C.ROOT / name).read_bytes()) for name in C.TOOL_PATHS}
        C.validate_tool_population(valid)
        for changed in [
            {},
            {**valid, "unrelated": "a" * 64},
            {name: value for name, value in valid.items() if name != next(iter(valid))},
        ]:
            with self.assertRaises(ValueError):
                C.validate_tool_population(changed)

    def test_rebuilt_receipt_is_consumed_and_checked(self):
        from unittest.mock import patch

        changed = C.read_rows(C.DERIVED / "build-receipt.json")
        changed["c"]["flags"] = ["-ffast-math"]
        with patch.object(
            C, "build", return_value=changed
        ) as build, self.assertRaisesRegex(
            ValueError, "C source/adapter/build conditions"
        ):
            C.check()
        build.assert_called_once()

    def test_current_build_identity_is_not_required_to_equal_historical_platform(self):
        import tempfile
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as temporary:
            context = Path(temporary)
            files = {
                "locked-constellation": b"current-c-control",
                "public-build/debug/ConstellationResearch": b"current-swift-control",
                "public-package/Package.swift": C.public_manifest().encode(),
            }
            for name, data in files.items():
                path = context / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            receipt = C.read_rows(C.DERIVED / "build-receipt.json")
            receipt.update(platform="Linux-control", architecture="x86_64-control")
            receipt["c"]["compiler"] = "current C compiler control"
            receipt["swift"]["compiler"] = "current Swift compiler control"
            receipt["c"]["binarySHA256"] = C.digest(files["locked-constellation"])
            receipt["swift"]["binarySHA256"] = C.digest(
                files["public-build/debug/ConstellationResearch"]
            )
            receipt["swift"]["manifestSHA256"] = C.digest(
                files["public-package/Package.swift"]
            )
            for altered in [False, True]:
                if altered:
                    receipt["c"]["binarySHA256"] = "a" * 64
                with patch.object(C, "CONTEXT", context), patch.object(
                    C.platform, "platform", return_value=receipt["platform"]
                ), patch.object(
                    C.platform, "machine", return_value=receipt["architecture"]
                ), patch.object(
                    C.subprocess,
                    "check_output",
                    side_effect=[
                        receipt["c"]["compiler"],
                        receipt["swift"]["compiler"],
                    ],
                ):
                    if altered:
                        with self.assertRaisesRegex(ValueError, "actual current build"):
                            C.validate_build_receipt(receipt, "current")
                    else:
                        C.validate_build_receipt(receipt, "current")


if __name__ == "__main__":
    unittest.main()
