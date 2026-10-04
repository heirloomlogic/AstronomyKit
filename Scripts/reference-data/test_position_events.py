"""Fault controls for independent position/event qualification."""
import importlib.util
import json
import math
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('position_events', Path(__file__).with_name('qualify-position-events.py'))
MODULE = importlib.util.module_from_spec(SPEC)
if SPEC.loader and Path(SPEC.origin).exists():
    SPEC.loader.exec_module(MODULE)

class ComparisonTests(unittest.TestCase):
    def test_small_angle_and_axis_fault(self):
        self.assertTrue(hasattr(MODULE, 'angle_arcminutes'), 'angular comparator missing')
        alpha = math.pi / 10800
        self.assertAlmostEqual(MODULE.angle_arcminutes([1, 0, 0], [math.cos(alpha), math.sin(alpha), 0]), 1, places=12)
        self.assertAlmostEqual(MODULE.angle_arcminutes([100, 0, 0], [1, 0, 0]), 0)
        self.assertGreater(MODULE.angle_arcminutes([1, 0, 0], [0, 1, 0]), 1)
        self.assertGreater(MODULE.angle_arcminutes([1, 0, 0], [-1, 0, 0]), 1)

    def test_invalid_vector_rejected(self):
        self.assertTrue(hasattr(MODULE, 'angle_arcminutes'), 'angular comparator missing')
        for vector in ([0, 0, 0], [math.nan, 0, 1], [math.inf, 0, 1], [1, 0]):
            with self.assertRaises(ValueError): MODULE.angle_arcminutes(vector, [1, 0, 0])

    def test_strict_event_boundary_and_uncertainty(self):
        self.assertTrue(hasattr(MODULE, 'event_classification'), 'event comparator missing')
        self.assertEqual(MODULE.event_classification(60, 0), 'exceeded')
        self.assertEqual(MODULE.event_classification(-61, 0.1), 'exceeded')
        self.assertEqual(MODULE.event_classification(59.5, 1), 'inconclusive-numerical-envelope')
        self.assertEqual(MODULE.event_classification(58, 1), 'within-target-numerical-envelope')
        self.assertEqual(MODULE.event_classification(60.5, 1), 'inconclusive-numerical-envelope')

    def test_independent_cubic_root_direction_and_ambiguity(self):
        self.assertTrue(hasattr(MODULE, 'interpolated_root'), 'root interpolation missing')
        rows = [{'julianDateTT': 2451545+x, 'rangeRateAUPerDay': (x-.125)*(1+.2*x*x)} for x in (-1, 0, 1, 2)]
        root,kind = MODULE.interpolated_root(rows, 3)
        self.assertAlmostEqual(root, 2451545.125, places=8)
        self.assertEqual(kind, 'pericenter')
        reversed_rows=[{**r,'rangeRateAUPerDay':-r['rangeRateAUPerDay']} for r in rows]
        self.assertEqual(MODULE.interpolated_root(reversed_rows, 3)[1], 'apocenter')
        with self.assertRaises(ValueError): MODULE.interpolated_root([{**r,'rangeRateAUPerDay':1} for r in rows],3)
        with self.assertRaises(ValueError): MODULE.interpolated_root([{'julianDateTT':i,'rangeRateAUPerDay':(-1)**i} for i in range(4)],3)

    def test_multiple_interpolant_roots_inside_one_sample_bracket_rejected(self):
        rows=[{'julianDateTT':x,'rangeRateAUPerDay':(x-.2)*(x-.5)*(x-.8)} for x in (-1,0,1,2)]
        with self.assertRaises(ValueError): MODULE.interpolated_root(rows,3)

    def test_wrong_body_center_site_rejected(self):
        directory=Path(__file__).parent/'sources/distance/characterization'
        recipe=json.loads((directory/'moon-geocentric.query.json').read_text())['parameters']
        envelope=json.loads((directory/'moon-geocentric.json').read_bytes())
        envelope['result']=envelope['result'].replace('Center-site name: BODY CENTER','Center-site name: Greenwich')
        with self.assertRaises(ValueError): MODULE.parse_response(json.dumps(envelope).encode(),recipe)

    def test_public_epoch_identity_and_event_window_faults_rejected(self):
        self.assertTrue(hasattr(MODULE, 'validate_public_results'), 'public response validator missing')
        request={'operation':'position','body':10,'mode':'geocentric-none','julianDateTT':2451545.0}
        correct={'status':'success','request':request,'julianDateTT':2451545.0,'positionAU':[1,0,0]}
        MODULE.validate_public_results([request],[correct])
        for wrong in ({**correct,'julianDateTT':2451546.0},{**correct,'request':{**request,'body':9}}):
            with self.assertRaises(ValueError): MODULE.validate_public_results([request],[wrong])
        window={'operation':'lunar-apsides','startJulianDateTT':2451545.0,'stopJulianDateTT':2451576.0}
        event={'julianDateTT':2451546.0,'kind':'pericenter','distanceAU':.002}
        correct_events={'status':'success','request':window,'events':[event]}
        MODULE.validate_public_results([window],[correct_events])
        for wrong in ([{**event,'julianDateTT':2451576.0}],[event,event],[event,{**event,'julianDateTT':2451547.0}]):
            with self.assertRaises(ValueError): MODULE.validate_public_results([window],[{**correct_events,'events':wrong}])

    def test_reference_metadata_faults(self):
        self.assertTrue(hasattr(MODULE, 'parse_response'), 'reference validator missing')
        directory=Path(__file__).parent/'sources/distance/characterization'
        recipe=json.loads((directory/'moon-geocentric.query.json').read_text())['parameters']
        data=(directory/'moon-geocentric.json').read_bytes()
        rows,_=MODULE.parse_response(data,recipe)
        self.assertEqual(len(rows),131)
        for key,value in [('TIME_TYPE', "'TDB'"), ('COMMAND', "'399'"), ('CENTER', "'500@10'"), ('VEC_CORR', "'LT'"), ('REF_SYSTEM', "'FK4'")]:
            with self.assertRaises(ValueError): MODULE.parse_response(data,{**recipe,key:value})
        with self.assertRaises(ValueError): MODULE.parse_response(data,{**recipe,'TLIST':"'2451545'"})

if __name__=='__main__': unittest.main()
