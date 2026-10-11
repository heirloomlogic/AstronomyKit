#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/bin" "$temporary_directory/Tests"

cat >"$temporary_directory/Tests/TimedSuites.swift" <<'SWIFT'
import Testing

@Suite("inverse", .timeLimit(.minutes(1)))
struct InverseRefractionTests {}

@Suite("search", .timeLimit(.minutes(1)))
struct SearchCallbackContractTests {}

@Suite("seasons", .timeLimit(.minutes(5)))
struct SeasonalEpochTests {}
SWIFT

cat >"$temporary_directory/bin/swift" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_SWIFT_LOG"
for argument in "$@"; do
    if [[ "$argument" == "list" ]]; then
        for index in {1..10}; do printf 'AstronomyKitTests.InverseRefractionTests/test%s()\n' "$index"; done
        for index in {1..18}; do printf 'AstronomyKitTests.SearchCallbackContractTests/test%s()\n' "$index"; done
        if [[ "${FAKE_LIST_MODE:-valid}" != "missing_suite" ]]; then
            for index in {1..4}; do printf 'AstronomyKitTests.SeasonalEpochTests/test%s()\n' "$index"; done
        fi
        if [[ "${FAKE_LIST_MODE:-valid}" != "missing_test" ]]; then
            printf '%s\n' 'AstronomyKitTests.DeltaTThreadSafetyTests/calculationKeepsCapturedModel()'
        fi
        printf '%s\n' 'AstronomyKitTests.DeltaTThreadSafetyTests/concurrentModelSwapIsSafe()'
        printf '%s\n' 'AstronomyKitTests.EngineStarConcurrencyTests/distinctStarsAndModelUpdates()'
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
        *SearchCallbackContractTests*) count=18 ;;
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
if ! "$script_directory/test-with-isolated-default-model.sh" --sanitize=address >"$temporary_directory/output.log" 2>&1; then
    cat "$temporary_directory/output.log" >&2
    echo "error: valid isolation wrapper control failed" >&2
    exit 1
fi
grep -Fq -- '--skip ' "$FAKE_SWIFT_LOG"
grep -Fq 'SeasonalEpochTests/' "$FAKE_SWIFT_LOG"

cat >"$temporary_directory/Tests/Unlisted.swift" <<'SWIFT'
import Testing
@Suite("unlisted", .timeLimit(.minutes(1)))
struct UnlistedTimedSuite {}
SWIFT
expect_failure "unlisted timed suite" "$script_directory/test-with-isolated-default-model.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: unlisted timed suite reached swift before manifest validation" >&2
    exit 1
fi
rm "$temporary_directory/Tests/Unlisted.swift"

cat >"$temporary_directory/Tests/Individual.swift" <<'SWIFT'
import Testing
@Test("individual", .timeLimit(.minutes(1)))
func individuallyTimed() {}
SWIFT
expect_failure "individual timed test" "$script_directory/test-with-isolated-default-model.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: individual timed test reached swift before manifest validation" >&2
    exit 1
fi
rm "$temporary_directory/Tests/Individual.swift"

cat >"$temporary_directory/Tests/Ambiguous.swift" <<'SWIFT'
import Testing
let unsupportedTraitShape = .timeLimit(.minutes(1))
SWIFT
expect_failure "unsupported time-limit trait shape" "$script_directory/test-with-isolated-default-model.sh" --sanitize=address
if [[ -s "$FAKE_SWIFT_LOG" ]]; then
    echo "error: unsupported time-limit trait reached swift before manifest validation" >&2
    exit 1
fi
rm "$temporary_directory/Tests/Ambiguous.swift"

expect_failure "missing timed suite selection" env FAKE_LIST_MODE=missing_suite "$script_directory/test-with-isolated-default-model.sh" --sanitize=address
if grep -Fq -- '--skip ' "$FAKE_SWIFT_LOG"; then
    echo "error: missing suite selection reached the main test run" >&2
    exit 1
fi

expect_failure "missing default-model selection" env FAKE_LIST_MODE=missing_test "$script_directory/test-with-isolated-default-model.sh" --sanitize=address
if grep -Fq -- '--skip ' "$FAKE_SWIFT_LOG"; then
    echo "error: missing default-model selection reached the main test run" >&2
    exit 1
fi

expect_failure "isolated failure propagation" env FAKE_FAIL_FILTER=SeasonalEpochTests "$script_directory/test-with-isolated-default-model.sh" --sanitize=address
grep -Fq 'SeasonalEpochTests/' "$FAKE_SWIFT_LOG"

echo "Sanitizer isolation wrapper controls passed"
