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
        "-I$source_root/detmath" \
        "$@"
}

compile -pthread -c "$astronomy_source" -o "$build_dir/astronomy.o"

for source in "$source_root"/detmath/*.c; do
    name=$(basename "$source" .c)
    case "$name" in
        cos)
            compile -Dak_cos=ak_uncounted_cos \
                -c "$source" -o "$build_dir/$name.o"
            ;;
        sin)
            compile -Dak_sin=ak_uncounted_sin \
                -c "$source" -o "$build_dir/$name.o"
            ;;
        *)
            compile -c "$source" -o "$build_dir/$name.o"
            ;;
    esac
done

compile -c "$script_dir/vsop_cache_probe.c" -o "$build_dir/probe.o"
"$compiler" -pthread "$build_dir"/*.o -lm -o "$build_dir/vsop-cache-probe"
"$build_dir/vsop-cache-probe"
