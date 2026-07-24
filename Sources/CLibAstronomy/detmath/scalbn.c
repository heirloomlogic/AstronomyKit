/*
 * Vendored from musl libc 1.2.5 (src/math/scalbn.c) for AstronomyKit.
 * Externally-visible symbols are prefixed with ak_ so nothing here can
 * collide with or resolve to the host libm at link time. Purpose:
 * bit-identical ephemeris results across operating systems (issue #28).
 * Original musl copyright/attribution comments are preserved below.
 */
#include <math.h>
#include <stdint.h>

/* AstronomyKit: pin FP contraction off so codegen cannot fuse into FMA
   and change results between targets/compilers (issue #28). */
#pragma STDC FP_CONTRACT OFF

double ak_scalbn(double x, int n)
{
	union {double f; uint64_t i;} u;
	double_t y = x;

	if (n > 1023) {
		y *= 0x1p1023;
		n -= 1023;
		if (n > 1023) {
			y *= 0x1p1023;
			n -= 1023;
			if (n > 1023)
				n = 1023;
		}
	} else if (n < -1022) {
		/* make sure final n < -53 to avoid double
		   rounding in the subnormal range */
		y *= 0x1p-1022 * 0x1p53;
		n += 1022 - 53;
		if (n < -1022) {
			y *= 0x1p-1022 * 0x1p53;
			n += 1022 - 53;
			if (n < -1022)
				n = -1022;
		}
	}
	u.i = (uint64_t)(0x3ff+n)<<52;
	x = y * u.f;
	return x;
}
