#!/usr/bin/env python3

import argparse
import hashlib
import json
import platform
import subprocess
from pathlib import Path


BASELINE_REVISION = "cdb533dbe85c76b39a958ca92f9155d8bd55b392"
UPSTREAM_REVISION = "826e26ff3a6dc03ee46658b1138fef582d96c5d9"
PREFIXES = (
    "Sources/CLibAstronomy/",
    "Scripts/model-data/",
    "Scripts/performance/polynomial/data/",
)
EXCLUDED = {"Sources/CLibAstronomy/generated/.gitattributes"}
BUILD_FLAGS = ["-std=c11", "-O3", "-DNDEBUG", "-fno-fast-math", "-ffp-contract=off", "-fno-ident"]
DRIVER_FILES = ("Tools/Migration/Oracle/oracle-main.c",)


def git(root, *arguments, text=False):
    return subprocess.check_output(["git", *arguments], cwd=root, text=text)


def tracked_paths(root):
    paths = git(root, "ls-tree", "-r", "--name-only", BASELINE_REVISION, text=True).splitlines()
    return sorted(path for path in paths if path.startswith(PREFIXES) and path not in EXCLUDED)


def object_hash(root, path):
    return hashlib.sha256(git(root, "show", f"{BASELINE_REVISION}:{path}")).hexdigest()


def first_line(command):
    return subprocess.check_output(command, text=True).splitlines()[0]


def current_environment():
    environment = {
        "os": platform.system(),
        "osVersion": platform.mac_ver()[0] or platform.release(),
        "architecture": platform.machine(),
        "compiler": first_line(["/usr/bin/clang", "--version"]),
        "swift": first_line(["swift", "--version"]),
    }
    if platform.system() == "Darwin":
        environment["xcode"] = first_line(["xcodebuild", "-version"])
    return environment


def lock(root, recorded_environment):
    paths = tracked_paths(root)
    return {
        "schemaVersion": 1,
        "sourceRepository": "https://github.com/heirloomlogic/AstronomyKit",
        "baselineRevision": BASELINE_REVISION,
        "upstreamRepository": "https://github.com/cosinekitty/astronomy",
        "upstreamRevision": UPSTREAM_REVISION,
        "files": {path: object_hash(root, path) for path in paths},
        "driverFiles": {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in DRIVER_FILES},
        "build": {
            "compiler": "/usr/bin/clang",
            "flags": BUILD_FLAGS,
            "linkLibraries": ["m", "pthread"],
            "fpContract": "off",
            "fastMath": False,
        },
        "recordedEnvironment": recorded_environment,
    }


def main():
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    output = Path(__file__).with_name("oracle-lock.json")
    if arguments.write:
        rendered = json.dumps(lock(root, current_environment()), indent=2, sort_keys=True) + "\n"
        output.write_text(rendered)
        print(f"Wrote {output.relative_to(root)}")
        return
    recorded = json.loads(output.read_text())
    rendered = json.dumps(lock(root, recorded["recordedEnvironment"]), indent=2, sort_keys=True) + "\n"
    if output.read_text() != rendered:
        raise SystemExit(f"{output.relative_to(root)} is stale; inspect the pinned revision before running {Path(__file__).name} --write")
    print(f"Verified {output.relative_to(root)}; environmentMatchesRecorded={current_environment() == recorded['recordedEnvironment']}")


if __name__ == "__main__":
    main()
