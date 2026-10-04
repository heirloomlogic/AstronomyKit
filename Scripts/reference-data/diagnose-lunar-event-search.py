#!/usr/bin/env python3
"""Separate same-model search precision from independent lunar timing accuracy."""
import argparse
import importlib.util
import json
import math
from pathlib import Path

SPEC=importlib.util.spec_from_file_location('qualification',Path(__file__).with_name('qualify-position-events.py'))
Q=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(Q)
ROOT=Q.ROOT
REPORT=ROOT/'Documentation/Migration/lunar-event-search-diagnosis.json'
PLAN=ROOT/'Documentation/Migration/lunar-event-search-diagnosis-plan.json'
WIDTHS=(.001,.0002,.00004)


def validate_parent_inputs(assessment,binary):
    if Q.digest(binary.read_bytes())!=assessment['executableProvenance']['sha256']: raise ValueError('different executable cannot be attributed to the parent model')
    for file,expected in assessment['inputSHA256'].items():
        if Q.digest((ROOT/file).read_bytes())!=expected: raise ValueError('assessment input drift before diagnosis')


def diagnose(binary):
    assessment=json.loads(Q.REPORT.read_bytes())
    validate_parent_inputs(assessment,binary)
    cases=[{'event':event,'stencilWidthTTDays':width,'loSeconds':-10.0,'hiSeconds':10.0} for event in assessment['lunarApsides'] for width in WIDTHS]
    def differences(offsets):
        requests=[]
        for case,offset in zip(cases,offsets):
            center=case['event']['actual']['julianDateTT']+offset/86400
            for sign in (-1,1): requests.append({'operation':'position','body':10,'mode':'geocentric-none','julianDateTT':center+sign*case['stencilWidthTTDays']/2})
        actuals=Q.public_batch(requests,binary)
        return [math.hypot(*b['positionAU'])-math.hypot(*a['positionAU']) for a,b in zip(actuals[::2],actuals[1::2])]
    left=differences([-10]*len(cases));right=differences([10]*len(cases))
    for case,a,b in zip(cases,left,right):
        if a*b>=0 or (a<b)!=(case['event']['actual']['kind']=='pericenter'): raise ValueError('same-model search diagnostic failed directed bracket')
        case['left']=a;case['initialBracketNormDifferencesAU']=[a,b]
    for _ in range(14):
        midpoints=[(case['loSeconds']+case['hiSeconds'])/2 for case in cases]
        values=differences(midpoints)
        for case,mid,value in zip(cases,midpoints,values):
            if (value<0)==(case['left']<0): case['loSeconds']=mid;case['left']=value
            else: case['hiSeconds']=mid
    results=[]
    for case in cases:
        event=case['event'];offset=(case['loSeconds']+case['hiSeconds'])/2
        results.append({'window':event['window'],'kind':event['actual']['kind'],'publicSearchJulianDateTT':event['actual']['julianDateTT'],
                        'referenceJulianDateTT':event['reference']['julianDateTT'],'stencilWidthTTDays':case['stencilWidthTTDays'],
                        'sameModelRootMinusPublicSearchSeconds':offset,'sameModelRootMinusReferenceSeconds':event['signedTimeErrorSeconds']+offset,
                        'finalBisectionWidthSeconds':case['hiSeconds']-case['loSeconds'],'initialBracketNormDifferencesAU':case['initialBracketNormDifferencesAU']})
    return {'classification':'same-model-public-api-diagnostic-not-independent-accuracy-qualification','assessmentSHA256':Q.digest(Q.REPORT.read_bytes()),
            'planSHA256':Q.digest(PLAN.read_bytes()),'scriptSHA256':Q.digest(Path(__file__).read_bytes()),'executableSHA256':Q.digest(binary.read_bytes()),'stencilWidthsTTDays':list(WIDTHS),'results':results,
            'maximumSameModelRootMinusSearchSeconds':max(abs(r['sameModelRootMinusPublicSearchSeconds']) for r in results),
            'referenceExceedancesByStencilWidth':{str(w):sum(abs(r['sameModelRootMinusReferenceSeconds'])>=60 for r in results if r['stencilWidthTTDays']==w) for w in WIDTHS},
            'limitations':['finite TT stencils and rounded public vector norms have cancellation/epoch rounding errors','same-model root agreement diagnoses the search but does not prove the lunar model or independent reference accuracy','all independent ephemeris uncertainty and finite sample limitations remain in the parent assessment']}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['report','check']);parser.add_argument('--binary',type=Path,default=Q.BINARY);args=parser.parse_args()
    report=diagnose(args.binary);data=Q.encoded(report)
    if args.action=='check':
        if REPORT.read_bytes()!=data: raise ValueError('lunar search diagnostic drift')
        print('Lunar same-model diagnosis replayed; max search offset seconds:',report['maximumSameModelRootMinusSearchSeconds'])
    else:
        if REPORT.exists(): raise ValueError('diagnosis already frozen')
        REPORT.write_bytes(data); print(json.dumps({k:report[k] for k in ['maximumSameModelRootMinusSearchSeconds','referenceExceedancesByStencilWidth']},sort_keys=True))

if __name__=='__main__': main()
