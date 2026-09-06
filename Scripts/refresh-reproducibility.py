#!/usr/bin/env python3
"""Refresh every bit golden from one run after independent production acceptance.

Writes a before/after numeric audit. Test instrumentation is restored even when
compilation or capture fails. This does not generate astronomical references.
"""
import argparse
import json
import hashlib
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TEST = ROOT/'Tests/AstronomyKitTests/ReproducibilityTests.swift'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--acceptance', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    acceptance = json.loads(args.acceptance.read_text())
    if not acceptance.get('passed') or len(acceptance['events']['results']) != 36:
        raise ValueError('A passing integrated production gate is required')
    for relative, checksum in acceptance['astronomySourceSHA256'].items():
        if hashlib.sha256((ROOT/relative).read_bytes()).hexdigest() != checksum:
            raise ValueError(f'Production acceptance is stale for {relative}; rerun it first')
    original = TEST.read_text()
    expressions = re.compile(r'([\w.]+(?:\([^()]*\))?) == Self.exact\(([^)]+)\)')
    instrumented = expressions.sub(r'recordValue(\1, expected: \2) == Self.exact(\2)', original)
    if instrumented == original:
        raise ValueError('No golden comparisons instrumented')
    marker = '    // MARK: - Comparison Helpers'
    instrumented = instrumented.replace(marker, '''    private func recordValue(_ value: Double, expected: UInt64) -> Double {
        print("GOLDEN \\(expected) \\(value.bitPattern)")
        return value
    }

'''+marker)
    try:
        TEST.write_text(instrumented)
        result = subprocess.run(['swift', 'test', '--filter', 'ReproducibilityTests'], cwd=ROOT,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    finally:
        TEST.write_text(original)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/'capture.log').write_text(result.stdout)
    values = {}
    for old, new in re.findall(r'GOLDEN (\d+) (\d+)', result.stdout):
        old, new = int(old), int(new)
        if old in values and values[old] != new:
            raise ValueError('A repeated old constant has distinct new values; capture needs site identities')
        values[old] = new
    literals = re.findall(r'0x[0-9a-fA-F_]+', original)
    if set(map(lambda s: int(s, 16), literals)) != set(values):
        raise ValueError('Golden capture did not exercise every constant')
    def replace(match):
        new = f'{values[int(match[0],16)]:016x}'
        return '0x'+'_'.join(new[i:i+4] for i in range(0, 16, 4))
    updated = re.sub(r'0x[0-9a-fA-F_]+', replace, original)
    # Exact decimals are in the audit; avoid leaving stale inline approximations.
    updated = re.sub(r'("[^"\n]+")  // (?:λ |RA |[0-9]).*', r'\1', updated)
    updated = updated.replace('The human-readable decimal appears in a\n//  trailing comment on each line purely for review; the bit pattern is the\n//  source of truth.', 'The before/after numeric audit records decimal values for review;\n//  the bit pattern is the source of truth.')
    updated = updated.replace('a musl/detmath update, or an upstream astronomy-engine resync.', 'a musl/detmath update, a physical-model or time-contract change, or an upstream resync.')
    audit = [{'beforeBits': f'{old:016x}', 'afterBits': f'{new:016x}',
              'before': struct.unpack('>d', old.to_bytes(8,'big'))[0],
              'after': struct.unpack('>d', new.to_bytes(8,'big'))[0]} for old,new in sorted(values.items())]
    (args.output/'goldens.json').write_text(json.dumps(audit, indent=2)+'\n')
    TEST.write_text(updated)
    print('Refreshed',len(literals),'constants;',sum(a['beforeBits']!=a['afterBits'] for a in audit),'changed unique values')


if __name__ == '__main__':
    main()
