#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
source_root="$repo_root/Sources/CLibAstronomy"
astronomy_source=${1:-"$source_root/astronomy.c"}
compiler=${CC:-cc}
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/astronomykit-vsop-cache.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM

compile()
{
    "$compiler" -std=c11 -O2 \
        "-I$source_root" \
        "-I$source_root/include" \
        "$@"
}

# Interpose only in the engine translation unit, after declaring host math.
# The probe's wrappers count calls and forward to the real libm.
cat > "$build_dir/count.h" <<'HEADER'
#include <math.h>
double counted_cos(double);
double counted_sin(double);
#define cos counted_cos
#define sin counted_sin
HEADER
compile -pthread -include "$build_dir/count.h" -c "$astronomy_source" -o "$build_dir/astronomy.o"
compile -c "$script_dir/vsop_cache_probe.c" -o "$build_dir/probe.o"
"$compiler" -pthread "$build_dir"/*.o -lm -o "$build_dir/vsop-cache-probe"
"$build_dir/vsop-cache-probe"

# A negative control proves the probe rejects an engine with caching disabled.
python3 - "$astronomy_source" "$build_dir/uncached.c" <<'PYTHON'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
marker = "static vsop_cache_entry_t *VsopCache(const vsop_model_t *model, double t)\n{"
assert source.count(marker) == 1
Path(sys.argv[2]).write_text(source.replace(marker, marker + "\n    return NULL; /* diagnostic: bypass cache */"))
PYTHON
compile -pthread -include "$build_dir/count.h" -c "$build_dir/uncached.c" -o "$build_dir/astronomy.o"
"$compiler" -pthread "$build_dir"/*.o -lm -o "$build_dir/vsop-cache-probe"
negative_status=0
"$build_dir/vsop-cache-probe" > "$build_dir/negative.log" 2>&1 || negative_status=$?
if [ "$negative_status" -ne 1 ]; then
    echo "ERROR: expected a cache assertion failure, got exit $negative_status" >&2
    cat "$build_dir/negative.log" >&2
    exit 1
fi
grep -F "HelioVector repeated the VSOP position series" "$build_dir/negative.log" > /dev/null
cat "$build_dir/negative.log"
echo "Cache probe rejected the uncached negative control."

# Separately prove that qualified NEW epochs avoid the full series.
compile -c "$script_dir/polynomial/work_probe.c" -o "$build_dir/probe.o"
compile -pthread -include "$build_dir/count.h" -c "$astronomy_source" -o "$build_dir/astronomy.o"
"$compiler" -pthread "$build_dir"/*.o -lm -o "$build_dir/polynomial-probe"
"$build_dir/polynomial-probe"
python3 - "$astronomy_source" "$build_dir/full-only.c" <<'PYTHON'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
marker = '#include "polynomial.h"'
assert source.count(marker) == 1
# Keep the real fallback implementation, replacing only the polynomial dispatch.
source = source.replace(marker, 'static int PolynomialPosition(int b, double t, double *p, double *v) { return 0; }')
Path(sys.argv[2]).write_text(source)
PYTHON
compile -pthread -include "$build_dir/count.h" -c "$build_dir/full-only.c" -o "$build_dir/astronomy.o"
"$compiler" -pthread "$build_dir"/*.o -lm -o "$build_dir/polynomial-probe"
negative_status=0
"$build_dir/polynomial-probe" > "$build_dir/negative.log" 2>&1 || negative_status=$?
if [ "$negative_status" -ne 1 ]; then
    echo "ERROR: expected a polynomial assertion failure, got exit $negative_status" >&2
    cat "$build_dir/negative.log" >&2
    exit 1
fi
grep -F "Polynomial path evaluated the VSOP trigonometric series" "$build_dir/negative.log" > /dev/null
cat "$build_dir/negative.log"
echo "Polynomial probe rejected the full-series negative control."
