import base64
import copy
import hashlib
import importlib.util
import json
import shutil
import tempfile
import unittest
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('comparison_execution', Path(__file__).with_name('comparison_execution.py'))
E = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(E)


def digest(data):
    return hashlib.sha256(data).hexdigest()


class ExecutionIntegrityTests(unittest.TestCase):
    def packet(self):
        case = {'id': 'sample', 'command': ['position', 'espenak-meeus']}
        stdout = b'{"model":"espenak-meeus","status":"success","value":1.0}\n'
        packet = {'id': 'sample', 'command': case['command'], 'stdoutBase64': base64.b64encode(stdout).decode(), 'stderrBase64': '', 'exitCode': 0, 'termination': 'process', 'result': json.loads(stdout), 'stdoutSHA256': digest(stdout), 'stderrSHA256': digest(b'')}
        return case, packet

    def test_raw_bytes_bind_saved_result_command_and_exit(self):
        case, packet = self.packet()
        E.validate_packet(packet, case)
        for field, value in [('result', {'status': 'bad-time'}), ('command', ['position', 'jpl-horizons']), ('stdoutSHA256', '0' * 64), ('exitCode', float('nan')), ('termination', 'timeout')]:
            changed = copy.deepcopy(packet)
            changed[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                E.validate_packet(changed, case)
        changed = copy.deepcopy(packet)
        raw = b'{"status":"success","value":NaN}'
        changed.update(stdoutBase64=base64.b64encode(raw).decode(), stdoutSHA256=digest(raw), result={'status': 'success', 'value': float('nan')})
        with self.assertRaises(ValueError):
            E.validate_packet(changed, case)

    def test_population_order_and_missing_extra_records_are_rejected(self):
        case, packet = self.packet()
        second_case = {**case, 'id': 'other'}
        second_packet = {**packet, 'id': 'other'}
        E.records([packet, second_packet], [case, second_case])
        for changed in [[packet], [packet, second_packet, packet], [second_packet, packet]]:
            with self.assertRaises(ValueError):
                E.records(changed, [case, second_case])

    def test_private_build_links_complete_inputs_recipe_tools_and_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            contents = {'Package.swift': b'manifest', 'Sources/AstronomyKit/Time.swift': b'time', 'Sources/CLibAstronomy/astronomy.c': b'engine', 'Sources/CLibAstronomy/generated/table.inc': b'coefficient', 'Tools/Migration/SwiftRunner/main.swift': b'runner'}
            for name, data in contents.items():
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            package = root / 'package'
            shutil.copytree(source, package)
            binary = root / 'runner'
            binary.write_bytes(b'fresh test executable')
            tools = {name: digest((ROOT / name).read_bytes()) for name in E.TOOL_PATHS}
            receipt = {'sourceInputsSHA256': {name: digest(data) for name, data in contents.items()}, 'toolSHA256': tools, 'recipe': {'configuration': 'release', 'product': 'AstronomyMigrationRunner', 'extraSwiftFlags': [], 'manifestConditions': {'.dev-tooling': False, '.model-prototype': False}}, 'binarySHA256': digest(binary.read_bytes())}
            E.validate_build(binary, receipt, source, package)
            for field, value in [('sourceInputsSHA256', {}), ('toolSHA256', {}), ('binarySHA256', '0' * 64), ('recipe', {'configuration': 'debug'})]:
                changed = copy.deepcopy(receipt)
                changed[field] = value
                with self.subTest(field=field), self.assertRaises(ValueError):
                    E.validate_build(binary, changed, source, package)
            generated = package / 'Sources/CLibAstronomy/generated/table.inc'
            generated.write_bytes(b'changed coefficient')
            with self.assertRaises(ValueError):
                E.validate_build(binary, receipt, source, package)
            generated.write_bytes(contents['Sources/CLibAstronomy/generated/table.inc'])
            binary.write_bytes(b'stale executable')
            with self.assertRaises(ValueError):
                E.validate_build(binary, receipt, source, package)

    def test_existing_destination_rejected_before_build_or_acquisition(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(E, 'materialize', side_effect=AssertionError('build started')), mock.patch.object(E, 'capture', side_effect=AssertionError('measurement started')):
            marker = Path(directory) / 'previous-evidence'
            marker.write_bytes(b'keep')
            with self.assertRaises(FileExistsError):
                E.execute('current', Path(directory))
            self.assertEqual(marker.read_bytes(), b'keep')

    def test_nonfinite_raw_packet_is_saved_before_assessment(self):
        case, _ = self.packet()
        completed = __import__('subprocess').CompletedProcess([], 0, stdout=b'{"value":1e999}', stderr=b'')
        with mock.patch.object(E.subprocess, 'run', return_value=completed):
            packet = E.capture(Path('/runner'), case, 1)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'raw.json'
            E.save(path, packet)
            saved = E.read_json(path.read_bytes())
            self.assertIsNone(saved['result'])
            self.assertTrue(saved['parseError'])
            self.assertEqual(base64.b64decode(saved['stdoutBase64']), b'{"value":1e999}')
            with self.assertRaises(ValueError):
                E.validate_packet(saved, case)

    def test_launch_failure_packet_remains_serializable_before_assessment(self):
        case, _ = self.packet()
        packet = E.capture(Path('/definitely/not/a/runner'), case, 1)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'raw.json'
            E.save(path, packet)
            saved = E.read_json(path.read_bytes())
            self.assertEqual(saved['termination'], 'launch-error')
            self.assertTrue(base64.b64decode(saved['stderrBase64']))
            with self.assertRaises(ValueError):
                E.validate_packet(saved, case)

    def test_rehashed_model_status_order_changes_remain_scientific_differences(self):
        c = E.load(ROOT / 'Scripts/migration/run-comparison.py', 'test_semantics')
        case, packet = self.packet()
        original = E.records([packet], [case])
        for field, value in [('model', 'jpl-horizons'), ('status', 'bad-time'), ('value', 2.0)]:
            changed = copy.deepcopy(packet)
            changed['result'][field] = value
            raw = json.dumps(changed['result']).encode()
            changed.update(stdoutBase64=base64.b64encode(raw).decode(), stdoutSHA256=digest(raw))
            records = E.records([changed], [case])
            differences, failed = E.compare(c, [case], original, records)
            self.assertEqual(failed, ['sample'])
            self.assertGreater(differences[0]['differenceCount'], 0)

    def test_old_archive_fingerprint_failure_is_not_normalized_away(self):
        self.assertFalse(E.original_reproduction_passes(sampled_match=True, fingerprint_match=False, original_closure_recorded=False))
        self.assertFalse(E.original_reproduction_passes(sampled_match=True, fingerprint_match=True, original_closure_recorded=False))
        self.assertFalse(E.original_reproduction_passes(sampled_match=False, fingerprint_match=True, original_closure_recorded=True))


if __name__ == '__main__':
    unittest.main()
