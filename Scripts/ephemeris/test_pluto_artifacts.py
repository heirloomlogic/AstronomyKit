"""Integrity negative controls plus compiler round-trip of every coefficient."""
import importlib.util
import json
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('pluto_integrity', HERE / 'verify-pluto.py')
V = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(V)


class PlutoArtifacts(unittest.TestCase):
    def test_checkout_integrity(self):
        self.assertEqual(V.check()['components'], 3)

    def test_negative_controls(self):
        manifest = json.loads((V.DATA / 'pluto-manifest.json').read_bytes())
        component = manifest['components'][0]
        details = {**component, **manifest['productionCFiles'][component['cFilename']], 'prefix': component['cPrefix']}
        data = (V.DATA / component['cFilename']).read_bytes()
        guards = [component['lowerJulianDateTDB'], component['upperJulianDateTDB']]
        for corrupt in (data[:-1], data.replace(b'static const', b'static      ', 1)):
            with self.assertRaises(ValueError):
                V.inspect_component(corrupt, details, guards)
        # Update superficial hash/length to reach structural validation.
        for corrupt in (data.replace(b'_RECORD_COUNT ', b'_MISSING_COUNT ', 1), data.replace(b'_STEP_DAYS 0x1.0000000000000p+5', b'_STEP_DAYS 0x0.0p+0', 1)):
            with self.assertRaises(ValueError):
                V.inspect_component(corrupt, {**details, 'sha256': V.sha(corrupt), 'bytes': len(corrupt)}, guards)
        with self.assertRaises(ValueError):
            V.inspect_component(data, details, [guards[0] - 100, guards[1]])

    @unittest.skipUnless(shutil.which('cc'), 'C compiler unavailable')
    def test_all_hex_constants_survive_c_compiler(self):
        manifest = json.loads((V.DATA / 'pluto-manifest.json').read_bytes())
        scratch = V.ROOT / '.context/pluto-integration'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            temp = Path(directory)
            source = ['#include <stdio.h>']
            source.extend('#include "' + str(V.DATA / c['cFilename']) + '"' for c in manifest['components'])
            source.append('int main(void) {')
            for c in manifest['components']:
                symbol = c['cPrefix'] + '_coefficients'
                source.append(f'if (fwrite({symbol}, sizeof({symbol}), 1, stdout) != 1) return 1;')
            source.append('return 0; }')
            (temp / 'constants.c').write_text('\n'.join(source) + '\n')
            subprocess.run(['cc', '-std=c99', '-O0', str(temp / 'constants.c'), '-o', str(temp / 'constants')], check=True, capture_output=True)
            actual = subprocess.check_output([str(temp / 'constants')])
            expected = bytearray()
            for c in manifest['components']:
                text = (V.DATA / c['cFilename']).read_text()
                body = text.split('_coefficients[] = {\n', 1)[1].split('\n};', 1)[0]
                expected.extend(b''.join(struct.pack('=d', float.fromhex(value.strip())) for value in body.replace('\n', '').split(',') if value.strip()))
            self.assertEqual(actual, expected)


if __name__ == '__main__':
    unittest.main()
