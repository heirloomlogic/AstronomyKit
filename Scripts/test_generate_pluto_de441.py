import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('pluto_generator', Path(__file__).with_name('generate-pluto-de441.py'))
g = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(g)


class PlutoDE441GeneratorTests(unittest.TestCase):
    def test_roundtrip_and_identity(self):
        data = bytes(range(256))
        text = g.render(data, 'pluto', -100.5, 32., 2)
        self.assertEqual(data, g.common.extract(text))
        candidate = {'encodedBytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        g.common.validate(data, candidate)
        with self.assertRaisesRegex(ValueError, 'digest'):
            g.common.validate(bytes(reversed(data)), candidate)
        with self.assertRaisesRegex(ValueError, 'length'):
            g.common.validate(data[:-1], candidate)

    def test_existing_and_new_generators_preserve_each_others_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = json.loads((g.ROOT/'Scripts/pluto-data/manifest.json').read_bytes())
            generated = g.ROOT/'Sources/AstronomyKit/Engine/Gravity/Generated'
            paths = ['Scripts/generate-pluto-tables.py', 'Scripts/generate-pluto-de441.py', 'Scripts/generate-moon-de441.py', 'Scripts/pluto-data/manifest.json', 'Scripts/pluto-data/de441-evidence.json']
            paths += list(manifest['files']) + [manifest['stateTable']['path']]
            paths += [str(p.relative_to(g.ROOT)) for p in generated.rglob('*.swift')]
            for relative in paths:
                target = root/relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(g.ROOT/relative, target)
            binaries = root/'binaries'
            binaries.mkdir()
            for target, name in g.BODIES.items():
                path = root/g.output(name).relative_to(g.ROOT)
                (binaries/f'cubic-float64-{target}.bin').write_bytes(g.common.extract(path.read_text()))
            expected = {p.relative_to(root): hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/generated.relative_to(g.ROOT)).rglob('*.swift')}
            for command in [('generate-pluto-tables.py', '--check'), ('generate-pluto-tables.py',), ('generate-pluto-de441.py', '--check'), ('generate-pluto-de441.py', '--binaries', str(binaries)), ('generate-pluto-tables.py', '--check'), ('generate-pluto-de441.py', '--check')]:
                if '--binaries' in command:
                    shutil.rmtree(root/g.output('pluto').parent.relative_to(g.ROOT))
                result = subprocess.run([sys.executable, str(root/'Scripts'/command[0]), *command[1:]], capture_output=True, text=True)
                self.assertEqual(0, result.returncode, result.stdout+result.stderr)
                actual = {p.relative_to(root): hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/generated.relative_to(g.ROOT)).rglob('*.swift')}
                self.assertEqual(expected, actual)

    def test_native_measurements_bind_the_current_runtime_and_fixture_sources(self):
        evidence = json.loads((g.ROOT/'Scripts/pluto-data/de441-native-evidence.json').read_bytes())
        for path, expected in evidence['sourceSHA256'].items():
            self.assertEqual(expected, hashlib.sha256((g.ROOT/path).read_bytes()).hexdigest(), path)
        self.assertEqual(6898944, evidence['nativeStorage']['decodedPayloadBytes'])
        self.assertEqual(143724, evidence['everyBoundaryRelease']['count'])
        self.assertEqual(4305, evidence['directSourceRelease']['bodySamples'])
        self.assertEqual(48, evidence['directSourceRelease']['integratedSamples'])
        self.assertEqual(44, len(evidence['archivedReferences']))

    def test_direct_fixture_provenance_and_selection(self):
        evidence = json.loads((g.ROOT/'Scripts/pluto-data/de441-native-fixtures.json').read_bytes())
        self.assertEqual(hashlib.sha256(g.MANIFEST.read_bytes()).hexdigest(), evidence['sourceEvidenceSHA256'])
        self.assertEqual({9, 10}, {row['target'] for row in evidence['bodyRows']})
        self.assertEqual({-1., -.5, 0., .5, 1.}, {row['x'] for row in evidence['bodyRows']})
        self.assertGreater(len(evidence['bodyRows']), 2500)
        self.assertEqual(72, len(evidence['heliocentricRows']))


if __name__ == '__main__':
    unittest.main()
