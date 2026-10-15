#!/usr/bin/env bash

set -euo pipefail

readonly timed_suites=(
    "AstronomyKitTests.InverseRefractionTests:10"
    "AstronomyKitTests.SearchCallbackContractTests:17"
    "AstronomyKitTests.SeasonalEpochTests:4"
)
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
readonly tests_root="${ASTRONOMYKIT_TEST_ISOLATION_ROOT:-${script_directory}/../Tests}"

selector_pattern() {
    local escaped_name="${1//./\\.}"
    local terminator="$2"
    printf '^%s%s' "$escaped_name" "$terminator"
}

count_matches() {
    local pattern="$1"
    grep -Ec -- "$pattern" <<<"$test_list" || true
}

manifest_arguments=()
for suite_entry in "${timed_suites[@]}"; do
    manifest_arguments+=(--suite "${suite_entry%%:*}")
done
python3 "${script_directory}/validate-test-isolation.py" --tests-root "$tests_root" "${manifest_arguments[@]}"

test_list="$(swift test "$@" list)"
readonly test_list
skip_alternatives=()
for suite_entry in "${timed_suites[@]}"; do
    suite_name="${suite_entry%%:*}"
    expected_tests="${suite_entry##*:}"
    suite_pattern="$(selector_pattern "$suite_name" '/')"
    matching_tests="$(count_matches "$suite_pattern")"
    if [[ "$matching_tests" != "$expected_tests" ]]; then
        echo "error: timed suite selector matched $matching_tests tests instead of $expected_tests: $suite_name" >&2
        exit 1
    fi
    skip_alternatives+=("${suite_pattern#^}")
done
skip_pattern="^($(IFS='|'; echo "${skip_alternatives[*]}"))"
readonly skip_pattern

swift test "$@" --skip-build --skip "$skip_pattern"

for suite_entry in "${timed_suites[@]}"; do
    suite_name="${suite_entry%%:*}"
    expected_tests="${suite_entry##*:}"
    suite_pattern="$(selector_pattern "$suite_name" '/')"
    output_file="$(mktemp)"
    if ! swift test "$@" --skip-build --filter "$suite_pattern" 2>&1 | tee "$output_file"; then
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
