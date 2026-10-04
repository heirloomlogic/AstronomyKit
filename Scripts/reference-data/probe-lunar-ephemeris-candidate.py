#!/usr/bin/env python3
"""Retrospective DE440 lunar feasibility, without selecting a production model."""
import argparse
import importlib.util
import json
import math
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
REFERENCE_ENV=ROOT/'.context/accuracy-qualification/python-reference'
sys.path.insert(0,str(REFERENCE_ENV))
import erfa
import jplephem
from jplephem.spk import SPK
SPEC=importlib.util.spec_from_file_location('geometric',Path(__file__).with_name('qualify-geometric-events.py'))
G=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(G)
Q=G.Q
KERNEL=ROOT/'.context/accuracy-qualification/de440s.bsp'
EXCERPT=ROOT/'.context/accuracy-qualification/moon-earth-1900-2130.bsp'
PLAN=ROOT/'Documentation/Migration/lunar-candidate-probe-plan.json'
REPORT=ROOT/'Documentation/Migration/lunar-ephemeris-candidate-probe.json'
AU_KM=149597870.7


def probe():
    G.load_plan();G.validate_reference_paths({'jplephem':jplephem.__file__})
    if jplephem.__version__!='2.24': raise ValueError('unexpected candidate evaluator version')
    kernel=SPK.open(str(KERNEL))
    moon=kernel[3,301];earth=kernel[3,399]
    if moon.frame!=1 or earth.frame!=1 or moon.data_type!=2 or earth.data_type!=2: raise ValueError('candidate segment frame/type differs from plan')
    # Geocentric ERFA periodic TDB-TT approximation, split Julian dates.
    def state(jdtt):
        offset=jdtt-2451545.0
        correction=erfa.dtdb(2451545.0,offset,0,0,0,0)
        a,b=erfa.tttdb(2451545.0,offset,correction)
        mp,mv=moon.compute_and_differentiate(a,b);ep,ev=earth.compute_and_differentiate(a,b)
        return mp-ep,mv-ev
    assessment=json.loads(Q.REPORT.read_bytes());geometry=json.loads(G.REPORT.read_bytes())
    positions=[]
    for row in assessment['positions']:
        if row['body']!='Moon' or row['mode']!='geocentric-none': continue
        ref=row['reference'];p,_=state(ref['julianDateTT']);vector=[float(x)/AU_KM for x in p]
        positions.append({'phase':row['phase'],'julianDateTT':ref['julianDateTT'],'angleErrorArcminutes':Q.angle_arcminutes(vector,ref['positionAU']),
                          'signedRangeErrorPPM':(math.hypot(*vector)-ref['rangeAU'])/ref['rangeAU']*1e6})
    events=[]
    cases=[('apsis',e) for e in assessment['lunarApsides']]+[('node',e) for e in geometry['events'] if e['family']=='node']
    for family,event in cases:
        reference=event['reference'];center=reference['julianDateTT'];kind=reference['kind']
        def scalar(offset):
            jd=center+offset/86400;p,v=state(jd)
            return float(sum(p*v)) if family=='apsis' else float((G.date_plane(jd)@p)[2])
        lo,hi=-10.0,10.0;left=scalar(lo);right=scalar(hi)
        direction=1 if kind in ('pericenter','ascending') else -1
        if left*right>=0 or (right-left)*direction<=0: raise ValueError('candidate event lacks planned directed bracket')
        for _ in range(18):
            mid=(lo+hi)/2;value=scalar(mid)
            if (value<0)==(left<0): lo=mid;left=value
            else: hi=mid
        events.append({'family':family,'kind':kind,'referenceJulianDateTT':center,'candidateMinusReferenceSeconds':(lo+hi)/2,'finalBracketWidthSeconds':hi-lo})
    segments=[]
    for segment in [moon,earth]:
        segments.append({'center':segment.center,'target':segment.target,'frame':segment.frame,'type':segment.data_type,'startJulianDateTDB':segment.start_jd,'stopJulianDateTDB':segment.end_jd,'dataBytes':(segment.end_i-segment.start_i+1)*8})
    kernel.close()
    return {'classification':'retrospective-candidate-feasibility-not-new-holdout-or-production-qualification','planSHA256':Q.digest(PLAN.read_bytes()),'scriptSHA256':Q.digest(Path(__file__).read_bytes()),
            'helperSourceSHA256':{str(Path(module.__file__).relative_to(ROOT)):Q.digest(Path(module.__file__).read_bytes()) for module in (G,Q)},'currentAssessmentSHA256':Q.digest(Q.REPORT.read_bytes()),'geometricAssessmentSHA256':Q.digest(G.REPORT.read_bytes()),'kernel':{'url':'https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp','sha256':Q.digest(KERNEL.read_bytes()),'bytes':KERNEL.stat().st_size,'segments':segments},
            'developmentExcerpt':{'sha256':Q.digest(EXCERPT.read_bytes()),'bytes':EXCERPT.stat().st_size,'targets':[301,399],'guardsTDB':['1899/12/31','2131/1/2'],'shippingDisposition':'not selected or shipped'},
            'referenceEnvironment':G.environment(),'jplephem':{'version':jplephem.__version__,'sourceSHA256':{p.name:Q.digest(p.read_bytes()) for p in sorted(Path(jplephem.__file__).parent.glob('*.py'))}},
            'positions':positions,'events':events,'summary':{'positionCount':len(positions),'maximumAngleErrorArcminutes':max(r['angleErrorArcminutes'] for r in positions),'maximumAbsoluteRangeErrorPPM':max(abs(r['signedRangeErrorPPM']) for r in positions),
                'eventCount':len(events),'maximumAbsoluteEventDifferenceSeconds':max(abs(e['candidateMinusReferenceSeconds']) for e in events),'nominalEventExceedances':sum(abs(e['candidateMinusReferenceSeconds'])>=60 for e in events)},
            'limitations':['retrospective DE440-vs-Horizons reference comparison uses previously observed cases, not a new candidate holdout','JPL solution families share observations; agreement is not independent observational proof or physical covariance','TT-to-TDB uses a geocentric periodic approximation, not future civil time','shipping Swift implementation, representation, frame/model integration, RSS/startup/runtime, API coverage and licensing/attribution validation remain unperformed','excerpt file bytes are development data size, not app download/install size or resident memory','this prototype does not repair Pluto or preserve its body-center semantics']}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['report','check']);args=parser.parse_args()
    report=probe();data=Q.encoded(report)
    if args.action=='check':
        if REPORT.read_bytes()!=data: raise ValueError('candidate feasibility drift')
        print('Candidate replay matched: '+json.dumps(report['summary'],sort_keys=True))
    else:
        if REPORT.exists(): raise ValueError('candidate report already frozen')
        REPORT.write_bytes(data);print(json.dumps(report['summary'],sort_keys=True));print('Development excerpt bytes:',report['developmentExcerpt']['bytes'])

if __name__=='__main__': main()
