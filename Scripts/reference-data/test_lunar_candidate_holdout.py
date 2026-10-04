"""Fresh candidate plan/source/request and acceptance controls."""
import importlib.util
import json
import unittest
from pathlib import Path
SPEC=importlib.util.spec_from_file_location('holdout',Path(__file__).with_name('qualify-lunar-candidate-holdout.py'))
H=importlib.util.module_from_spec(SPEC)
if Path(SPEC.origin).exists(): SPEC.loader.exec_module(H)

class LunarHoldoutTests(unittest.TestCase):
    def test_frozen_disjoint_population_and_policy_binding(self):
        self.assertTrue(hasattr(H,'validate_plan'),'candidate holdout validator missing')
        plan=json.loads(H.PLAN.read_bytes());H.validate_plan(plan)
        bad=json.loads(json.dumps(plan));bad['positionJulianDatesTT'][0]=bad['excludedIndependentEpochsJulianDateTT'][0]
        with self.assertRaises(ValueError): H.validate_plan(bad)
        bad=json.loads(json.dumps(plan));bad['policySHA256']='0'*64
        with self.assertRaises(ValueError): H.validate_plan(bad)
        bad=json.loads(json.dumps(plan));bad['eventWindows'][0]['startJulianDateTT']=bad['excludedLunarWindows'][0]['startJulianDateTT']
        with self.assertRaises(ValueError): H.validate_plan(bad)

    def test_exclusion_catalog_cannot_be_detached_from_sources(self):
        plan=json.loads(H.PLAN.read_bytes());plan['excludedIndependentEpochsJulianDateTT'].pop()
        with self.assertRaises(ValueError): H.validate_plan(plan)
        plan=json.loads(H.PLAN.read_bytes());plan['excludedLunarWindows']=[]
        with self.assertRaises(ValueError): H.validate_plan(plan)

    def test_detached_native_response_and_wrong_event_kind_rejected(self):
        self.assertTrue(hasattr(H,'validate_native'),'candidate response validator missing')
        request={'operation':'events','family':'apsis','startJulianDateTT':2451545.,'stopJulianDateTT':2451576.}
        result={'status':'success','request':request,'events':[{'kind':'pericenter','julianDateTT':2451546.,'finalBracketWidthSeconds':.0003}]}
        H.validate_native([request],[result])
        bad=json.loads(json.dumps(result));bad['request']['family']='node'
        with self.assertRaises(ValueError): H.validate_native([request],[bad])
        bad=json.loads(json.dumps(result));bad['events'][0]['kind']='ascending'
        with self.assertRaises(ValueError): H.validate_native([request],[bad])
        bad=json.loads(json.dumps(result));bad['events'][0]['finalBracketWidthSeconds']=1.
        with self.assertRaises(ValueError): H.validate_native([request],[bad])

    def test_exact_timing_boundary_retained(self):
        self.assertTrue(hasattr(H,'event_result'),'candidate event comparator missing')
        result=H.event_result(60.,1.)
        self.assertFalse(result['nominalWithinTarget'])
        self.assertEqual(result['numericalEnvelopeClassification'],'inconclusive-numerical-envelope')
        self.assertEqual(H.Q.event_classification(60.,0.),'exceeded')

if __name__=='__main__': unittest.main()
