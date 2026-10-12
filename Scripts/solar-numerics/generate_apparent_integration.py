#!/usr/bin/env python3
"""Independent 80-digit site kinematics and fixed-input lunar-overlap arithmetic."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import mpmath as mp
import solar_reference as solar
import precession_bounds
import apparent_bounds
from numerics import ROOT, BINDINGS, source_hashes

OUTPUT=ROOT/'Scripts/apparent-place-data/integration-reference.json'
CASES=[[-36000.25,-36000.251,[-90.,0.,-10000.]], [0.125,0.124,[35.6,-82.55,0.]],
       [9500.75,9500.749,[90.,55.,10000.]], [36000.5,36000.499,[0.,180.,420.]]]


def site(ut,tt,location):
    rotation,sidereal=solar.orientation(ut,tt)
    latitude,longitude,height=map(solar.ref.exact,location)
    phi=latitude*mp.pi/180
    theta=(sidereal+longitude)*mp.pi/180
    polar=1-1/mp.mpf('298.25642')
    coefficient=1/mp.sqrt(mp.cos(phi)**2+polar**2*mp.sin(phi)**2)
    a=mp.mpf('6378.1366');au=mp.mpf('149597870.700')
    return rotation.T*mp.matrix([(a*coefficient+height/1000)*mp.cos(phi)*mp.cos(theta)/au,
                                (a*coefficient+height/1000)*mp.cos(phi)*mp.sin(theta)/au,
                                (a*polar**2*coefficient+height/1000)*mp.sin(phi)/au])


def source_row(body):
    path=ROOT/f'Scripts/apparent-place-data/horizons/{body}-geocentric.json'
    document=json.loads(path.read_bytes())
    text=document['result']
    rows=list(csv.reader(text.split('$$SOE\n')[1].split('$$EOE')[0].splitlines()))
    row=rows[-1]
    return {'jdTT':row[0].strip(),'raDegrees':row[10].strip(),'declinationDegrees':row[11].strip(),
            'distanceAU':row[7].strip(),'path':str(path.relative_to(ROOT)),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


def direction(row):
    a,d=[mp.mpf(row[key])*mp.pi/180 for key in ['raDegrees','declinationDegrees']]
    return mp.matrix([mp.cos(d)*mp.cos(a),mp.cos(d)*mp.sin(a),mp.sin(d)])


def overlap(sun,moon):
    s,m=direction(sun),direction(moon)
    dot=-mp.fsum(x*y for x,y in zip(s,m))
    cross=mp.matrix([s[1]*m[2]-s[2]*m[1],s[2]*m[0]-s[0]*m[2],s[0]*m[1]-s[1]*m[0]])
    angle=mp.atan2(mp.sqrt(mp.fsum(x*x for x in cross)),dot)
    au=mp.mpf('149597870.700');dm=mp.mpf(moon['distanceAU'])*au;ds=mp.mpf(sun['distanceAU'])*au
    re=mp.mpf('6378.1366');rs=mp.mpf('695700');rm=mp.mpf('1737.4')
    r=dm*mp.tan(mp.asin(rm/dm))
    R=dm*mp.tan(mp.mpf('1.01')*mp.asin(re/dm)-mp.asin(rs/ds)+mp.asin(re/ds))
    d=dm*mp.tan(angle)
    area=r*r*mp.acos((d*d+r*r-R*R)/(2*d*r))+R*R*mp.acos((d*d+R*R-r*r)/(2*d*R))-mp.sqrt((-d+r+R)*(d+r-R)*(d-r+R)*(d+r+R))/2
    return {'separationArcseconds':str(angle*180/mp.pi*3600),'axisDistanceKilometers':str(d),
            'umbraRadiusKilometers':str(R),'moonRadiusKilometers':str(r),'obscuration':str(area/(mp.pi*r*r))}


def artifact():
    with mp.workdps(80):
        cases=[]
        for tt,ut,observer in CASES:
            t,u=solar.ref.exact(tt),solar.ref.exact(ut)
            trajectory=lambda delta:site(u+delta,t+delta,observer)
            cases.append({'tt':tt,'ut':ut,'observer':observer,
                          'position':[str(x) for x in trajectory(mp.mpf(0))],
                          'velocity':[str(x) for x in mp.diff(trajectory,mp.mpf(0))],
                          'acceleration':[str(x) for x in mp.diff(trajectory,mp.mpf(0),2)]})
        sun,moon=source_row('sun'),source_row('moon')
        altitude_ut=1826.5056790659519
        altitude_tt=altitude_ut+float(solar.ref.delta_t(solar.ref.exact(altitude_ut)))/86400
        altitude=solar.Solar().altitude(solar.ref.exact(altitude_ut),solar.ref.exact(altitude_tt),'espenakMeeus',[-33.87,151.21,-10000.])['altitude']
        paths=['Scripts/solar-numerics/generate_apparent_integration.py','Scripts/solar-numerics/solar_reference.py',
               'Scripts/solar-numerics/apparent_reference.py','Scripts/apparent-place-data/dtdb.c',
               'Scripts/solar-numerics/reference.py','Scripts/solar-numerics/numerics.py',
               'Sources/AstronomyKit/Engine/Orientation/Generated/IAU2000ATerms.swift',
               'Sources/AstronomyKit/Engine/Orientation/Generated/EquinoxComplementaryTerms.swift',
               'Sources/AstronomyKit/Engine/Orientation/Generated/Vondrak2011Terms.swift']
        return {'schemaVersion':1,'precisionDigits':80,'sourceSHA256':source_hashes(ROOT,sorted(set(paths+BINDINGS+precession_bounds.PATHS+apparent_bounds.PATHS))),
                'scope':'Selected mathematical site trajectory with dUT/dTT=1; fixed archived Horizons inputs for eclipse arithmetic. Neither comparison certifies physical accuracy.',
                'altitudeSample':{'ut':altitude_ut,'tt':altitude_tt,'altitude':str(altitude)},
                'siteCases':cases,'lunarOverlap':{'sun':sun,'moon':moon,'expected':overlap(sun,moon),
                'arithmeticToleranceFraction':1e-12,'constants':{'earthRadiusKilometers':'6378.1366','sunRadiusKilometers':'695700','moonRadiusKilometers':'1737.4','danjonParallaxFactor':'1.01'}}}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    content=json.dumps(artifact(),indent=2,sort_keys=True)+'\n'
    if args.check:
        if OUTPUT.read_text()!=content:raise SystemExit('Independent apparent integration reference differs')
        print('Four 80-digit site trajectories and the archived-input overlap verified')
    else:
        OUTPUT.write_text(content);print(OUTPUT)

if __name__=='__main__':main()
