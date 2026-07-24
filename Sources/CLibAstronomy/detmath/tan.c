/*
 * Vendored from musl libc 1.2.5 (src/math/tan.c) for AstronomyKit.
 * Externally-visible symbols are prefixed with ak_ so nothing here can
 * collide with or resolve to the host libm at link time. Purpose:
 * bit-identical ephemeris results across operating systems (issue #28).
 * Original musl copyright/attribution comments are preserved below.
 */
/* origin: FreeBSD /usr/src/lib/msun/src/s_tan.c */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */
/* ak_tan(x)
 * Return tangent function of x.
 *
 * kernel function:
 *      ak___tan           ... tangent function on [-pi/4,pi/4]
 *      ak___rem_pio2      ... argument reduction routine
 *
 * Method.
 *      Let S,C and T denote the ak_sin, ak_cos and ak_tan respectively on
 *      [-PI/4, +PI/4]. Reduce the argument x to y1+y2 = x-k*pi/2
 *      in [-pi/4 , +pi/4], and let n = k mod 4.
 *      We have
 *
 *          n        ak_sin(x)      ak_cos(x)        ak_tan(x)
 *     ----------------------------------------------------------
 *          0          S           C             T
 *          1          C          -S            -1/T
 *          2         -S          -C             T
 *          3         -C           S            -1/T
 *     ----------------------------------------------------------
 *
 * Special cases:
 *      Let trig be any of ak_sin, ak_cos, or ak_tan.
 *      trig(+-INF)  is NaN, with signals;
 *      trig(NaN)    is that NaN;
 *
 * Accuracy:
 *      TRIG(x) returns trig(x) nearly rounded
 */

#include "ak_libm.h"

/* AstronomyKit: pin FP contraction off so codegen cannot fuse into FMA
   and change results between targets/compilers (issue #28). */
#pragma STDC FP_CONTRACT OFF

double ak_tan(double x)
{
	double y[2];
	uint32_t ix;
	unsigned n;

	GET_HIGH_WORD(ix, x);
	ix &= 0x7fffffff;

	/* |x| ~< pi/4 */
	if (ix <= 0x3fe921fb) {
		if (ix < 0x3e400000) { /* |x| < 2**-27 */
			/* raise inexact if x!=0 and underflow if subnormal */
			FORCE_EVAL(ix < 0x00100000 ? x/0x1p120f : x+0x1p120f);
			return x;
		}
		return ak___tan(x, 0.0, 0);
	}

	/* ak_tan(Inf or NaN) is NaN */
	if (ix >= 0x7ff00000)
		return x - x;

	/* argument reduction */
	n = ak___rem_pio2(x, y);
	return ak___tan(y[0], y[1], n&1);
}
