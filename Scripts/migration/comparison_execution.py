"""Bounded, isolated execution for the comparison replay experiment (#144)."""
import base64
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import platform
import subprocess
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PROTOCOL = ROOT / 'Documentation/Migration/comparison-replay-execution-protocol.json'
TOOL_PATHS = ('Scripts/migration/comparison_execution.py', 'Scripts/migration/run-comparison.py', 'Scripts/migration/replay_historical_research.py', 'Tools/Migration/Oracle/build-oracle.py', 'Tools/Migration/Oracle/build-oracle.sh')
ENVIRONMENT_MARKER = b'# comparison-build-environment '
RECIPE = {'configuration': 'release', 'product': 'AstronomyMigrationRunner', 'extraSwiftFlags': [], 'manifestConditions': {'.dev-tooling': False, '.model-prototype': False}}


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_json(data):
    def reject(value):
        raise ValueError(f'nonfinite JSON constant: {value}')
    def finite_float(value):
        number = float(value)
        if not math.isfinite(number):
            raise ValueError('nonfinite JSON number')
        return number
    return json.loads(data, parse_constant=reject, parse_float=finite_float)


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')


def tool_hashes():
    return {name: sha((ROOT / name).read_bytes()) for name in TOOL_PATHS}


def source_inputs(root):
    paths = [root / 'Package.swift']
    paths.extend(p for p in (root / 'Sources').rglob('*') if p.is_file())
    paths.extend(p for p in (root / 'Tools/Migration/SwiftRunner').rglob('*') if p.is_file())
    return {str(p.relative_to(root)): sha(p.read_bytes()) for p in sorted(paths)}


def generated_inputs(build_root):
    if build_root is None:
        return {}
    return {str(p.relative_to(build_root)): sha(p.read_bytes()) for p in sorted(build_root.rglob('*')) if p.is_file() and p.suffix in {'.swift', '.h', '.modulemap'}}


def validate_build(binary, receipt, source, package, expected_tools=None, build_root=None):
    expected = source_inputs(source)
    if receipt['sourceInputsSHA256'] != expected or source_inputs(package) != expected:
        raise ValueError('complete source input population or digest changed')
    if receipt['toolSHA256'] != (tool_hashes() if expected_tools is None else expected_tools):
        raise ValueError('mandatory execution tool population or digest changed')
    if receipt['recipe'] != RECIPE or any((package / name).exists() for name in RECIPE['manifestConditions']):
        raise ValueError('private build recipe or manifest conditions changed')
    if receipt['generatedInputsSHA256'] != generated_inputs(build_root):
        raise ValueError('generated private-build input population or digest changed')
    if receipt['binarySHA256'] != sha(binary.read_bytes()):
        raise ValueError('detached or stale executable')


def capture_environment(swift_command):
    captured = {}
    for name, command in [('swift', [swift_command, '--version']), ('platform', [sys.executable, '-c', 'import platform; print(platform.platform())'])]:
        completed = subprocess.run(command, capture_output=True, timeout=120)
        captured.update({name + 'Command': command, name + 'ExitCode': completed.returncode, name + 'StdoutBase64': base64.b64encode(completed.stdout).decode(), name + 'StderrBase64': base64.b64encode(completed.stderr).decode()})
    return captured


def select_current_environment():
    swift_command = shutil.which('swift')
    if swift_command is None:
        raise ValueError('no independently selected current Swift executable')
    return capture_environment(swift_command)


def validate_environment(receipt, log, attempt=None, binary_sha256=None):
    """Bind the receipt to retained bytes and corroborate its environment against the current runtime."""
    if attempt is not None and binary_sha256 is None:
        raise ValueError('retained executable digest required for execution authority')
    if binary_sha256 is not None and receipt.get('binarySHA256') != binary_sha256:
        raise ValueError('receipt detached from retained executable bytes')
    if not log.startswith(ENVIRONMENT_MARKER):
        raise ValueError('environment lacks current runtime capture')
    header, body = log.split(b'\n', 1)
    captured = read_json(header[len(ENVIRONMENT_MARKER):])
    required = {name + suffix for name in ('swift', 'platform') for suffix in ('Command', 'ExitCode', 'StdoutBase64', 'StderrBase64')}
    if set(captured) != required or any(type(captured[name + 'ExitCode']) is not int for name in ('swift', 'platform')):
        raise ValueError('environment capture population or termination type changed')
    selected = select_current_environment()
    if captured != selected:
        raise ValueError('environment capture detached from independently selected current runtime')
    identities = {}
    for name in ('swift', 'platform'):
        command = selected[name + 'Command']
        expected_tail = ['--version'] if name == 'swift' else ['-c', 'import platform; print(platform.platform())']
        if not isinstance(command, list) or not command or not isinstance(command[0], str) or not Path(command[0]).is_absolute() or command[1:] != expected_tail or type(selected[name + 'ExitCode']) is not int or selected[name + 'ExitCode'] != 0:
            raise ValueError('environment command or termination changed')
        stdout = base64.b64decode(selected[name + 'StdoutBase64'], validate=True).decode().strip()
        base64.b64decode(selected[name + 'StderrBase64'], validate=True)
        if not stdout:
            raise ValueError('environment command capture failed')
        identities[name] = stdout
    compiler_command = selected['swiftCommand'][0]
    if any(type(receipt.get(name)) is not str or receipt[name] != identities[name] for name in ('swift', 'platform')):
        raise ValueError('receipt compiler/platform identity detached from build evidence')
    if identities['swift'].splitlines()[0].encode() not in [line.strip() for line in body.splitlines()]:
        raise ValueError('captured compiler version absent from consumed compilation log')
    return compiler_command


def validate_request_result(packet, case):
    command = case['command']
    if not command or command[-1] not in {'espenak-meeus', 'jpl-horizons'}:
        raise ValueError('unsupported requested model')
    result = packet['result']
    if command[0] == 'invalid':
        if packet['exitCode'] != 64 or result is not None:
            raise ValueError('invalid request status/result changed')
        return
    if packet['exitCode'] != 0 or type(result) is not dict or result.get('model') != command[-1]:
        raise ValueError('returned model/process status detached from request')
    statuses = {'success', 'bad-time', 'invalid-body', 'invalid-parameter', 'astronomy-error', 'runner-error'}
    if type(result.get('status')) is not str or result['status'] not in statuses:
        raise ValueError('returned status is not a runner status')
    frozen = read_json((ROOT / 'Tools/Migration/Comparison/Artifacts/reference/c-output.json').read_bytes())['cases']
    for record in frozen:
        if record['command'] == command and result['status'] != record['result']['status']:
            raise ValueError('returned status detached from frozen finite request contract')


def validate_packet(packet, case):
    if packet['id'] != case['id'] or packet['command'] != case['command']:
        raise ValueError('packet selection or order changed')
    if type(packet['exitCode']) is not int or packet['termination'] != 'process':
        raise ValueError('execution did not terminate as a recorded process')
    for field in ('stdout', 'stderr'):
        raw = base64.b64decode(packet[field + 'Base64'], validate=True)
        if sha(raw) != packet[field + 'SHA256']:
            raise ValueError('raw packet digest changed')
    stdout = base64.b64decode(packet['stdoutBase64'])
    parsed = read_json(stdout) if stdout else None
    if json.dumps(parsed, sort_keys=True, allow_nan=False) != json.dumps(packet['result'], sort_keys=True, allow_nan=False):
        raise ValueError('saved result detached from raw stdout')
    validate_request_result(packet, case)


def records(packets, cases):
    if len(packets) != len(cases):
        raise ValueError('packet population changed')
    outputs = []
    for packet, case in zip(packets, cases):
        validate_packet(packet, case)
        outputs.append({'id': case['id'], 'command': case['command'], 'process': {'exitCode': packet['exitCode'], 'stdoutSha256': packet['stdoutSHA256'], 'stderr': base64.b64decode(packet['stderrBase64']).decode(), 'parseError': None}, 'result': packet['result']})
    return outputs


def original_reproduction_passes(sampled_match, fingerprint_match, original_closure_recorded):
    return sampled_match is True and fingerprint_match is True and original_closure_recorded is True


def reserve(output, mode):
    if output is None:
        parent = ROOT / '.context'
        parent.mkdir(exist_ok=True)
        return Path(tempfile.mkdtemp(prefix=f'comparison-{mode}-', dir=parent))
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    return output


def materialize(revision, destination):
    subprocess.run(['git', 'init', '-q', str(destination)], check=True)
    objects = Path(subprocess.check_output(['git', 'rev-parse', '--git-path', 'objects'], cwd=ROOT, text=True).strip())
    if not objects.is_absolute():
        objects = ROOT / objects
    (destination / '.git/objects/info/alternates').write_text(str(objects.resolve()) + '\n')
    subprocess.run(['git', 'checkout', '--detach', revision], cwd=destination, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return load(ROOT / 'Scripts/migration/replay_historical_research.py', 'historical_authentication').authenticate(destination, revision)


def capture(binary, case, timeout):
    try:
        completed = subprocess.run([str(binary), *case['command']], capture_output=True, timeout=timeout)
        stdout, stderr, code, termination = completed.stdout, completed.stderr, completed.returncode, 'process'
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code, termination = error.stdout or b'', error.stderr or b'', None, 'timeout'
    except OSError as error:
        stdout, stderr, code, termination = b'', str(error).encode(), None, 'launch-error'
    try:
        result = read_json(stdout) if stdout else None
        parse_error = None
    except (ValueError, UnicodeDecodeError) as error:
        result, parse_error = None, str(error)
    return {'id': case['id'], 'command': case['command'], 'stdoutBase64': base64.b64encode(stdout).decode(), 'stderrBase64': base64.b64encode(stderr).decode(), 'stdoutSHA256': sha(stdout), 'stderrSHA256': sha(stderr), 'exitCode': code, 'termination': termination, 'result': result, 'parseError': parse_error}


def compare(c, cases, first, second):
    comparisons, failed = [], []
    for case, left, right in zip(cases, first, second):
        differences = c.canonical_differences(left['result'], right['result'])
        if left['process']['exitCode'] != right['process']['exitCode']:
            differences.append({'path': '$.process.exitCode', 'expected': left['process']['exitCode'], 'actual': right['process']['exitCode'], 'kind': 'value'})
        item = {'id': case['id'], 'differenceCount': len(differences), 'differences': differences}
        if accepted := case.get('acceptedDifference'):
            item.update(acceptedDifference=accepted, accepted=c.comparison_passes(case, differences))
        comparisons.append(item)
        if not c.comparison_passes(case, differences):
            failed.append(case['id'])
    return comparisons, failed


def execute(mode, output=None):
    if mode not in ('historical', 'current'):
        raise ValueError('unknown execution mode')
    output = reserve(output, mode)  # Reserve custody before any fresh build or measurement.
    protocol = read_json(PROTOCOL.read_bytes())
    c = load(ROOT / 'Scripts/migration/run-comparison.py', 'comparison_contract')
    revision = protocol['historicalSelection'] if mode == 'historical' else subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    initial_tools = tool_hashes()
    tool_revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    save(output / 'attempt.json', {'mode': mode, 'sourceRevision': revision, 'protocolSHA256': sha(PROTOCOL.read_bytes()), 'toolSHA256': initial_tools, 'toolRevision': tool_revision})
    try:
        if initial_tools != {name: sha(c.git_blob(tool_revision, name)) for name in TOOL_PATHS} or PROTOCOL.read_bytes() != c.git_blob(tool_revision, str(PROTOCOL.relative_to(ROOT))):
            raise ValueError('acquisition tooling/protocol must match its committed receipt identity')
        archive = c.ARTIFACT_PATH
        if sha((archive / 'manifest.json').read_bytes()) != protocol['originalArchiveManifestSHA256'] or sha(c.ORACLE_LOCK_PATH.read_bytes()) != protocol['oracleLockSHA256']:
            raise ValueError('frozen archive or oracle selection changed')
        c.validate_archive(archive, read_json((archive / 'manifest.json').read_bytes()))
        corpus = read_json(c.CORPUS_PATH.read_bytes())
        c.validate_corpus(corpus)
        populations, selected = c.recover_populations(read_json(c.POPULATION_LOCK_PATH.read_bytes()))
        cases = corpus['cases'] + selected
        if {'schemaVersion': 1, 'cases': cases} != read_json((archive / 'inputs.json').read_bytes()) or populations != read_json((archive / 'downstream-populations.json').read_bytes()):
            raise ValueError('frozen input population changed')
        package = output / 'source'
        tracked = materialize(revision, package)
        if mode == 'current':
            load(ROOT / 'Scripts/migration/replay_historical_research.py', 'current_authentication').authenticate(ROOT, revision)
        metadata = read_json((archive / 'metadata.json').read_bytes())
        if mode == 'historical' and any(tracked.get(name) != value for name, value in metadata['sourceHashes'].items()):
            raise ValueError('selected historical source does not match recorded inputs')
        if protocol['recipe'] != RECIPE:
            raise ValueError('prospective recipe changed')
        swift_command = shutil.which('swift')
        if swift_command is None:
            raise ValueError('Swift compiler unavailable')
        environment = capture_environment(swift_command)
        command = [swift_command, 'build', '--package-path', str(package), '--scratch-path', str(output / 'build'), '-c', 'release', '--product', 'AstronomyMigrationRunner', '--verbose']
        with (output / 'swift-build.log').open('wb') as log:
            log.write(ENVIRONMENT_MARKER + json.dumps(environment, sort_keys=True, allow_nan=False).encode() + b'\n')
            log.flush()
            subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=protocol['buildTimeoutSeconds'])
        bin_path = subprocess.check_output([swift_command, 'build', '--package-path', str(package), '--scratch-path', str(output / 'build'), '-c', 'release', '--show-bin-path'], text=True).strip()
        binary = Path(bin_path) / 'AstronomyMigrationRunner'
        receipt = {'generatedInputsSHA256': generated_inputs(output / 'build'), 'sourceRevision': revision, 'sourceInputsSHA256': source_inputs(package), 'sourcePopulationMeaning': 'all project Sources plus public runner and actual manifest; includes conservative uncompiled optional sources', 'trackedTreeSHA256': tracked, 'toolSHA256': initial_tools, 'recipe': RECIPE, 'command': command, 'manifestSHA256': sha((package / 'Package.swift').read_bytes()), 'binaryRelativePath': str(binary.relative_to(output)), 'binarySHA256': sha(binary.read_bytes()), 'fingerprintSHA256': c.executable_fingerprint(binary), 'swift': base64.b64decode(environment['swiftStdoutBase64']).decode().strip(), 'platform': base64.b64decode(environment['platformStdoutBase64']).decode().strip(), 'buildLogSHA256': sha((output / 'swift-build.log').read_bytes())}
        save(output / 'candidate-build.json', receipt)
        validate_environment(receipt, (output / 'swift-build.log').read_bytes(), read_json((output / 'attempt.json').read_bytes()), sha(binary.read_bytes()))
        validate_build(binary, receipt, ROOT if mode == 'current' else package, package, build_root=output / 'build')
        with (output / 'oracle-build.log').open('wb') as log:
            subprocess.run([sys.executable, str(ROOT / 'Tools/Migration/Oracle/build-oracle.py'), str(output / 'oracle')], check=True, stdout=log, stderr=subprocess.STDOUT, timeout=protocol['buildTimeoutSeconds'])
        oracle = output / 'oracle/astronomy-oracle'
        oracle_hash = sha(oracle.read_bytes())
        save(output / 'oracle-build.json', read_json((output / 'oracle/build-metadata.json').read_bytes()))
        packets = {'frozenC': [], 'swiftCandidate': []}
        save(output / 'raw-processes.json', packets)
        for case in cases + [{'id': 'invalid-request-control', 'command': ['invalid', 'request', 'espenak-meeus']}]:
            for role, executable in [('frozenC', oracle), ('swiftCandidate', binary)]:
                packet = capture(executable, case, protocol['processTimeoutSeconds'])
                packets[role].append(packet)
                save(output / 'raw-processes.json', packets)  # Every packet precedes its assessment, including failures.
                if packet['termination'] != 'process' or packet['parseError'] is not None:
                    raise ValueError(f'non-successful acquisition: {case["id"]}/{role}')
        first, second = records(packets['frozenC'][:-1], cases), records(packets['swiftCandidate'][:-1], cases)
        for role in packets:
            validate_packet(packets[role][-1], {'id': 'invalid-request-control', 'command': ['invalid', 'request', 'espenak-meeus']})
            if packets[role][-1]['exitCode'] == 0:
                raise ValueError('invalid request unexpectedly succeeded')
            control_record = records([packets[role][-1]], [{'id': 'invalid-request-control', 'command': ['invalid', 'request', 'espenak-meeus']}])[0]
            if {name: value for name, value in control_record.items() if name != 'id'} != metadata['failureControls'][role]:
                raise ValueError('invalid-request archived control changed')
        validate_build(binary, receipt, ROOT if mode == 'current' else package, package, build_root=output / 'build')
        load(ROOT / 'Scripts/migration/replay_historical_research.py', 'post_execution_authentication').authenticate(package, revision)
        if sha(oracle.read_bytes()) != oracle_hash:
            raise ValueError('oracle executable changed during acquisition')
        if sha(PROTOCOL.read_bytes()) != read_json((output / 'attempt.json').read_bytes())['protocolSHA256']:
            raise ValueError('protocol changed during acquisition')
        report = assess(output, mode, revision, c, cases, first, second, receipt, metadata, protocol)
        save(output / 'assessment.json', report)
        return report
    except BaseException as error:
        save(output / 'failure.json', {'type': type(error).__name__, 'message': str(error), 'mode': mode, 'sourceRevision': revision, 'rawPacketsRetained': (output / 'raw-processes.json').exists()})
        raise


def assess(output, mode, revision, c, cases, first, second, receipt, metadata, protocol):
    comparisons, failed = compare(c, cases, first, second)
    sampled_match = first == read_json((c.ARTIFACT_PATH / 'c-output.json').read_bytes())['cases'] and second == read_json((c.ARTIFACT_PATH / 'swift-output.json').read_bytes())['cases']
    controls = c.negative_controls(first)
    original_diffs = read_json((c.ARTIFACT_PATH / 'diffs.json').read_bytes())
    if mode == 'historical' and sampled_match and (comparisons != original_diffs['comparisons'] or controls != original_diffs['negativeControls']):
        raise ValueError('original derived comparison semantics changed')
    fingerprint_match = receipt['fingerprintSHA256'] == metadata['executables']['swiftCandidate']['fingerprintSHA256']
    return {'classification': 'historical-executable-replay' if mode == 'historical' else 'current-executable-comparison', 'executionCompleted': True, 'sourceRevision': revision, 'evidenceDirectory': str(output), 'candidateBuildSHA256': sha((output / 'candidate-build.json').read_bytes()), 'rawProcessesSHA256': sha((output / 'raw-processes.json').read_bytes()), 'caseCount': len(cases), 'processCount': 2 * (len(cases) + 1), 'comparisons': comparisons, 'failed': failed, 'negativeControls': controls, 'scientificComparisonPassed': not failed, 'historicalSampledReplayPassed': sampled_match if mode == 'historical' else None, 'candidateFingerprintMatchesOriginal': fingerprint_match, 'originalCompleteClosureRecorded': False, 'originalReproductionPassed': original_reproduction_passes(sampled_match, fingerprint_match, False) if mode == 'historical' else None, 'originalIdentityLimit': protocol['originalClosureLimit']}


def verify_evidence(output):
    """Replay saved raw/derived semantics and authenticate the retained build inputs."""
    output = Path(output).resolve()
    c = load(ROOT / 'Scripts/migration/run-comparison.py', 'offline_comparison_contract')
    attempt = read_json((output / 'attempt.json').read_bytes())
    protocol_bytes = c.git_blob(attempt['toolRevision'], 'Documentation/Migration/comparison-replay-execution-protocol.json')
    if sha(protocol_bytes) != attempt['protocolSHA256']:
        raise ValueError('saved protocol detached from committed acquisition tools')
    protocol = read_json(protocol_bytes)
    if sha((c.ARTIFACT_PATH / 'manifest.json').read_bytes()) != protocol['originalArchiveManifestSHA256'] or sha(c.ORACLE_LOCK_PATH.read_bytes()) != protocol['oracleLockSHA256']:
        raise ValueError('frozen selection changed')
    c.validate_archive(c.ARTIFACT_PATH, read_json((c.ARTIFACT_PATH / 'manifest.json').read_bytes()))
    expected_tools = {name: sha(c.git_blob(attempt['toolRevision'], name)) for name in TOOL_PATHS}
    if attempt['toolSHA256'] != expected_tools or protocol['recipe'] != RECIPE or attempt['mode'] not in ('historical', 'current'):
        raise ValueError('mandatory committed tool identities, mode or recipe changed')
    revision = protocol['historicalSelection'] if attempt['mode'] == 'historical' else attempt['toolRevision']
    if attempt['sourceRevision'] != revision:
        raise ValueError('source selection changed')
    receipt = read_json((output / 'candidate-build.json').read_bytes())
    package = output / 'source'
    tracked = load(ROOT / 'Scripts/migration/replay_historical_research.py', 'offline_source_authentication').authenticate(package, revision)
    if receipt['sourceRevision'] != revision or receipt['trackedTreeSHA256'] != tracked:
        raise ValueError('build receipt source revision or tracked population changed')
    binary = (output / receipt['binaryRelativePath']).resolve()
    if not binary.is_relative_to((output / 'build').resolve()) or binary.name != RECIPE['product']:
        raise ValueError('binary location detached from isolated build')
    validate_build(binary, receipt, package, package, expected_tools, output / 'build')
    compiler_command = validate_environment(receipt, (output / 'swift-build.log').read_bytes(), attempt, sha(binary.read_bytes()))
    expected_command = [compiler_command, 'build', '--package-path', str(package), '--scratch-path', str(output / 'build'), '-c', 'release', '--product', 'AstronomyMigrationRunner', '--verbose']
    if receipt['command'] != expected_command or receipt['manifestSHA256'] != sha((package / 'Package.swift').read_bytes()) or receipt['buildLogSHA256'] != sha((output / 'swift-build.log').read_bytes()) or receipt['fingerprintSHA256'] != c.executable_fingerprint(binary):
        raise ValueError('build conditions, log or fingerprint changed')
    corpus = read_json(c.CORPUS_PATH.read_bytes())
    c.validate_corpus(corpus)
    populations, selected = c.recover_populations(read_json(c.POPULATION_LOCK_PATH.read_bytes()))
    cases = corpus['cases'] + selected
    if {'schemaVersion': 1, 'cases': cases} != read_json((c.ARTIFACT_PATH / 'inputs.json').read_bytes()) or populations != read_json((c.ARTIFACT_PATH / 'downstream-populations.json').read_bytes()):
        raise ValueError('case selection changed')
    metadata = read_json((c.ARTIFACT_PATH / 'metadata.json').read_bytes())
    if attempt['mode'] == 'historical' and any(tracked.get(name) != value for name, value in metadata['sourceHashes'].items()):
        raise ValueError('historical recorded source changed')
    packets = read_json((output / 'raw-processes.json').read_bytes())
    if set(packets) != {'frozenC', 'swiftCandidate'}:
        raise ValueError('runner population changed')
    control = {'id': 'invalid-request-control', 'command': ['invalid', 'request', 'espenak-meeus']}
    outputs = {role: records(items, cases + [control]) for role, items in packets.items()}
    if any(items[-1]['process']['exitCode'] == 0 for items in outputs.values()):
        raise ValueError('invalid request control passed')
    for role, original_role in [('frozenC', 'frozenC'), ('swiftCandidate', 'swiftCandidate')]:
        expected = metadata['failureControls'][original_role]
        actual = {name: value for name, value in outputs[role][-1].items() if name != 'id'}
        if actual != expected:
            raise ValueError('invalid-request archived control changed')
    oracle = output / 'oracle/astronomy-oracle'
    oracle_receipt = read_json((output / 'oracle-build.json').read_bytes())
    oracle_lock = read_json(c.ORACLE_LOCK_PATH.read_bytes())
    if oracle_receipt != read_json((output / 'oracle/build-metadata.json').read_bytes()) or oracle_receipt['binarySha256'] != sha(oracle.read_bytes()):
        raise ValueError('oracle build or binary detached')
    # The oracle builder verifies its exact locked files before each fresh compilation.
    if oracle_receipt['baselineRevision'] != oracle_lock['baselineRevision'] or oracle_receipt['sourceLockSha256'] != sha(c.ORACLE_LOCK_PATH.read_bytes()) or oracle_receipt['buildFlags'] != oracle_lock['build']['flags']:
        raise ValueError('oracle revision changed')
    recomputed = assess(output, attempt['mode'], revision, c, cases, outputs['frozenC'][:-1], outputs['swiftCandidate'][:-1], receipt, metadata, protocol)
    if read_json((output / 'assessment.json').read_bytes()) != recomputed:
        raise ValueError('saved assessment differs from raw/derived semantics')
    return recomputed
