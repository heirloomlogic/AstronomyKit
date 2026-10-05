import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
INVENTORY_PATH = ROOT / "Documentation/Migration/contract-inventory.json"
LOCK_PATH = ROOT / "Tools/Migration/Oracle/oracle-lock.json"
EVIDENCE_PATH = ROOT / "Documentation/Migration/numerical-evidence.json"


def load_generator():
    path = ROOT / "Scripts/migration/generate-contract-inventory.py"
    spec = importlib.util.spec_from_file_location("contract_inventory", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ContractInventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()
        cls.inventory = json.loads(INVENTORY_PATH.read_text())

    def test_inventory_matches_sources(self):
        graph = self.generator.load_inventory_symbol_graph(ROOT)
        generated = self.generator.generate_inventory(ROOT, graph)
        self.assertEqual(self.inventory, generated)

    def test_every_entry_has_one_migration_owner(self):
        for collection in (
            "publicSwiftAPI",
            "cDependencies",
            "localPatches",
            "generatedArtifacts",
            "crossCuttingContracts",
            "testOwners",
        ):
            with self.subTest(collection=collection):
                entries = self.inventory[collection]
                self.assertTrue(entries)
                self.assertEqual(len(entries), len({entry["id"] for entry in entries}))
                self.assertTrue(all(entry["migrationIssue"] in range(80, 100) for entry in entries))

    def test_required_contract_dimensions_are_explicit(self):
        expected = {"errors", "nil-results", "serialization", "supported-dates", "mutable-state"}
        contracts = {entry["id"] for entry in self.inventory["crossCuttingContracts"]}
        self.assertEqual(expected, contracts)
        for symbol in self.inventory["publicSwiftAPI"]:
            self.assertEqual(expected, set(symbol["contracts"]))

    def test_optional_parameters_do_not_make_a_result_optional(self):
        self.assertEqual(
            "nonoptional",
            self.generator.nil_result_contract(
                "swift.init",
                "init(tt: Double, deltaTModel: DeltaTModel? = nil)",
            ),
        )
        self.assertEqual(
            "optional",
            self.generator.nil_result_contract(
                "swift.type.method",
                "static func find(from startTime: AstroTime) throws -> AstroTime?",
            ),
        )

    def test_process_global_mutation_is_classified(self):
        mutable_paths = {
            "AstronomyConfig.setDeltaTModel(_:)",
            "AstronomyConfig.reset()",
            "FixedStar.equatorial(at:from:equatorDate:)",
            "FixedStar.ecliptic(at:)",
            "FixedStar.horizon(at:from:refraction:)",
            "FixedStar.constellation(at:)",
        }
        entries = {entry["path"]: entry for entry in self.inventory["publicSwiftAPI"]}
        for path in mutable_paths:
            with self.subTest(path=path):
                self.assertEqual("process-global-mutable", entries[path]["contracts"]["mutable-state"])

    def test_all_documented_patch_groups_are_present(self):
        patches = self.inventory["localPatches"]
        self.assertEqual(list(range(1, 21)), [entry["patch"] for entry in patches])

    def test_all_generated_sources_are_present(self):
        expected = {
            "Sources/CLibAstronomy/EphemerisData/moon_data.inc",
            "Sources/CLibAstronomy/EphemerisData/pluto_barycenter.inc",
            "Sources/CLibAstronomy/EphemerisData/pluto_negative_sun.inc",
            "Sources/CLibAstronomy/EphemerisData/pluto_center_offset.inc",
            "Scripts/numerics/solar-altitude/bounds.json",
            "Sources/AstronomyKit/SolarAltitudeBounds.swift",
            "Sources/AstronomyKit/UTCOffsetTable.swift",
            "Sources/CLibAstronomy/generated/iau2000b_full.h",
            "Sources/CLibAstronomy/generated/polynomial-data.h",
            "Sources/CLibAstronomy/generated/vsop87b_full.h",
        }
        prototype_manifest = json.loads((ROOT / "Scripts/model-data/swift-prototype-manifest.json").read_text())
        expected.update(f"Sources/{path}" for path in prototype_manifest["outputs"])
        actual = {entry["path"] for entry in self.inventory["generatedArtifacts"]}
        self.assertEqual(expected, actual)

    def test_all_test_files_are_owned_and_classified(self):
        expected = self.generator.test_paths(ROOT)
        actual = {entry["path"] for entry in self.inventory["testOwners"]}
        self.assertEqual(expected, actual)
        allowed = {"independent-reference", "regression-fixture", "invariant", "smoke"}
        self.assertTrue(all(entry["classification"] in allowed for entry in self.inventory["testOwners"]))
        self.assertTrue(
            {
                "Scripts/migration/test_foundation.py",
                "Scripts/numerics/solar-altitude/test_bounds.py",
                "Scripts/performance/polynomial/test_polynomial.py",
                "Scripts/performance/test-moon-cache.sh",
                "Scripts/performance/test-nutation-cache.sh",
                "Scripts/performance/test-vsop-cache.sh",
            }.issubset(actual)
        )

    def test_consumed_c_constants_types_functions_and_fields_are_present(self):
        dependencies = {entry["id"] for entry in self.inventory["cDependencies"]}
        expected = {
            "APSIS_PERICENTER",
            "ECLIPSE_TOTAL",
            "ASCENDING_NODE",
            "VISIBLE_MORNING",
            "Astronomy_SearchLunarApsis",
            "astro_deltat_func",
            "astro_apsis_t",
            "astro_apsis_t.kind",
            "astro_apsis_t.dist_au",
            "astro_local_solar_eclipse_t.partial_begin",
        }
        self.assertTrue(expected.issubset(dependencies), expected - dependencies)

    def test_callback_typedefs_are_discovered_from_declarations(self):
        header = (ROOT / "Sources/CLibAstronomy/include/astronomy.h").read_text()
        typedefs = self.generator.c_typedefs(header)
        self.assertTrue({"astro_deltat_func", "astro_search_func_t", "astro_position_func_t"}.issubset(typedefs))

    def test_inventory_generation_always_reads_a_symbol_graph(self):
        with mock.patch.object(self.generator, "load_symbol_graph", return_value={"symbols": [], "relationships": []}) as load:
            self.generator.load_inventory_symbol_graph(ROOT)
        load.assert_called_once_with(ROOT)

    def test_synthesized_ownership_spelling_is_toolchain_independent(self):
        base = {
            "identifier": {"precise": "operator::SYNTHESIZED::Type"},
            "declarationFragments": [{"spelling": "static func != (lhs: borrowing Self, rhs: consuming Self) -> Bool"}],
        }
        self.assertEqual("static func != (lhs: Self, rhs: Self) -> Bool", self.generator.declaration(base))


class OracleLockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()

    def test_lock_covers_all_frozen_inputs(self):
        lock = json.loads(LOCK_PATH.read_text())
        # The oracle is frozen at its named revision, independently of new
        # production models. Derive its complete population from that tree.
        names = subprocess.check_output(
            ["git", "ls-tree", "-r", "--name-only", lock["baselineRevision"]],
            cwd=ROOT, text=True,
        ).splitlines()
        expected = {
            name for name in names
            if name.startswith(("Sources/CLibAstronomy/", "Scripts/model-data/", "Scripts/performance/polynomial/data/"))
            and Path(name).name not in {".gitattributes", "swift-prototype-manifest.json"}
        }
        self.assertEqual(expected, set(lock["files"]))
        self.assertTrue(all(len(digest) == 64 for digest in lock["files"].values()))

    def test_lock_pins_the_oracle_driver(self):
        lock = json.loads(LOCK_PATH.read_text())
        driver = "Tools/Migration/Oracle/oracle-main.c"
        self.assertEqual({driver}, set(lock["driverFiles"]))
        self.assertEqual(self.generator.sha256(ROOT / driver), lock["driverFiles"][driver])

    def test_oracle_build_is_reproducible(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            command = [str(ROOT / "Tools/Migration/Oracle/build-oracle.sh")]
            subprocess.run(command + [first], cwd=ROOT, check=True)
            subprocess.run(command + [second], cwd=ROOT, check=True)
            first_binary = Path(first) / "astronomy-oracle"
            second_binary = Path(second) / "astronomy-oracle"
            self.assertEqual(first_binary.read_bytes(), second_binary.read_bytes())
            output = subprocess.check_output([str(first_binary), "--smoke"], text=True)
            self.assertEqual("ASTRO_SUCCESS finite\n", output)

    def test_failed_rebuild_removes_stale_outputs(self):
        with tempfile.TemporaryDirectory() as output:
            binary = Path(output) / "astronomy-oracle"
            metadata = Path(output) / "build-metadata.json"
            binary.write_text("stale")
            metadata.write_text("stale")
            environment = dict(os.environ, CC="/usr/bin/false")
            with self.assertRaises(subprocess.CalledProcessError):
                subprocess.run(
                    [str(ROOT / "Tools/Migration/Oracle/build-oracle.sh"), output],
                    cwd=ROOT,
                    check=True,
                    env=environment,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            self.assertFalse(binary.exists())
            self.assertFalse(metadata.exists())


class NumericalEvidenceContractTests(unittest.TestCase):
    def test_evidence_classes_are_separate_and_owned(self):
        evidence = json.loads(EVIDENCE_PATH.read_text())
        self.assertEqual(1, evidence["schemaVersion"])
        classes = evidence["classes"]
        self.assertEqual({"exactEquality", "numericalRegression", "independentAccuracy", "derivedBounds"}, set(classes))
        for name, entries in classes.items():
            with self.subTest(name=name):
                self.assertTrue(entries)
                self.assertTrue(all(entry["migrationIssue"] in range(80, 100) for entry in entries))
                self.assertTrue(all(entry["evidence"] for entry in entries))

    def test_regression_and_accuracy_limits_are_not_cross_classified(self):
        evidence = json.loads(EVIDENCE_PATH.read_text())
        regression = {entry["id"] for entry in evidence["classes"]["numericalRegression"]}
        accuracy = {entry["id"] for entry in evidence["classes"]["independentAccuracy"]}
        self.assertIn("platform-libm-fixtures", regression)
        self.assertIn("jpl-geocentric-equatorial-positions", accuracy)
        self.assertTrue(regression.isdisjoint(accuracy))

    def test_native_candidate_does_not_inherit_exact_c_output_requirement(self):
        evidence = json.loads(EVIDENCE_PATH.read_text())
        comparison = next(entry for entry in evidence["classes"]["exactEquality"] if entry["id"] == "comparison-runner-current-backend")
        self.assertEqual("current-c-backed-swift-only", comparison["scope"])
        self.assertFalse(comparison["appliesToNativeSwiftCandidate"])

    def test_independent_accuracy_records_every_existing_suite_and_tolerance(self):
        evidence = json.loads(EVIDENCE_PATH.read_text())
        accuracy = {entry["id"]: entry for entry in evidence["classes"]["independentAccuracy"]}
        geocentric = accuracy["jpl-geocentric-equatorial-positions"]
        self.assertEqual(
            {
                "Sun": 1.0,
                "Moon": 1.0,
                "Mercury": 1.0,
                "Venus": 1.0,
                "Mars": 1.0,
                "Jupiter": 1.0,
                "Saturn": 1.0,
                "Uranus": 1.0,
                "Neptune": 1.5,
                "Pluto": 1.0,
            },
            geocentric["maximumAngularErrorArcminutes"],
        )
        topocentric = accuracy["jpl-topocentric-equatorial-positions"]
        self.assertEqual(
            {"Moon": 1.0, "Mercury": 1.0, "Venus": 1.0, "Mars": 1.0, "Jupiter": 1.0, "Saturn": 1.0, "Uranus": 1.0, "Neptune": 1.5, "Pluto": 1.5},
            topocentric["maximumAngularErrorArcminutes"],
        )
        audit = accuracy["independent-audit-validation"]
        self.assertEqual(["Tests/AstronomyKitTests/AuditValidationTests.swift"], audit["evidence"])


if __name__ == "__main__":
    unittest.main()
