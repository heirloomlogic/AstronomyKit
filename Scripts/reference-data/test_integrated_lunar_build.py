"""Pinned official-source cache controls for the native development builder."""
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
SPEC=importlib.util.spec_from_file_location('builder',Path(__file__).with_name('build-integrated-lunar-probe.py'))
B=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(B)

class NativeBuildTests(unittest.TestCase):
    def test_edited_cached_official_source_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            file=Path(directory)/'erfa/src/dtdb.c';file.parent.mkdir(parents=True);file.write_text('/* edited source */')
            with patch.object(B,'BUILD',Path(directory)),patch.object(B.urllib.request,'urlopen') as network:
                with self.assertRaises(ValueError): B.fetch('src/dtdb.c')
                network.assert_not_called()

    def test_uncatalogued_source_rejected(self):
        with patch.object(B.urllib.request,'urlopen') as network:
            with self.assertRaises(ValueError): B.fetch('src/unapproved.c')
            network.assert_not_called()

if __name__=='__main__': unittest.main()
