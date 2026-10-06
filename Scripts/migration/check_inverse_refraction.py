#!/usr/bin/env python3
"""Run the finite #147 public probes in disposable, reaped processes."""
import argparse
import base64
import gzip
import hashlib
import io
import itertools
import json
import math
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
HOME = ROOT / "Tools/Migration/InverseRefraction147"
PROTOCOL = ROOT / "Documentation/Migration/inverse-refraction-147-protocol.json"
STRADDLE_PROTOCOL = ROOT / "Documentation/Migration/inverse-refraction-147-straddle-protocol.json"
TOOLS = [Path(__file__), HOME / "Probe.swift", HOME / "Package.swift.txt"]
EVIDENCE = HOME / "Evidence"
EVIDENCE_MANIFEST_SHA256 = "707c9dd4aaacbb9f808638da450fd83643776e846b76b08fb5a3a8c0a2a6ee0f"
REPAIR_EVIDENCE = HOME / "StraddleRepairEvidence"
REPAIR_MANIFEST_SHA256 = "1ab42acfcf6ade24af03972281c9c8d45a9921ac97c2c788db538d8f589c655a"
REGISTRATIONS = ((EVIDENCE, EVIDENCE_MANIFEST_SHA256, ("baseline", "initial-current", "current")),
                 (REPAIR_EVIDENCE, REPAIR_MANIFEST_SHA256, ("current", "straddle-pre-repair", "straddle-current")))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def dumps(value):
    return json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n"


def save(path, value):
    data = dumps(value).encode()
    if path.suffix == ".gz":
        data = gzip.compress(data, mtime=0)
    path.write_bytes(data)


def load(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == ".gz" else data)


def selection(protocol):
    cases = list(itertools.product(protocol["modes"], protocol["inputs"], protocol["routes"], protocol["models"]))
    if len(cases) != protocol["processesPerRevision"] or len(set(cases)) != len(cases):
        raise ValueError("case population differs")
    return cases


def kill_group(child):
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):  # Already exited; macOS reports EPERM for a zombie-only group.
        pass


def stop_on_signal(number, frame):
    raise SystemExit(128 + number)


def process(command, timeout, environment):
    """Run a child in its own session; every exit path kills its process group and reaps it."""
    start = time.monotonic()
    # The child's new session keeps terminal signals away from it, so the runner must stop it.
    handlers = {number: signal.signal(number, stop_on_signal) for number in (signal.SIGTERM, signal.SIGHUP)}
    try:
        with subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, env=environment, start_new_session=True) as child:
            termination = "process"
            try:
                out, err = child.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                kill_group(child)
                out, err = child.communicate(timeout=5)
                termination = "timeout-killed-and-reaped"
            except BaseException:
                kill_group(child)
                child.wait()
                raise
    finally:
        for number, handler in handlers.items():
            signal.signal(number, signal.SIG_DFL if handler is None else handler)
    return {"command": command, "termination": termination, "exitCode": child.returncode,
            "reaped": child.poll() is not None, "elapsedSeconds": time.monotonic() - start,
            "stdoutBase64": base64.b64encode(out).decode(), "stderrBase64": base64.b64encode(err).decode(),
            "stdoutSHA256": sha(out), "stderrSHA256": sha(err)}


def source_files(revision):
    archive = subprocess.check_output(["git", "archive", revision, "Sources/AstronomyKit", "Sources/CLibAstronomy", "Package.swift"], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        return {member.name: bundle.extractfile(member).read() for member in bundle if member.isfile()}


def input_files(revision):
    files = source_files(revision)
    original = files.pop("Package.swift")
    files["Package.swift"] = (HOME / "Package.swift.txt").read_bytes()
    files["Sources/InverseRefractionProbe/main.swift"] = (HOME / "Probe.swift").read_bytes()
    return files, sha(original)


def hashes(files):
    return {name: sha(data) for name, data in sorted(files.items())}


def acquire(output, revision, protocol_path=PROTOCOL):
    output.mkdir(parents=True, exist_ok=False)  # Reserve before any build or fresh process.
    protocol = load(protocol_path)
    cases = selection(protocol)
    tool_revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    tools = {path.relative_to(ROOT).as_posix(): path.read_bytes() for path in TOOLS + [protocol_path]}
    for name, data in tools.items():
        if data != subprocess.check_output(["git", "show", tool_revision + ":" + name], cwd=ROOT):
            raise ValueError("commit probe tooling before acquisition: " + name)
    revision = subprocess.check_output(["git", "rev-parse", revision], cwd=ROOT, text=True).strip()
    files, original_manifest = input_files(revision)
    package, scratch = output / "package", output / "build"
    for name, data in files.items():
        path = package / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    temporary = output / "tmp"
    temporary.mkdir()
    environment = {"PATH": os.defpath, "HOME": os.environ["HOME"], "TMPDIR": str(temporary), "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"}
    swift = shutil.which("swift")
    command = [swift, "build", "--package-path", str(package), "--scratch-path", str(scratch), "-c", protocol["configuration"], "--product", "InverseRefractionProbe", "--verbose"]
    build_packet = process(command, protocol["buildTimeoutSeconds"], environment)
    save(output / "build-process.json.gz", build_packet)
    if build_packet["exitCode"] != 0 or build_packet["termination"] != "process":
        raise ValueError("build failed; raw build packet retained")
    binary = scratch / protocol["configuration"] / "InverseRefractionProbe"
    receipt = {"sourceRevision": revision, "toolRevision": tool_revision, "toolSHA256": hashes(tools),
               "inputSHA256": hashes(files), "originalManifestSHA256": original_manifest,
               "generatedSHA256": {path.relative_to(scratch).as_posix(): sha(path.read_bytes()) for path in sorted(scratch.rglob("*")) if path.is_file() and path.suffix in {".swift", ".h", ".modulemap"}},
               "binaryPath": str(binary), "binarySHA256": sha(binary.read_bytes()), "buildCommand": command,
               "buildProcessSHA256": sha((output / "build-process.json.gz").read_bytes()),
               "swiftVersion": process([swift, "--version"], 10, environment), "environmentKeys": sorted(environment)}
    save(output / "build-receipt.json.gz", receipt)
    packets = []
    for case in cases:
        packet = {"case": list(case), **process([str(binary), *case], protocol["processTimeoutSeconds"], environment)}
        packets.append(packet)
        save(output / "raw-processes.json.gz", packets)  # Custody precedes parsing/assessment.
    if hashes({name: (package / name).read_bytes() for name in files}) != receipt["inputSHA256"] or sha(binary.read_bytes()) != receipt["binarySHA256"]:
        raise ValueError("inputs or executable changed during execution")
    return validate(output, protocol_path)


def registered_records():
    """Map each registered executable identity to the hashes of its immutable execution record."""
    registered = {}
    for directory, digest, labels in REGISTRATIONS:
        data = (directory / "manifest.json").read_bytes()
        if sha(data) != digest:
            raise ValueError("immutable execution authority differs")
        files = json.loads(data)["filesSHA256"]
        for label in labels:
            path = directory / label / "build-receipt.json.gz"
            if sha(path.read_bytes()) != files[label + "/build-receipt.json.gz"]:
                raise ValueError("registered build receipt differs")
            identity = load(path)["binarySHA256"]
            if identity in registered:
                raise ValueError("registered executable identity is ambiguous")
            registered[identity] = {name: files[label + "/" + name] for name in ("build-receipt.json.gz", "build-process.json.gz", "raw-processes.json.gz")}
    return registered


def validate(folder, protocol_path=PROTOCOL):
    protocol = load(protocol_path)
    receipt = load(folder / "build-receipt.json.gz")
    registered = registered_records()
    tools = {path.relative_to(ROOT).as_posix(): subprocess.check_output(["git", "show", receipt["toolRevision"] + ":" + path.relative_to(ROOT).as_posix()], cwd=ROOT) for path in TOOLS + [protocol_path]}
    if receipt["toolSHA256"] != hashes(tools) or tools[protocol_path.relative_to(ROOT).as_posix()] != protocol_path.read_bytes():
        raise ValueError("tool/protocol identity differs")
    original = source_files(receipt["sourceRevision"])
    original_manifest = sha(original.pop("Package.swift"))
    original["Package.swift"] = tools[(HOME / "Package.swift.txt").relative_to(ROOT).as_posix()]
    original["Sources/InverseRefractionProbe/main.swift"] = tools[(HOME / "Probe.swift").relative_to(ROOT).as_posix()]
    if receipt["inputSHA256"] != hashes(original) or receipt["originalManifestSHA256"] != original_manifest:
        raise ValueError("complete source/manifest population differs")
    build_path = folder / "build-process.json.gz"
    build = load(build_path)
    if sha(build_path.read_bytes()) != receipt["buildProcessSHA256"] or build["command"] != receipt["buildCommand"] or build["exitCode"] != 0 or not build["reaped"] or build["termination"] != "process":
        raise ValueError("build execution differs")
    binary = Path(receipt["binaryPath"])
    identity = sha(binary.read_bytes()) if binary.exists() else receipt["binarySHA256"]
    if identity in registered:
        for name, digest in registered[identity].items():
            if sha((folder / name).read_bytes()) != digest:
                raise ValueError("registered execution record detached: " + name)
    elif not binary.exists():
        raise ValueError("unregistered executable unavailable; historical execution is not authenticated")
    else:
        copied = {str(path.relative_to(folder / "package")): path.read_bytes() for path in (folder / "package/Sources").rglob("*") if path.is_file()}
        copied["Package.swift"] = (folder / "package/Package.swift").read_bytes()
        if hashes(copied) != receipt["inputSHA256"]:
            raise ValueError("fresh executable private source inputs detached")
        swift = shutil.which("swift")
        if receipt["buildCommand"] != [swift, "build", "--package-path", str(folder / "package"), "--scratch-path", str(folder / "build"), "-c", protocol["configuration"], "--product", "InverseRefractionProbe", "--verbose"]:
            raise ValueError("fresh build command differs from actual selected recipe")
        version = subprocess.check_output([swift, "--version"], env={"PATH": os.defpath, "HOME": os.environ["HOME"]})
        if base64.b64decode(receipt["swiftVersion"]["stdoutBase64"]) != version:
            raise ValueError("unregistered live compiler differs; no historical attestation")
    if binary.exists():
        if sha(binary.read_bytes()) != receipt["binarySHA256"]:
            raise ValueError("retained executable differs")
        scratch = binary.parent.parent
        generated = {path.relative_to(scratch).as_posix(): sha(path.read_bytes()) for path in sorted(scratch.rglob("*")) if path.is_file() and path.suffix in {".swift", ".h", ".modulemap"}}
        if generated != receipt["generatedSHA256"]:
            raise ValueError("actual generated build inputs differ")
    packets = load(folder / "raw-processes.json.gz")
    cases = selection(protocol)
    if [packet["case"] for packet in packets] != [list(case) for case in cases]:
        raise ValueError("ordered packet population differs")
    results = []
    for case, packet in zip(cases, packets):
        out, err = (base64.b64decode(packet[key + "Base64"], validate=True) for key in ("stdout", "stderr"))
        if sha(out) != packet["stdoutSHA256"] or sha(err) != packet["stderrSHA256"] or packet["command"] != [receipt["binaryPath"], *case] or not packet["reaped"]:
            raise ValueError("process custody/request differs")
        if packet["termination"] == "timeout-killed-and-reaped":
            if packet["exitCode"] != -signal.SIGKILL or out != b"entered\n":
                raise ValueError("timeout status differs")
            results.append(None)
        elif packet["termination"] == "process" and packet["exitCode"] == 0:
            lines = out.decode().splitlines()
            if len(lines) != 2 or lines[0] != "entered":
                raise ValueError("public payload framing differs")
            result = json.loads(lines[1])
            validate_payload(case, result)
            results.append(result)
        else:
            raise ValueError("public process failed; raw packet retained")
    return results


def check_registration(directory, digest):
    data = (directory / "manifest.json").read_bytes()
    if sha(data) != digest:
        raise ValueError("immutable measured execution manifest differs")
    manifest = json.loads(data)
    population = {str(path.relative_to(directory)) for path in directory.rglob("*") if path.is_file()}
    if population != set(manifest["filesSHA256"]) | {"manifest.json"}:
        raise ValueError("measured artifact population differs")
    for name, digest in manifest["filesSHA256"].items():
        if sha((directory / name).read_bytes()) != digest:
            raise ValueError("measured execution artifact differs: " + name)


def check_archive(directory=EVIDENCE):
    check_registration(directory, EVIDENCE_MANIFEST_SHA256)
    for current in ("initial-current", "current"):
        expected = load(directory / current / "assessment.json")
        actual = assess(directory / current, directory / "baseline", write=False)
        if actual != expected:
            raise ValueError("saved measured assessment differs")
    return {"recordedCurrentProofs": 2, "baselineProcesses": 312, "currentProcessesPerProof": 312, "baselineTimeouts": 68}


def check_repair_archive(directory=REPAIR_EVIDENCE):
    check_registration(directory, REPAIR_MANIFEST_SHA256)
    paired = load(directory / "current/assessment.json")
    straddle = load(directory / "straddle-current/assessment.json")
    if assess(directory / "current", EVIDENCE / "baseline", write=False) != paired or assess_straddle(directory / "straddle-current", directory / "straddle-pre-repair", write=False) != straddle:
        raise ValueError("saved measured assessment differs")
    try:
        assess_straddle(directory / "straddle-pre-repair", directory / "straddle-pre-repair", write=False)
    except ValueError as error:
        if str(error) != "straddle correction is not an adjacent converged inverse":
            raise
    else:
        raise ValueError("pre-repair straddle record meets the repaired expectation")
    return {"repairedSourceProcesses": paired["currentProcesses"], "successfulBaselinePayloadsExactlyMatched": paired["successfulBaselinePayloadsExactlyMatched"],
            "straddleProcessesPerRecord": straddle["currentProcesses"], "repairedStraddleProcesses": straddle["repairedStraddleProcesses"]}


def number(bits):
    if not isinstance(bits, str) or not 1 <= len(bits) <= 16 or any(character not in "0123456789abcdef" for character in bits):
        raise ValueError("invalid double bits")
    return struct.unpack(">d", int(bits, 16).to_bytes(8, "big"))[0]


def validate_payload(case, result):
    fields = {"mode", "input", "route", "model", "inputBits", "utBits", "ttBits", "finite"}
    fields.update({"correctionBits"} if case[2] == "direct" else {"vectorBits", "timePreserved"})
    if set(result) != fields or type(result["finite"]) is not bool:
        raise ValueError("payload field/type population differs")
    if [result[key] for key in ("mode", "input", "route", "model")] != list(case):
        raise ValueError("returned request differs")
    input_value = case[1]
    if ".next" in input_value:
        base, direction = input_value.split(".")
        expected = math.nextafter(float(base), math.inf if direction == "nextUp" else -math.inf)
    else:
        expected = float(input_value)
    actual = number(result["inputBits"])
    if not ((math.isnan(expected) and math.isnan(actual)) or struct.pack(">d", actual) == struct.pack(">d", expected)):
        raise ValueError("input double differs")
    if number(result["utBits"]) != 10000 or not math.isfinite(number(result["ttBits"])):
        raise ValueError("time payload differs")
    if case[2] == "direct":
        values = [number(result["correctionBits"])]
    else:
        if not isinstance(result["vectorBits"], list) or len(result["vectorBits"]) != 3 or type(result["timePreserved"]) is not bool:
            raise ValueError("vector payload differs")
        values = [number(value) for value in result["vectorBits"]]
    if result["finite"] != all(math.isfinite(value) for value in values):
        raise ValueError("saved finiteness differs")


def assess(current, baseline=None, write=True):
    results = validate(current)
    protocol = load(PROTOCOL)
    cases = selection(protocol)
    for case, result in zip(cases, results):
        if result is None or (case[2] == "direct" and not result["finite"]) or (case[2] == "horizon" and not result["timePreserved"]):
            raise ValueError("current termination/result expectation failed")
        if case[2] == "direct" and (case[1] in {"nan", "inf", "-inf", "-91", "91"} or case[0] == "none") and result["correctionBits"] != "0":
            raise ValueError("no-correction expectation failed")
    old = validate(baseline) if baseline else []
    if baseline and load(baseline / "build-receipt.json.gz")["sourceRevision"] != protocol["baselineRevision"]:
        raise ValueError("baseline revision differs")
    known_hangs = {("none", "nan"), ("normal", "nan"), ("jplHorizons", "nan"), ("normal", "90"), ("jplHorizons", "90"), ("jplHorizons", "-90")}
    for case, saved, result in zip(cases, old, results):
        if tuple(case[:2]) in known_hangs and saved is not None:
            raise ValueError("baseline known hang control did not fail")
        if saved is None and case[2] == "direct" and result["correctionBits"] != "0":
            raise ValueError("nonconvergent inverse did not return zero correction")
        if saved is not None and saved != result:
            raise ValueError("successful baseline payload changed")
    assessment = {"currentProcesses": len(results), "currentTimeouts": 0, "baselineProcesses": len(old),
                  "baselineTimeouts": old.count(None), "successfulBaselinePayloadsExactlyMatched": len(old) - old.count(None),
                  "currentReceiptSHA256": sha((current / "build-receipt.json.gz").read_bytes()),
                  "baselineReceiptSHA256": sha((baseline / "build-receipt.json.gz").read_bytes()) if baseline else None}
    if write:
        save(current / "assessment.json", assessment)
    return assessment


def straddle_neighbors(protocol):
    neighbors = {value: [repr(math.nextafter(float(value), direction)) for direction in (-math.inf, math.inf)] for value in protocol["straddles"]}
    if protocol["inputs"] != [name for value in protocol["straddles"] for name in [value, *neighbors[value]]]:
        raise ValueError("straddle population differs from its adjacent doubles")
    return neighbors


def assess_straddle(current, pre_repair, write=True):
    protocol = load(STRADDLE_PROTOCOL)
    neighbors = straddle_neighbors(protocol)
    cases = selection(protocol)
    if load(pre_repair / "build-receipt.json.gz")["sourceRevision"] != protocol["preRepairRevision"]:
        raise ValueError("pre-repair revision differs")
    saved = dict(zip(cases, validate(pre_repair, STRADDLE_PROTOCOL)))
    results = dict(zip(cases, validate(current, STRADDLE_PROTOCOL)))
    for case, result in results.items():
        if saved[case] is None or result is None or not result["finite"] or (case[2] == "horizon" and not result["timePreserved"]):
            raise ValueError("straddle termination/result expectation failed")
    for (mode, value, route, model), result in results.items():
        before = saved[(mode, value, route, model)]
        if mode != "normal" or value not in neighbors:
            if before != result:
                raise ValueError("payload outside the straddle repair changed")
        elif route == "direct":
            if before["correctionBits"] != "0":
                raise ValueError("pre-repair straddle did not return zero correction")
            if result["correctionBits"] == "0" or result["correctionBits"] not in {results[(mode, name, route, model)]["correctionBits"] for name in neighbors[value]}:
                raise ValueError("straddle correction is not an adjacent converged inverse")
        else:
            uncorrected = saved[("none", value, route, model)]["vectorBits"]
            if before["vectorBits"] != uncorrected:
                raise ValueError("pre-repair straddle vector was corrected")
            if result["vectorBits"] == uncorrected:
                raise ValueError("straddle vector kept zero correction")
    assessment = {"currentProcesses": len(results), "preRepairProcesses": len(saved), "repairedStraddleProcesses": len(neighbors) * len(protocol["routes"]) * len(protocol["models"]),
                  "unchangedPayloads": len(results) - len(neighbors) * len(protocol["routes"]) * len(protocol["models"]),
                  "currentReceiptSHA256": sha((current / "build-receipt.json.gz").read_bytes()),
                  "preRepairReceiptSHA256": sha((pre_repair / "build-receipt.json.gz").read_bytes())}
    if write:
        save(current / "assessment.json", assessment)
    return assessment


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--acquire", type=Path)
    parser.add_argument("--revision", default="HEAD")
    parser.add_argument("--current", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--check-archive", action="store_true")
    parser.add_argument("--straddle", action="store_true", help="Use the adjacent-double straddle protocol; --current then requires the pre-repair record as --baseline.")
    arguments = parser.parse_args()
    if arguments.check_archive:
        print(dumps({"initialMeasurements": check_archive(), "straddleRepair": check_repair_archive()}))
    elif arguments.acquire:
        acquire(arguments.acquire.resolve(), arguments.revision, STRADDLE_PROTOCOL if arguments.straddle else PROTOCOL)
    elif arguments.current and arguments.straddle:
        if not arguments.baseline:
            parser.error("--straddle --current requires the pre-repair record as --baseline")
        print(dumps(assess_straddle(arguments.current.resolve(), arguments.baseline.resolve())))
    elif arguments.current:
        print(dumps(assess(arguments.current.resolve(), arguments.baseline.resolve() if arguments.baseline else None)))
    else:
        parser.error("--acquire or --current is required")
