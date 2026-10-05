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
TOOLS = [Path(__file__), HOME / "Probe.swift", HOME / "Package.swift.txt", PROTOCOL]


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


def process(command, timeout, environment):
    start = time.monotonic()
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=environment, start_new_session=True)
    termination = "process"
    try:
        out, err = child.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, err = child.communicate(timeout=5)
        termination = "timeout-killed-and-reaped"
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


def acquire(output, revision):
    output.mkdir(parents=True, exist_ok=False)  # Reserve before any build or fresh process.
    protocol = load(PROTOCOL)
    cases = selection(protocol)
    tool_revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    tools = {path.relative_to(ROOT).as_posix(): path.read_bytes() for path in TOOLS}
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
    return validate(output)


def validate(folder):
    protocol = load(PROTOCOL)
    receipt = load(folder / "build-receipt.json.gz")
    tools = {path.relative_to(ROOT).as_posix(): subprocess.check_output(["git", "show", receipt["toolRevision"] + ":" + path.relative_to(ROOT).as_posix()], cwd=ROOT) for path in TOOLS}
    if receipt["toolSHA256"] != hashes(tools) or tools[PROTOCOL.relative_to(ROOT).as_posix()] != PROTOCOL.read_bytes():
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
            if [result[key] for key in ("mode", "input", "route", "model")] != list(case):
                raise ValueError("returned request differs")
            validate_payload(case, result)
            results.append(result)
        else:
            raise ValueError("public process failed; raw packet retained")
    return results


def number(bits):
    if not isinstance(bits, str) or not 1 <= len(bits) <= 16 or any(character not in "0123456789abcdef" for character in bits):
        raise ValueError("invalid double bits")
    return struct.unpack(">d", int(bits, 16).to_bytes(8, "big"))[0]


def validate_payload(case, result):
    fields = {"mode", "input", "route", "model", "inputBits", "utBits", "ttBits", "finite"}
    fields.update({"correctionBits"} if case[2] == "direct" else {"vectorBits", "timePreserved"})
    if set(result) != fields or type(result["finite"]) is not bool:
        raise ValueError("payload field/type population differs")
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


def assess(current, baseline=None):
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
    save(current / "assessment.json", assessment)
    return assessment


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--acquire", type=Path)
    parser.add_argument("--revision", default="HEAD")
    parser.add_argument("--current", type=Path)
    parser.add_argument("--baseline", type=Path)
    arguments = parser.parse_args()
    if arguments.acquire:
        acquire(arguments.acquire.resolve(), arguments.revision)
    elif arguments.current:
        print(dumps(assess(arguments.current.resolve(), arguments.baseline.resolve() if arguments.baseline else None)))
    else:
        parser.error("--acquire or --current is required")
