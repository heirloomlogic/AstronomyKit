#!/usr/bin/env python3
"""Fail closed when Swift Testing time-limit traits are not isolated by the sanitizer wrapper."""

import argparse
import pathlib
import re
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


def timed_declarations(path: pathlib.Path) -> tuple[list[str], list[str]]:
    source = path.read_text()
    clean = code_only(source)
    consumed: set[int] = set()
    suites: list[str] = []
    tests: list[str] = []
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
            declaration = re.match(r"\s*(?:(?:public|package|internal|private|fileprivate|final|indirect)\s+)*(?:struct|class|actor|enum)\s+([A-Za-z_][A-Za-z0-9_]*)\b", following)
            if not declaration:
                raise ValueError(f"{path}: timed @Suite must be followed directly by a named type declaration")
            suites.append(declaration.group(1))
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


def validate(root: pathlib.Path, expected: set[str]) -> None:
    discovered: set[str] = set()
    timed_tests: list[str] = []
    for path in sorted(root.rglob("*.swift")):
        try:
            suites, tests = timed_declarations(path)
        except ValueError as error:
            raise ValueError(f"cannot conservatively inventory timed tests: {error}") from error
        for name in suites:
            selector = f"AstronomyKitTests.{name}"
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
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    print(f"Verified {len(arguments.suite)} timed suites in the sanitizer isolation manifest")


if __name__ == "__main__":
    main()
