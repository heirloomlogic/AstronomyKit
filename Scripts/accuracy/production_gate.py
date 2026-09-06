#!/usr/bin/env python3
"""Run frozen acceptance against built, integrated production Swift/C objects.

No model, time-conversion, or coordinate override is permitted in this driver.
Build the paired AstrologyKit checkout first, using this AstronomyKit candidate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

from measure import FIXTURES, fixtures
from models import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--astrology', type=Path, required=True)
    parser.add_argument('--products', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    astrology, products, output = args.astrology.resolve(), args.products.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    dependencies = json.loads(subprocess.check_output(
        ['swift', 'package', 'show-dependencies', '--format', 'json'], cwd=astrology))
    matching = [d for d in dependencies['dependencies'] if d['identity'] == 'astronomykit']
    if len(matching) != 1 or Path(matching[0]['path']).resolve() != ROOT:
        raise ValueError('Paired checkout must build this exact AstronomyKit working tree')
    subprocess.run(['swift', 'build'], cwd=astrology, check=True, stdout=subprocess.DEVNULL)
    actual_products = Path(subprocess.check_output(
        ['swift', 'build', '--show-bin-path'], cwd=astrology, text=True).strip()).resolve()
    if products != actual_products:
        raise ValueError('Objects must come from the freshly built production products directory')
    for script in ('generate-models.py', 'generate-time-table.py'):
        subprocess.run(['python3', str(ROOT/'Scripts'/script), '--check'], check=True)
    original = {(case, i): e for case, oracle in fixtures() for i, e in enumerate(oracle['events'])}
    module_map = ROOT/'Sources/CLibAstronomy/module.modulemap'
    probe = ROOT/'Scripts/accuracy/production-probe.swift'
    objects = [products/name for name in ('AstrologyKit.o', 'AstronomyKit.o', 'CLibAstronomy.o')]
    executable = output/'production-gate'
    subprocess.run(['swiftc', '-I', str(products), '-Xcc', f'-fmodule-map-file={module_map}',
                    str(probe), *map(str, objects), '-o', str(executable)], check=True)
    raw = output/'events.json'
    subprocess.run([str(executable), str(FIXTURES.resolve()), str(raw)], check=True,
                   env={**os.environ, 'ASTROLOGY_PROBE_DATE_ROTATION': '0',
                        'ASTROLOGY_PROBE_MODEL': 'integrated-production'}, stdout=subprocess.DEVNULL)
    events = json.loads(raw.read_text())
    rows = events['results']
    if len(rows) != 36 or any('error' in r for r in rows):
        raise ValueError('Production did not resolve exactly 36 events')
    if {(r['caseID'], r['eventIndex']) for r in rows} != set(original):
        raise ValueError('Changed event identities/count')
    for row in rows:
        if row['identity'] != original[(row['caseID'], row['eventIndex'])]:
            raise ValueError('Frozen event reference changed')
        row['passesConvergence'] = row['bracketWidthSeconds'] <= 1 and abs(row['localResidual']) <= (
            1e-6 if row['kind'] == 'station' else 1e-4)
    passed = all(r['passes60SecondReferenceGate'] and r['passesConvergence'] for r in rows)
    def sources(repository):
        return {str(p.relative_to(repository)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted((repository/'Sources').rglob('*')) if p.is_file()}
    report = {'purpose': __doc__, 'passed': passed, 'events': events,
              'astronomyRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'astrologyRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=astrology, text=True).strip(),
              'astronomySourceSHA256': sources(ROOT), 'astrologySourceSHA256': sources(astrology),
              'inputSHA256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*objects, module_map, probe]},
              'compiler': subprocess.check_output(['swiftc', '--version'], text=True).strip()}
    (output/'acceptance.json').write_text(json.dumps(report, indent=2)+'\n')
    print('Integrated production:', len(rows), 'events; maximum timing difference:',
          max(r['absoluteTimeErrorSeconds'] for r in rows), 'seconds; passed:', passed)
    if not passed:
        raise SystemExit('Production acceptance gate failed')


if __name__ == '__main__':
    main()
