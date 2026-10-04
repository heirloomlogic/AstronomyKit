#!/bin/sh
# Build the shared immutable evaluator/time support for standalone C probes.
set -eu
source_root=$1
destination=$2
compiler=${CC:-cc}
mkdir -p "$destination/ephemeris-objects"
for source in "$source_root/ephemeris.c" "$source_root"/EphemerisTime/*.c; do
    object="$destination/ephemeris-objects/$(basename "$source" .c).o"
    "$compiler" -std=c11 -O2 -I"$source_root/include" -c "$source" -o "$object"
done
ar rcs "$destination/ephemeris.a" "$destination"/ephemeris-objects/*.o
