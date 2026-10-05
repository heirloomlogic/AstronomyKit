#!/usr/bin/env python3
"""Rebuild three retained experiments from their reviewed historical Git trees."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SUITES = {
    "callback": ("a06ce8653f7de3aed64bb4ce0509b1d10bc683ab", [
        [sys.executable, "-m", "unittest", "Scripts/migration/test_search_callback_corpus.py", "-v"],
        [sys.executable, "Scripts/migration/search_callback_corpus.py", "check"],
    ]),
    "constellation": ("97fc275f6fd455ed73063a6961698569783dddb8", [
        [sys.executable, "-m", "unittest", "Scripts/migration/test_constellation_corpus.py", "-v"],
        [sys.executable, "Scripts/migration/constellation-corpus.py", "check"],
    ]),
    "seasonal": ("2d54fd251a36e94f14324daed6d0937fc250d364", [
        [sys.executable, "Scripts/reference-data/build-accuracy-runner.py"],
        [sys.executable, "-m", "unittest", "Scripts/reference-data/test_seasonal_roots.py", "-v"],
        [sys.executable, "Scripts/reference-data/check-seasonal-public-runner.py"],
        [sys.executable, "Scripts/reference-data/qualify-seasonal-roots.py", "check"],
    ]),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def authenticate(checkout, revision):
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip()
    if actual != revision:
        raise ValueError("historical checkout revision changed")
    tree = subprocess.check_output(["git", "ls-tree", "-r", "-z", revision], cwd=checkout)
    identities = {}
    for entry in tree.split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, object_id = metadata.decode().split()
        path = name.decode()
        if kind != "blob":
            raise ValueError("unsupported historical tree entry")
        item = checkout / path
        data = os.readlink(item).encode() if mode == "120000" else item.read_bytes()
        git_hash = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if git_hash != object_id:
            raise ValueError(f"historical tracked file changed: {path}")
        identities[path] = sha(data)
    expected = {p for p in identities if p.startswith("Sources/")}
    found = {str(p.relative_to(checkout)) for p in (checkout / "Sources").rglob("*") if p.is_file()}
    if found != expected:
        raise ValueError("historical source population changed")
    return identities


def materialize(suite, destination):
    revision, _ = SUITES[suite]
    if destination.exists():
        authenticate(destination, revision)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "--shared", "--no-checkout", str(ROOT), str(destination)], check=True)
        subprocess.run(["git", "checkout", "--detach", revision], cwd=destination, check=True)
        authenticate(destination, revision)
    if suite == "seasonal":
        source = ROOT / ".context/accuracy-qualification/python-reference"
        target = destination / ".context/accuracy-qualification/python-reference"
        if not source.is_dir():
            raise ValueError("install the existing pinned independent reference dependencies first")
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(source, target)
    return destination


def replay(suite):
    revision, commands = SUITES[suite]
    checkout = materialize(suite, ROOT / ".context/historical-research" / suite)
    identities = authenticate(checkout, revision)
    logs = {}
    for index, command in enumerate(commands):
        log = checkout / f".context/historical-step-{index}.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("wb") as output:
            result = subprocess.run(command, cwd=checkout, stdout=output, stderr=subprocess.STDOUT)
        logs[str(index)] = {"command": command, "exitCode": result.returncode, "logSHA256": sha(log.read_bytes())}
        if result.returncode:
            raise RuntimeError(f"historical {suite} failed: {log}")
    if authenticate(checkout, revision) != identities:
        raise ValueError("historical tree changed during execution")
    receipt = {
        "classification": "historical-source-rebuild-not-current-production-validation",
        "suite": suite, "historicalRevision": revision,
        "currentDriverRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "currentDriverSHA256": sha(Path(__file__).read_bytes()),
        "historicalTrackedFilesSHA256": identities, "executions": logs,
    }
    if suite == "callback":
        measured = json.loads((checkout / ".context/search-replay.json").read_text())
        receipt["actualHistoricalBuildReceipt"] = measured["currentBuildReceipt"]
    output = ROOT / f".context/historical-{suite}-replay.json"
    output.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    print(f"Authenticated historical {suite} rebuild passed at {revision}; receipt: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", choices=SUITES)
    replay(parser.parse_args().suite)
