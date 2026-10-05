import copy
import importlib.util
import json
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("current_seasons", Path(__file__).with_name("check-current-seasonal-search.py"))
C = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(C)


class CurrentSeasonalInputs(unittest.TestCase):
    def test_actual_inputs_and_tampered_population_hashes(self):
        saved = json.loads(C.S.REPORT.read_text())
        current = {'inputSHA256': C.S.source_hashes()}
        C.validate_inputs(saved, current)
        for path in ['Sources/CLibAstronomy/astronomy.c', 'Scripts/reference-data/qualify-seasonal-roots.py']:
            mutated = copy.deepcopy(current)
            mutated['inputSHA256'][path] = '0' * 64
            with self.assertRaisesRegex(ValueError, 'actual files'):
                C.validate_inputs(saved, mutated)
        for mutation in ['missing', 'extra']:
            mutated = copy.deepcopy(current)
            if mutation == 'missing':
                mutated['inputSHA256'].pop('Sources/CLibAstronomy/astronomy.c')
            else:
                mutated['inputSHA256']['unapproved'] = '0' * 64
            with self.assertRaisesRegex(ValueError, 'actual files'):
                C.validate_inputs(saved, mutated)

    def test_complete_map_includes_generated_coefficients(self):
        complete = C.complete_sources()
        coefficient_paths = {str(p.relative_to(C.ROOT)) for p in (C.ROOT / 'Sources/CLibAstronomy').rglob('*.inc')}
        self.assertTrue(coefficient_paths)
        self.assertTrue(coefficient_paths <= set(complete))
        for path in coefficient_paths:
            self.assertEqual(complete[path], C.S.Q.digest((C.ROOT / path).read_bytes()))
