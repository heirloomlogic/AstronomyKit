#!/usr/bin/env python3
"""Compare current seasonal searches with retained epochs without relabeling history."""
import copy
import importlib.util
import json
import subprocess
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("seasons", Path(__file__).with_name("qualify-seasonal-roots.py"))
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)
BUILD_SPEC = importlib.util.spec_from_file_location("accuracy_build", Path(__file__).with_name("build-accuracy-runner.py"))
B = importlib.util.module_from_spec(BUILD_SPEC)
BUILD_SPEC.loader.exec_module(B)

def validate_inputs(saved, current):
    if current['inputSHA256'] != S.source_hashes():
        raise ValueError('current seasonal source map detached from actual files')
    changed = sorted(path for path in set(saved['inputSHA256']) | set(current['inputSHA256']) if saved['inputSHA256'].get(path) != current['inputSHA256'].get(path))
    if changed != ['Scripts/reference-data/qualify-seasonal-roots.py', 'Sources/CLibAstronomy/astronomy.c']:
        raise ValueError('current seasonal source changes exceed the named repair')
    validator_inputs = copy.deepcopy(current)
    validator_inputs['inputSHA256']['Sources/CLibAstronomy/astronomy.c'] = saved['inputSHA256']['Sources/CLibAstronomy/astronomy.c']
    S.validate_source_provenance(saved, validator_inputs, json.loads(S.REPLAY_RECEIPT.read_text()))


def complete_sources():
    return {str(path.relative_to(ROOT)): S.Q.digest(path.read_bytes()) for name in ('AstronomyKit', 'CLibAstronomy') for path in sorted((ROOT / 'Sources' / name).rglob('*')) if path.is_file()}


def runner_sources():
    return {str(path.relative_to(ROOT)): S.Q.digest(path.read_bytes()) for path in sorted((ROOT / 'Tools/Migration/AccuracyQualificationRunner').rglob('*')) if path.is_file()}


def build_current(work, output):
    source = complete_sources()
    adapter = runner_sources()
    package = work / 'package'
    (package / 'Sources').mkdir(parents=True)
    for name in ('AstronomyKit', 'CLibAstronomy'):
        shutil.copytree(ROOT / 'Sources' / name, package / 'Sources' / name)
    shutil.copytree(ROOT / 'Tools/Migration/AccuracyQualificationRunner', package / 'Sources/AccuracyQualificationRunner')
    snapshot = {str(path.relative_to(package)): S.Q.digest(path.read_bytes()) for path in sorted((package / 'Sources').rglob('*')) if path.is_file()}
    expected = dict(source)
    expected.update({path.replace('Tools/Migration/', 'Sources/', 1): digest for path, digest in adapter.items()})
    if snapshot != expected:
        raise ValueError('copied seasonal build inputs detached from actual files')
    (package / 'Package.swift').write_text(B.MANIFEST)
    command = ['swift', 'build', '--package-path', str(package), '--scratch-path', str(work / 'build')]
    log = output / 'build.log'
    with log.open('wb') as stream:
        subprocess.run(command + ['--product', 'AccuracyQualificationRunner', '--verbose'], cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True)
    binpath = subprocess.check_output(command + ['--show-bin-path'], cwd=ROOT, text=True).strip()
    binary = Path(binpath) / 'AccuracyQualificationRunner'
    after = {str(path.relative_to(package)): S.Q.digest(path.read_bytes()) for path in sorted((package / 'Sources').rglob('*')) if path.is_file()}
    if after != expected or complete_sources() != source or runner_sources() != adapter:
        raise ValueError('seasonal build inputs changed during build')
    receipt = {'classification': 'fresh-current-copied-source-build', 'completeCurrentSourceSHA256': source,
        'runnerSourceSHA256': adapter, 'manifestSHA256': S.Q.digest(B.MANIFEST.encode()),
        'buildRecipeSHA256': S.Q.digest(Path(__file__).read_bytes()), 'manifestProviderSHA256': S.Q.digest(Path(B.__file__).read_bytes()),
        'binarySHA256': S.Q.digest(binary.read_bytes()), 'buildLogSHA256': S.Q.digest(log.read_bytes()),
        'swiftCompiler': subprocess.check_output(['swift', '--version'], text=True).strip(),
        'flags': [], 'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()}
    validate_build_link(binary, receipt, package / 'Package.swift')
    return binary, receipt


def validate_build_link(binary, receipt, manifest=None):
    if receipt['classification'] != 'fresh-current-copied-source-build' or receipt['completeCurrentSourceSHA256'] != complete_sources() or receipt['runnerSourceSHA256'] != runner_sources():
        raise ValueError('seasonal executable/source linkage stale or detached')
    if receipt['manifestSHA256'] != S.Q.digest(B.MANIFEST.encode()) or receipt['buildRecipeSHA256'] != S.Q.digest(Path(__file__).read_bytes()) or receipt['manifestProviderSHA256'] != S.Q.digest(Path(B.__file__).read_bytes()) or receipt['flags'] != []:
        raise ValueError('seasonal build recipe detached')
    if manifest is not None and receipt['manifestSHA256'] != S.Q.digest(manifest.read_bytes()):
        raise ValueError('seasonal private build manifest detached')
    if receipt['binarySHA256'] != S.Q.digest(binary.read_bytes()):
        raise ValueError('seasonal executable changed after authenticated build')


def check():
    saved = json.loads(S.REPORT.read_text())
    S.validate_report_semantics(saved)
    (ROOT / '.context').mkdir(exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='current-seasonal-search-', dir=ROOT / '.context'))
    with tempfile.TemporaryDirectory(prefix='seasonal-build-', dir=ROOT / '.context') as directory:
        binary, build_receipt = build_current(Path(directory), output)
        (output / 'build-receipt.json').write_text(json.dumps(build_receipt, sort_keys=True, indent=2, allow_nan=False) + '\n')
        manifest = Path(directory) / 'package/Package.swift'
        validate_build_link(binary, build_receipt, manifest)
        before = S.source_hashes()
        current = S.assess(binary, manifest=manifest)
        # Keep the measured payload before assessment/validation can reject it.
        payload = output / 'assessment.json'
        payload.write_text(json.dumps(current, sort_keys=True, indent=2, allow_nan=False) + '\n')
        validate_build_link(binary, build_receipt, manifest)
        if S.source_hashes() != before:
            raise ValueError('current seasonal inputs changed during execution')
        S.validate_report_semantics(current)
        receipt = {'classification': 'current-seasonal-regression-not-original-historical-build', 'executionValidatorSHA256': S.Q.digest(Path(__file__).read_bytes()), 'actualSourceSHA256': current['inputSHA256'], 'completeCurrentSourceSHA256': build_receipt['completeCurrentSourceSHA256'], 'currentExecutionRevision': build_receipt['revision'], 'actualPublicRunner': current['publicRunner'], 'rawAssessmentSHA256': S.Q.digest(payload.read_bytes()), 'actualBuildReceiptSHA256': S.Q.digest((output / 'build-receipt.json').read_bytes())}
        (output / 'execution-receipt.json').write_text(json.dumps(receipt, sort_keys=True, indent=2, allow_nan=False) + '\n')
        validate_inputs(saved, current)
        normalized = copy.deepcopy(current)
        normalized['inputSHA256'] = saved['inputSHA256']
        S.validate_replay(saved, normalized)
        print(f"Current seasonal epoch/residual regression passed; authenticated fresh build and attempt: {output}")
    return output


if __name__ == '__main__':
    check()
