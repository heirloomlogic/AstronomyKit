#!/usr/bin/env python3
"""Compare direct Saturn center representations and reproduce the six source apsides."""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('pluto_assessment', ROOT/'Scripts/assess-pluto-de441.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
d = p.direct
SAT_URL = 'https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/sat441.bsp'
SAT_ID = [661592064, None, 'Sat, 29 Jan 2022 14:38:13 GMT']
START, END = 2414988.5, 2499423.5  # 1900–2130 core with 32-day exterior blends.
OUTPUT = ROOT/'Scripts/saturn-data/assessment.json'


class SatelliteReader:
    def __init__(self, cache, expected=None):
        self.cache = Path(cache)
        self.cache.mkdir(parents=True, exist_ok=True)
        self.expected = expected or {}
        self.ranges = {}

    def read(self, start, count):
        key = f'{start}-{start+count-1}'
        path = self.cache/f'{key}.bin'
        receipt = path.with_suffix('.json')
        if path.exists():
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            if json.loads(receipt.read_text()) != dict(sha256=digest, identity=SAT_ID):
                raise ValueError('satellite cache identity or digest mismatch')
        else:
            reader = d.RangeReader(SAT_URL)
            data = reader.read(start, count)
            if [reader.total_bytes, reader.etag, reader.last_modified] != SAT_ID:
                raise ValueError('satellite source identity changed')
            digest = hashlib.sha256(data).hexdigest()
            path.write_bytes(data)
            receipt.write_text(json.dumps(dict(sha256=digest, identity=SAT_ID)))
        if len(data) != count or (key in self.expected and digest != self.expected[key]):
            raise ValueError('satellite range length or digest mismatch')
        self.ranges[key] = digest
        return data


def quantize(records, kind):
    code = 'd' if kind == 'float64' else 'f'
    encoded = bytearray()
    rounded = []
    worst_position = worst_rate = 0.
    worst_indices = [0, 0]
    for index, (start, days, axes) in enumerate(records):
        new_axes = []
        for axis in axes:
            raw = struct.pack(f'<{len(axis)}{code}', *axis)
            encoded.extend(raw)
            new_axes.append(struct.unpack(f'<{len(axis)}{code}', raw))
        intervals = [[(v, v) for v in axis] for axis in new_axes]
        position, rate = p.error_bounds(axes, intervals, days)
        if position > worst_position: worst_position, worst_indices[0] = position, index
        if rate > worst_rate: worst_rate, worst_indices[1] = rate, index
        rounded.append((start, days, tuple(new_axes)))
    return bytes(encoded), rounded, dict(positionBoundKm=worst_position, rateBoundKmPerTDBDay=worst_rate, worstRecords=worst_indices)


def seam_jumps(records):
    maximum_position = maximum_rate = 0.
    previous = None
    for _, days, axes in records:
        left = p.evaluate(axes, -1., days)
        right = p.evaluate(axes, 1., days)
        if previous is not None:
            maximum_position = max(maximum_position, d.norm([a-b for a,b in zip(previous[0], left[0])]))
            maximum_rate = max(maximum_rate, d.norm([a-b for a,b in zip(previous[1], left[1])]))
        previous = right
    return dict(boundaries=len(records)-1, maximumPositionJumpKm=maximum_position, maximumRateJumpKmPerTDBDay=maximum_rate)


def state(records, jd):
    start, days, _ = records[0]
    index = math.floor((jd-start)/days)
    if not 0 <= index < len(records):
        raise ValueError('epoch outside source table')
    record_start, days, axes = records[index]
    return p.evaluate(axes, 2*(jd-record_start)/days-1, days)


def center_state(tables, jd):
    a, av = state(tables[6], jd)
    b, bv = state(tables[10], jd)
    c, cv = state(tables[699], jd)
    return [a[i]-b[i]+c[i] for i in range(3)], [av[i]-bv[i]+cv[i] for i in range(3)]


_tdb_spec = importlib.util.spec_from_file_location('moon_tables', ROOT/'Scripts/generate-moon-tables.py')
_tdb_module = importlib.util.module_from_spec(_tdb_spec)
_tdb_spec.loader.exec_module(_tdb_module)
_TDB_TERMS = [[tuple(map(float,row)) for row in group] for group in _tdb_module.tdb_terms((ROOT/'Sources/CLibAstronomy/EphemerisTime/dtdb.c').read_text())]


def tt_to_tdb(jd):
    t = (jd-2451545.)/365250.
    sums = [math.fsum(a*math.sin(f*t+phase) for a,f,phase in reversed(group)) for group in _TDB_TERMS]
    wf = t*(t*(t*(t*sums[4]+sums[3])+sums[2])+sums[1])+sums[0]
    wj = .00065e-6*math.sin(6069.776754*t+4.021194) + .00033e-6*math.sin(213.299095*t+5.543132) - .00196e-6*math.sin(6208.294251*t+5.696701) - .00173e-6*math.sin(74.781599*t+2.435900) + .03638e-6*t*t
    return jd+(wf+wj)/86400


def roots(tables):
    archive = json.loads((ROOT/'Scripts/reference-data/sources/horizons/saturn-apsis-precision.json').read_bytes())['result']
    lines = archive.split('$$SOE')[1].split('$$EOE')[0].strip().splitlines()
    result = []
    for line in lines[2::5]:
        fields = line.split(',')
        jd = float(fields[0])
        def rate(tt):
            position, velocity = center_state(tables, tt_to_tdb(tt))
            return math.fsum(x*y for x,y in zip(position,velocity))/d.norm(position)
        lo, hi = jd-.1, jd+.1
        left, right = rate(lo), rate(hi)
        if left*right >= 0: raise ValueError('reference root not bracketed by direct center model')
        for _ in range(45):
            mid=(lo+hi)/2
            if mid==lo or mid==hi: break
            if rate(mid)*left > 0: lo=mid
            else: hi=mid
        root=(lo+hi)/2
        position, _=center_state(tables,tt_to_tdb(jd))
        result.append(dict(referenceJDTT=jd, rootJDTT=root, errorSeconds=(root-jd)*86400,
                           rateAtReferenceKmPerDay=rate(jd), rangeErrorKm=d.norm(position)-float(fields[9])*d.AU_KM))
    return result


def assess(cache):
    prior = json.loads(OUTPUT.read_bytes()) if OUTPUT.exists() else {}
    sat = SatelliteReader(cache/'sat441',prior.get('satellite',{}).get('ranges'))
    de = p.shared.CachedReader(ROOT/'.context/issue-184/compact/ranges',prior.get('planetary',{}).get('ranges'))
    readers={699:sat,6:de,10:de}
    segments = {699:d.read_segments(sat),6:d.read_segments(de)}
    segments[10]=segments[6]
    tables, layouts = {}, {}
    for target in [699,6,10]:
        selected=[(s,d.read_metadata(readers[target],s)) for s in segments[target] if s.target==target and s.center==(6 if target==699 else 0)]
        layout=p.windows(selected,target,START-2.2e-8,END+2.2e-8,center=6 if target==699 else 0)
        tables[target]=p.load_records(readers[target],layout)
        layouts[str(target)]=[dict(segment=s._asdict(),metadata=m._asdict(),firstRecord=f,recordCount=c) for s,m,f,c in layout]
        print('Loaded',target,len(tables[target]),flush=True)
    candidates={}
    for encoding in ['float64','float32']:
        rounded, bodies = {}, {}
        for target in [699,6,10]:
            # Keep the large barycentric terms in Float64 in both candidates.
            kind = encoding if target==699 else 'float64'
            data, rounded[target], bounds=quantize(tables[target],kind)
            (cache/f'{encoding}-{target}.bin').write_bytes(data)
            bodies[str(target)]=dict(startJDTDB=tables[target][0][0],recordDays=tables[target][0][1],recordCount=len(tables[target]),coefficientCount=len(tables[target][0][2][0]),encoding=kind,encodedBytes=len(data),sha256=hashlib.sha256(data).hexdigest(),seams=seam_jumps(rounded[target]),**bounds)
        candidates[encoding]=dict(bodies=bodies,roots=roots(rounded),encodedBytes=sum(b['encodedBytes'] for b in bodies.values()))
    samples=[]
    for target,records in tables.items():
        indices={i*(len(records)-1)//128 for i in range(129)}
        indices.update(candidates['float32']['bodies'][str(target)]['worstRecords'])
        for index in sorted(indices):
            for x in [-1.,0.,1.]:
                pos,vel=p.evaluate(records[index][2],x,records[index][1]); samples.append(dict(target=target,record=index,x=x,positionKm=pos,velocityKmPerTDBDay=vel))
    result=dict(schemaVersion=1,requestedJDTDB=[START-2.2e-8,END+2.2e-8],satellite=dict(url=SAT_URL,identity=SAT_ID,ranges=sat.ranges),planetary=dict(url=d.SOURCE_URL,identity=p.shared.identity(),ranges=de.ranges),layouts=layouts,candidates=candidates)
    return result,dict(selection='129 uniform records per body plus all Float32 worst-bound records, at x=-1,0,1.',rows=samples)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache',type=Path,default=ROOT/'.context/issue-92/saturn-assessment')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args();args.cache.mkdir(parents=True,exist_ok=True)
    result,samples=assess(args.cache)
    encoded=json.dumps(result,indent=2,sort_keys=True)+'\n'
    sample_text=json.dumps(samples,indent=2,sort_keys=True)+'\n'
    sample_path=OUTPUT.with_name('direct-fixtures.json')
    if args.check:
        if OUTPUT.read_text()!=encoded or sample_path.read_text()!=sample_text: raise SystemExit('Saturn assessment differs')
    else:
        OUTPUT.write_text(encoded);sample_path.write_text(sample_text)
    print(json.dumps(result['candidates'],indent=2))

if __name__=='__main__': main()
