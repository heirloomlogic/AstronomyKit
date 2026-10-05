#!/usr/bin/env python3
"""Compare current seasonal searches with retained epochs without relabeling history."""
import copy
import importlib.util
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("seasons", Path(__file__).with_name("qualify-seasonal-roots.py"))
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)

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


def check():
    saved = json.loads(S.REPORT.read_text())
    S.validate_report_semantics(saved)
    before = S.source_hashes()
    complete_before = complete_sources()
    binary_before = S.Q.digest(S.Q.BINARY.read_bytes())
    current = S.assess(S.Q.BINARY)
    S.validate_report_semantics(current)
    if complete_sources() != complete_before or S.source_hashes() != before or S.Q.digest(S.Q.BINARY.read_bytes()) != binary_before:
        raise ValueError('current seasonal inputs changed during execution')
    output = ROOT / ".context/current-seasonal-search.json"
    output.write_text(json.dumps(current, sort_keys=True, indent=2, allow_nan=False) + "\n")
    receipt = {'classification': 'current-seasonal-regression-not-original-historical-build', 'executionValidatorSHA256': S.Q.digest(Path(__file__).read_bytes()), 'actualSourceSHA256': current['inputSHA256'], 'completeCurrentSourceSHA256': complete_before, 'currentExecutionRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'actualPublicRunner': current['publicRunner'], 'rawAssessmentSHA256': S.Q.digest(output.read_bytes())}
    output.with_suffix('.receipt.json').write_text(json.dumps(receipt, sort_keys=True, indent=2, allow_nan=False) + '\n')
    validate_inputs(saved, current)
    normalized = copy.deepcopy(current)
    normalized['inputSHA256'] = saved['inputSHA256']
    S.validate_replay(saved, normalized)
    print(f"Current seasonal epoch/residual regression passed; actual current source and binary receipt: {output}")


if __name__ == '__main__':
    check()
