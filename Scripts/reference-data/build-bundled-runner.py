#!/usr/bin/env python3
"""Bind the isolated production qualification executable to its source inputs."""
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / '.context/accuracy-qualification/bundled-runner-build.json'
spec = importlib.util.spec_from_file_location('accuracy_builder', Path(__file__).with_name('build-accuracy-runner.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    paths = [ROOT / 'Package.swift', Path(__file__), Path(builder.__file__)]
    for directory, patterns in [('Sources/AstronomyKit', ['*.swift']), ('Sources/CLibAstronomy', ['*.c', '*.h', '*.inc']), ('Tools/Migration/AccuracyQualificationRunner', ['*.swift'])]:
        for pattern in patterns:
            paths.extend((ROOT / directory).rglob(pattern))
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(set(paths))}


def toolchain():
    return {'swiftVersion': subprocess.check_output(['swift', '--version'], text=True, stderr=subprocess.STDOUT).strip()}


def validate(binary):
    report = json.loads(MANIFEST.read_bytes())
    if report['sourceSHA256'] != sources():
        raise ValueError('production runner source inputs changed after build')
    if report['toolchain'] != toolchain():
        raise ValueError('production runner toolchain changed after build')
    if report['executableSHA256'] != digest(binary):
        raise ValueError('production qualification executable differs from bound build')
    if report['buildManifestSHA256'] != digest(builder.PACKAGE / 'Package.swift'):
        raise ValueError('production runner build manifest changed')
    return report


def main():
    before = sources()
    compiler = toolchain()
    builder.main()
    if before != sources() or compiler != toolchain():
        raise ValueError('production runner source inputs changed during build')
    binary = builder.BUILD / 'debug/AccuracyQualificationRunner'
    report = {'schemaVersion': 2, 'toolchain': compiler, 'sourceSHA256': before, 'executableSHA256': digest(binary), 'buildManifestSHA256': digest(builder.PACKAGE / 'Package.swift'),
              'command': 'python3 Scripts/reference-data/build-bundled-runner.py'}
    MANIFEST.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
