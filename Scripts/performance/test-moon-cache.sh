#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
source_root="$repo_root/Sources/CLibAstronomy"
astronomy_source=${1:-"$source_root/astronomy.c"}
compiler=${CC:-cc}
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/astronomykit-moon-cache.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM

compile()
{
    "$compiler" -std=c11 -O2 -pthread \
        "-I$source_root" \
        "-I$source_root/include" \
        "$@"
}

cat > "$build_dir/rewrite.py" <<'PYTHON'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
output = Path(sys.argv[2])
mode = sys.argv[3]

if mode == "instrument":
    marker = """static void CalcMoonRaw(
    double centuries_since_j2000,
    double *geo_eclip_lon,      /* (LAMBDA) equinox of date */
    double *geo_eclip_lat,      /* (BETA)   equinox of date */
    double *distance_au)        /* (R) */
{"""
    replacement = marker + "\n    counted_calc_moon_raw();"
elif mode == "bypass":
    marker = "static moon_cache_entry_t *MoonCache(double t)\n{"
    replacement = marker + "\n    return NULL; /* diagnostic: bypass cache */"
else:
    raise ValueError(f"unknown rewrite mode: {mode}")

assert source.count(marker) == 1
output.write_text(source.replace(marker, replacement, 1))
PYTHON

cat > "$build_dir/count.h" <<'HEADER'
void counted_calc_moon_raw(void);
HEADER
python3 "$build_dir/rewrite.py" "$astronomy_source" "$build_dir/instrumented.c" instrument
compile -include "$build_dir/count.h" -c "$build_dir/instrumented.c" -o "$build_dir/astronomy.o"
compile -c "$script_dir/moon_cache_probe.c" -o "$build_dir/probe.o"
"$compiler" -pthread "$build_dir/astronomy.o" "$build_dir/probe.o" -lm -o "$build_dir/moon-cache-probe"
"$build_dir/moon-cache-probe"

python3 "$build_dir/rewrite.py" "$astronomy_source" "$build_dir/uncached.c" bypass
compile -c "$astronomy_source" -o "$build_dir/astronomy.o"
compile -c "$script_dir/moon_output_probe.c" -o "$build_dir/output-probe.o"
"$compiler" -pthread "$build_dir/astronomy.o" "$build_dir/output-probe.o" -lm -o "$build_dir/cached-output-probe"
"$build_dir/cached-output-probe" > "$build_dir/cached.out"
compile -c "$build_dir/uncached.c" -o "$build_dir/astronomy.o"
"$compiler" -pthread "$build_dir/astronomy.o" "$build_dir/output-probe.o" -lm -o "$build_dir/uncached-output-probe"
"$build_dir/uncached-output-probe" > "$build_dir/uncached.out"
cmp "$build_dir/cached.out" "$build_dir/uncached.out"
echo "Cached and bypassed Moon positions, rates, clients, and metadata are bit-identical."

python3 "$build_dir/rewrite.py" "$build_dir/uncached.c" "$build_dir/uncached-instrumented.c" instrument
compile -include "$build_dir/count.h" -c "$build_dir/uncached-instrumented.c" -o "$build_dir/astronomy.o"
"$compiler" -pthread "$build_dir/astronomy.o" "$build_dir/probe.o" -lm -o "$build_dir/moon-cache-probe"
negative_status=0
"$build_dir/moon-cache-probe" > "$build_dir/negative.log" 2>&1 || negative_status=$?
if [ "$negative_status" -ne 1 ]; then
    echo "ERROR: expected a cache assertion failure, got exit $negative_status" >&2
    cat "$build_dir/negative.log" >&2
    exit 1
fi
grep -F "MoonEclipticState did not reuse three lunar samples" "$build_dir/negative.log" > /dev/null
cat "$build_dir/negative.log"
echo "Cache probe rejected the bypassed negative control."
