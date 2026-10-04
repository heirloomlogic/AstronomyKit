"""Historical replay controls preserve baseline identity while production evolves."""
import hashlib
import tempfile
import unittest
from pathlib import Path
import importlib.util
import subprocess
import sys

spec = importlib.util.spec_from_file_location('source_archive', Path(__file__).with_name('source_archive.py'))
source_archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source_archive)

ROOT = Path(__file__).resolve().parents[2]


class SourceArchiveTests(unittest.TestCase):
    def test_sibling_archive_imports_in_clean_root_processes(self):
        for script in ['distance-accuracy.py', 'investigate-range-rate.py', 'outer-planet-diagnostic.py', 'pluto-model-diagnostic.py', 'investigate-apparent-range.py', 'diagnose-polar-sunrise.py']:
            with self.subTest(script=script):
                command = "import importlib.util; from pathlib import Path; p=Path('Scripts/reference-data')/" + repr(script) + "; s=importlib.util.spec_from_file_location('isolated',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)"
                result = subprocess.run([sys.executable, '-B', '-I', '-c', command], cwd=ROOT, capture_output=True, text=True)
                self.assertEqual(0, result.returncode, result.stderr)

    def test_migration_archive_allows_comments_but_rejects_code_and_archive_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in source_archive.MIGRATION_RATE_SOURCES:
                historical = ROOT / 'Scripts/reference-data/sources/migration-rate-contract' / (name + '.archive')
                archived = root / historical.relative_to(ROOT)
                archived.parent.mkdir(parents=True, exist_ok=True)
                archived.write_bytes(historical.read_bytes())
                live = root / 'Sources/AstronomyKit' / name
                live.parent.mkdir(parents=True, exist_ok=True)
                live.write_bytes(historical.read_bytes() + b'/// Updated API documentation.\n')
            original = source_archive.migration_source_hashes(root, {})
            self.assertEqual(3, len(original))
            live.write_bytes(live.read_bytes() + b'let executableChange = 1\n')
            with self.assertRaisesRegex(ValueError, 'live migration Swift code differs'):
                source_archive.migration_source_hashes(root, {})
            live.write_bytes(historical.read_bytes())
            archived.write_bytes(archived.read_bytes() + b'/// Tampered archive.\n')
            with self.assertRaisesRegex(ValueError, 'historical migration Swift source hash mismatch'):
                source_archive.migration_source_hashes(root, {})

    def test_baseline_paths_are_canonical_for_original_script_relative_labels(self):
        with source_archive.baseline_tree(ROOT) as baseline:
            self.assertEqual(baseline, baseline.resolve())
            source = baseline / 'Sources/CLibAstronomy/astronomy.c'
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), '40c9c17447a2725fd6002f7e450612e9ca149becf9617e71fa57fefca0f491ed')
            self.assertEqual(len(list((baseline / 'Sources/CLibAstronomy').rglob('*.c'))), 1)
            for name, expected in source_archive.MIGRATION_RATE_SOURCES.items():
                self.assertEqual(expected, hashlib.sha256((baseline / 'Sources/AstronomyKit' / name).read_bytes()).hexdigest())

    def test_changed_manifest_cannot_relabel_an_archive_as_original(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / source_archive.ARCHIVE; archive.mkdir(parents=True)
            (archive / 'manifest.json').write_text('{"filesSHA256":{}}')
            with self.assertRaisesRegex(ValueError, 'archive manifest hash mismatch'):
                source_archive.manifest(root)


if __name__ == '__main__':
    unittest.main()
