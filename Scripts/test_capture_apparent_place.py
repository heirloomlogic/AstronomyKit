"""Fail-closed publication of validated Horizons apparent-place archives."""
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('capture_apparent', Path(__file__).with_name('capture-apparent-place.py'))
g = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(g)


class ApparentCaptureTests(unittest.TestCase):
    def setUp(self):
        self.original = (g.DATA/'sun-geocentric.json').read_bytes()
        self.receipt = (g.DATA/'sun-geocentric.query.json').read_bytes()
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.data = Path(self.directory.name)
        (self.data/'sun-geocentric.json').write_bytes(self.original)
        (self.data/'sun-geocentric.query.json').write_bytes(self.receipt)

    def test_invalid_candidate_does_not_publish_either_file(self):
        source = json.loads(self.original)
        for old, new in [('Sun (10)', 'Sun (11)'), ('Earth (399)', 'Moon (301)'),
                         ('Center-site name: GEOCENTRIC', 'Center-site name: TOPOCENTRIC'),
                         ('NO (AIRLESS)', 'YES (REFRACTED)'), ('RA_(ICRF-a-app)', 'RA_WRONG')]:
            with self.subTest(old=old):
                candidate = dict(source, result=source['result'].replace(old, new))
                self.assertNotEqual(candidate, source)
                with patch.object(g, 'DATA', self.data), patch.object(g.urllib.request, 'urlopen', return_value=io.BytesIO(json.dumps(candidate).encode())):
                    with self.assertRaises(ValueError):
                        g.case('sun', False, True)
                self.assertEqual((self.data/'sun-geocentric.json').read_bytes(), self.original)
                self.assertEqual((self.data/'sun-geocentric.query.json').read_bytes(), self.receipt)

    def test_missing_row_does_not_publish(self):
        candidate = json.loads(self.original)
        before, rest = candidate['result'].split('$$SOE\n')
        rows, after = rest.split('$$EOE')
        candidate['result'] = before+'$$SOE\n'+'\n'.join(rows.splitlines()[1:])+'\n$$EOE'+after
        with patch.object(g, 'DATA', self.data), patch.object(g.urllib.request, 'urlopen', return_value=io.BytesIO(json.dumps(candidate).encode())):
            with self.assertRaises(ValueError):
                g.case('sun', False, True)
        self.assertEqual((self.data/'sun-geocentric.json').read_bytes(), self.original)
        self.assertEqual((self.data/'sun-geocentric.query.json').read_bytes(), self.receipt)

    def test_valid_candidate_replays(self):
        with patch.object(g, 'DATA', self.data), patch.object(g.urllib.request, 'urlopen', return_value=io.BytesIO(self.original)):
            captured = g.case('sun', False, True)
            self.assertEqual(captured, g.case('sun', False, False))

    def test_second_publication_error_restores_existing_pair(self):
        replace = g.os.replace
        failed = False

        def fail_receipt_once(source, destination):
            nonlocal failed
            if Path(destination).name.endswith('.query.json') and not failed:
                failed = True
                raise OSError('injected receipt publication failure')
            return replace(source, destination)

        candidate = json.loads(self.original)
        candidate['signature']['version'] = 'test candidate with valid astronomical rows'
        with patch.object(g, 'DATA', self.data), patch.object(g.urllib.request, 'urlopen', return_value=io.BytesIO(json.dumps(candidate).encode())), patch.object(g.os, 'replace', side_effect=fail_receipt_once):
            with self.assertRaisesRegex(OSError, 'injected receipt'):
                g.case('sun', False, True)
        self.assertTrue(failed)
        self.assertEqual((self.data/'sun-geocentric.json').read_bytes(), self.original)
        self.assertEqual((self.data/'sun-geocentric.query.json').read_bytes(), self.receipt)

    def test_interrupted_mismatched_pair_is_rejected_by_replay(self):
        changed = json.loads(self.original)
        changed['signature']['version'] = 'interrupted publication'
        (self.data/'sun-geocentric.json').write_text(json.dumps(changed))
        with patch.object(g,'DATA',self.data), self.assertRaisesRegex(ValueError,'Recipe or response changed'):
            g.case('sun',False,False)


if __name__ == '__main__':
    unittest.main()
