import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("inverse", Path(__file__).with_name("check_inverse_refraction.py"))
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)


class InverseRefractionControls(unittest.TestCase):
    def test_exact_frozen_population(self):
        cases = M.selection(M.load(M.PROTOCOL))
        self.assertEqual(312, len(cases))
        self.assertEqual(312, len(set(cases)))

    def test_existing_output_rejects_before_execution(self):
        with tempfile.TemporaryDirectory() as name, patch.object(M, "process") as process:
            with self.assertRaises(FileExistsError):
                M.acquire(Path(name), "HEAD")
            process.assert_not_called()

    def test_timeout_is_killed_and_reaped_with_raw_output(self):
        import os
        import sys
        packet = M.process([sys.executable, "-c", "import time; print('entered', flush=True); time.sleep(30)"], 0.25, {"PATH": os.defpath})
        self.assertEqual("timeout-killed-and-reaped", packet["termination"])
        self.assertEqual(-9, packet["exitCode"])
        self.assertTrue(packet["reaped"])
        self.assertEqual("ZW50ZXJlZAo=", packet["stdoutBase64"])

    def test_saved_finiteness_cannot_override_bits(self):
        case = ("none", "0", "direct", "espenakMeeus")
        result = {"mode": case[0], "input": case[1], "route": case[2], "model": case[3],
                  "inputBits": "0", "utBits": "40c3880000000000", "ttBits": "40c3880000000000", "finite": True,
                  "correctionBits": "7ff8000000000000"}
        with self.assertRaisesRegex(ValueError, "finiteness"):
            M.validate_payload(case, result)

    def test_nonfinite_time_and_changed_input_reject(self):
        case = ("none", "0", "direct", "espenakMeeus")
        result = {"mode": case[0], "input": case[1], "route": case[2], "model": case[3],
                  "inputBits": "0", "utBits": "40c3880000000000", "ttBits": "7ff8000000000000", "finite": True, "correctionBits": "0"}
        with self.assertRaisesRegex(ValueError, "time"):
            M.validate_payload(case, result)
        result["ttBits"] = result["utBits"]
        result["inputBits"] = "3ff0000000000000"
        with self.assertRaisesRegex(ValueError, "input double"):
            M.validate_payload(case, result)

    def test_extra_payload_and_bool_type_reject(self):
        case = ("none", "0", "direct", "espenakMeeus")
        result = {"mode": case[0], "input": case[1], "route": case[2], "model": case[3],
                  "inputBits": "0", "utBits": "40c3880000000000", "ttBits": "40c3880000000000", "finite": 1, "correctionBits": "0"}
        with self.assertRaisesRegex(ValueError, "population"):
            M.validate_payload(case, result)
        result["finite"] = True
        result["extra"] = 0
        with self.assertRaisesRegex(ValueError, "population"):
            M.validate_payload(case, result)


if __name__ == "__main__":
    unittest.main()
