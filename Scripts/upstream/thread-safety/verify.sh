#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
negative_revision=42cc23924f404a4f35a4a3221dd8bf7ba8486da0
compiler=${CC:-clang}
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/astronomykit-thread-safety.XXXXXX")
if [ "${KEEP_TSAN_ARTIFACTS:-0}" = 1 ]; then
    trap 'echo "preserved ThreadSanitizer artifacts: $build_dir"' EXIT
else
    trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
fi

mkdir -p "$build_dir/patched/include" "$build_dir/unpatched/include" "$build_dir/logs"
cp "$repo_root/Sources/CLibAstronomy/astronomy.c" "$build_dir/patched/astronomy.c"
cp "$repo_root/Sources/CLibAstronomy/include/astronomy.h" "$build_dir/patched/include/astronomy.h"
cp "$repo_root/Sources/CLibAstronomy/polynomial.h" "$build_dir/patched/polynomial.h"
cp -R "$repo_root/Sources/CLibAstronomy/generated" "$build_dir/patched/generated"
git -C "$repo_root" show "$negative_revision:Sources/CLibAstronomy/astronomy.c" > "$build_dir/unpatched/astronomy.c"
git -C "$repo_root" show "$negative_revision:Sources/CLibAstronomy/include/astronomy.h" > "$build_dir/unpatched/include/astronomy.h"
python3 - "$build_dir/unpatched/astronomy.c" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
declarations = "    static astro_time_t epoch2000;\n    static astro_rotation_t rot = { ASTRO_NOT_INITIALIZED };\n"
global_declarations = "astro_time_t epoch2000;\nastro_rotation_t rot = { ASTRO_NOT_INITIALIZED };\n\n"
function_marker = "astro_constellation_t Astronomy_Constellation(double ra, double dec)\n"
needle = "    if (rot.status != ASTRO_SUCCESS)\n    {\n"
replacement = needle + "        extern void AstronomyKit_ConstellationRaceHook(void);\n        AstronomyKit_ConstellationRaceHook();\n"
if source.count(declarations) != 1 or source.count(function_marker) != 1 or source.count(needle) != 1:
    raise SystemExit("constellation initialization site changed")
source = source.replace(declarations, "")
source = source.replace(function_marker, global_declarations + function_marker)
path.write_text(source.replace(needle, replacement))
PY

compile_probe() {
    source_name=$1
    "$compiler" -std=c11 -O1 -g -fno-omit-frame-pointer -fsanitize=thread -pthread -I"$build_dir/$source_name/include" -c "$build_dir/$source_name/astronomy.c" -o "$build_dir/$source_name-astronomy.o"
    "$compiler" -std=c11 -O1 -g -Wall -Wextra -Werror -fno-omit-frame-pointer -fsanitize=thread -pthread -I"$build_dir/$source_name/include" -c "$script_dir/thread_safety_probe.c" -o "$build_dir/$source_name-probe.o"
    "$compiler" -fsanitize=thread -pthread "$build_dir/$source_name-astronomy.o" "$build_dir/$source_name-probe.o" -lm -o "$build_dir/$source_name-probe"
}

run_patched() {
    mode=$1
    log="$build_dir/logs/patched-$mode.log"
    if ! TSAN_OPTIONS="halt_on_error=1:exitcode=66" "$build_dir/patched-probe" "$mode" >"$log" 2>&1; then
        sed -n '1,160p' "$log" >&2
        echo "patched $mode probe failed" >&2
        return 1
    fi
    if grep -q "WARNING: ThreadSanitizer" "$log"; then
        sed -n '1,160p' "$log" >&2
        echo "patched $mode probe reported a race" >&2
        return 1
    fi
    echo "patched $mode: clean bounded run"
}

run_negative() {
    mode=$1
    expected=$2
    log="$build_dir/logs/unpatched-$mode.log"
    set +e
    TSAN_OPTIONS="halt_on_error=1:exitcode=66" "$build_dir/unpatched-probe" "$mode" >"$log" 2>&1
    status=$?
    set -e
    if [ "$status" -ne 0 ] && grep -q "WARNING: ThreadSanitizer" "$log" && grep -Eq "$expected" "$log"; then
        echo "unpatched $mode: expected race reproduced"
        return 0
    fi
    sed -n '1,200p' "$log" >&2
    echo "unpatched $mode did not produce the expected race report" >&2
    return 1
}

compile_probe patched
compile_probe unpatched

for mode in delta-t pluto counters constellation; do
    run_patched "$mode"
done

run_negative delta-t 'Astronomy_SetDeltaTFunction|TerrestrialTime|DeltaTFunc'
run_negative pluto 'Astronomy_Reset|GetSegment|CalcPluto|pluto_cache'
run_negative counters 'CalcMoon|_CalcMoonCount'
run_negative constellation 'Astronomy_Constellation|rot|epoch2000'

echo "ThreadSanitizer controls passed."
