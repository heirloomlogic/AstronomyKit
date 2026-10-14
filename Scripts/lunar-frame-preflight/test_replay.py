#!/usr/bin/env python3
"""Tests for the self-contained lunar-frame preflight."""

import copy
import importlib.util
import json
import math
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("lunar_frame_replay", HERE / "replay.py")
replay = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(replay)


class LunarFrameReplayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.analysis = replay.analyze()

    def test_receipts_bind_the_complete_source_inventory(self):
        receipt = replay.read_receipts()
        self.assertEqual({entry["path"] for entry in receipt["sources"]}, replay.SOURCE_PATHS)
        self.assertEqual(receipt["capture"]["revision"], replay.BASE_REVISION)
        self.assertEqual(receipt["capture"]["astronomyKitSourceTree"], replay.SOURCE_TREE)

    def test_receipts_reject_omission_digest_change_and_unsafe_paths(self):
        receipt = json.loads(replay.RECEIPTS_PATH.read_text())
        omitted = copy.deepcopy(receipt)
        omitted["sources"].pop()
        with self.assertRaises(replay.ReplayError):
            replay.read_receipts(omitted)
        changed = copy.deepcopy(receipt)
        changed["sources"][0]["sha256"] = "0" * 64
        with self.assertRaises(replay.ReplayError):
            replay.read_receipts(changed)
        missing_origin = copy.deepcopy(receipt)
        missing_origin["sources"][0]["origin"].pop("basePath")
        with self.assertRaises(replay.ReplayError):
            replay.read_receipts(missing_origin)
        changed_command = copy.deepcopy(receipt)
        changed_command["capture"]["command"][-1] = "different capture command"
        with self.assertRaises(replay.ReplayError):
            replay.read_receipts(changed_command)
        for path in ("../source", "/tmp/source", "sources/../source"):
            with self.assertRaises(replay.ReplayError):
                replay.contained_path(path)

    def test_receipts_reject_wrong_container_types_and_missing_members(self):
        receipt = json.loads(replay.RECEIPTS_PATH.read_text())
        invalid = [[], "receipt"]
        for value in (None, [], "capture"):
            changed = copy.deepcopy(receipt)
            changed["capture"] = value
            invalid.append(changed)
        for value in (None, [], "program"):
            changed = copy.deepcopy(receipt)
            changed["capture"]["program"] = value
            invalid.append(changed)
        for value in (None, {}, [None]):
            changed = copy.deepcopy(receipt)
            changed["sources"] = value
            invalid.append(changed)
        wrong_origin = copy.deepcopy(receipt)
        wrong_origin["sources"][0]["origin"] = None
        invalid.append(wrong_origin)
        missing_capture_member = copy.deepcopy(receipt)
        missing_capture_member["capture"].pop("command")
        invalid.append(missing_capture_member)
        missing_program_member = copy.deepcopy(receipt)
        missing_program_member["capture"]["program"].pop("sha256")
        invalid.append(missing_program_member)
        for value in invalid:
            with self.subTest(value=value):
                with self.assertRaises(replay.ReplayError):
                    replay.read_receipts(value)

    def test_report_encoding_quantizes_floats(self):
        self.assertEqual(replay.encoded({"value": 1.1234567890123456}), b'{\n  "value": 1.123456789012\n}\n')

    def test_primary_sources_state_coverage_and_leave_svs_frame_unnamed(self):
        contract = replay.source_contract()
        self.assertEqual(contract["naif"]["pckCoverageTDB"], ["1549-12-31T00:00:00", "2650-01-25T00:00:00"])
        self.assertEqual(contract["naif"]["anglesArcseconds"], [67.8526, 78.6944, 0.2785])
        self.assertTrue(all(not source["bodyFixedFrameNamed"] and not source["lightTimeRecipeNamed"] for source in contract["svs"].values()))

    def test_all_svs_rows_have_complete_hourly_utc_coverage(self):
        rows, coverage = replay.parse_tables()
        self.assertEqual(len(rows), 26305)
        self.assertEqual([coverage[str(year)]["rows"] for year in range(2020, 2023)], [8785, 8760, 8760])
        self.assertTrue(all(item["stepSeconds"] == 3600 for item in coverage.values()))

    def test_capture_binds_base_source_and_ut_to_tt_conversion(self):
        rows, _, toolchain = replay.paired_rows()
        self.assertEqual(len(rows), 26305)
        self.assertEqual(toolchain, replay.CAPTURE_TOOLCHAIN)
        self.assertTrue(all(0 < row["terrestrialTime"] - row["universalTime"] < 0.002 for row in rows))

    def test_fixed_frame_matrix_matches_cspice_cross_check(self):
        matrix = self.analysis["frameMatrixPAtoME"]
        expected = [[0.9999998731138765, -0.0003289586579141938, 0.00038152120821145725], [0.00032895919698748533, 0.9999999458920105, -1.3502060036227025e-06], [-0.00038152074340615683, 1.4757107425872328e-06, 0.9999999272198697]]
        for actual_row, expected_row in zip(matrix, expected):
            for actual, wanted in zip(actual_row, expected_row):
                self.assertAlmostEqual(actual, wanted, places=16)
        determinant = matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) - matrix[0][1] * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0]) + matrix[0][2] * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0])
        self.assertAlmostEqual(determinant, 1.0, places=15)

    def test_identity_replays_the_preserved_libration_gates(self):
        identity = self.analysis["comparisons"]["identity"]
        self.assertAlmostEqual(identity["latitudeArcminutes"]["meanSigned"], 1.4047045114847714)
        self.assertAlmostEqual(identity["latitudeArcminutes"]["maxAbsolute"], 1.6691774564322515)
        self.assertLess(identity["latitudeArcminutes"]["maxAbsolute"], 1.67)
        self.assertLess(identity["longitudeArcminutes"]["maxAbsolute"], 0.1304)
        self.assertEqual(identity["latitudeArcminutes"]["worst"]["stampUTC"], "2020-01-12T08:00:00Z")

    def test_pa_to_me_rotation_reduces_latitude_but_breaks_longitude_gate(self):
        candidate = self.analysis["comparisons"]["interpretBaseAsPAThenConvertToME"]
        identity = self.analysis["comparisons"]["identity"]
        self.assertLess(candidate["latitudeArcminutes"]["rms"], identity["latitudeArcminutes"]["rms"] * 0.13)
        self.assertLess(candidate["latitudeArcminutes"]["maxAbsolute"], 0.36)
        self.assertGreater(candidate["longitudeArcminutes"]["maxAbsolute"], 0.1304 * 9)

    def test_reverse_frame_direction_worsens_latitude(self):
        reverse = self.analysis["comparisons"]["interpretBaseAsMEThenConvertToPA"]
        identity = self.analysis["comparisons"]["identity"]
        self.assertGreater(reverse["latitudeArcminutes"]["rms"], identity["latitudeArcminutes"]["rms"] * 1.9)
        self.assertGreater(reverse["latitudeArcminutes"]["maxAbsolute"], 2.97)

    def test_clock_and_axis_negative_controls_are_detected(self):
        controls = self.analysis["negativeControls"]
        self.assertGreater(controls["oneHourShift"]["angularSeparationArcminutes"]["rms"], self.analysis["comparisons"]["identity"]["angularSeparationArcminutes"]["rms"] * 2.5)
        self.assertGreater(controls["longitudeLatitudeSwap"]["angularSeparationArcminutes"]["rms"], 100)

    def test_report_states_the_supported_limit(self):
        finding = self.analysis["finding"]
        self.assertGreater(finding["paToMeLongitudeGateRatio"], 9)
        self.assertIn("does not explain", finding["supportedConclusion"])
        self.assertEqual(len(finding["unresolved"]), 3)


if __name__ == "__main__":
    unittest.main()
