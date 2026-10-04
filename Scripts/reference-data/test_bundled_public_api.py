"""Controls for production qualification identity and strict timing gates."""
import importlib.util
import unittest
import json
import tempfile
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location('bundled', Path(__file__).with_name('qualify-bundled-ephemeris.py'))
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)


class BundledPublicAPIControls(unittest.TestCase):
    def test_missing_extra_and_reversed_events_fail_identity(self):
        reference = [{'julianDateTT': 0., 'kind': 'ascending'}, {'julianDateTT': 1., 'kind': 'descending'}]
        for actual in [reference[:1], reference + reference[:1], list(reversed(reference))]:
            events, failures = M.match_events('control', reference, actual, 1.)
            self.assertEqual([], events)
            self.assertEqual(1, len(failures))

    def test_exact_sixty_seconds_fails_and_smaller_passes(self):
        reference = [{'julianDateTT': 0., 'kind': 'ascending'}]
        for seconds, expected in [(60., False), (59.999, True), (-60., False)]:
            events, failures = M.match_events('control', reference, [{'julianDateTT': seconds / 86400., 'kind': 'ascending'}], 1.)
            self.assertFalse(failures)
            self.assertEqual(expected, events[0]['nominalWithinTarget'])

    def test_bound_build_rejects_source_and_executable_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            binary = directory / 'binary'
            binary.write_bytes(b'first')
            manifest = directory / 'build.json'
            record = {'sourceSHA256': {'coefficients.inc': 'locked'}, 'executableSHA256': M.B.digest(binary), 'buildManifestSHA256': 'unused'}
            manifest.write_text(json.dumps(record))
            with patch.object(M.B, 'MANIFEST', manifest), patch.object(M.B, 'sources', return_value={'coefficients.inc': 'changed'}):
                with self.assertRaisesRegex(ValueError, 'source inputs changed'):
                    M.B.validate(binary)
            binary.write_bytes(b'changed')
            with patch.object(M.B, 'MANIFEST', manifest), patch.object(M.B, 'sources', return_value={'coefficients.inc': 'locked'}):
                with self.assertRaisesRegex(ValueError, 'executable differs'):
                    M.B.validate(binary)


if __name__ == '__main__':
    unittest.main()
