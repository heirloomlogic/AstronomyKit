/*
    ak_math.h - compatibility entry points for platform-native math.

    Existing C and Swift callers retain the ak_ symbols. Each forwards to the
    host math library; cross-platform bit identity is not guaranteed.
    astronomy.c calls native math directly so the compiler can optimize it.
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
