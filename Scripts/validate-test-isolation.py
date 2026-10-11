#!/usr/bin/env python3
"""Fail closed when Swift Testing time-limit traits are not isolated by the sanitizer wrapper."""

import argparse
import json
import pathlib
import re
import subprocess
import sys


def code_only(source: str) -> str:
    """Blank comments and string literals while preserving offsets and newlines."""
    result = list(source)
    index = 0
    block_depth = 0
    while index < len(source):
        if block_depth:
            if source.startswith("/*", index):
                result[index:index + 2] = "  "
                block_depth += 1
                index += 2
            elif source.startswith("*/", index):
                result[index:index + 2] = "  "
                block_depth -= 1
                index += 2
            else:
                if source[index] != "\n":
                    result[index] = " "
                index += 1
            continue
        if source.startswith("//", index):
            stop = source.find("\n", index)
            stop = len(source) if stop < 0 else stop
            result[index:stop] = " " * (stop - index)
            index = stop
            continue
        if source.startswith("/*", index):
            result[index:index + 2] = "  "
            block_depth = 1
            index += 2
            continue
        if source.startswith('"""', index):
            stop = source.find('"""', index + 3)
            if stop < 0:
                raise ValueError("unterminated multiline string")
            stop += 3
            for position in range(index, stop):
                if source[position] != "\n":
                    result[position] = " "
            index = stop
            continue
        if source[index] == '"':
            stop = index + 1
            while stop < len(source):
                if source[stop] == "\\":
                    stop += 2
                elif source[stop] == '"':
                    stop += 1
                    break
                else:
                    stop += 1
            else:
                raise ValueError("unterminated string")
            result[index:stop] = " " * (stop - index)
            index = stop
            continue
        index += 1
    if block_depth:
        raise ValueError("unterminated block comment")
    return "".join(result)


def closing_parenthesis(source: str, opening: int) -> int:
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "(":
            depth += 1
        elif source[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("unterminated attribute argument list")


def top_level_types(path: pathlib.Path) -> set[tuple[int, int, str]]:
    """Use Swift's parser for scope; literals can contain arbitrary braces.

    Accept only the compiler's direct source-file children. The parse dump is
    deliberately fail-closed: an unfamiliar compiler format cannot prove that
    a timed declaration is top-level and requires updating this guard.
    """
    result = subprocess.run(
        ["swiftc", "-frontend", "-swift-version", "6", "-dump-parse", str(path)],
        capture_output=True, text=True, check=True,
    )
    pattern = (
        r'^  \((?:struct|class|enum)_decl\b[^\n]*\brange=\['
        + re.escape(str(path))
        + r':(\d+):(\d+) - [^\n]*\] "([^"\n]+)"'
    )
    return {(int(line), int(column), name) for line, column, name in re.findall(pattern, result.stdout, re.MULTILINE)}


def timed_declarations(path: pathlib.Path) -> tuple[list[str], list[str]]:
    source = path.read_text()
    clean = code_only(source)
    consumed: set[int] = set()
    suites: list[str] = []
    tests: list[str] = []
    parsed_types: set[tuple[int, int, str]] | None = None
    for attribute in re.finditer(r"@(Suite|Test)\b", clean):
        opening = attribute.end()
        while opening < len(clean) and clean[opening].isspace():
            opening += 1
        if opening >= len(clean) or clean[opening] != "(":
            continue
        closing = closing_parenthesis(clean, opening)
        occurrences = list(re.finditer(r"\.timeLimit\b", clean[opening:closing + 1]))
        if not occurrences:
            continue
        if len(occurrences) != 1:
            raise ValueError(f"{path}: timed attribute contains multiple .timeLimit traits")
        occurrence = opening + occurrences[0].start()
        consumed.add(occurrence)
        following = clean[closing + 1:]
        if attribute.group(1) == "Suite":
            declaration = re.match(r"\s*(?:(?:public|package|internal|private|fileprivate|final|indirect)\s+)*(?P<keyword>struct|class|actor|enum)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b", following)
            if not declaration:
                raise ValueError(f"{path}: timed @Suite must be followed directly by a named type declaration")
            if parsed_types is None:
                parsed_types = top_level_types(path)
            offset = closing + 1 + declaration.start("keyword")
            line = source.count("\n", 0, offset) + 1
            line_start = source.rfind("\n", 0, offset) + 1
            column = len(source[line_start:offset].encode("utf-8")) + 1
            name = declaration.group("name")
            if (line, column, name) not in parsed_types:
                raise ValueError(f"{path}:{line}: timed suite is not a compiler-verified top-level type; nested timed suites and unsupported parse shapes are not supported")
            suites.append(name)
        else:
            declaration = re.match(r"\s*(?:(?:public|package|internal|private|fileprivate|static|class|mutating|nonmutating)\s+)*func\s+([A-Za-z_][A-Za-z0-9_]*)\b", following)
            name = declaration.group(1) if declaration else "<unparsed>"
            tests.append(f"{path}:{name}")
    all_traits = {match.start() for match in re.finditer(r"\.timeLimit\b", clean)}
    unparsed = sorted(all_traits - consumed)
    if unparsed:
        line = clean.count("\n", 0, unparsed[0]) + 1
        raise ValueError(f"{path}:{line}: .timeLimit is outside the supported direct @Suite/@Test attribute shape")
    return suites, tests


def test_source_owners(root: pathlib.Path) -> dict[pathlib.Path, str]:
    """Resolve module ownership through SwiftPM, including custom source paths."""
    result = subprocess.run(
        ["swift", "package", "--package-path", str(root.parent), "describe", "--type", "json"],
        capture_output=True, text=True, check=True,
    )
    description = json.loads(result.stdout)
    package_root = pathlib.Path(description["path"])
    owners: dict[pathlib.Path, str] = {}
    for target in description["targets"]:
        if target["type"] != "test":
            continue
        module = target["c99name"]
        for source in target["sources"]:
            path = (package_root / target["path"] / source).resolve()
            if path.suffix != ".swift":
                continue
            if path in owners:
                raise ValueError(f"test source belongs to multiple targets: {path}")
            owners[path] = module
    return owners


def validate(root: pathlib.Path, expected: set[str]) -> None:
    root = root.resolve()
    owners = test_source_owners(root)
    discovered: set[str] = set()
    timed_tests: list[str] = []
    # Keep the full Tests-tree guard and include registered test sources outside
    # it. Never infer a module from a directory name or a matching runtime count.
    paths = {path.resolve() for path in root.rglob("*.swift")} | set(owners)
    for path in sorted(paths):
        try:
            suites, tests = timed_declarations(path)
        except ValueError as error:
            raise ValueError(f"cannot conservatively inventory timed tests: {error}") from error
        for name in suites:
            if path not in owners:
                raise ValueError(f"timed suite has no SwiftPM test target owner: {path}:{name}")
            selector = f"{owners[path]}.{name}"
            if selector in discovered:
                raise ValueError(f"duplicate timed suite declaration is ambiguous: {selector}")
            discovered.add(selector)
        timed_tests.extend(tests)
    if timed_tests:
        raise ValueError("individual @Test time limits are not supported by the sanitizer isolation manifest: " + ", ".join(timed_tests))
    missing = sorted(expected - discovered)
    unlisted = sorted(discovered - expected)
    if missing or unlisted:
        details = []
        if missing:
            details.append("manifest entries without a timed suite: " + ", ".join(missing))
        if unlisted:
            details.append("timed suites missing from the manifest: " + ", ".join(unlisted))
        raise ValueError("; ".join(details))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tests-root", type=pathlib.Path, required=True)
    parser.add_argument("--suite", action="append", default=[])
    arguments = parser.parse_args()
    try:
        validate(arguments.tests_root, set(arguments.suite))
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    print(f"Verified {len(arguments.suite)} timed suites in the sanitizer isolation manifest")


if __name__ == "__main__":
    main()
