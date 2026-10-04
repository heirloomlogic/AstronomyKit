"""Independent date-plane and event identity controls."""
import importlib.util
import math
import unittest
from pathlib import Path
SPEC=importlib.util.spec_from_file_location('geometric',Path(__file__).with_name('qualify-geometric-events.py'))
G=importlib.util.module_from_spec(SPEC)
if Path(SPEC.origin).exists(): SPEC.loader.exec_module(G)

class GeometricTests(unittest.TestCase):
    def test_pinned_independent_date_plane(self):
        self.assertTrue(hasattr(G,'date_plane'), 'independent date-plane function missing')
        if G.erfa is None: self.skipTest('install isolated reference dependencies for independent date-plane tests')
        matrix=G.date_plane(2456165.5+.401182685)
        # Official ERFA test vector, with a single-double JD rounding allowance.
        self.assertAlmostEqual(matrix[2][1],-.3977506604161195467,places=13)
        self.assertAlmostEqual(matrix[2][2],.9174935488232863071,places=13)
        for a in range(3):
            for b in range(3): self.assertAlmostEqual(sum(matrix[a][k]*matrix[b][k] for k in range(3)),float(a==b),places=13)

    def test_node_and_longitude_kind_mapping(self):
        self.assertTrue(hasattr(G,'event_kind'), 'event kind mapping missing')
        self.assertEqual(G.event_kind('node','pericenter'),'ascending')
        self.assertEqual(G.event_kind('node','apocenter'),'descending')
        self.assertEqual(G.event_kind('alignment','pericenter'),'relative-0')
        self.assertEqual(G.event_kind('alignment','apocenter'),'relative-180')
        with self.assertRaises(ValueError): G.event_kind('station','pericenter')

    def test_reference_dependency_escape_rejected(self):
        self.assertTrue(hasattr(G,'validate_reference_paths'), 'reference dependency origin check missing')
        G.validate_reference_paths({'erfa':str(G.REFERENCE_ENV/'erfa/__init__.py')})
        with self.assertRaises(ValueError): G.validate_reference_paths({'erfa':'/tmp/system-erfa/__init__.py'})

    def test_unpaired_vector_epochs_rejected(self):
        self.assertTrue(hasattr(G,'scalar_rows'), 'reference scalar function missing')
        if G.erfa is None: self.skipTest('install isolated reference dependencies')
        row={'julianDateTT':2451545.0,'positionAU':[1,0,0]}
        with self.assertRaises(ValueError): G.scalar_rows([row],[{**row,'julianDateTT':2451546.0}],'alignment','Mars')

if __name__=='__main__': unittest.main()
