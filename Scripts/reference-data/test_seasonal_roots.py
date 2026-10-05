import copy
import importlib.util
import json
import math
import tempfile
import unittest
from pathlib import Path

SPEC=importlib.util.spec_from_file_location('seasonal',Path(__file__).with_name('qualify-seasonal-roots.py'))
S=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(S)


class SeasonalControls(unittest.TestCase):
    def test_frame_algebra_and_mean_frame_negative_control(self):
        for jd in [2415020.5,2451545.0,2499391.5]:
            matrix=S.date_frame(jd)
            dp,_=S.G.erfa.nut06a(2451545.0,jd-2451545.0)
            z=S.G.numpy.array([[math.cos(dp),-math.sin(dp),0],[math.sin(dp),math.cos(dp),0],[0,0,1]])
            expected=z@S.G.erfa.ecm06(2451545.0,jd-2451545.0)
            self.assertLess(float(S.G.numpy.max(S.G.numpy.abs(matrix-expected))),1e-14)
            self.assertLess(float(S.G.numpy.max(S.G.numpy.abs(matrix@matrix.T-S.G.numpy.eye(3)))),1e-14)
            self.assertGreater(float(S.G.numpy.max(S.G.numpy.abs(matrix-S.G.erfa.ecm06(2451545.0,jd-2451545.0)))),1e-7)

    def test_directed_root_and_nonmonotonic_control(self):
        rows=[{'julianDateTT':2451545+x/86400,'rangeRateAUPerDay':x} for x in [-600,-200,200,600]]
        root,kind=S.Q.interpolated_root(rows,3)
        self.assertEqual(root,2451545);self.assertEqual(kind,'pericenter')
        with self.assertRaises(ValueError):
            S.Q.interpolated_root([{'julianDateTT':i,'rangeRateAUPerDay':v} for i,v in enumerate([-1,2,-2,1])],3)

    def test_public_selection_and_echo_controls(self):
        request={'operation':'seasonal-roots','year':2000,'deltaTModel':'jpl-horizons'}
        result={'request':request,'status':'success','events':[{'kind':kind,'julianDateTT':2451600+i*90} for i,kind in enumerate(S.KINDS)]}
        S.validate_public(request,result)
        variants=[]
        for events in [result['events'][:-1],result['events']+result['events'][:1],list(reversed(result['events']))]:
            item=copy.deepcopy(result);item['events']=events;variants.append(item)
        item=copy.deepcopy(result);item['request']['year']=2001;variants.append(item)
        item=copy.deepcopy(result);item['events'][0]['julianDateTT']=2415020.5;variants.append(item)
        item=copy.deepcopy(result);item['events'][0]['julianDateTT']=float('nan');variants.append(item)
        for item in variants:
            with self.subTest(item=item),self.assertRaises(ValueError): S.validate_public(request,item)

    def test_strict_timing_and_shift_control(self):
        self.assertEqual(S.Q.event_classification(58,1),'within-target-numerical-envelope')
        self.assertEqual(S.Q.event_classification(60,1),'inconclusive-numerical-envelope')
        self.assertEqual(S.Q.event_classification(61,1),'exceeded')
        self.assertFalse(abs(60)<60)
        self.assertNotEqual(S.Q.event_classification(0,1),S.Q.event_classification(60,1))

    def test_pair_hash_and_recipe_binding(self):
        with tempfile.TemporaryDirectory() as folder:
            directory=Path(folder);recipe=S.Q.parameters('10','399','LT+S',[2451545])
            data=b'{"result":"control"}'
            S.archive_pair(directory,'control',recipe,data)
            self.assertEqual(S.bound_bytes(directory,'control',recipe),data)
            path=directory/'control.json.gz';path.write_bytes(S.gzip.compress(b'{}',mtime=0))
            with self.assertRaises(ValueError):S.bound_bytes(directory,'control',recipe)
            S.archive_pair(directory,'other',recipe,data)
            for key,value in [('TIME_TYPE',"'TDB'"),('REF_PLANE',"'ECLIPTIC'"),('VEC_CORR',"'NONE'")]:
                changed=dict(recipe);changed[key]=value
                with self.assertRaises(ValueError): S.bound_bytes(directory,'other',changed)


if __name__=='__main__': unittest.main()
