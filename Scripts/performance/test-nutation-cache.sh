#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
source_root="$repo_root/Sources/CLibAstronomy"
astronomy_source=${1:-"$source_root/astronomy.c"}
compiler=${CC:-cc}
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/astronomykit-nutation-cache.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM

compile()
{
    "$compiler" -std=c11 -O2 -pthread \
        "-I$source_root" \
        "-I$source_root/include" \
        "$@"
}

python3 - "$astronomy_source" "$build_dir/instrumented.c" <<'PYTHON'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
declaration = "static void iau2000b_eval(double t, double *dp, double *de, double *dp_rate, double *de_rate)\n{"
assert source.count(declaration) == 1
source = source.replace(declaration, declaration + "\n    counted_iau2000b_eval();")
Path(sys.argv[2]).write_text(source)
PYTHON
cat > "$build_dir/count.h" <<'HEADER'
void counted_iau2000b_eval(void);
HEADER
compile -include "$build_dir/count.h" -c "$build_dir/instrumented.c" -o "$build_dir/astronomy.o"
compile -c "$script_dir/nutation_cache_probe.c" -o "$build_dir/probe.o"
"$compiler" -pthread "$build_dir/astronomy.o" "$build_dir/probe.o" -lm -o "$build_dir/nutation-cache-probe"
"$build_dir/nutation-cache-probe"

python3 - "$astronomy_source" "$build_dir/legacy.c" <<'PYTHON'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
cached_angles = """        iau2000b_result_t result = Iau2000bResult(time->tt / 36525.0);
        time->psi = result.psi;
        time->eps = result.eps;"""
legacy_angles = """        double dp, de;
        iau2000b_eval(time->tt / 36525.0, &dp, &de, NULL, NULL);
        time->psi = -0.000135 + dp * 1.0e-7;
        time->eps = +0.000388 + de * 1.0e-7;"""
cached_rates = """    iau2000b_result_t result = Iau2000bResult(time->tt / 36525.0);
    if (isnan(time->psi))
    {
        time->psi = result.psi;
        time->eps = result.eps;
    }
    *dpsi_rate = result.psi_rate;
    *deps_rate = result.eps_rate;"""
legacy_rates = """    const double t = time->tt / 36525.0;
    double dp, de, pr, er;
    iau2000b_eval(t, &dp, &de, &pr, &er);
    if (isnan(time->psi))
    {
        time->psi = -0.000135 + dp * 1.0e-7;
        time->eps = +0.000388 + de * 1.0e-7;
    }
    *dpsi_rate = pr * 1.0e-7 / 36525.0;
    *deps_rate = er * 1.0e-7 / 36525.0;"""
assert source.count(cached_angles) == 1
assert source.count(cached_rates) == 1
source = source.replace(cached_angles, legacy_angles).replace(cached_rates, legacy_rates)
Path(sys.argv[2]).write_text(source)
PYTHON

compile -c "$astronomy_source" -o "$build_dir/astronomy.o"
compile -c "$script_dir/nutation_output_probe.c" -o "$build_dir/output-probe.o"
"$compiler" -pthread "$build_dir/astronomy.o" "$build_dir/output-probe.o" -lm -o "$build_dir/cached-output-probe"
"$build_dir/cached-output-probe" > "$build_dir/cached.out"
compile -c "$build_dir/legacy.c" -o "$build_dir/astronomy.o"
"$compiler" -pthread "$build_dir/astronomy.o" "$build_dir/output-probe.o" -lm -o "$build_dir/legacy-output-probe"
"$build_dir/legacy-output-probe" > "$build_dir/legacy.out"
cmp "$build_dir/cached.out" "$build_dir/legacy.out"
echo "Cached and pre-cache nutation positions, rates, and metadata are bit-identical."

python3 - "$build_dir/instrumented.c" "$build_dir/uncached-instrumented.c" <<'PYTHON'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
marker = "static nutation_cache_entry_t *NutationCache(double t)\n{"
assert source.count(marker) == 1
Path(sys.argv[2]).write_text(source.replace(marker, marker + "\n    return NULL; /* diagnostic: bypass cache */"))
PYTHON
compile -include "$build_dir/count.h" -c "$build_dir/uncached-instrumented.c" -o "$build_dir/astronomy.o"
"$compiler" -pthread "$build_dir/astronomy.o" "$build_dir/probe.o" -lm -o "$build_dir/nutation-cache-probe"
negative_status=0
"$build_dir/nutation-cache-probe" > "$build_dir/negative.log" 2>&1 || negative_status=$?
if [ "$negative_status" -ne 1 ]; then
    echo "ERROR: expected a cache assertion failure, got exit $negative_status" >&2
    cat "$build_dir/negative.log" >&2
    exit 1
fi
grep -F "GeoEclipticState did not reuse one nutation evaluation" "$build_dir/negative.log" > /dev/null
cat "$build_dir/negative.log"
echo "Cache probe rejected the uncached negative control."
