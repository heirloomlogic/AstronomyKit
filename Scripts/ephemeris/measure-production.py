#!/usr/bin/env python3
"""Build and measure release public Swift state calls and process peak RSS."""
import importlib.util
import json
import platform
import re
import statistics
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'Documentation/Migration/bundled-production-costs.json'
WORK = ROOT / '.context/ephemeris-production-costs'
spec = importlib.util.spec_from_file_location('builder', ROOT / 'Scripts/reference-data/build-accuracy-runner.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def main():
    builder.PACKAGE = WORK / 'package'
    builder.BUILD = WORK / 'build'
    # Reuse the isolated source-link checks; replace only the evidence executable.
    builder.MANIFEST = builder.MANIFEST.replace('AccuracyQualificationRunner', 'BundledEphemerisCostRunner')
    sources = builder.PACKAGE / 'Sources'
    sources.mkdir(parents=True, exist_ok=True)
    for name, target in [('AstronomyKit', ROOT / 'Sources/AstronomyKit'), ('CLibAstronomy', ROOT / 'Sources/CLibAstronomy'), ('BundledEphemerisCostRunner', ROOT / 'Tools/Migration/BundledEphemerisCostRunner')]:
        link = sources / name
        if link.is_symlink() and link.resolve() != target.resolve():
            raise ValueError('cost runner source link drift')
        if not link.exists():
            link.symlink_to(target, target_is_directory=True)
    (builder.PACKAGE / 'Package.swift').write_text(builder.MANIFEST)
    subprocess.run(['swift', 'build', '-c', 'release', '--package-path', str(builder.PACKAGE), '--scratch-path', str(builder.BUILD), '--product', 'BundledEphemerisCostRunner'], cwd=ROOT, check=True)
    binary = builder.BUILD / 'release/BundledEphemerisCostRunner'
    if platform.system() != 'Darwin':
        raise ValueError('this descriptive RSS measurement requires macOS time -l')
    trials = {}
    for operation in ['baseline', 'moon', 'pluto']:
        trials[operation] = []
        for _ in range(5):
            result = subprocess.run(['/usr/bin/time', '-l', str(binary), operation], text=True, capture_output=True, check=True)
            row = json.loads(result.stdout)
            row['peakRSSBytes'] = int(re.search(r'(\d+)\s+maximum resident set size', result.stderr)[1])
            trials[operation].append(row)
    summary = {name: {'medianPeakRSSBytes': statistics.median(r['peakRSSBytes'] for r in rows),
                     'medianMicrosecondsPerStateIncludingTimeConstruction': statistics.median(r['elapsedNanoseconds'] / max(r['count'], 1) / 1000 for r in rows)} for name, rows in trials.items()}
    paths = [Path(__file__), ROOT / 'Tools/Migration/BundledEphemerisCostRunner/main.swift', ROOT / 'Sources/CLibAstronomy/astronomy.c', ROOT / 'Sources/CLibAstronomy/ephemeris.c'] + list((ROOT / 'Sources/CLibAstronomy/EphemerisData').glob('*.inc'))
    import hashlib
    report = {'classification': 'descriptive-local-release-public-API-cost-not-a-platform-or-hosted-performance-gate',
              'host': platform.platform(), 'swiftVersion': subprocess.check_output(['swift', '--version'], text=True).strip(),
              'binaryBytes': binary.stat().st_size, 'binarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
              'trials': trials, 'summary': summary,
              'limitations': ['Five new process trials per operation on one macOS host; no device or hosted RSS qualification.', 'Baseline launches the same executable without touching coefficient tables; RSS deltas are descriptive and do not isolate table mappings from framework/runtime allocations.', 'Each operation evaluates100000 distinct TT epochs spanning1900–2130, including AstroTime construction.']}
    OUTPUT.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps(summary, sort_keys=True))


if __name__ == '__main__':
    main()
