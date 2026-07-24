/*
    ak_math.h - deterministic transcendental math for AstronomyKit.

    Declares the double-precision transcendental functions vendored from
    musl libc 1.2.5 into Sources/CLibAstronomy/detmath/. They are prefixed
    ak_ so they can never collide with or resolve to the host libm at link
    time, and they produce bit-identical results on every supported OS and
    architecture (issue #28).

    astronomy.c is redirected onto these via ak_detmath.h; Swift code that
    needs a transcendental whose result feeds user-visible ephemeris values
    should call these instead of the host libm as well. IEEE-exact,
    correctly-rounded operations (sqrt, fabs, fmod, floor, ceil) are not
    vendored - the host versions are identical everywhere.
*/
#ifndef AK_MATH_H
#define AK_MATH_H

#ifdef __cplusplus
extern "C" {
#endif

extern double ak_sin(double x);
extern double ak_cos(double x);
extern double ak_tan(double x);
extern double ak_asin(double x);
extern double ak_acos(double x);
extern double ak_atan(double x);
extern double ak_atan2(double y, double x);
extern double ak_exp(double x);
extern double ak_log10(double x);
extern double ak_pow(double x, double y);
extern double ak_cbrt(double x);
extern double ak_hypot(double x, double y);

#ifdef __cplusplus
}
#endif

#endif /* AK_MATH_H */
