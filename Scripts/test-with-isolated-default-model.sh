#!/usr/bin/env bash

set -euo pipefail

readonly isolated_tests=(
    "AstronomyKitTests.DeltaTThreadSafetyTests/calculationKeepsCapturedModel"
    "AstronomyKitTests.DeltaTThreadSafetyTests/concurrentModelSwapIsSafe"
    "AstronomyKitTests.EngineStarConcurrencyTests/distinctStarsAndModelUpdates"
)
readonly isolated_suites=(
    "AstronomyKitTests.InverseRefractionTests:10"
    "AstronomyKitTests.SearchCallbackContractTests:18"
)
isolated_identifiers=()
for test_name in "${isolated_tests[@]}"; do
    isolated_identifiers+=("${test_name##*/}")
done
for suite_entry in "${isolated_suites[@]}"; do
    suite_name="${suite_entry%%:*}"
    isolated_identifiers+=("${suite_name##*.}")
done
isolated_pattern="$(IFS='|'; echo "${isolated_identifiers[*]}")"
readonly isolated_pattern

swift test "$@" --skip "$isolated_pattern"

test_list="$(swift test "$@" --skip-build list)"
readonly test_list
for suite_entry in "${isolated_suites[@]}"; do
    suite_name="${suite_entry%%:*}"
    expected_tests="${suite_entry##*:}"
    matching_tests="$(grep -Fc "${suite_name}/" <<<"$test_list")"
    if [[ "$matching_tests" != "$expected_tests" ]]; then
        echo "error: isolated suite selector matched $matching_tests tests instead of $expected_tests: $suite_name" >&2
        exit 1
    fi
    output_file="$(mktemp)"
    if ! swift test "$@" --skip-build --filter "$suite_name" 2>&1 | tee "$output_file"; then
        rm -f "$output_file"
        exit 1
    fi
    if ! grep -Eq "Test run with ${expected_tests} tests? in 1 suite passed" "$output_file"; then
        echo "error: isolated suite invocation did not pass exactly $expected_tests tests: $suite_name" >&2
        rm -f "$output_file"
        exit 1
    fi
    rm -f "$output_file"
done
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
