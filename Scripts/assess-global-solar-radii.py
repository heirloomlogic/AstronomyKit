#!/usr/bin/env python3
"""Reproduce the bounded solar-radius discriminator from separately captured native vectors."""
import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT/'Scripts/eclipse-data'
EARTH = 6378.1366
POLAR_RATIO = 1-1/298.25642
EPOCHS = [-2061.783027, -2061.7840335648148, -2061.7805613425926, -4837.703993055556]


def norm(vector):
    return math.sqrt(math.fsum(x*x for x in vector))


def dot(first, second):
    return math.fsum(x*y for x, y in zip(first, second))


def subtract(first, second):
    return [x-y for x, y in zip(first, second)]


def build(vectors):
    if [row['tt'] for row in vectors] != EPOCHS:
        raise ValueError('radius probe source epochs differ')
    rows=[]
    for item in vectors:
        if set(item) != {'tt','sun','moon','sunEQD','moonEQD'}:
            raise ValueError('radius probe schema')
        for key in ['sun','moon','sunEQD','moonEQD']:
            if len(item[key])!=3 or not all(math.isfinite(x) for x in item[key]):
                raise ValueError('nonfinite probe vector')
        for body in ['sun','moon']:
            if abs(norm(item[body])-norm(item[body+'EQD'])) > 16*math.ulp(norm(item[body])):
                raise ValueError('rotation length relation')
        sun, moon = item['sunEQD'], item['moonEQD']
        direction = subtract(moon,sun)
        v = [direction[0],direction[1],direction[2]/POLAR_RATIO]
        e = [-moon[0],-moon[1],-moon[2]/POLAR_RATIO]
        a, b, c = dot(v,v), -2*dot(v,e), dot(e,e)-EARTH**2
        discriminant = b*b-4*a*c
        if discriminant<=0: raise ValueError('expected central source geometry')
        fraction = (-b-math.sqrt(discriminant))/(2*a)
        point = [fraction*v[i]-e[i] for i in range(3)]
        point[2] *= POLAR_RATIO
        sun_distance, moon_distance = norm(subtract(sun,point)), norm(subtract(moon,point))
        candidates = [('retained',695700,1736), ('k2-nominal',695700,EARTH*.272281), ('k2-695992',695992,EARTH*.272281), ('k2-959.63',149597870.69098932*math.sin(math.radians(959.63/3600)),EARTH*.272281)]
        for label, sun_radius, moon_radius in candidates:
            solar_angle = math.asin(sun_radius/sun_distance)
            lunar_angle = math.asin(moon_radius/moon_distance)
            umbra = moon_radius-fraction*(sun_radius-moon_radius)
            ratio = lunar_angle/solar_angle
            rows.append({'tt':item['tt'], 'case':label, 'sunGeoArcseconds':math.degrees(math.asin(sun_radius/norm(sun)))*3600, 'moonGeoArcseconds':math.degrees(math.asin(moon_radius/norm(moon)))*3600, 'sunTopocentricArcseconds':math.degrees(solar_angle)*3600, 'moonTopocentricArcseconds':math.degrees(lunar_angle)*3600, 'diameterRatio':ratio, 'diameterRatioSquared':ratio**2, 'areaObscuration':min(1,ratio**2), 'surfaceUmbraKm':umbra, 'biasedTotal':umbra>.014, 'unbiasedTotal':umbra>0})
    # Separately printed RP1301 input observables constrain the source/radius discriminator.
    first=vectors[0]
    sun_geo=next(row['sunGeoArcseconds'] for row in rows if row['tt']==EPOCHS[0] and row['case']=='k2-959.63')
    moon_geo=math.degrees(math.asin(EARTH*.2725076/norm(first['moonEQD'])))*3600
    parallax=math.degrees(math.asin(EARTH/norm(first['moonEQD'])))*3600
    if abs(sun_geo-950.22)>.005 or abs(moon_geo-884.08)>.005 or abs(parallax-3244.35)>.005:
        raise ValueError('RP1301 input print intervals')
    return rows


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    rows=build(json.loads((DATA/'radius-vectors.json').read_bytes()))
    expected=(json.dumps(rows,indent=2,sort_keys=True,allow_nan=False)+'\n').encode()
    output=DATA/'radius-comparison.json'
    if args.check:
        if output.read_bytes()!=expected:raise SystemExit('radius comparison differs')
    else:output.write_bytes(expected)
    print('radius comparison matches recorded native vectors')

if __name__=='__main__':main()
