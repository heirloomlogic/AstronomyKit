#!/usr/bin/env python3
"""Isolate a documented future UTC convention; not a production time API repair.

The archived leap-second table supplies TT-UTC from its final effective date.
Earlier epochs retain the original delta-T approximation in this experiment.
Every frozen event is later than that date. UT1 for Earth rotation remains
approximated by UTC; no future Earth-orientation knowledge is claimed.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from measure import EPOCH, FIXTURES, Model, fixtures, measure, production
from models import ROOT, build

DATA = Path(__file__).parent / 'time-data'


def utc_policy():
    manifest = json.loads((DATA / 'manifest.json').read_text())
    for name, record in manifest['files'].items():
        if hashlib.sha256((DATA/name).read_bytes()).hexdigest() != record['sha256']:
            raise ValueError('Time source checksum mismatch')
    rows = re.findall(r'=JD\s+([\d.]+)\s+TAI-UTC=\s+([\d.]+)\s+S.*?X\s+([\d.]+)',
                      (DATA/'tai-utc.dat').read_text())
    if not rows or float(rows[-1][2]) != 0:
        raise ValueError('Missing constant final TAI-UTC entry')
    jd, tai, _ = map(float, rows[-1])
    return {'effectiveUTDays': jd-2451545, 'ttMinusUTCSeconds': tai+32.184,
            'convention': 'Hold the last announced leap-second offset for future UTC dates',
            'sourceManifest': manifest}


def civil_production(library, products, module_map, output, policy):
    """Keep native TT/UT1 coherent while assigning the input Date a civil UTC TT.

    The baseline TT constructor inverts the unchanged TT-UT1 approximation.
    This tests Earth rotation with modeled UT1 instead of approximating it by UTC.
    """
    template = (ROOT/'Scripts/accuracy/production-probe.swift').read_text()
    if template.count('AstroTime(date)') != 2 or template.count('AstroTime(at)') != 1:
        raise ValueError('Unexpected probe time construction sites')
    source = template.replace('AstroTime(date)', 'diagnosticCivilTime(date)').replace(
        'AstroTime(at)', 'diagnosticCivilTime(at)')
    source += f"""
func diagnosticCivilTime(_ date: Date) -> AstroTime {{
    let civilDays = (date.timeIntervalSince1970 - 946728000) / 86400
    precondition(civilDays > {policy['effectiveUTDays']:.17g})
    return AstroTime(tt: civilDays + {policy['ttMinusUTCSeconds']:.17g} / 86400)
}}
"""
    path = output/'civil-time-probe.swift'
    path.write_text(source)
    executable = output/'production-civil-tt-modeled-ut1'
    subprocess.run(['swiftc', '-I', str(products), '-Xcc', f'-fmodule-map-file={module_map}',
                    str(path), str(products/'AstrologyKit.o'), str(products/'AstronomyKit.o'),
                    library['path'], '-o', str(executable)], check=True)
    report = output/'production-civil-tt-modeled-ut1.json'
    subprocess.run([str(executable), str(FIXTURES.resolve()), str(report)], check=True,
                   env={**os.environ, 'ASTROLOGY_PROBE_DATE_ROTATION': '1',
                        'ASTROLOGY_PROBE_MODEL': 'civil-tt-modeled-ut1'}, stdout=subprocess.DEVNULL)
    data = json.loads(report.read_text())
    if len(data['results']) != 36 or any('error' in r for r in data['results']):
        raise ValueError('Civil-TT probe did not refine all 36 events')
    return {'convention': 'UTC -> TT via last announced TAI-UTC; native TT -> modeled UT1 via unchanged delta-T',
            'library': library, 'probeSourceSHA256': hashlib.sha256(source.encode()).hexdigest(),
            'data': data}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--products', type=Path)
    parser.add_argument('--module-map', type=Path)
    parser.add_argument('--require-pass', action='store_true')
    args = parser.parse_args()
    if bool(args.products) != bool(args.module_map):
        parser.error('--products and --module-map must be supplied together')
    policy = utc_policy()
    for _, oracle in fixtures():
        for event in oracle['events']:
            ut = (dt.datetime.fromisoformat(event['instant'])-EPOCH).total_seconds()/86400
            if ut-1 <= policy['effectiveUTDays']:
                raise ValueError('Frozen event/search window is outside this future-only experiment')
    output = args.output.resolve()
    libraries = build(output)
    original = (output/'full.c').read_text()
    old = 'static _Atomic(astro_deltat_func) DeltaTFunc = Astronomy_DeltaT_EspenakMeeus;'
    new = f'''static double DiagnosticFutureUTC(double ut)
{{
    return ut >= {policy['effectiveUTDays']:.17g} ? {policy['ttMinusUTCSeconds']:.17g}
        : Astronomy_DeltaT_EspenakMeeus(ut);
}}
static _Atomic(astro_deltat_func) DeltaTFunc = DiagnosticFutureUTC;'''
    if original.count(old) != 1:
        raise ValueError('Default time conversion was not found exactly once')
    source = original.replace(old, new)
    path = output/'full-future-utc.c'
    path.write_text(source)
    library = output/('full-future-utc.dylib' if sys.platform == 'darwin' else 'full-future-utc.so')
    croot = ROOT/'Sources/CLibAstronomy'
    subprocess.run(['clang', '-O2', '-dynamiclib' if sys.platform == 'darwin' else '-shared',
                    '-fPIC', '-pthread', '-I', str(croot/'include'), '-I', str(croot),
                    '-I', str(ROOT/'Sources/CLibAstronomy/generated'), str(path),
                    str(ROOT/'Scripts/accuracy/sample.c'),
                    *map(str, sorted((croot/'detmath').glob('*.c'))), '-lm', '-o', str(library)], check=True)
    record = {'path': str(library), 'sourceSHA256': hashlib.sha256(source.encode()).hexdigest(),
              'binarySHA256': hashlib.sha256(library.read_bytes()).hexdigest()}
    report = {'purpose': __doc__, 'policy': policy, 'library': record, 'fullModel': libraries['full'],
              'compiler': subprocess.check_output(['clang', '--version'], text=True),
              'scriptSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'native': measure(Model(library))}
    passed = all(r['passesTimeGate'] and r['passesConvergence'] for r in report['native'])
    if args.products:
        report['production'] = production({'full-future-utc': record}, args.products.resolve(),
                                          args.module_map.resolve(), output)
        report['swiftInputSHA256'] = {name: hashlib.sha256((args.products/name).read_bytes()).hexdigest()
                                     for name in ('AstrologyKit.o', 'AstronomyKit.o')}
        report['moduleMapSHA256'] = hashlib.sha256(args.module_map.read_bytes()).hexdigest()
        rows = report['production']['full-future-utc-date']['results']
        passed &= all(r['passes60SecondReferenceGate'] and r['bracketWidthSeconds'] <= 1
                      and abs(r['localResidual']) <= (1e-6 if r['kind'] == 'station' else 1e-4) for r in rows)
        report['civilTTModeledUT1'] = civil_production(libraries['full'], args.products.resolve(),
                                                      args.module_map.resolve(), output, policy)
        civil_rows = report['civilTTModeledUT1']['data']['results']
        passed &= all(r['passes60SecondReferenceGate'] and r['bracketWidthSeconds'] <= 1
                      and abs(r['localResidual']) <= (1e-6 if r['kind'] == 'station' else 1e-4) for r in civil_rows)
        print('Civil TT / modeled UT1 events:', len(civil_rows), 'maximum absolute seconds:',
              max(r['absoluteTimeErrorSeconds'] for r in civil_rows))
        print('Swift events:', len(rows), 'maximum absolute seconds:', max(r['absoluteTimeErrorSeconds'] for r in rows))
    (output/'future-utc.json').write_text(json.dumps(report, indent=2)+'\n')
    print('All available time/convergence gates passed:', passed)
    if args.require_pass and (not passed or not args.products):
        raise SystemExit('Complete 36-event future-UTC diagnostic acceptance is required')


if __name__ == '__main__':
    main()
