#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/bin" "$temporary_directory/Tests/OtherTarget" "$temporary_directory/Tests/AstronomyKitTests"
REAL_SWIFT="$(command -v swift)"
export REAL_SWIFT
printf 'struct Placeholder {}\n' >"$temporary_directory/Tests/OtherTarget/Placeholder.swift"

cat >"$temporary_directory/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "IsolationControls", targets: [
    .testTarget(name: "AstronomyKitTests"),
    .testTarget(name: "OtherTarget"),
])
SWIFT

cat >"$temporary_directory/Tests/AstronomyKitTests/TimedSuites.swift" <<'SWIFT'
import Testing

func topLevelRegex() { _ = /[}]/ }

@Suite("inverse", .timeLimit(.minutes(1)))
struct InverseRefractionTests {}

@Suite("search", .timeLimit(.minutes(1)))
struct SearchCallbackContractTests {}

@Suite("seasons", .timeLimit(.minutes(5)))
struct SeasonalEpochTests {}
SWIFT

# Changing the process default inside an exit test's child process is allowed.
cat >"$temporary_directory/Tests/AstronomyKitTests/ChildProcessWriter.swift" <<'SWIFT'
import Testing

@Test func childProcessWriter() async {
    await #expect(processExitsWith: .success) {
        AstronomyConfig.setDeltaTModel(.jplHorizons)
    }
}
SWIFT

cat >"$temporary_directory/bin/swift" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == package ]]; then
    if [[ "${FAKE_PACKAGE_MODE:-valid}" == failed ]]; then
        echo 'intentional package-description failure' >&2
        exit 47
    fi
    exec "$REAL_SWIFT" "$@"
fi
printf '%s\n' "$*" >>"$FAKE_SWIFT_LOG"
for argument in "$@"; do
    if [[ "$argument" == "list" ]]; then
        for index in {1..10}; do printf 'AstronomyKitTests.InverseRefractionTests/test%s()\n' "$index"; done
        for index in {1..17}; do printf 'AstronomyKitTests.SearchCallbackContractTests/test%s()\n' "$index"; done
        if [[ "${FAKE_LIST_MODE:-valid}" != "missing_suite" ]]; then
            for index in {1..4}; do printf 'AstronomyKitTests.SeasonalEpochTests/test%s()\n' "$index"; done
        fi
        exit 0
    fi
done
filter=""
while (($#)); do
    if [[ "$1" == "--filter" ]]; then
        filter="$2"
        break
    fi
    shift
done
if [[ -n "$filter" ]]; then
    if [[ -n "${FAKE_FAIL_FILTER:-}" && "$filter" == *"$FAKE_FAIL_FILTER"* ]]; then
        echo "intentional fake failure: $filter" >&2
        exit 23
    fi
    case "$filter" in
        *InverseRefractionTests*) count=10 ;;
        *SearchCallbackContractTests*) count=17 ;;
        *SeasonalEpochTests*) count=4 ;;
        *) count=1 ;;
    esac
    if [[ "$count" == 1 ]]; then
        echo "Test run with 1 test in 1 suite passed"
    else
        echo "Test run with $count tests in 1 suite passed"
    fi
    exit 0
fi
echo "Test run with 1 test in 1 suite passed"
FAKE
chmod +x "$temporary_directory/bin/swift"

export PATH="$temporary_directory/bin:$PATH"
export ASTRONOMYKIT_TEST_ISOLATION_ROOT="$temporary_directory/Tests"
export FAKE_SWIFT_LOG="$temporary_directory/swift.log"

expect_failure() {
    local label="$1"
    shift
    : >"$FAKE_SWIFT_LOG"
    if "$@" >"$temporary_directory/output.log" 2>&1; then
        echo "error: negative control unexpectedly passed: $label" >&2
        exit 1
    fi
}

: >"$FAKE_SWIFT_LOG"
if ! "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address >"$temporary_directory/output.log" 2>&1; then
    cat "$temporary_directory/output.log" >&2
    echo "error: valid isolation wrapper control failed" >&2
    exit 1
fi
grep -Fq -- '--skip ' "$FAKE_SWIFT_LOG"
grep -Fq 'SeasonalEpochTests/' "$FAKE_SWIFT_LOG"
# A process default change outside an exit test reaches suites running in parallel.
cat >"$temporary_directory/Tests/AstronomyKitTests/SharedProcessWriter.swift" <<'SWIFT'
import Testing

@Test func sharedProcessWriter() async {
    await #expect(processExitsWith: .success) {}
    AstronomyConfig.setDeltaTModel(.jplHorizons)
}
SWIFT
expect_failure "process default changed outside an exit test" "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: a shared-process default model write reached swift before validation" >&2
    exit 1
fi
grep -Fq 'SharedProcessWriter.swift:5' "$temporary_directory/output.log"
rm "$temporary_directory/Tests/AstronomyKitTests/SharedProcessWriter.swift"

# Directory names are not module names: a valid target may use a custom path.
cp "$temporary_directory/Package.swift" "$temporary_directory/Package.saved"
mv "$temporary_directory/Tests/AstronomyKitTests" "$temporary_directory/Tests/CustomDirectory"
python3 - "$temporary_directory/Package.swift" <<'PYTHON'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text().replace('.testTarget(name: "AstronomyKitTests")', '.testTarget(name: "AstronomyKitTests", path: "Tests/CustomDirectory")'))
PYTHON
if ! "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address >"$temporary_directory/output.log" 2>&1; then
    cat "$temporary_directory/output.log" >&2
    echo "error: valid custom target path was rejected" >&2
    exit 1
fi
mv "$temporary_directory/Tests/CustomDirectory" "$temporary_directory/Tests/AstronomyKitTests"
mv "$temporary_directory/Package.saved" "$temporary_directory/Package.swift"

cat >"$temporary_directory/Tests/OtherTarget/Unlisted.swift" <<'SWIFT'
import Testing
@Suite("unlisted", .timeLimit(.minutes(1)))
struct UnlistedTimedSuite {}
SWIFT
expect_failure "unlisted timed suite in another registered target" "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: another target's unlisted timed suite reached swift before manifest validation" >&2
    exit 1
fi
rm "$temporary_directory/Tests/OtherTarget/Unlisted.swift"

cat >"$temporary_directory/Tests/OtherTarget/Duplicate.swift" <<'SWIFT'
import Testing
@Suite("duplicate", .timeLimit(.minutes(1)))
struct InverseRefractionTests {}
SWIFT
expect_failure "duplicate timed suite owner" "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: duplicate timed suite owner reached swift before manifest validation" >&2
    exit 1
fi
rm "$temporary_directory/Tests/OtherTarget/Duplicate.swift"

# The correct target still lists ten untimed tests with the same suite name.
# A timed declaration in another module must not borrow that runtime selection.
cp "$temporary_directory/Tests/AstronomyKitTests/TimedSuites.swift" "$temporary_directory/TimedSuites.saved"
python3 - "$temporary_directory/Tests/AstronomyKitTests/TimedSuites.swift" <<'PYTHON'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text().replace(', .timeLimit(.minutes(1))', '', 1))
PYTHON
cat >"$temporary_directory/Tests/OtherTarget/Collision.swift" <<'SWIFT'
import Testing
@Suite("same name, different module", .timeLimit(.minutes(1)))
struct InverseRefractionTests {}
SWIFT
expect_failure "timed owner in another module borrows untimed suite selector" "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: target-owner collision reached Swift tests" >&2
    exit 1
fi
rm "$temporary_directory/Tests/OtherTarget/Collision.swift"
mv "$temporary_directory/TimedSuites.saved" "$temporary_directory/Tests/AstronomyKitTests/TimedSuites.swift"

# Resolve custom paths using the manifest, including sources outside Tests.
cp "$temporary_directory/Package.swift" "$temporary_directory/Package.saved"
mkdir -p "$temporary_directory/CustomTimedTarget"
cat >"$temporary_directory/CustomTimedTarget/Outside.swift" <<'SWIFT'
import Testing
@Suite("outside Tests", .timeLimit(.minutes(1)))
struct OutsideTimedSuite {}
SWIFT
python3 - "$temporary_directory/Package.swift" <<'PYTHON'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text().replace('.testTarget(name: "OtherTarget"),', '.testTarget(name: "OtherTarget"), .testTarget(name: "CustomTarget", path: "CustomTimedTarget"),'))
PYTHON
expect_failure "custom-path timed suite outside Tests" "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: custom-path timed suite reached Swift tests" >&2
    exit 1
fi
grep -Fq 'CustomTarget.OutsideTimedSuite' "$temporary_directory/output.log"
mv "$temporary_directory/Package.saved" "$temporary_directory/Package.swift"

# A nested suite cannot borrow the selector of an untimed top-level suite.
cp "$temporary_directory/Tests/AstronomyKitTests/TimedSuites.swift" "$temporary_directory/TimedSuites.saved"
python3 - "$temporary_directory/Tests/AstronomyKitTests/TimedSuites.swift" <<'PYTHON'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text().replace(', .timeLimit(.minutes(1))', '', 1))
PYTHON
cat >"$temporary_directory/Tests/AstronomyKitTests/Nested.swift" <<'SWIFT'
import Testing
func braceRegex() { _ = /[}]/ }
struct Container {
    @Suite("nested", .timeLimit(.minutes(1)))
    struct InverseRefractionTests {}
}
SWIFT
expect_failure "nested timed suite borrows a top-level selector" "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: nested timed suite reached Swift tests" >&2
    exit 1
fi
grep -Fq 'nested timed suites' "$temporary_directory/output.log"
rm "$temporary_directory/Tests/AstronomyKitTests/Nested.swift"
mv "$temporary_directory/TimedSuites.saved" "$temporary_directory/Tests/AstronomyKitTests/TimedSuites.swift"

expect_failure "SwiftPM ownership unavailable" env FAKE_PACKAGE_MODE=failed "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: unavailable SwiftPM ownership reached Swift tests" >&2
    exit 1
fi

cat >"$temporary_directory/Tests/Individual.swift" <<'SWIFT'
import Testing
@Test("individual", .timeLimit(.minutes(1)))
func individuallyTimed() {}
SWIFT
expect_failure "individual timed test" "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: individual timed test reached swift before manifest validation" >&2
    exit 1
fi
rm "$temporary_directory/Tests/Individual.swift"

cat >"$temporary_directory/Tests/Ambiguous.swift" <<'SWIFT'
import Testing
let unsupportedTraitShape = .timeLimit(.minutes(1))
SWIFT
expect_failure "unsupported time-limit trait shape" "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: unsupported time-limit trait reached swift before manifest validation" >&2
    exit 1
fi
rm "$temporary_directory/Tests/Ambiguous.swift"

expect_failure "missing timed suite selection" env FAKE_LIST_MODE=missing_suite "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
if grep -Fq -- '--skip ' "$FAKE_SWIFT_LOG"; then
    echo "error: missing suite selection reached the main test run" >&2
    exit 1
fi

expect_failure "isolated failure propagation" env FAKE_FAIL_FILTER=SeasonalEpochTests "$script_directory/test-with-isolated-timed-suites.sh" --sanitize=address
grep -Fq 'SeasonalEpochTests/' "$FAKE_SWIFT_LOG"

echo "Sanitizer isolation wrapper controls passed"
