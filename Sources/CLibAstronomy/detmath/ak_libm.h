/*
 * Vendored from musl libc 1.2.5 (src/internal/libm.h) for AstronomyKit,
 * trimmed to the double-precision subset used by the detmath/ sources.
 * Externally-visible symbols are prefixed with ak_ so nothing here can
 * collide with or resolve to the host libm at link time. Purpose:
 * bit-identical ephemeris results across operating systems (issue #28).
 *
 * Removed relative to upstream: long-double union ldshape and all float/
 * long-double kernel declarations, <endian.h>/"fp_arch.h" includes, the
 * TOINT_INTRINSICS fast path, signaling-NaN support, and the `hidden`
 * visibility attribute (these are ordinary internal symbols now).
 */
#ifndef AK_LIBM_H
#define AK_LIBM_H

#include <stdint.h>
#include <float.h>
#include <math.h>

/* Public declarations of the 12 ak_ entry points. musl's sources relied on
   <math.h> declaring these (e.g. atan2.c calls atan); after prefixing they
   need explicit prototypes. Resolved via the target's "include" header
   search path. */
#include "ak_math.h"

/* Pin FP contraction off so codegen cannot fuse into FMA and change
   results between targets/compilers (issue #28). */
#pragma STDC FP_CONTRACT OFF

/* Support non-nearest rounding mode.  */
#define WANT_ROUNDING 1

/* Signaling NaN support is disabled, as in a default musl build.  */
#define issignaling_inline(x) 0

/* The TOINT_INTRINSICS fast path is disabled: it is only enabled by musl on
   archs providing round/convert intrinsics, and keeping one code path keeps
   results identical everywhere.  */
#define TOINT_INTRINSICS 0

/* Helps static branch prediction so hot path can be better optimized.
   __builtin_expect is a branch hint only; it has no effect on FP results.  */
#ifdef __GNUC__
#define predict_true(x) __builtin_expect(!!(x), 1)
#define predict_false(x) __builtin_expect(x, 0)
#else
#define predict_true(x) (x)
#define predict_false(x) (x)
#endif

/* Evaluate an expression as the specified type. With standard excess
   precision handling a type cast or assignment is enough (with
   -ffloat-store an assignment is required, in old compilers argument
   passing and return statement may not drop excess precision).  */

static inline float eval_as_float(float x)
{
	float y = x;
	return y;
}

static inline double eval_as_double(double x)
{
	double y = x;
	return y;
}

/* fp_barrier returns its input, but limits code transformations
   as if it had a side-effect (e.g. observable io) and returned
   an arbitrary value.  */

#ifndef fp_barrierf
#define fp_barrierf fp_barrierf
static inline float fp_barrierf(float x)
{
	volatile float y = x;
	return y;
}
#endif

#ifndef fp_barrier
#define fp_barrier fp_barrier
static inline double fp_barrier(double x)
{
	volatile double y = x;
	return y;
}
#endif

/* fp_force_eval ensures that the input value is computed when that's
   otherwise unused.  To prevent the constant folding of the input
   expression, an additional fp_barrier may be needed or a compilation
   mode that does so (e.g. -frounding-math in gcc). Then it can be
   used to evaluate an expression for its fenv side-effects only.   */

#ifndef fp_force_evalf
#define fp_force_evalf fp_force_evalf
static inline void fp_force_evalf(float x)
{
	volatile float y;
	y = x;
	(void)y;
}
#endif

#ifndef fp_force_eval
#define fp_force_eval fp_force_eval
static inline void fp_force_eval(double x)
{
	volatile double y;
	y = x;
	(void)y;
}
#endif

/* Long-double variant removed with the rest of the long-double support;
   every FORCE_EVAL argument in the vendored subset is float or double.  */
#define FORCE_EVAL(x) do {                        \
	if (sizeof(x) == sizeof(float)) {         \
		fp_force_evalf(x);                \
	} else {                                  \
		fp_force_eval(x);                 \
	}                                         \
} while(0)

#define asuint(f) ((union{float _f; uint32_t _i;}){f})._i
#define asfloat(i) ((union{uint32_t _i; float _f;}){i})._f
#define asuint64(f) ((union{double _f; uint64_t _i;}){f})._i
#define asdouble(i) ((union{uint64_t _i; double _f;}){i})._f

#define EXTRACT_WORDS(hi,lo,d)                    \
do {                                              \
  uint64_t __u = asuint64(d);                     \
  (hi) = __u >> 32;                               \
  (lo) = (uint32_t)__u;                           \
} while (0)

#define GET_HIGH_WORD(hi,d)                       \
do {                                              \
  (hi) = asuint64(d) >> 32;                       \
} while (0)

#define GET_LOW_WORD(lo,d)                        \
do {                                              \
  (lo) = (uint32_t)asuint64(d);                   \
} while (0)

#define INSERT_WORDS(d,hi,lo)                     \
do {                                              \
  (d) = asdouble(((uint64_t)(hi)<<32) | (uint32_t)(lo)); \
} while (0)

#define SET_HIGH_WORD(d,hi)                       \
  INSERT_WORDS(d, hi, (uint32_t)asuint64(d))

#define SET_LOW_WORD(d,lo)                        \
  INSERT_WORDS(d, asuint64(d)>>32, lo)

/* Cross-file internals of the vendored subset (ak_-prefixed).  */
int    ak___rem_pio2_large(double*,double*,int,int,int);
int    ak___rem_pio2(double,double*);
double ak___sin(double,double,int);
double ak___cos(double,double);
double ak___tan(double,double,int);
double ak_scalbn(double,int);

/* error handling functions */
double ak___math_xflow(uint32_t, double);
double ak___math_uflow(uint32_t);
double ak___math_oflow(uint32_t);
double ak___math_invalid(double);

#endif
