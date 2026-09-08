#!/usr/bin/env python3
"""Check the manifest and actual SwiftPM compilation inputs, ignoring stale objects."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--configuration", choices=["debug", "release"], default="debug")
parser.add_argument("--build-path", type=Path, default=Path(".build"))
args = parser.parse_args()
configuration = args.configuration
package = json.loads(subprocess.check_output(["swift", "package", "describe", "--type", "json"], text=True))
target = next(t for t in package["targets"] if t["name"] == "CLibAstronomy")
assert set(target["sources"]) == {"astronomy.c", "ak_math.c"}, target["sources"]
# Xcode-backed SwiftPM links a combined object, excluding stale individual files.
combined = args.build_path / configuration / "CLibAstronomy.o"
objects = []
if combined.exists():
    objects = [combined]
else:
    plan = args.build_path / (configuration + ".yaml")
    assert plan.exists(), "Build/test the selected configuration before running this guard"
    for line in plan.read_text().splitlines():
        if "args:" not in line or '\"-c\"' not in line or "CLibAstronomy" not in line:
            continue
        command = json.loads(line.split("args:", 1)[1])
        source = command[command.index("-c") + 1]
        # Swift compilation also mentions CLibAstronomy's module map. Inspect
        # the C inputs, not every command importing that module.
        if Path(source).suffix != ".c":
            continue
        assert Path(source).name in {"astronomy.c", "ak_math.c"}, source
        assert "/detmath/" not in source, source
        objects.append(Path(command[command.index("-o") + 1]))
    assert len(objects) == 2, objects
symbols = "\n".join(subprocess.check_output(["nm", str(obj)], text=True) for obj in objects)
assert "ak___" not in symbols, "Deterministic kernel linked into the shipping target"
for name in ["sin", "cos", "tan", "asin", "acos", "atan", "atan2", "exp", "log10", "pow", "cbrt", "hypot"]:
    assert any(line.split()[-1].lstrip("_") == "ak_" + name and line.split()[-2].upper() == "T"
               for line in symbols.splitlines() if len(line.split()) >= 2), name
print(f"Native math guard passed ({configuration}): compatibility symbols present; no deterministic kernels")
