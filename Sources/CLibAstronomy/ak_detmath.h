/*
    ak_detmath.h - private redirection header for astronomy.c (issue #28).

    Included by astronomy.c immediately after astronomy.h, this header does
    two things for the remainder of astronomy.c's translation unit:

    1. The `#pragma STDC FP_CONTRACT OFF` below applies from this point to
       the end of the translation unit, pinning FMA contraction off so the
       compiler cannot fuse a*b+c into a fused multiply-add. Contraction is
       target- and compiler-dependent, so leaving it on would make results
       differ between architectures even with identical libm code.

    2. The object-like macros redirect every libm transcendental astronomy.c
       calls (sin, cos, tan, asin, acos, atan, atan2, exp, log10, pow, cbrt,
       hypot) to the ak_-prefixed implementations vendored from musl 1.2.5
       in detmath/, removing the dependency on the host libm whose last-ULP
       behavior varies across OSes and OS point releases.

    Deliberately NOT redirected: sqrt, fabs, fmod, floor, ceil (IEEE-exact /
    correctly rounded on every host - not a determinism risk) and isnan
    (a <math.h> macro; redefining it would break its implementation).

    This header is private to the CLibAstronomy target (it lives outside
    include/); the public declarations are in include/ak_math.h.
*/
#ifndef AK_DETMATH_H
#define AK_DETMATH_H

#pragma STDC FP_CONTRACT OFF

#include "include/ak_math.h"

#define sin   ak_sin
#define cos   ak_cos
#define tan   ak_tan
#define asin  ak_asin
#define acos  ak_acos
#define atan  ak_atan
#define atan2 ak_atan2
#define exp   ak_exp
#define log10 ak_log10
#define pow   ak_pow
#define cbrt  ak_cbrt
#define hypot ak_hypot

#endif /* AK_DETMATH_H */
