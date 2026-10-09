import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


a = module('saturn_assessment', 'assess-saturn-apsides.py')
g = module('saturn_generator', 'generate-saturn-tables.py')


class SaturnEphemerisTests(unittest.TestCase):
    def test_quantization_encloses_position_and_analytic_rate(self):
        records = [(100., 1.5, [(300.123456789, -.112345678, .0987654321, -.0032109876)] * 3)]
        data, rounded, bounds = a.quantize(records, 'float32')
        self.assertEqual(48, len(data))
        for i in range(101):
            exact = a.p.evaluate(records[0][2], i / 50 - 1, 1.5)
            compact = a.p.evaluate(rounded[0][2], i / 50 - 1, 1.5)
            for axis, key in enumerate(('positionBoundKm', 'rateBoundKmPerTDBDay')):
                self.assertLessEqual(a.d.norm([x-y for x, y in zip(exact[axis], compact[axis])]), bounds[key])
        full, _, exact_bounds = a.quantize(records, 'float64')
        self.assertEqual(96, len(full))
        self.assertLess(exact_bounds['positionBoundKm'], 1e-150)
        self.assertLess(exact_bounds['rateBoundKmPerTDBDay'], 1e-150)

    def test_cached_satellite_rejects_corruption_identity_length_and_pinned_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / '0-3.bin'
            data = b'abcd'
            path.write_bytes(data)
            receipt = path.with_suffix('.json')
            digest = hashlib.sha256(data).hexdigest()
            receipt.write_text(json.dumps(dict(sha256=digest, identity=a.SAT_ID)))
            self.assertEqual(data, a.SatelliteReader(directory, {'0-3': digest}).read(0, 4))
            with self.assertRaisesRegex(ValueError, 'digest'):
                a.SatelliteReader(directory, {'0-3': '0'*64}).read(0, 4)
            path.write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'identity or digest'):
                a.SatelliteReader(directory).read(0, 4)
            receipt.write_text(json.dumps(dict(sha256=hashlib.sha256(b'bad').hexdigest(), identity=a.SAT_ID)))
            with self.assertRaisesRegex(ValueError, 'length'):
                a.SatelliteReader(directory).read(0, 4)
            receipt.write_text(json.dumps(dict(sha256=hashlib.sha256(b'bad').hexdigest(), identity=[])))
            with self.assertRaisesRegex(ValueError, 'identity'):
                a.SatelliteReader(directory).read(0, 4)

    def test_native_measurement_bindings_and_negative_controls(self):
        recorder = module('planetary_recorder', 'record-planetary-event-evidence.py')
        evidence = json.loads(recorder.OUTPUT.read_bytes())
        self.assertEqual(recorder.source_hashes(), evidence['sourceSHA256'])
        for configuration in ['debug', 'release']:
            recorder.validate(evidence[configuration])
        changed = copy.deepcopy(evidence['debug'])
        changed['saturn'][0]['signedTimingErrorSeconds'] = 60
        with self.assertRaisesRegex(ValueError, 'sixty-second'):
            recorder.validate(changed)
        changed = copy.deepcopy(evidence['debug'])
        changed['source'][0]['sourceLowerJDTT'] += 1
        with self.assertRaisesRegex(ValueError, 'bracket'):
            recorder.validate(changed)

    def test_packed_payload_identity_and_generator_coexistence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = json.loads((g.ROOT/'Scripts/planet-data/manifest.json').read_bytes())
            generated = Path('Sources/AstronomyKit/Engine/Planets/Generated')
            paths = ['Scripts/generate-planet-tables.py', 'Scripts/generate-saturn-tables.py', 'Scripts/generate-moon-de441.py', 'Scripts/planet-data/manifest.json', 'Scripts/saturn-data/assessment.json']
            paths += list(manifest['files'])
            paths += [str(p.relative_to(g.ROOT)) for p in (g.ROOT/generated).rglob('*.swift')]
            for relative in paths:
                target = root/relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(g.ROOT/relative, target)
            binaries = root/'binaries'
            binaries.mkdir()
            candidate = json.loads(g.MANIFEST.read_bytes())['candidates']['float32']
            for target, name in g.BODIES.items():
                body = candidate['bodies'][str(target)]
                data = g.common.extract((g.OUTPUT/f'Saturn{name.title()}Data.swift').read_text())
                g.common.validate(data, body)
                with self.assertRaisesRegex(ValueError, 'digest'):
                    g.common.validate(bytes([data[0] ^ 1]) + data[1:], body)
                (binaries/f'float32-{target}.bin').write_bytes(data)
            expected = {p.relative_to(root): hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/generated).rglob('*.swift')}
            for command in [('generate-planet-tables.py', '--check'), ('generate-planet-tables.py',), ('generate-saturn-tables.py', '--check'), ('generate-saturn-tables.py', '--binaries', str(binaries)), ('generate-planet-tables.py', '--check'), ('generate-saturn-tables.py', '--check')]:
                if '--binaries' in command:
                    shutil.rmtree(root/generated/'Saturn')
                result = subprocess.run([sys.executable, str(root/'Scripts'/command[0]), *command[1:]], capture_output=True, text=True)
                self.assertEqual(0, result.returncode, result.stdout+result.stderr)
                actual = {p.relative_to(root): hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/generated).rglob('*.swift')}
                self.assertEqual(expected, actual)


if __name__ == '__main__':
    unittest.main()
