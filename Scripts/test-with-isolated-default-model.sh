#!/usr/bin/env bash

set -euo pipefail

readonly timed_suites=(
    "AstronomyKitTests.InverseRefractionTests:10"
    "AstronomyKitTests.SearchCallbackContractTests:18"
    "AstronomyKitTests.SeasonalEpochTests:4"
)
readonly default_mutator_tests=(
    "AstronomyKitTests.DeltaTThreadSafetyTests/calculationKeepsCapturedModel"
    "AstronomyKitTests.DeltaTThreadSafetyTests/concurrentModelSwapIsSafe"
    "AstronomyKitTests.EngineStarConcurrencyTests/distinctStarsAndModelUpdates"
)
readonly skip_pattern='^(AstronomyKitTests\.(InverseRefractionTests|SearchCallbackContractTests|SeasonalEpochTests)/|AstronomyKitTests\.DeltaTThreadSafetyTests/(calculationKeepsCapturedModel|concurrentModelSwapIsSafe).*|AstronomyKitTests\.EngineStarConcurrencyTests/distinctStarsAndModelUpdates.*)'
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
readonly tests_root="${ASTRONOMYKIT_TEST_ISOLATION_ROOT:-${script_directory}/../Tests/AstronomyKitTests}"

manifest_arguments=()
for suite_entry in "${timed_suites[@]}"; do
    manifest_arguments+=(--suite "${suite_entry%%:*}")
done
python3 "${script_directory}/validate-test-isolation.py" --tests-root "$tests_root" "${manifest_arguments[@]}"

test_list="$(swift test "$@" list)"
readonly test_list
for suite_entry in "${timed_suites[@]}"; do
    suite_name="${suite_entry%%:*}"
    expected_tests="${suite_entry##*:}"
    matching_tests="$(awk -v prefix="${suite_name}/" 'index($0, prefix) == 1 { count++ } END { print count + 0 }' <<<"$test_list")"
    if [[ "$matching_tests" != "$expected_tests" ]]; then
        echo "error: timed suite selector matched $matching_tests tests instead of $expected_tests: $suite_name" >&2
        exit 1
    fi
done
for test_name in "${default_mutator_tests[@]}"; do
    matching_tests="$(awk -v expected="${test_name}()" '$0 == expected { count++ } END { print count + 0 }' <<<"$test_list")"
    if [[ "$matching_tests" != 1 ]]; then
        echo "error: isolated default-model selector matched $matching_tests tests instead of 1: $test_name" >&2
        exit 1
    fi
done

swift test "$@" --skip-build --skip "$skip_pattern"

for suite_entry in "${timed_suites[@]}"; do
    suite_name="${suite_entry%%:*}"
    expected_tests="${suite_entry##*:}"
    escaped_suite="${suite_name//./\\.}"
    output_file="$(mktemp)"
    if ! swift test "$@" --skip-build --filter "^${escaped_suite}/" 2>&1 | tee "$output_file"; then
        rm -f "$output_file"
        exit 1
    fi
    if ! grep -Eq "Test run with ${expected_tests} tests? in 1 suite passed" "$output_file"; then
        echo "error: isolated timed suite did not pass exactly $expected_tests listed tests: $suite_name" >&2
        rm -f "$output_file"
        exit 1
    fi
    rm -f "$output_file"
done
for test_name in "${default_mutator_tests[@]}"; do
    escaped_test="${test_name//./\\.}"
    output_file="$(mktemp)"
    if ! swift test "$@" --skip-build --filter "^${escaped_test}.*" 2>&1 | tee "$output_file"; then
        rm -f "$output_file"
        exit 1
    fi
    if ! grep -Eq 'Test run with 1 test( |$)' "$output_file"; then
        echo "error: isolated default-model invocation did not run exactly one test: $test_name" >&2
        rm -f "$output_file"
        exit 1
    fi
    rm -f "$output_file"
done
