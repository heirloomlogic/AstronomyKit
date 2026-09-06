#!/usr/bin/env python3
"""Freeze independent broad references, then separately evaluate common-TT errors."""
import argparse
import ctypes
import datetime as dt
import gzip
import hashlib
import importlib.metadata
import json
from pathlib import Path
import time

import swisseph as swe

from measure import BODIES, EPOCH, Model, signed

BODIES_SELECTED = ['mercury', 'venus', 'mars', 'jupiter', 'saturn', 'uranus', 'neptune', 'pluto', 'sun', 'moon']
STATIONS = BODIES_SELECTED[:5]
FLAGS = swe.FLG_MOSEPH | swe.FLG_SPEED
PROTOCOL = Path(__file__).with_name('RANGE-PROTOCOL.md')


def epoch(year, month=1, day=1, hour=0):
    return (dt.datetime(year, month, day, hour, tzinfo=dt.timezone.utc)-EPOCH).total_seconds()/86400


def position(body, tt):
    values, flags = swe.calc(2451545+tt, getattr(swe, body.upper()), FLAGS)
    if flags != FLAGS:
        raise ValueError('Unexpected oracle flags')
    return values[:2]


def speed(pos, body, tt, width=.02):
    return signed(pos(body, tt+width/2)[0]-pos(body, tt-width/2)[0])/width


def root(fn, lo, hi):
    low, high = fn(lo), fn(hi)
    if not low*high <= 0:
        raise ValueError('Unbracketed or nonfinite station')
    while (hi-lo)*86400 > .01:
        mid = (lo+hi)/2
        value = fn(mid)
        if not float('-inf') < value < float('inf'):
            raise ValueError('Nonfinite station')
        if low*value <= 0:
            hi = mid
        else:
            lo, low = mid, value
    return (hi+lo)/2


def freeze(path):
    if path.exists():
        raise ValueError('Refusing to overwrite frozen references')
    rows = [[body, epoch(year, month, 15, 12), *position(body, epoch(year, month, 15, 12))]
            for year in range(1900, 2101) for month in range(1, 13) for body in BODIES_SELECTED]
    stations = []
    for body in STATIONS:
        start, stop = epoch(1900), epoch(2101)
        lo, previous = start, speed(position, body, start)
        while lo < stop:
            hi = min(stop, lo+1)
            value = speed(position, body, hi)
            if previous*value < 0:
                at = root(lambda tt: speed(position, body, tt), lo, hi)
                widths = {str(w): root(lambda tt: speed(position, body, tt, w), at-.02, at+.02)
                          for w in (.01, .04)}
                stations.append({'body': body, 'tt': at, 'widthTTDays': widths,
                                 'referenceWidthSpreadSeconds': (max([at, *widths.values()])-min([at, *widths.values()]))*86400})
            lo, previous = hi, value
        print('Frozen stations:', body, sum(s['body']==body for s in stations), flush=True)
    data = {'protocolSHA256': hashlib.sha256(PROTOCOL.read_bytes()).hexdigest(),
            'oracle': {'package': 'pyswisseph==2.10.3.2', 'version': swe.version, 'flags': FLAGS,
                       'binarySHA256': hashlib.sha256(Path(swe.__file__).read_bytes()).hexdigest()},
            'positions': rows, 'stations': stations}
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(gzip.compress((json.dumps(data, separators=(',', ':'))+'\n').encode(), mtime=0))
    print('Frozen', len(rows), 'positions and', len(stations), 'stations')


class TerrestrialModel(Model):
    def __init__(self, path):
        super().__init__(path)
        self.sample = self.library.ak_sample_tt
        self.sample.argtypes = [ctypes.c_int, ctypes.c_double, ctypes.c_int, ctypes.POINTER(ctypes.c_double)]
        self.sample.restype = ctypes.c_int


def evaluate(path, library, output):
    data = json.loads(gzip.decompress(path.read_bytes()))
    if data['protocolSHA256'] != hashlib.sha256(PROTOCOL.read_bytes()).hexdigest():
        raise ValueError('Frozen selection protocol changed')
    model = TerrestrialModel(library.resolve())
    positions, stations = [], []
    for body, tt, longitude, latitude in data['positions']:
        actual = model.position(body, tt)
        positions.append({'body': body, 'tt': tt, 'longitudeErrorArcseconds': signed(actual[0]-longitude)*3600,
                          'latitudeErrorArcseconds': (actual[1]-latitude)*3600})
    print('Measured', len(positions), 'monthly positions', flush=True)
    for record in data['stations']:
        body, at = record['body'], record['tt']
        native = root(lambda tt: speed(model.position, body, tt), at-.5, at+.5)
        stations.append({**record, 'nativeTT': native, 'timingErrorSeconds': (native-at)*86400})
    report = {'purpose': 'Common-TT diagnostic population; not certified search coverage or universal UTC accuracy',
              'referenceSHA256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'librarySHA256': hashlib.sha256(library.read_bytes()).hexdigest(),
              'scriptSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'positions': positions, 'stations': stations,
              'stationFailuresOver60Seconds': [s for s in stations if abs(s['timingErrorSeconds'])>60]}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(gzip.compress((json.dumps(report, separators=(',', ':'))+'\n').encode(), mtime=0))
    print('Station count', len(stations), 'failures >60s', len(report['stationFailuresOver60Seconds']),
          'max seconds', max(abs(s['timingErrorSeconds']) for s in stations))
    for body in BODIES_SELECTED:
        subset = [s for s in positions if s['body']==body]
        print(body, 'max lon/lat arcsec', max(abs(s['longitudeErrorArcseconds']) for s in subset),
              max(abs(s['latitudeErrorArcseconds']) for s in subset))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['freeze', 'evaluate'])
    parser.add_argument('references', type=Path)
    parser.add_argument('--library', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if importlib.metadata.version('pyswisseph') != '2.10.3.2':
        raise ValueError('The oracle package must be pyswisseph==2.10.3.2')
    if args.mode == 'freeze':
        freeze(args.references)
    else:
        if args.library is None or args.output is None:
            parser.error('evaluate requires --library and --output')
        evaluate(args.references, args.library, args.output)
