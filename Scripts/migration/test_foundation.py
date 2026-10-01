import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INVENTORY_PATH = ROOT / "Documentation/Migration/contract-inventory.json"
LOCK_PATH = ROOT / "Tools/Migration/Oracle/oracle-lock.json"


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
        graph = self.generator.load_symbol_graph(ROOT) if self.generator.has_recorded_swift_toolchain(ROOT) else None
        generated = self.generator.generate_inventory(ROOT, graph, self.inventory["publicSwiftAPI"])
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

    def test_all_documented_patch_groups_are_present(self):
        patches = self.inventory["localPatches"]
        self.assertEqual(list(range(1, 19)), [entry["patch"] for entry in patches])

    def test_all_generated_sources_are_present(self):
        expected = {
            path.relative_to(ROOT).as_posix()
            for path in (ROOT / "Sources").rglob("*")
            if path.is_file() and self.generator.is_generated_source(path)
        }
        actual = {entry["path"] for entry in self.inventory["generatedArtifacts"]}
        self.assertEqual(expected, actual)

    def test_all_test_files_are_owned_and_classified(self):
        expected = {
            path.relative_to(ROOT).as_posix()
            for path in (ROOT / "Tests").rglob("*.swift")
        }
        actual = {entry["path"] for entry in self.inventory["testOwners"]}
        self.assertEqual(expected, actual)
        allowed = {"independent-reference", "regression-fixture", "invariant", "smoke"}
        self.assertTrue(all(entry["classification"] in allowed for entry in self.inventory["testOwners"]))


class OracleLockTests(unittest.TestCase):
    def test_lock_covers_all_frozen_inputs(self):
        lock = json.loads(LOCK_PATH.read_text())
        expected = {
            path.relative_to(ROOT).as_posix()
            for pattern in (
                "Sources/CLibAstronomy/**/*",
                "Scripts/model-data/**/*",
                "Scripts/performance/polynomial/data/**/*",
            )
            for path in ROOT.glob(pattern)
            if path.is_file() and path.name != ".gitattributes"
        }
        self.assertEqual(expected, set(lock["files"]))
        self.assertTrue(all(len(digest) == 64 for digest in lock["files"].values()))

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


if __name__ == "__main__":
    unittest.main()
