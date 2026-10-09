import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('planetary_apsides', Path(__file__).with_name('capture-planetary-apsides.py'))
f = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(f)


class PlanetaryApsisSourceTests(unittest.TestCase):
    def test_frozen_windows_replay_all_crossings(self):
        evidence = json.loads(f.OUTPUT.read_bytes())
        self.assertEqual(8, len(evidence['cases']))
        for case, recorded in zip(f.CASES, evidence['cases']):
            body, target, epoch, _ = case
            raw = (f.DATA/f'{body}.json').read_bytes()
            _, rows, crossings = f.parse(target, epoch, raw)
            self.assertEqual(recorded['samples'], rows)
            self.assertEqual(recorded['crossings'], crossings)
            roots, digest = f.refine(body, target, epoch, crossings, False)
            self.assertEqual(recorded['roots'], roots)
            self.assertEqual(recorded['refinementSHA256'], digest)
            self.assertTrue(all((r['upperJDTT']-r['lowerJDTT'])*86400 <= 1 for r in roots))
        self.assertEqual([1, 1, 1, 1, 3, 3, 2, 3], [len(c['roots']) for c in evidence['cases']])

    def test_center_timescale_frame_and_nonfinite_substitution_fail(self):
        body, target, epoch, _ = f.CASES[0]
        raw = (f.DATA/f'{body}.json').read_bytes()
        for old, new in [(b'Sun (10)', b'Earth (399)'), (b'JDTT', b'JDTDB'), (b'ICRF', b'B1950'), (b'Mercury (199)', b'Mercury (1)')]:
            self.assertIn(old, raw)
            with self.assertRaises(ValueError):
                f.parse(target, epoch, raw.replace(old, new))
        response = json.loads(raw)
        before, rest = response['result'].split('$$SOE')
        fields = rest.splitlines()[1].split(',')
        fields[10] = 'nan'
        lines = rest.splitlines()
        lines[1] = ','.join(fields)
        response['result'] = before + '$$SOE' + '\n'.join(lines)
        with self.assertRaisesRegex(ValueError, 'nonfinite'):
            f.parse(target, epoch, json.dumps(response).encode())

    def test_refinement_rejects_changed_query_and_digest(self):
        body, target, epoch, _ = f.CASES[0]
        _, _, crossings = f.parse(target, epoch, (f.DATA/f'{body}.json').read_bytes())
        original = json.loads((f.DATA/f'{body}-refinement.json').read_bytes())
        with tempfile.TemporaryDirectory() as directory, patch.object(f, 'DATA', Path(directory)):
            for change in ('query', 'sha256'):
                transcript = copy.deepcopy(original)
                if change == 'query':
                    transcript[0]['query']['CENTER'] = "'500@0'"
                else:
                    transcript[0]['sha256'] = '0'*64
                (f.DATA/f'{body}-refinement.json').write_text(json.dumps(transcript))
                with self.assertRaisesRegex(ValueError, 'changed'):
                    f.refine(body, target, epoch, crossings, False)


if __name__ == '__main__':
    unittest.main()
