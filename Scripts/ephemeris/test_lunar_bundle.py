"""Source-identity and native time/frame controls for the shipping lunar bundle."""
import ctypes
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).with_name('generate-lunar-bundle.py')
sys.path.insert(0, str(ROOT / '.context/accuracy-qualification/python-reference'))


class LunarBundleTests(unittest.TestCase):
    def test_official_kernel_regenerates_qualified_payload_and_manifest(self):
        self.assertTrue(SCRIPT.is_file(), 'shipping source-bound lunar generator is missing')
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            subprocess.run([sys.executable, str(SCRIPT), 'generate', '--proof-payload', '--output', str(output)], check=True, capture_output=True)
            payload = output / 'moon-de440.bin'
            self.assertEqual(hashlib.sha256(payload.read_bytes()).hexdigest(), 'a1921ec68223515ce97bea46d6db171329ddba8219c349f4c4b0d2ecce81f89c')
            self.assertEqual(payload.stat().st_size, 6581696)
            manifest = json.loads((output / 'moon-de440.manifest.json').read_bytes())
            self.assertEqual(manifest['state']['target'], 301)
            self.assertEqual(manifest['state']['center'], 399)
            self.assertTrue((output / 'moon_data.inc').is_file(), 'compiled lunar data is missing')
            subprocess.run([sys.executable, str(SCRIPT), 'check', '--output', str(output)], check=True, capture_output=True)
            compiled = output / 'moon_data.inc'
            compiled.write_bytes(compiled.read_bytes() + b'/* changed */')
            result = subprocess.run([sys.executable, str(SCRIPT), 'check', '--output', str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('bundle drift', result.stderr)

    def test_checkout_only_check_needs_no_original_kernel(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / 'absent.bsp'
            result = subprocess.run([sys.executable, str(SCRIPT), '--check', '--kernel', str(missing)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('checkout integrity', result.stdout)

    def test_compiled_float64_coefficients_match_official_source_including_guards(self):
        import numpy
        from jplephem.spk import SPK
        with tempfile.TemporaryDirectory() as directory:
            probe = Path(directory) / 'coefficients.c'
            probe.write_text('#include "moon_data.inc"\nconst double *coefficients(void) { return moon_bundle_coefficients; }\n')
            library = Path(directory) / 'coefficients.dylib'
            subprocess.run(['clang', '-shared', '-O1', '-I', str(ROOT / 'Sources/CLibAstronomy/EphemerisData'), str(probe), '-o', str(library)], check=True, capture_output=True)
            code = ctypes.CDLL(str(library)); code.coefficients.restype = ctypes.POINTER(ctypes.c_double)
            actual = numpy.ctypeslib.as_array(code.coefficients(), shape=(21111 * 3 * 13,))
            kernel = SPK.open(str(ROOT / '.context/accuracy-qualification/de440s.bsp'))
            try:
                _, _, moon = kernel[3, 301].load_array()
                _, _, earth = kernel[3, 399].load_array()
                expected = ((moon[:, 4558:25669, :] - earth[:, 4558:25669, :]).transpose(1, 0, 2) / 149597870.7).ravel()
                numpy.testing.assert_array_equal(actual, expected)
            finally:
                kernel.close()

    def test_changed_official_kernel_rejected_before_writing(self):
        self.assertTrue(SCRIPT.is_file(), 'shipping source-bound lunar generator is missing')
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source.bsp'; source.write_bytes(b'edited kernel')
            output = Path(directory) / 'output'
            result = subprocess.run([sys.executable, str(SCRIPT), 'generate', '--kernel', str(source), '--output', str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('official DE440s source identity', result.stderr)
            self.assertFalse(output.exists())

    def test_native_time_and_bias_match_pinned_reference(self):
        native = ROOT / 'Sources/CLibAstronomy/EphemerisTime'
        self.assertTrue((native / 'ephemeris_time.c').is_file(), 'shipping native time/frame adapter is missing')
        import erfa
        import numpy
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / 'time.dylib'
            subprocess.run(['clang', '-shared', '-O2', '-fno-fast-math', '-ffp-contract=off', '-I', str(ROOT / 'Sources/CLibAstronomy/include'), *map(str, sorted(native.glob('*.c'))), '-o', str(library)], check=True, capture_output=True)
            code = ctypes.CDLL(str(library))
            code.Astronomy_EphemerisTDBOffsetSeconds.argtypes = [ctypes.c_double]
            code.Astronomy_EphemerisTDBOffsetSeconds.restype = ctypes.c_double
            for offset in [-36524.5, -20000.125, 0., 10000.4567, 47846.5, 1e-9]:
                self.assertAlmostEqual(code.Astronomy_EphemerisTDBOffsetSeconds(offset), float(erfa.dtdb(2451545., offset, 0, 0, 0, 0)), delta=1e-16)
            self.assertTrue(hasattr(code, 'Astronomy_EphemerisTDBRate'), 'native TDB derivative is missing')
            code.Astronomy_EphemerisTDBRate.argtypes = [ctypes.c_double]
            code.Astronomy_EphemerisTDBRate.restype = ctypes.c_double
            self.assertAlmostEqual(code.Astronomy_EphemerisTDBRate(0.), 1.0000000003348732, delta=2e-15)
            self.assertAlmostEqual(code.Astronomy_EphemerisTDBRate(-20000.125), 1.0000000000137008, delta=2e-15)
            vector_type = ctypes.c_double * 3
            code.Astronomy_EphemerisICRSToEQJ.argtypes = [vector_type, vector_type]
            matrix = erfa.pmat06(2451545., 0.)
            for vector in [(1., 0., 0.), (0., 1., 0.), (0., 0., 1.), (1e5, -2e5, 3e5)]:
                expected = matrix @ numpy.array(vector)
                source = vector_type(*vector); target = vector_type()
                code.Astronomy_EphemerisICRSToEQJ(source, target)
                numpy.testing.assert_allclose(list(target), expected, rtol=0, atol=1e-10)
                code.Astronomy_EphemerisICRSToEQJ(source, source)
                numpy.testing.assert_allclose(list(source), expected, rtol=0, atol=1e-10)


if __name__ == '__main__':
    unittest.main()
