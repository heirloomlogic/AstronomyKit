#!/usr/bin/env python3
"""Focused Debug/sanitizer regressions. Full numerical coverage runs in Release on every PR."""
import argparse
from pathlib import Path
import re
import subprocess

# Whole suites deliberately include new regressions added to these owners. Keep
# exhaustive event censuses and measurement suites in qualification, not here.
# These suites have no Swift Testing time limits; the exhaustive ASan workflow
# retains test-with-isolated-default-model.sh for its timed-suite safeguards.
SUITES = tuple("AstronomyKitTests." + name for name in (
    "NativeSafetyTests",
    "DeltaTModelCaptureTests",
    "DeltaTThreadSafetyTests",
    "FixedStarConcurrencyTests",
    "ConstellationThreadSafetyTests",
    "PlutoThreadSafetyTests",
    "EngineStarConcurrencyTests",
    "EngineExactKeyTests",
    "EngineBoundedCacheTests",
    "EngineCacheRegistryTests",
    "EngineMoonCacheTests",
    "EngineVSOP87BCacheTests",
    "EngineNutationCacheTests",
))


def filter_pattern():
    return "^(" + "|".join(re.escape(suite) for suite in SUITES) + ")/"


def select_tests(inventory):
    for suite in SUITES:
        if not any(test.startswith(suite + "/") for test in inventory):
            raise ValueError(f"PR suite missing from Swift test discovery: {suite}")
    pattern = re.compile(filter_pattern())
    return [test for test in inventory if pattern.search(test)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitize", choices=("address", "thread"))
    parser.add_argument("--list", action="store_true", help="build and validate selection without executing tests")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    flags = [f"--sanitize={args.sanitize}"] if args.sanitize else []
    inventory = subprocess.check_output(["swift", "test", *flags, "list"], cwd=root, text=True).splitlines()
    selected = select_tests(inventory)
    print(f"PR selection: {len(selected)} tests in {len(SUITES)} suites", flush=True)
    if args.list:
        print("\n".join(selected))
        return
    # Serial suite execution protects process-wide state; the concurrency tests
    # still launch their own simultaneous callers inside each test.
    subprocess.run(["swift", "test", *flags, "--skip-build", "--no-parallel", "--filter", filter_pattern()], cwd=root, check=True)


if __name__ == "__main__":
    main()
