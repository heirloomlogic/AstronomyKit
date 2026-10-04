"""Reject attribution of a different binary to the parent model."""
import importlib.util
import tempfile
import unittest
from pathlib import Path
SPEC=importlib.util.spec_from_file_location('diagnosis',Path(__file__).with_name('diagnose-lunar-event-search.py'))
D=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(D)

class DiagnosisTests(unittest.TestCase):
    def test_detached_model_executable_rejected(self):
        self.assertTrue(hasattr(D,'validate_parent_inputs'),'same-model executable validation missing')
        with tempfile.TemporaryDirectory() as directory:
            binary=Path(directory)/'binary';binary.write_bytes(b'original model')
            parent={'inputSHA256':{},'executableProvenance':{'sha256':D.Q.digest(binary.read_bytes())}}
            D.validate_parent_inputs(parent,binary)
            binary.write_bytes(b'different model')
            with self.assertRaises(ValueError): D.validate_parent_inputs(parent,binary)

if __name__=='__main__': unittest.main()
