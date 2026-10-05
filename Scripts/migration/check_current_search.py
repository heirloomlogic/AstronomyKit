#!/usr/bin/env python3
"""Check repaired public callback behavior separately from retained historical traces."""
import argparse
from functools import lru_cache
import gzip
import importlib.util
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("callbacks", ROOT / "Scripts/migration/search_callback_corpus.py")
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)
PLAN = ROOT / "Tools/Migration/SearchRepair/protocol.json"
PROSPECTIVE = "ae52585219e6c5e64bdc75debdb179bfe3bbe46e"


def selection():
    if PLAN.read_bytes() != M.git_bytes(PROSPECTIVE, str(PLAN.relative_to(ROOT))):
        raise ValueError("repair regression selection changed")
    plan = json.loads(PLAN.read_text())
    for path, key in [(M.HOME / "protocol.json", "originalProtocolSHA256"), (M.HOME / "supplement.json", "supplementProtocolSHA256")]:
        if M.sha(path.read_bytes()) != plan[key]:
            raise ValueError("historical protocol changed")
    return plan


@lru_cache(maxsize=1)
def baseline_sources():
    revision = selection()['baseRevision']
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', revision, '--', 'Sources/AstronomyKit', 'Sources/CLibAstronomy'], cwd=ROOT, text=True).splitlines()
    return {path: M.sha(M.git_bytes(revision, path)) for path in paths}


def source_identity():
    actual = {str(p.relative_to(ROOT)): M.sha(p.read_bytes()) for scope in ("AstronomyKit", "CLibAstronomy") for p in sorted((ROOT / "Sources" / scope).rglob("*")) if p.is_file()}
    original = baseline_sources()
    changed = sorted(p for p in set(actual) | set(original) if actual.get(p) != original.get(p))
    if changed != selection()["sourceChangePopulation"]:
        raise ValueError("current source changes exceed the named solver repair")
    return actual


def load_supplement(directory=M.SUPPLEMENT):
    manifest_bytes = (directory / "manifest.json").read_bytes()
    if M.sha(manifest_bytes) != M.SUPPLEMENT_MANIFEST_SHA256:
        raise ValueError("supplement immutable identity changed")
    manifest = json.loads(manifest_bytes)
    expected = {"protocol.json", "build-receipt.json", "assessment.json", "raw-runs.json.gz", "collector.txt"}
    if set(manifest["filesSHA256"]) != expected or {p.name for p in directory.iterdir() if p.is_file()} != expected | {"manifest.json"}:
        raise ValueError("supplement artifact population changed")
    for name, digest in manifest["filesSHA256"].items():
        if M.sha((directory / name).read_bytes()) != digest:
            raise ValueError("supplement raw artifact detached")
    if (directory / "protocol.json").read_bytes() != (M.HOME / "supplement.json").read_bytes():
        raise ValueError("supplement archived selection changed")
    M.validate_receipt(json.loads((directory / "build-receipt.json").read_text()), M.SUPPLEMENT_REVISION)
    runs = json.loads(gzip.decompress((directory / "raw-runs.json.gz").read_bytes()))
    derived = M.assessment(runs, M.supplement_protocol()["cases"])
    if derived != json.loads((directory / "assessment.json").read_text()):
        raise ValueError("supplement saved derivation false")
    M.validate_supplement_branches(runs, M.supplement_protocol()["cases"])
    return runs


def compare(saved, current, cases):
    plan = selection()
    M.require_population([c["id"] for c in cases], [c["id"] for c in M.protocol()["cases"] + M.supplement_protocol()["cases"]])
    for model in M.protocol()["models"]:
        M.require_population([r["id"] for r in current[model]], [c["id"] for c in cases])
        for case, old, new in zip(cases, saved[model], current[model]):
            events = M.validate_run(new, case, model, "swift")
            M.validate_run(old, case, model, "swift")
            if case["id"] in plan["namedExpectedChanges"][model]:
                if events[-1].get("outcome") != plan["expectedOutcomeForNamedChanges"] or new["termination"] != "algorithm":
                    raise ValueError("named repair did not reject false success")
                # Start and end callbacks retain their exact selection and model behavior.
                if events[:3] != [json.loads(s) for s in old["stdout"].splitlines()][:3]:
                    raise ValueError("named repair changed input callbacks")
            else:
                compare_events([json.loads(s) for s in old["stdout"].splitlines()], events)
                for key in ("id", "exitCode", "termination"):
                    if type(old[key]) is not type(new[key]) or old[key] != new[key]:
                        raise ValueError("unchanged process result differs")
    return {model: plan["namedExpectedChanges"][model] for model in M.protocol()["models"]}


def compare_events(old, new, field=""):
    if isinstance(old, str) and (old.startswith("f64:") or old in ("nan", "+inf", "-inf")):
        tolerance = 1e-8 if field in ("ut", "tt", "expectedCapturedTT") else 1e-12
        if not packet_equal(old, new, tolerance):
            raise ValueError("unchanged numerical packet exceeds historical envelope")
    elif isinstance(old, dict):
        if not isinstance(new, dict) or set(old) != set(new):
            raise ValueError("unchanged event field population differs")
        for key in old:
            compare_events(old[key], new[key], key)
    elif isinstance(old, list):
        if not isinstance(new, list) or len(old) != len(new):
            raise ValueError("unchanged event population differs")
        for left, right in zip(old, new):
            compare_events(left, right, field)
    elif type(old) is not type(new) or old != new:
        raise ValueError("unchanged semantic field differs")


def packet_equal(old, new, tolerance):
    return isinstance(new, str) and M.close_packets(old, new, tolerance)


def build(work):
    identities = source_identity()
    package = work / "package"
    (package / "Sources/SearchResearch").mkdir(parents=True)
    for name in ("AstronomyKit", "CLibAstronomy"):
        (package / "Sources" / name).symlink_to(ROOT / "Sources" / name, target_is_directory=True)
    shutil.copyfile(M.HOME / "main.swift", package / "Sources/SearchResearch/main.swift")
    (package / "Package.swift").write_text(M.MANIFEST)
    lock = json.loads(M.LOCK.read_text())
    if M.sha(M.LOCK.read_bytes()) != M.protocol()["oracleLockSHA256"]:
        raise ValueError("oracle lock changed")
    flags = [v for flag in lock["build"]["flags"] for v in ("-Xcc", flag)]
    command = ["swift", "build", "--package-path", str(package), "--scratch-path", str(work / "build"), *flags]
    subprocess.run(command + ["--product", "SearchResearch"], check=True, cwd=ROOT)
    binpath = subprocess.check_output(command + ["--show-bin-path"], text=True, cwd=ROOT).strip()
    binary = Path(binpath) / "SearchResearch"
    if source_identity() != identities:
        raise ValueError("current sources changed during build")
    receipt = {"classification": "actual-current-public-build", "sourceSHA256": identities,
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "trackedTreeDirty": bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT)),
        "planSHA256": M.sha(PLAN.read_bytes()), "adapterSHA256": M.sha((M.HOME / "main.swift").read_bytes()),
        "manifestSHA256": M.sha(M.MANIFEST.encode()), "flags": lock["build"]["flags"], "binarySHA256": M.sha(binary.read_bytes()),
        "validatorSHA256": M.sha(Path(__file__).read_bytes()), "os": platform.system(),
        "swiftCompiler": subprocess.check_output(["swift", "--version"], text=True).splitlines()[0]}
    return binary, receipt


def check():
    selection()
    original, _, _ = M.load_archive()
    supplement = load_supplement()
    cases = M.protocol()["cases"] + M.supplement_protocol()["cases"]
    saved = {model: original[model]["swift"] + supplement[model]["swift"] for model in M.protocol()["models"]}
    with tempfile.TemporaryDirectory(prefix="current-search-", dir=ROOT / ".context") as directory:
        binary, receipt = build(Path(directory))
        current = {model: [{"id": case["id"], **M.run_command([str(binary), *M.arguments(case, model)], M.protocol()["bounds"]["subprocessTimeoutSeconds"])} for case in cases] for model in M.protocol()["models"]}
        output = ROOT / ".context/current-search-repair"
        output.mkdir(exist_ok=False)
        M.write_gzip(output / "raw-runs.json.gz", current)
        (output / "build-receipt.json").write_text(M.dumps(receipt))
        changes = compare(saved, current, cases)
        if source_identity() != receipt["sourceSHA256"]:
            raise ValueError("current sources changed during execution")
        report = {"classification": "current-public-finite-repair-regression", "processes": sum(map(len, current.values())), "namedChanges": changes,
            "partitions": selection()["historicalPartitions"], "rawSHA256": M.sha((output / "raw-runs.json.gz").read_bytes()), "actualBuildReceiptSHA256": M.sha((output / "build-receipt.json").read_bytes())}
        (output / "assessment.json").write_text(M.dumps(report))
        print(M.dumps(report))


if __name__ == "__main__":
    argparse.ArgumentParser(description=__doc__).parse_args()
    check()
