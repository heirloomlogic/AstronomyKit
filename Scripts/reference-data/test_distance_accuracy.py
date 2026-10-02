import copy
import importlib.util
import json
import math
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

PATH = Path(__file__).with_name("distance-accuracy.py")
spec = importlib.util.spec_from_file_location("distance_accuracy", PATH)
distance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distance)


class DistanceAccuracyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = distance.RAW / "characterization"
        cls.recipe = json.loads((directory / "mercury-heliocentric.query.json").read_bytes())["parameters"]
        cls.response = json.loads((directory / "mercury-heliocentric.json").read_bytes())

    def test_epochs_are_disjoint_stratified_and_fixed_before_measurement(self):
        characterization = distance.epochs("characterization")
        heldout = distance.epochs("heldout")
        self.assertEqual(131, len(characterization))
        self.assertEqual(134, len(heldout))
        self.assertFalse(set(characterization) & set(heldout))
        self.assertEqual(distance.START, characterization[0])
        self.assertTrue(all(distance.START <= jd < distance.STOP for jd in characterization + heldout))

    def test_parser_rejects_time_frame_origin_and_unit_mutations(self):
        for original, replacement in [("JDTT", "JDTDB"), ("Reference frame : ICRF", "Reference frame : B1950"),
                                      ("Sun (10)", "Earth (399)"), ("Output units    : AU-D", "Output units    : KM-S"),
                                      ("GEOMETRIC cartesian", "LT CORRECTED cartesian")]:
            with self.subTest(original=original):
                changed = copy.deepcopy(self.response)
                self.assertIn(original, changed["result"])
                changed["result"] = changed["result"].replace(original, replacement)
                with self.assertRaises(ValueError):
                    distance.parse_response(distance.encoded(changed), self.recipe)

    def test_parser_rejects_missing_epoch_or_nonfinite_values(self):
        for mutation in ("missing", "nonfinite"):
            changed = copy.deepcopy(self.response)
            text = changed["result"]
            prefix, rest = text.split("$$SOE", 1)
            data, suffix = rest.split("$$EOE", 1)
            lines = data.strip().splitlines()
            if mutation == "missing":
                lines.pop()
            else:
                fields = lines[0].split(",")
                fields[2] = " nan"
                lines[0] = ",".join(fields)
            changed["result"] = prefix + "$$SOE\n" + "\n".join(lines) + "\n$$EOE" + suffix
            with self.assertRaises(ValueError):
                distance.parse_response(distance.encoded(changed), self.recipe)

    def test_response_and_recipe_cannot_be_rebound_silently(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = distance.encoded(self.response)
            (root / "sample.json").write_bytes(data)
            recipe = {"parameters": self.recipe, "responseSHA256": distance.digest(data)}
            (root / "sample.query.json").write_bytes(distance.encoded(recipe))
            distance.read_pair(root, "sample", self.recipe)
            (root / "sample.json").write_bytes(data + b" ")
            with self.assertRaisesRegex(ValueError, "hash"):
                distance.read_pair(root, "sample", self.recipe)

    def test_frozen_policy_blocks_characterization_refresh_and_retuning(self):
        with tempfile.TemporaryDirectory() as directory:
            budget = Path(directory) / "budget.json"
            budget.write_text("{}")
            with patch.object(distance, "BUDGET", budget):
                with self.assertRaisesRegex(ValueError, "frozen"):
                    distance.refresh("characterization")
                with self.assertRaisesRegex(ValueError, "frozen"):
                    distance.characterize()
                with self.assertRaisesRegex(ValueError, "already frozen"):
                    distance.freeze()

    def test_heldout_cannot_be_acquired_before_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(distance, "BUDGET", Path(directory) / "absent.json"):
                with self.assertRaisesRegex(ValueError, "before acquiring"):
                    distance.refresh("heldout")

    def test_allowances_retain_approved_policy_and_characterization_binding(self):
        if not distance.BUDGET.exists():
            self.skipTest("allowances not yet frozen")
        budget = json.loads(distance.BUDGET.read_bytes())
        characterization = json.loads(distance.CHARACTERIZATION.read_bytes())
        self.assertEqual(2, budget["marginMultiplier"])
        self.assertEqual(distance.digest(distance.CHARACTERIZATION.read_bytes()), budget["characterizationSHA256"])
        self.assertEqual(19, len(budget["allowances"]))
        for key, allowance in budget["allowances"].items():
            maximum = characterization["summary"][key]["maximumRangeErrorKm"]
            self.assertEqual(maximum, allowance["characterizationMaximumKm"])
            expected = 2 * max(maximum, allowance["literatureScaleFloorKm"]) + .001 + allowance["alignmentAllowanceKm"]
            self.assertEqual(math.ceil(expected * 1000) / 1000, allowance["allowedErrorKm"])

    def test_heldout_failure_cannot_grow_a_frozen_allowance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            characterization = root / "characterization.json"
            characterization.write_bytes(distance.encoded({"inputSHA256": {}}))
            budget = root / "budget.json"
            policy = {"characterizationSHA256": distance.digest(characterization.read_bytes()),
                      "allowances": {"mercury-heliocentric": {"allowedErrorKm": 10}}}
            budget.write_bytes(distance.encoded(policy))
            record = {"body": "Mercury", "mode": "heliocentric", "julianDateTT": 2451545,
                      "referenceRangeAU": 1, "alignmentRemainderEstimateKm": 0}
            result = {**record, "signedRangeErrorKm": 11, "allowedErrorKm": 10}
            with patch.multiple(distance, BUDGET=budget, CHARACTERIZATION=characterization,
                                FIXTURE=root / "fixture.json", REPORT=root / "report.json"), \
                    patch.object(distance, "references", return_value=([record], {})), \
                    patch.object(distance, "input_hashes", return_value={}), \
                    patch.object(distance, "measure", return_value=[result]), \
                    patch.object(distance, "series", return_value=[("Mercury", "heliocentric")]):
                with self.assertRaisesRegex(ValueError, "acceptance failed"):
                    distance.acceptance()
            self.assertEqual(distance.encoded(policy), budget.read_bytes())
            self.assertEqual(1, json.loads((root / "report.json").read_bytes())["failureCount"])


if __name__ == "__main__":
    unittest.main()
