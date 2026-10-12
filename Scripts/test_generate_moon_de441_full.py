"""Lossless coefficient storage and complete source-layout controls."""
import base64
import importlib.util
import math
from pathlib import Path
import struct
import unittest

SPEC = importlib.util.spec_from_file_location('full', Path(__file__).with_name('generate-moon-de441-full.py'))
full = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(full)


class FullMoonTests(unittest.TestCase):
    def test_all_bits_including_signed_zero_and_subnormal(self):
        bits = [0, 1, 0x8000000000000000, 0x7FEFFFFFFFFFFFFF, 0x3FF0000000000001]
        raw = b''.join(struct.pack('<Q', bits[k % len(bits)]) for k in range(78))
        text = full.encode_records(raw)
        self.assertEqual(full.decode_records(text), raw)
        self.assertEqual(len(text), 2 * 417 - 1)

    def test_invalid_record_shape_and_base64_rejected(self):
        for raw in (b'', b'abc', bytes(311)):
            with self.assertRaises(ValueError):
                full.encode_records(raw)
        valid = full.encode_records(bytes(312))
        for text in (valid[:-1], valid+'\n', valid.replace('A', '!', 1), valid+'\n'+valid[:-1]):
            with self.assertRaises(ValueError):
                full.decode_records(text)

    def test_complete_subtraction_without_quantization(self):
        moon = (0.0, 172800.0, *[math.nextafter(2.0**k, math.inf) for k in range(39)])
        earth = (0.0, 172800.0, *[2.0**(k-4) for k in range(39)])
        raw = full.compose(moon, earth, 0.0)
        self.assertEqual(raw, struct.pack('<39d', *[moon[k]-earth[k] for k in range(2,41)]))
        self.assertEqual(len(raw), 312)

    def test_source_grid_nonfinite_and_overflow_rejected(self):
        good = (0.0, 172800.0, *([1.0]*39))
        for bad in ((1.0,*good[1:]), (0.0,1.0,*good[2:]), (0.0,172800.0,math.inf,*good[3:])):
            with self.assertRaises(ValueError): full.compose(bad,good,0.0)
        with self.assertRaises(ValueError):
            full.compose((0.0,172800.0,*([1e308]*39)),(0.0,172800.0,*([-1e308]*39)),0.0)

    def test_manifest_coverage_and_order_mutations_rejected(self):
        import copy,json
        original=json.loads(full.MANIFEST.read_text())
        full.validate_manifest(original)
        for change in ('coverage','order','missing'):
            value=copy.deepcopy(original)
            if change=='coverage': value['coverage']['startTDBDays']+=4
            elif change=='order':value['chunks'][0]['index']=1
            else:value['chunks'].pop()
            with self.assertRaises(ValueError):full.validate_manifest(value)

    def test_rounding_bound_encloses_exact_difference(self):
        from fractions import Fraction
        moon=(0.0,172800.0,*([1.1]*39)); earth=(0.0,172800.0,*([.3]*39))
        derived=struct.unpack('<39d',full.compose(moon,earth,0.0))
        bounds=full.subtraction_bounds(derived)
        error=abs(Fraction(derived[0])-(Fraction(1.1)-Fraction(.3)))
        self.assertGreaterEqual(bounds[0], float(error)*13*math.sqrt(3))
        self.assertGreaterEqual(bounds[1], float(error)*sum(k*k/2 for k in range(13))*math.sqrt(3))


if __name__ == '__main__': unittest.main()
