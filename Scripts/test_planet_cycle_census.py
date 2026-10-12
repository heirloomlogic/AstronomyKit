"""Controls for the direct-source complete-cycle planetary census."""
import copy
import importlib.util
import json
import math
from pathlib import Path
import unittest

PATH = Path(__file__).with_name("generate-planet-cycle-census.py")
SPEC = importlib.util.spec_from_file_location("planet_cycle_census", PATH)
census = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(census)


class PlanetCycleCensusTests(unittest.TestCase):
    def test_dense_scan_retains_every_crossing_and_principal_pair(self):
        result = census.scan_cycle(lambda value: math.sin(value), 0.25, 2 * math.pi + 0.25, 0.125)
        self.assertEqual([row["kind"] for row in result["crossings"]], ["apocenter", "pericenter"])
        self.assertEqual([row["kind"] for row in result["principal"]], ["apocenter", "pericenter"])
        self.assertGreater(result["sampleCount"], 40)
        exact = census.scan_cycle(lambda value: value - 1, 0, 2, 0.25)
        self.assertEqual(exact["crossings"], [{"kind": "pericenter", "lower": 1.0, "upper": 1.0, "root": 1.0, "distance": -math.cos(1)}])

    def test_validation_rejects_an_omitted_crossing_or_failed_residual(self):
        record = census.validate(json.loads(census.OUTPUT.read_bytes()))
        self.assertEqual(set(record["cases"]), set(census.BODIES))
        omitted = copy.deepcopy(record)
        omitted["cases"]["jupiter"]["physicalCrossings"].pop()
        with self.assertRaisesRegex(ValueError, "crossing"):
            census.validate(omitted)
        unmatched = copy.deepcopy(record)
        unmatched["cases"]["jupiter"]["principalPhysicalCrossingIndices"] = [0, 0]
        with self.assertRaisesRegex(ValueError, "principal"):
            census.validate(unmatched)

    def test_source_contract_is_clib_independent_and_bound_to_the_foundation(self):
        record = census.validate(json.loads(census.OUTPUT.read_bytes()))
        self.assertNotIn("Sources/CLibAstronomy", json.dumps(record))
        self.assertEqual(record["foundationSHA256"], census.digest(census.FOUNDATION.read_bytes()))
        self.assertEqual(record["sourceSHA256"], census.source_hashes())


if __name__ == "__main__":
    unittest.main()
