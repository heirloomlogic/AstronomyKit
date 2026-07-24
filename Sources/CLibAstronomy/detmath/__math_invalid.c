/*
 * Vendored from musl libc 1.2.5 (src/math/__math_invalid.c) for AstronomyKit.
 * Externally-visible symbols are prefixed with ak_ so nothing here can
 * collide with or resolve to the host libm at link time. Purpose:
 * bit-identical ephemeris results across operating systems (issue #28).
 * Original musl copyright/attribution comments are preserved below.
 */
#include "ak_libm.h"

/* AstronomyKit: pin FP contraction off so codegen cannot fuse into FMA
   and change results between targets/compilers (issue #28). */
#pragma STDC FP_CONTRACT OFF

double ak___math_invalid(double x)
{
	return (x - x) / (x - x);
}
