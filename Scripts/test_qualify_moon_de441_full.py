"""Mutation controls for the original-component precision replay."""
import base64
import copy
import importlib.util
import json
from pathlib import Path
import unittest

SPEC=importlib.util.spec_from_file_location('qualification_full',Path(__file__).with_name('qualify-moon-de441-full.py'))
q=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(q)


class ComponentTests(unittest.TestCase):
    def setUp(self):
        self.evidence=json.loads(q.OUTPUT.read_text())

    def test_saved_measurements_replay(self):
        self.assertEqual(q.calculate(self.evidence['rows']),self.evidence['measurements'])

    def test_original_component_mutation_rejected(self):
        rows=copy.deepcopy(self.evidence['rows']);raw=bytearray(base64.b64decode(rows[0]['moonRecordBase64']));raw[23]^=1
        rows[0]['moonRecordBase64']=base64.b64encode(raw).decode()
        with self.assertRaises(ValueError):q.calculate(rows)

    def test_midpoint_and_derived_digest_mutations_rejected(self):
        for field,value in [('midpointSecondsTDB',0),('derivedSHA256','0'*64)]:
            rows=copy.deepcopy(self.evidence['rows']);rows[0][field]=value
            with self.assertRaises(ValueError):q.calculate(rows)


if __name__=='__main__':unittest.main()
