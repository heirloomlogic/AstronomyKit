import copy
import importlib.util
import json
import math
import tempfile
import unittest
from unittest import mock
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

    def test_replay_report_payload_controls(self):
        saved=json.loads(S.REPORT.read_bytes())
        rebuilt=copy.deepcopy(saved);rebuilt['publicRunner']['executableSHA256']='new';rebuilt['referenceEnvironment']['platform']='new'
        S.validate_replay(saved,rebuilt)
        for edit in ['summary','classification','input','time','event']:
            changed=copy.deepcopy(rebuilt)
            if edit=='summary':changed['summary']['nominal/jpl-horizons']['count']=2
            if edit=='classification':changed['classification']='qualified'
            if edit=='input':changed['inputSHA256']['raw']='unbound'
            if edit=='time':changed['events'][0]['actual']['julianDateTT']+=60/86400
            if edit=='event':changed['events'][0]['nominalWithinStrictTarget']=False
            with self.subTest(edit=edit),self.assertRaises(ValueError): S.validate_replay(saved,changed)

    def test_retained_response_convention_controls(self):
        name='nominal-coarse-000'
        saved=json.loads((S.RAW/(name+'.query.json')).read_bytes());recipe=saved['parameters'];data=S.bound_bytes(S.RAW,name,recipe)
        rows,_=S.Q.parse_response(data,recipe);self.assertEqual(len(rows),1000)
        for key,value in [('TIME_TYPE',"'TDB'"),('REF_PLANE',"'ECLIPTIC'"),('VEC_CORR',"'NONE'"),('COMMAND',"'399'")]:
            wrong=dict(recipe);wrong[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError): S.Q.parse_response(data,wrong)
        for replacement in [b'{}',b'not JSON',data.replace(b'$$SOE',b'absent')]:
            with self.assertRaises(ValueError): S.Q.parse_response(replacement,recipe)

    def test_saved_signed_residual_cannot_be_overwritten(self):
        saved=json.loads(S.REPORT.read_bytes());current=copy.deepcopy(saved)
        for value in [3600,123456789]:
            changed=copy.deepcopy(saved);changed['events'][0]['signedTimeErrorSeconds']=value
            with self.subTest(value=value),self.assertRaises(ValueError): S.validate_replay(changed,current)

    def test_nonfinite_payload_class_rejected_before_normalization(self):
        saved=json.loads(S.REPORT.read_bytes())
        for side in ['saved','current']:
            for value in [float('nan'),float('inf'),-float('inf')]:
                for location in ['actual','reference','residual','summary','control']:
                    old=copy.deepcopy(saved);new=copy.deepcopy(saved);changed=old if side=='saved' else new
                    event=changed['events'][0]
                    if location=='actual':event['actual']['julianDateTT']=value
                    if location=='reference':event['reference']['julianDateTT']=value
                    if location=='residual':event['signedTimeErrorSeconds']=value
                    if location=='summary':changed['summary']['nominal/jpl-horizons']['maximumAbsoluteTimeErrorSeconds']=value
                    if location=='control':event['reference']['halfGridDifferenceSeconds']=value
                    with self.subTest(side=side,value=value,location=location),self.assertRaises(ValueError): S.validate_replay(old,new)

    def test_archived_epochs_survive_one_ulp_seed_perturbation(self):
        original=S.coarse_candidates
        def perturbed(rows,mode):
            return [{**root,'julianDateTT':math.nextafter(root['julianDateTT'],math.inf)} for root in original(rows,mode)]
        for mode in ['nominal','matched']:
            with self.subTest(mode=mode),mock.patch.object(S,'coarse_candidates',side_effect=perturbed):
                roots,_=S.references(mode)
            self.assertEqual(len(roots),924)
            self.assertFalse(any(root['numericalFailures'] for root in roots))

    def test_authenticated_sample_selection_rejects_actual_drift(self):
        offsets=[-600,-300,-200,-100,100,200,300,600];seeds=[{'julianDateTT':2451545},{'julianDateTT':2451635}]
        dates=sorted(round(root['julianDateTT']+offset/86400,8) for root in seeds for offset in offsets)
        S.validate_sample_epochs(dates,seeds,offsets)
        for edit in ['missing','duplicate','reordered','shifted','seed']:
            changed=list(dates);new_seeds=copy.deepcopy(seeds)
            if edit=='missing':changed.pop()
            if edit=='duplicate':changed[1]=changed[0]
            if edit=='reordered':changed[0],changed[1]=changed[1],changed[0]
            if edit=='shifted':changed[2]=round(changed[2]+1/86400,8)
            if edit=='seed':new_seeds[0]['julianDateTT']+=1/86400
            with self.subTest(edit=edit),self.assertRaises(ValueError): S.validate_sample_epochs(changed,new_seeds,offsets)

    def test_valid_rebuilt_residual_is_checked_then_normalized(self):
        saved=json.loads(S.REPORT.read_bytes());current=copy.deepcopy(saved);event=current['events'][0]
        event['actual']['julianDateTT']=math.nextafter(event['actual']['julianDateTT'],math.inf)
        event['signedTimeErrorSeconds']=(event['actual']['julianDateTT']-event['reference']['julianDateTT'])*86400
        S.validate_replay(saved,current)
        # Even consistent epochs/residuals cannot change the strict classifications.
        current=copy.deepcopy(saved);current['events'][0]['nominalWithinStrictTarget']=False
        with self.assertRaises(ValueError):S.validate_replay(saved,current)

    def test_replay_provenance_binds_original_and_current_inputs(self):
        saved=json.loads(S.REPORT.read_bytes());current=copy.deepcopy(saved);current['inputSHA256']=S.source_hashes()
        # This control isolates validator replay binding; current repair sources are checked separately.
        current['inputSHA256']['Sources/CLibAstronomy/astronomy.c']=saved['inputSHA256']['Sources/CLibAstronomy/astronomy.c']
        receipt={'originalAssessmentSHA256':S.Q.digest(S.REPORT.read_bytes()),'replayInputSHA256':current['inputSHA256'],'originalValidatorSHA256':saved['inputSHA256']['Scripts/reference-data/qualify-seasonal-roots.py'],'changedValidatorPaths':['Scripts/reference-data/qualify-seasonal-roots.py'],'planSHA256':S.Q.digest(S.PLAN.read_bytes())}
        S.validate_source_provenance(saved,current,receipt)
        for edit in ['report','raw','plan','validator']:
            changed=copy.deepcopy(receipt)
            if edit=='report':changed['originalAssessmentSHA256']='unbound'
            if edit=='raw':changed['replayInputSHA256']['Scripts/reference-data/sources/seasonal-roots/nominal-coarse-000.json.gz']='unbound'
            if edit=='plan':changed['planSHA256']='unbound'
            if edit=='validator':changed['originalValidatorSHA256']='unbound'
            with self.subTest(edit=edit),self.assertRaises(ValueError):S.validate_source_provenance(saved,current,changed)


if __name__=='__main__': unittest.main()
