"""Historical replay controls preserve baseline identity while production evolves."""
import hashlib
import tempfile
import unittest
from pathlib import Path
import source_archive

ROOT = Path(__file__).resolve().parents[2]


class SourceArchiveTests(unittest.TestCase):
    def test_baseline_paths_are_canonical_for_original_script_relative_labels(self):
        with source_archive.baseline_tree(ROOT) as baseline:
            self.assertEqual(baseline, baseline.resolve())
            source = baseline / 'Sources/CLibAstronomy/astronomy.c'
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), '40c9c17447a2725fd6002f7e450612e9ca149becf9617e71fa57fefca0f491ed')
            self.assertEqual(len(list((baseline / 'Sources/CLibAstronomy').rglob('*.c'))), 1)

    def test_changed_manifest_cannot_relabel_an_archive_as_original(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / source_archive.ARCHIVE; archive.mkdir(parents=True)
            (archive / 'manifest.json').write_text('{"filesSHA256":{}}')
            with self.assertRaisesRegex(ValueError, 'archive manifest hash mismatch'):
                source_archive.manifest(root)


if __name__ == '__main__':
    unittest.main()
