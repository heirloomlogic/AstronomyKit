"""Controls for the read-only planetary source-model diagnostic."""
import base64
import copy
import importlib.util
import json
from pathlib import Path
import unittest

PATH = Path(__file__).with_name('qualify-planet-source-model.py')
spec = importlib.util.spec_from_file_location('planet_source_model', PATH)
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)


class SourceModelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.archive = json.loads(model.ARCHIVE.read_bytes())

    def test_original_ranges_and_selected_sources(self):
        readers = model.readers(self.archive)
        table = model.Kernel(readers['ura184_part-3'])
        self.assertIsNotNone(table.record(799, 7, 2470033))
        self.assertIsNotNone(table.record(7, 0, 2470033))
        with self.assertRaisesRegex(ValueError, 'target/center'):
            table.record(799, 0, 2470033)

    def test_changed_raw_byte_is_rejected(self):
        archive = copy.deepcopy(self.archive)
        source = archive['sources']['de441']
        row = next(iter(source['ranges'].values()))
        data = bytearray(base64.b64decode(row['base64']))
        data[0] ^= 1
        row['base64'] = base64.b64encode(data).decode()
        with self.assertRaisesRegex(ValueError, 'digest'):
            model.readers(archive)

    def test_changed_identity_or_url_is_rejected(self):
        for key, value in [('identity', [1, None, 'wrong']), ('url', 'https://example.com/wrong.bsp')]:
            with self.subTest(key=key):
                archive = copy.deepcopy(self.archive)
                archive['sources']['de441'][key] = value
                with self.assertRaisesRegex(ValueError, 'identity'):
                    model.readers(archive)

    def test_missing_range_fails_closed(self):
        archive = copy.deepcopy(self.archive)
        del archive['sources']['de441']['ranges']['0-1023']
        reader = model.readers(archive)['de441']
        with self.assertRaisesRegex(ValueError, 'unarchived'):
            model.Kernel(reader)

    def test_wrong_frame_cannot_be_evaluated(self):
        reader = model.readers(self.archive)['ura184_part-3']
        kernel = model.Kernel(reader)
        kernel.segments = [s._replace(frame=2) for s in kernel.segments]
        with self.assertRaisesRegex(ValueError, 'frame'):
            kernel.record(799, 7, 2470033)

    def test_clock_and_derivative_on_exact_polynomial(self):
        import mpmath as mp
        mp.mp.dps = 50
        p, v = model.chebyshev([mp.mpf(1), mp.mpf(2), mp.mpf(3)], mp.mpf('0.25'), mp.mpf(2))
        self.assertEqual(p, mp.mpf('-1.125'))
        self.assertEqual(v, mp.mpf(5))
        self.assertLess(abs(model.offset_seconds(mp.mpf(180))), mp.mpf('.002'))

    def test_reference_semantics_and_bytes_remain_independent(self):
        roots, rows = model.references('uranus')
        self.assertEqual(len(roots), 3)
        self.assertEqual(len(rows), 65)
        raw = model.reference_path('uranus').read_text()
        with self.assertRaisesRegex(ValueError, 'semantics'):
            model.parse_reference('uranus', raw.replace('JDTT', 'JDTDB'))
        with self.assertRaisesRegex(ValueError, 'semantics'):
            model.parse_reference('uranus', raw.replace('Center body name: Sun (10)', 'Center body name: Earth (399)'))

    def test_bracket_refinement_preserves_sign_and_tolerance(self):
        import mpmath as mp
        lo, hi = model.bisect(lambda x: x*x-2, mp.mpf(1), mp.mpf(2))
        self.assertLessEqual(lo*lo, 2)
        self.assertGreaterEqual(hi*hi, 2)
        self.assertLessEqual((hi-lo)*86400, mp.mpf('.0001'))
        with self.assertRaisesRegex(ValueError, 'bracket'):
            model.bisect(lambda x: x*x+1, mp.mpf(1), mp.mpf(2))


if __name__ == '__main__':
    unittest.main()
