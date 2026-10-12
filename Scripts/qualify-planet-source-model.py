#!/usr/bin/env python3
"""Replay the issue-248 source-model diagnostic without changing planetary routing."""
import argparse
import base64
from functools import lru_cache
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import urllib.request

import mpmath as mp

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'Scripts/planet-data/model-preflight'
ARCHIVE = DATA / 'ranges.json'
EVIDENCE = DATA / 'evidence.json'
CLOCK = ROOT / 'Scripts/apparent-place-data/dtdb.c'
APSIDES = ROOT / 'Scripts/reference-data/planetary-apsis-evidence.json'
SPEC = importlib.util.spec_from_file_location('spk_direct', ROOT / 'Scripts/assess-moon-de441.py')
spk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(spk)
J2000 = mp.mpf(2451545)
SOURCES = {
    'de441': ('https://ssd.jpl.nasa.gov/ftp/eph/planets/bsp/de441.bsp',
              [3307878400, '"5fe1446a-c52a3800"', 'Tue, 22 Dec 2020 00:57:14 GMT']),
    'jup365': ('https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/jup365.bsp',
              [1136581632, None, 'Sun, 14 Mar 2021 15:29:22 GMT']),
    'ura184_part-3': ('https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/ura184_part-3.bsp',
                    [386885632, None, 'Fri, 26 Sep 2025 13:43:01 GMT']),
    'nep098_part-1': ('https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/nep098_part-1.bsp',
                    [821838848, None, 'Mon, 13 Jul 2026 17:57:46 GMT']),
}
BODIES = {'jupiter': (5, 'jup365', 'jup365_merged', 'jup365_merged'),
          'uranus': (7, 'ura184_part-3', 'ura184_merged', 'DE441'),
          'neptune': (8, 'nep098_part-1', 'nep098_merged', 'nep098_merged')}
MODES = ('DE441', 'merged', 'mergedBarycenterDE441Sun')


class Reader:
    """Read only bytes in the digest-checked archive; never fill gaps from a network."""
    def __init__(self, name, document):
        url, identity = SOURCES[name]
        if document['url'] != url or document['identity'] != identity:
            raise ValueError('source identity differs')
        self.ranges = {}
        for key, row in document['ranges'].items():
            if not re.fullmatch(r'\d+-\d+', key):
                raise ValueError('invalid byte range')
            start, end = map(int, key.split('-'))
            data = base64.b64decode(row['base64'], validate=True)
            if start < 0 or end >= identity[0] or len(data) != end-start+1:
                raise ValueError('byte range length or domain differs')
            if hashlib.sha256(data).hexdigest() != row['sha256']:
                raise ValueError('source range digest differs')
            self.ranges[(start, len(data))] = data
        if name != 'de441':
            comment = document['comments']
            if comment['url'] != url[:-4]+'.cmt' or hashlib.sha256(comment['text'].encode()).hexdigest() != comment['sha256']:
                raise ValueError('source comment digest or URL differs')

    def read(self, start, count):
        try:
            return self.ranges[(start, count)]
        except KeyError as exc:
            raise ValueError(f'unarchived source range: {start}-{start+count-1}') from exc


def readers(archive):
    if archive['schemaVersion'] != 1 or set(archive['sources']) != set(SOURCES):
        raise ValueError('source archive inventory differs')
    return {name: Reader(name, archive['sources'][name]) for name in SOURCES}


class Kernel:
    def __init__(self, reader):
        self.reader = reader
        self.segments = spk.read_segments(reader)

    @lru_cache(maxsize=None)
    def metadata(self, segment):
        metadata = spk.read_metadata(self.reader, segment)
        if metadata.record_days <= 0 or metadata.record_count <= 0 or metadata.record_words < 5 or (metadata.record_words-2) % 3:
            raise ValueError('invalid SPK coefficient layout')
        return metadata

    @lru_cache(maxsize=None)
    def values(self, segment, metadata, index):
        data = self.reader.read((segment.first_word-1+index*metadata.record_words)*8, metadata.record_words*8)
        values = tuple(map(mp.mpf, struct.unpack(f'<{metadata.record_words}d', data)))
        expected = (mp.mpf(metadata.start_jd_tdb)-J2000+(index+mp.mpf('.5'))*metadata.record_days)*86400
        if not all(mp.isfinite(x) for x in values) or values[0] != expected or values[1] != mp.mpf(metadata.record_days)*43200:
            raise ValueError('source record midpoint, radius or finite-domain differs')
        return values

    def record(self, target, center, jdtdb):
        if not mp.isfinite(jdtdb):
            raise ValueError('nonfinite TDB')
        seconds = (jdtdb-J2000)*86400
        # SPK later-segment priority applies where summaries overlap.
        segment = next((s for s in reversed(self.segments) if (s.target, s.center) == (target, center)
                        and s.start_seconds_tdb <= seconds <= s.end_seconds_tdb), None)
        if segment is None:
            raise ValueError('target/center or source time is unavailable')
        if (segment.frame, segment.kind) != (1, 2):
            raise ValueError('source frame/type differs')
        metadata = self.metadata(segment)
        index = min(int(mp.floor((jdtdb-metadata.start_jd_tdb)/metadata.record_days)), metadata.record_count-1)
        if index < 0:
            raise ValueError('source record exterior')
        values = self.values(segment, metadata, index)
        x = (seconds-values[0])/values[1]
        if abs(x) > 1:
            raise ValueError('source record exterior')
        return values, x, mp.mpf(metadata.record_days)

    def state(self, target, center, jdtdb):
        values, x, days = self.record(target, center, jdtdb)
        count = (len(values)-2)//3
        axes = [chebyshev(values[2+a*count:2+(a+1)*count], x, days) for a in range(3)]
        return [[axis[k] for axis in axes] for k in range(2)]


def chebyshev(coefficients, x, days):
    """Direct T_n and T'_n recurrences; derivative per TDB day."""
    values, rates = [mp.mpf(1), x], [mp.mpf(0), mp.mpf(1)]
    for _ in range(2, len(coefficients)):
        values.append(2*x*values[-1]-values[-2])
        rates.append(2*values[-2]+2*x*rates[-1]-rates[-2])
    return (mp.fsum(c*t for c, t in zip(coefficients, values)),
            mp.fsum(c*t for c, t in zip(coefficients, rates))*2/days)


@lru_cache(maxsize=1)
def clock_terms():
    body = CLOCK.read_text().split('static const double fairhd[787][3] = {')[1].split('};')[0]
    terms = [[mp.mpf(x.strip()) for x in row.split(',')] for row in re.findall(r'\{([^{}]+)\}', body)]
    if len(terms) != 787:
        raise ValueError('pinned clock layout differs')
    return terms


@lru_cache(maxsize=4096)
def offset_seconds(tt):
    """Pinned ERFA geocentric TDB minus TT, with TT in days from J2000."""
    t = tt/365250
    terms = clock_terms()
    values = [mp.fsum(a*mp.sin(b*t+c) for a,b,c in terms[lo:hi])
              for lo,hi in [(0,474),(474,679),(679,764),(764,784),(784,787)]]
    value = mp.fsum(v*t**i for i,v in enumerate(values))
    for a,b,c in [('0.00065e-6','6069.776754','4.021194'), ('0.00033e-6','213.299095','5.543132'),
                  ('-0.00196e-6','6208.294251','5.696701'), ('-0.00173e-6','74.781599','2.435900')]:
        value += mp.mpf(a)*mp.sin(mp.mpf(b)*t+mp.mpf(c))
    return value+mp.mpf('0.03638e-6')*t*t


def reference_path(body):
    return ROOT / f'Scripts/reference-data/sources/planetary-apsides/{body}.json'


def parse_reference(body, raw):
    planet, _, source, sun = BODIES[body]
    text = json.loads(raw)['result']
    target_line = next(line for line in text.splitlines() if line.startswith('Target body name:'))
    center_line = next(line for line in text.splitlines() if line.startswith('Center body name:'))
    if (f'({100*planet+99})' not in target_line or f'{{source: {source}}}' not in target_line
            or 'Sun (10)' not in center_line or f'{{source: {sun}}}' not in center_line
            or any(token not in text for token in ['JDTT', 'Output units    : AU-D', 'Reference frame : ICRF',
                                                   'Output type     : GEOMETRIC cartesian states'])):
        raise ValueError('reference semantics differ')
    rows = []
    for line in text.split('$$SOE')[1].split('$$EOE')[0].strip().splitlines():
        fields = line.split(',')
        if len(fields) != 12:
            raise ValueError('reference row layout differs')
        numbers = list(map(mp.mpf, [fields[0], *fields[2:11]]))
        if not all(mp.isfinite(x) for x in numbers):
            raise ValueError('nonfinite reference')
        rows.append(numbers)
    if len(rows) != 65 or any(b[0] <= a[0] for a,b in zip(rows, rows[1:])):
        raise ValueError('reference row inventory differs')
    return rows


def references(body):
    rows = parse_reference(body, reference_path(body).read_text())
    cases = json.loads(APSIDES.read_text(), parse_float=mp.mpf)['cases']
    case = next(c for c in cases if c['body'] == body)
    roots = case['roots']
    for root in roots:
        lo, hi = root['lowerJDTT'], root['upperJDTT']
        if not lo < hi or (hi-lo)*86400 > 1 or not any(a[0] <= lo < hi <= b[0] and a[-1]*b[-1] < 0 for a,b in zip(rows, rows[1:])):
            raise ValueError('reference root is not a retained source crossing')
    return roots, rows


def bisect(function, lo, hi):
    left, right = function(lo), function(hi)
    if not mp.isfinite(left) or not mp.isfinite(right) or left*right > 0:
        raise ValueError('root bracket is invalid')
    for _ in range(80):
        if (hi-lo)*86400 <= mp.mpf('.0001'):
            return lo, hi
        mid = (lo+hi)/2
        value = function(mid)
        if not mp.isfinite(value) or mid == lo or mid == hi:
            raise ValueError('root failed to progress')
        if left*value <= 0:
            hi = mid
        else:
            lo, left = mid, value
    raise ValueError('root iteration limit')


def norm(vector):
    return mp.sqrt(mp.fsum(v*v for v in vector))


def input_hashes():
    paths = [ARCHIVE, CLOCK, APSIDES, Path(__file__), ROOT/'Scripts/assess-moon-de441.py']
    paths += [reference_path(body) for body in BODIES]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def measure():
    mp.mp.dps = 50
    # Constants cached under another caller's precision must not contaminate the replay.
    clock_terms.cache_clear()
    offset_seconds.cache_clear()
    kernels = {name: Kernel(reader) for name, reader in readers(json.loads(ARCHIVE.read_bytes())).items()}
    report = {'schemaVersion': 1, 'precisionDecimalDigits': 50, 'sourceHashes': input_hashes(), 'cases': {}}
    for body, (planet, satellite, _, _) in BODIES.items():
        roots, rows = references(body)
        cases = {}
        for mode in MODES:
            def state(jdtt):
                jdtdb = jdtt+offset_seconds(jdtt-J2000)/86400
                bary = kernels['de441' if mode == 'DE441' else satellite].state(planet, 0, jdtdb)
                sun = kernels[satellite if mode == 'merged' else 'de441'].state(10, 0, jdtdb)
                center = kernels[satellite].state(100*planet+99, planet, jdtdb)
                return [[bary[k][a]-sun[k][a]+center[k][a] for a in range(3)] for k in range(2)]
            def rate(jdtt):
                p, v = state(jdtt)
                return mp.fsum(a*b for a,b in zip(p,v))/norm(p)
            measured = []
            for root in roots:
                lo, hi = root['lowerJDTT'], root['upperJDTT']
                midpoint = (lo+hi)/2
                lower, upper = bisect(rate, midpoint-mp.mpf('.02'), midpoint+mp.mpf('.02'))
                measured.append({'kind': root['kind'], 'referenceBracketJDTT': [str(lo), str(hi)],
                                 'candidateBracketJDTT': [mp.nstr(lower, 35), mp.nstr(upper, 35)],
                                 'residualSeconds': float(((lower+upper)/2-midpoint)*86400)})
            vectors = []
            for row in [rows[0], rows[32], rows[64]]:
                actual = state(row[0])
                errors = [norm([actual[k][a]-row[1+3*k+a]*mp.mpf('149597870.7') for a in range(3)]) for k in range(2)]
                vectors.append({'jdTT': str(row[0]), 'positionResidualKm': float(errors[0]),
                                'velocityResidualKmPerTDBDay': float(errors[1])})
            cases[mode] = {'roots': measured, 'vectors': vectors}
        report['cases'][body] = cases
    return report


def verify_remote(archive):
    """Compare official bytes with existing pins; never write an archive or receipt."""
    for name, reader in readers(archive).items():
        remote = spk.RangeReader(SOURCES[name][0])
        for (start, count), expected in reader.ranges.items():
            actual = remote.read(start, count)
            if actual != expected or [remote.total_bytes, remote.etag, remote.last_modified] != SOURCES[name][1]:
                raise ValueError(f'remote source bytes/identity differ: {name}')
        if name != 'de441':
            comment = archive['sources'][name]['comments']
            with urllib.request.urlopen(comment['url'], timeout=60) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != comment['sha256']:
                raise ValueError('remote source comment digest differs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='replay and compare the pinned diagnostic evidence')
    parser.add_argument('--verify-remote', action='store_true', help='also compare every archived range with the official URL')
    args = parser.parse_args()
    if args.verify_remote:
        verify_remote(json.loads(ARCHIVE.read_bytes()))
    result = measure()
    if args.check:
        expected = json.loads(EVIDENCE.read_bytes())
        if result != expected:
            raise SystemExit('source-model diagnostic or input hashes differ')
        print('Verified source-model diagnostic; Uranus DE441 acceptance remains unresolved')
    else:
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
