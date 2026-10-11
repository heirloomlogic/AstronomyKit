#!/usr/bin/env bash

set -euo pipefail

readonly isolated_tests=(
    "AstronomyKitTests.DeltaTThreadSafetyTests/calculationKeepsCapturedModel"
    "AstronomyKitTests.DeltaTThreadSafetyTests/concurrentModelSwapIsSafe"
    "AstronomyKitTests.EngineStarConcurrencyTests/distinctStarsAndModelUpdates"
)
isolated_identifiers=()
for test_name in "${isolated_tests[@]}"; do
    isolated_identifiers+=("${test_name##*/}")
done
readonly isolated_pattern="$(IFS='|'; echo "${isolated_identifiers[*]}")"

swift test "$@" --skip "$isolated_pattern"

readonly test_list="$(swift test "$@" --skip-build list)"
for test_name in "${isolated_tests[@]}"; do
    if ! grep -Fqx "${test_name}()" <<<"$test_list"; then
        echo "error: isolated test not found: $test_name" >&2
        exit 1
    fi
    test_identifier="${test_name##*/}"
    matching_tests="$(grep -Fc "/${test_identifier}()" <<<"$test_list")"
    if [[ "$matching_tests" != 1 ]]; then
        echo "error: isolated selector is not unique: $test_identifier" >&2
        exit 1
    fi
    output_file="$(mktemp)"
    if ! swift test "$@" --skip-build --filter "$test_identifier" 2>&1 | tee "$output_file"; then
        rm -f "$output_file"
        exit 1
    fi
    if ! grep -Eq 'Test run with 1 test( |$)' "$output_file"; then
        echo "error: isolated invocation did not run exactly one test: $test_name" >&2
        rm -f "$output_file"
        exit 1
    fi
    rm -f "$output_file"
done
