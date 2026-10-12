#!/usr/bin/env python3
"""Certify contraction and successful-return residuals for barycentric TDB solar light time."""
import argparse
import json
import re
from fractions import Fraction as Q
from pathlib import Path

import apparent_bounds
from intervals import Interval as I, DeltaT, year_start, equatorial_matrix
from numerics import ROOT, BINDINGS, source_hashes, check_hashes

C=Q(299792458)*86400/149597870700
JUMPS=[1900,1920,1941,1961,1986,2005,2050]


def constants():
    artifact=json.loads((ROOT/'Scripts/solar-numerics/derived-earth.json').read_text())
    check_hashes(ROOT,artifact['sourceSHA256'])
    terms={key:Q(value['rational']) for key,value in artifact['terms'].items()}
    matrix=equatorial_matrix()
    gram=[[sum(matrix[k][i]*matrix[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    frame_norm=Q('1.000001')
    if max(sum(abs(v) for v in row) for row in gram)>frame_norm**2:
        raise ValueError('Fixed EQJ matrix exceeds its norm enclosure')
    if min(gram[i][i]-sum(abs(gram[i][j]) for j in range(3) if j!=i) for i in range(3)) < 1/frame_norm**2:
        raise ValueError('Fixed EQJ matrix violates its lower singular-value enclosure')
    source=(ROOT/'Sources/AstronomyKit/Engine/Positions/EngineApparentPlace.swift').read_text()
    required=['for iteration in 1...20',
              'abs(nextDelay - delay) <= max(4 * nextDelay.ulp, emission.ulp) || tt - nextDelay == emission',
              'lightTime - (observedClock.offsetSeconds - emittedClock.offsetSeconds) / Engine.secondsPerDay',
              'lightTime <= 1, nextDelay >= 0']
    if any(line not in source for line in required):
        raise ValueError('TDB light-time equation, iteration count or stop expression changed')
    constants_source=(ROOT/'Sources/AstronomyKit/Engine/Foundation/EngineConstants.swift').read_text()
    literal=re.search(r'speedOfLightAUPerDay = ([0-9_.]+)',constants_source)[1].replace('_','')
    if float(literal)!=float(C):
        raise ValueError('Light-speed constant no longer rounds the SI/IAU value')
    sun=apparent_bounds.solar_bounds()
    delta=DeltaT()
    slope=max(delta.derivative_at_year(I(year,year+1),year).abs_upper()/(year_start(year+1)-year_start(year))
              for year in range(1898,2102))
    jumps=sum((delta.at_year(I(year),year)-delta.at_year(I(year),year-1)).abs_upper()/86400 for year in JUMPS)
    site=Q('6388.1366')/Q('149597870.700')
    radius=terms['radiusMaximumAU']*frame_norm
    # Every iterate is in [0,T]: |S(t-delay)-S(t)| <= V_s*T.
    t=Q('.006')
    q=sun['rateDeparture']
    v=sun['speedTT']
    k=v/C+q
    if (radius+site+v*t)/C+q*t>=t or k>=1:
        raise ValueError('Solar contraction does not preserve the delay interval')
    lower=(terms['radiusMinimumAU']/frame_norm-site-v*t)/C-q*t
    # The smallest binary64 spacing on the certified positive delay interval.
    if lower<=Q(1,256) or t>=Q(1,128):
        raise ValueError('Delay ULP bin changed')
    stop_floor=Q(4,2**60)
    residuals=[t*k**i for i in range(20)]
    exact_return=next(i+1 for i,r in enumerate(residuals) if r<stop_floor)
    # Four delay ULP, one emission-TT ULP, or equal rounded emission times. Subtraction and comparison rounding included.
    u=Q(1,2**53)
    successful_residual=16*u*(Q(37000)+t)/(1-4*u)
    result={'a':1+slope/86400,'D':jumps,'deltaTSlopeSecondsPerDay':slope,'deltaTJumpSumDays':jumps,
            'T':t,'k':k,'V':v,'clockRateDeparture':q,'minimumDelayDays':lower,
            'exactReturnEvaluations':Q(exact_return),'stopFloorDays':stop_floor,
            'successfulResidualDays':successful_residual,
            'successfulRootErrorDays':successful_residual/(1-k),
            **{'solar'+key[0].upper()+key[1:]:value for key,value in sun.items()}}
    global_clock=apparent_bounds.clock_bounds(Q(1461002))
    if Q(1)/(1-global_clock['rateDeparture'])>=2:
        raise ValueError('One elapsed-TDB-day delay exceeds the private TT padding')
    if sun['sourceStartTDB']>=-1461002-global_clock['offsetDays'] or sun['sourceStopTDB']<=1461000+global_clock['offsetDays']:
        raise ValueError('Source endpoints do not enclose the complete accepted interval and emission padding')
    return result


def certify():
    bounds=constants()
    paths=sorted(set(BINDINGS+apparent_bounds.PATHS+[
        'Scripts/solar-numerics/derived-earth.json','Scripts/solar-numerics/intervals.py',
        'Scripts/solar-numerics/certify_light_time.py',
        'Sources/AstronomyKit/Engine/Orientation/EngineRotations.swift','Sources/AstronomyKit/Time.swift']))
    residuals=[{'evaluation':i+1,'successiveDelayDifferenceUpperDays':str(bounds['T']*bounds['k']**i)} for i in range(20)]
    return {'kind':'exact-model-barycentric-TDB-solar-convergence','schemaVersion':2,
            'domain':'Reception TT within Earth polynomial coverage and |TT|<37000; surface height within 10 km; Earth/site held at reception; compiled Sun at emission',
            'dependency':'derived-earth.json must pass numerics.py --check; every compiled solar record intersecting the padded domain is enclosed',
            'sourceSHA256':source_hashes(ROOT,paths),'constants':{k:str(v) for k,v in bounds.items()},
            'records':residuals,
            'proof':['The compiled solar cubic is C1 at shared endpoints; no Delta T conversion occurs at emission.',
                     'F(delay)=|Sun(TT-delay)-observer(TT)|/c-offset(TT)+offset(TT-delay), where offset is in days.',
                     'F maps [0,T] into itself and is Lipschitz with k=solarSpeedTT/c+max|TDBprime-1|<1.',
                     'The exact-model successive differences are bounded by T*k^(n-1), below the native minimum four-delay-ULP threshold before the 20-evaluation cap.',
                     'Every successful native stop has the stated residual enclosure for the evaluated map; dividing by 1-k bounds its exact-model root displacement conditional on the separately excluded evaluation errors.',
                     'The native loop either returns or throws within 20 evaluations. Exact-model contraction is not a proof that every rounded native input returns.'],
            'excluded':['Native interpolation, vector/norm and trigonometric evaluation errors beyond the named stop arithmetic',
                        'Ephemeris interpolation/source accuracy, omitted relativistic terms, and physical accuracy',
                        'Unconditional successful return for every binary64 native input']}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'Scripts/solar-numerics/derived-light-convergence.json')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    actual=json.dumps(certify(),indent=2,sort_keys=True)+'\n'
    if args.check:
        if args.output.read_text()!=actual:
            raise SystemExit('Finite convergence certificate differs from reconstructed canonical coverage')
        print('Barycentric TDB solar convergence certificate verified')
    else:
        args.output.write_text(actual)
        print(args.output)


if __name__=='__main__':
    main()
