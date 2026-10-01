#!/usr/bin/env python3

import hashlib
import io
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def first_line(command):
    return subprocess.check_output(command, text=True).splitlines()[0]


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: build-oracle.py OUTPUT_DIRECTORY")
    root = Path(__file__).resolve().parents[3]
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    lock = json.loads(Path(__file__).with_name("oracle-lock.json").read_text())
    revision = lock["baselineRevision"]
    with tempfile.TemporaryDirectory(prefix="astronomy-oracle-") as temporary:
        source_root = Path(temporary) / "source"
        source_root.mkdir()
        archive = subprocess.check_output(["git", "archive", revision, *lock["files"]], cwd=root)
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
            stream.extractall(source_root)
        mismatches = [path for path, digest in lock["files"].items() if sha256(source_root / path) != digest]
        if mismatches:
            raise SystemExit(f"oracle source hash mismatch: {', '.join(mismatches)}")
        compiler = os.environ.get("CC") or lock["build"]["compiler"]
        if not Path(compiler).exists():
            compiler = shutil.which("cc")
        if not compiler:
            raise SystemExit("no C compiler found")
        object_path = Path(temporary) / "astronomy.o"
        binary_path = output / "astronomy-oracle"
        engine = source_root / "Sources/CLibAstronomy"
        common = [compiler, *lock["build"]["flags"], "-I", str(engine / "include"), "-I", str(engine)]
        environment = dict(os.environ, SOURCE_DATE_EPOCH="0", ZERO_AR_DATE="1")
        subprocess.run(common + ["-c", str(engine / "astronomy.c"), "-o", str(object_path)], check=True, env=environment)
        link_flags = ["-lm", "-pthread"]
        subprocess.run(common + [str(Path(__file__).with_name("oracle-main.c")), str(object_path), *link_flags, "-o", str(binary_path)], check=True, env=environment)
        actual_environment = {
            "os": platform.system(),
            "osVersion": platform.mac_ver()[0] or platform.release(),
            "architecture": platform.machine(),
            "compiler": first_line([compiler, "--version"]),
        }
        metadata = {
            "schemaVersion": 1,
            "baselineRevision": revision,
            "sourceLockSha256": sha256(Path(__file__).with_name("oracle-lock.json")),
            "binarySha256": sha256(binary_path),
            "actualEnvironment": actual_environment,
            "recordedEnvironment": lock["recordedEnvironment"],
            "environmentMatchesRecorded": all(actual_environment[key] == lock["recordedEnvironment"][key] for key in actual_environment),
            "buildFlags": lock["build"]["flags"],
        }
        (output / "build-metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
        print(json.dumps(metadata, sort_keys=True))


if __name__ == "__main__":
    main()
