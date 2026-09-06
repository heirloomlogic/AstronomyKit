"""Checks for the diagnostic gate; optional compiled-model check uses ERFA's reference."""
import ctypes
import gzip
import json
import math
import os
from pathlib import Path
import unittest

from measure import fixtures, refine


class DiagnosticTests(unittest.TestCase):
    def test_frozen_population_and_conventions(self):
        cases = list(fixtures())  # also verifies every original file checksum
        self.assertEqual(len(cases), 24)
        events = [event for _, oracle in cases for event in oracle["events"]]
        self.assertEqual(len(events), 36)
        self.assertEqual(sum(event["kind"] == "station" for event in events), 12)
        for _, oracle in cases:
            self.assertEqual(oracle["settings"]["flags"], "260")
            self.assertEqual(oracle["settings"]["package"], "pyswisseph==2.10.3.2")

    def test_refinement_precision_is_separate_from_reference_accuracy(self):
        offset, width, residual = refine(lambda seconds: (seconds-75.857)**3)
        self.assertLessEqual(width, .001)
        self.assertLess(abs(residual), 1e-8)
        self.assertGreater(abs(offset), 60)  # a converged root can fail absolute accuracy

    def test_bracket_expands_and_accepts_either_direction(self):
        for sign in (-1, 1):
            offset, width, _ = refine(lambda seconds: sign*(seconds+238.116))
            self.assertAlmostEqual(offset, -238.116, delta=.001)
            self.assertLessEqual(width, .001)

    def test_no_sign_bracket_is_unresolved(self):
        with self.assertRaisesRegex(ValueError, "No local sign bracket"):
            refine(lambda seconds: seconds*seconds+1)

    def test_nonfinite_is_unresolved(self):
        for value in (math.nan, math.inf, -math.inf):
            with self.assertRaisesRegex(ValueError, "Non-finite"):
                refine(lambda seconds: value)

    def test_component_report_matches_archived_full_library(self):
        results = Path(__file__).resolve().parent / "results"
        with gzip.open(results / "components.json.gz", "rt") as stream:
            components = json.load(stream)
        with gzip.open(results / "matrix.json.gz", "rt") as stream:
            matrix = json.load(stream)
        self.assertEqual(components["nativeLibrarySHA256"],
                         matrix["libraries"]["full"]["binarySHA256"])

    @unittest.skipUnless(os.environ.get("ASTRONOMY_ACCURACY_LIBRARY"), "requires an isolated full-model library")
    def test_full_nutation_matches_independent_erfa_reference(self):
        # ERFA t_nut00b, https://github.com/liberfa/erfa/blob/master/src/t_erfa_c.c
        # JD(TT)=2400000.5+53736.0; expected angles are radians.
        library = ctypes.CDLL(str(Path(os.environ["ASTRONOMY_ACCURACY_LIBRARY"]).resolve()))
        function = library.ak_nutation
        function.argtypes = [ctypes.c_double, ctypes.POINTER(ctypes.c_double)]
        function.restype = None
        output = (ctypes.c_double*2)()
        function(2191.5, output)
        self.assertAlmostEqual(output[0]*math.pi/(180*3600), -0.9632552291148362783e-5, delta=1e-13)
        self.assertAlmostEqual(output[1]*math.pi/(180*3600), 0.4063197106621159367e-4, delta=1e-13)


if __name__ == "__main__":
    unittest.main()
