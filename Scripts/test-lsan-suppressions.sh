#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
readonly suppressions="$repo_root/.github/lsan-suppressions.txt"
scratch="$(mktemp -d)"
readonly scratch
trap 'rm -rf "$scratch"' EXIT

cat >"$scratch/static-data.swift" <<'SWIFT'
import Foundation

enum MoonDE441 {
    static let data = Data(base64Encoded: String(repeating: "QUFB", count: 349_526))!
}

print(MoonDE441.data.count)
SWIFT

swiftc -sanitize=address "$scratch/static-data.swift" -o "$scratch/static-data" >"$scratch/static-data-compile.log" 2>&1 || {
    cat "$scratch/static-data-compile.log" >&2
    exit 1
}
set +e
LSAN_OPTIONS="suppressions=$suppressions:print_suppressions=1" "$scratch/static-data" >"$scratch/static-data.out" 2>"$scratch/static-data.err"
static_status=$?
set -e
if [[ "$static_status" != 0 ]]; then
    cat "$scratch/static-data.err" >&2
    echo "error: generated static Data suppression did not allow a clean exit" >&2
    exit 1
fi
grep -Fxq "1048578" "$scratch/static-data.out" || {
    echo "error: generated static Data control did not decode the expected bytes" >&2
    exit 1
}
grep -Fq "MoonDE441O4data_WZ" "$scratch/static-data.err" || {
    echo "error: generated static Data control did not exercise its initializer suppression" >&2
    exit 1
}

cat >"$scratch/leak-helper.c" <<'C'
#include <stdlib.h>
#include <string.h>

static volatile unsigned char sink;

__attribute__((noinline)) void leak_memory(void) {
    void *pointer = malloc(1048576);
    memset(pointer, 42, 1048576);
    sink = ((unsigned char *)pointer)[0];
    __asm__ __volatile__("" : : "r"(pointer) : "memory");
}

__attribute__((noinline)) void scrub_stack(void) {
    volatile unsigned char bytes[65536];
    memset((void *)bytes, 0, sizeof(bytes));
    sink = bytes[0];
}
C

cat >"$scratch/unsuppressed-leak.swift" <<'SWIFT'
@_silgen_name("leak_memory")
func leakMemory()

@_silgen_name("scrub_stack")
func scrubStack()

@_silgen_name("__lsan_do_leak_check")
func checkLeaks()

leakMemory()
scrubStack()
checkLeaks()
SWIFT

clang -O1 -g -fsanitize=address -c "$scratch/leak-helper.c" -o "$scratch/leak-helper.o"
swiftc -sanitize=address "$scratch/unsuppressed-leak.swift" "$scratch/leak-helper.o" -o "$scratch/unsuppressed-leak" >"$scratch/unsuppressed-leak-compile.log" 2>&1 || {
    cat "$scratch/unsuppressed-leak-compile.log" >&2
    exit 1
}
set +e
LSAN_OPTIONS="suppressions=$suppressions:print_suppressions=1" "$scratch/unsuppressed-leak" >"$scratch/unsuppressed-leak.out" 2>"$scratch/unsuppressed-leak.err"
leak_status=$?
set -e
if [[ "$leak_status" == 0 ]]; then
    echo "error: independent unsuppressed leak was not detected" >&2
    exit 1
fi
grep -Fq "ERROR: LeakSanitizer: detected memory leaks" "$scratch/unsuppressed-leak.err" || {
    cat "$scratch/unsuppressed-leak.err" >&2
    echo "error: independent control failed for a reason other than LeakSanitizer" >&2
    exit 1
}
grep -Fq "Direct leak of 1048576 byte(s) in 1 object(s)" "$scratch/unsuppressed-leak.err" || {
    cat "$scratch/unsuppressed-leak.err" >&2
    echo "error: LeakSanitizer did not report the independent allocation" >&2
    exit 1
}
grep -Fq "SUMMARY: AddressSanitizer: 1048576 byte(s) leaked in 1 allocation(s)" "$scratch/unsuppressed-leak.err" || {
    cat "$scratch/unsuppressed-leak.err" >&2
    echo "error: independent leak summary was not exact" >&2
    exit 1
}

echo "LeakSanitizer suppression controls passed"
