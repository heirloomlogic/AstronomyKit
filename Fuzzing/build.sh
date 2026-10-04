#!/bin/sh
# Builds the C bridge fuzz harness into .build/fuzz/.
#
#   sh Fuzzing/build.sh replay      .build/fuzz/replay-bridge: ASan + UBSan, plain main() that replays inputs
#   sh Fuzzing/build.sh libfuzzer   .build/fuzz/fuzz-bridge:   libFuzzer + ASan + UBSan
#
# CC selects the compiler (default clang). Apple clang has no libFuzzer runtime,
# so libfuzzer mode needs clang from LLVM (Linux, or Homebrew's llvm on macOS).
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
source_root="$repo_root/Sources/CLibAstronomy"
sanitizers=address,undefined
set -- "${1:-}" "$source_root/astronomy.c" "$source_root/ephemeris.c" "$source_root"/EphemerisTime/*.c "$script_dir/fuzz_bridge.c"

case "$1" in
    replay)
        output="$repo_root/.build/fuzz/replay-bridge"
        set -- "$@" "$script_dir/replay_main.c"
        ;;
    libfuzzer)
        output="$repo_root/.build/fuzz/fuzz-bridge"
        sanitizers="fuzzer,$sanitizers"
        ;;
    *)
        echo "usage: sh Fuzzing/build.sh replay|libfuzzer" >&2
        exit 2
        ;;
esac
shift

mkdir -p "$(dirname -- "$output")"

# -fno-sanitize-recover makes the first UBSan report abort, so it counts as a
# crash instead of scrolling past. Optimization stays low enough for useful
# stack traces; the engine's FP_CONTRACT pragma governs contraction as it
# does in the package build.
"${CC:-clang}" -std=c11 -O1 -g -fno-omit-frame-pointer -pthread \
    "-fsanitize=$sanitizers" -fno-sanitize-recover=undefined \
    "-I$source_root" "-I$source_root/include" \
    "$@" -lm -o "$output"

echo "$output"
