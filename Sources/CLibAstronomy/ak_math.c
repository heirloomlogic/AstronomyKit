/* Native-math compatibility symbols; do not compile with vendored detmath sources. */
#include <math.h>
#include "ak_math.h"

#pragma STDC FP_CONTRACT OFF

double ak_sin(double x) { return sin(x); }
double ak_cos(double x) { return cos(x); }
double ak_tan(double x) { return tan(x); }
double ak_asin(double x) { return asin(x); }
double ak_acos(double x) { return acos(x); }
double ak_atan(double x) { return atan(x); }
double ak_exp(double x) { return exp(x); }
double ak_log10(double x) { return log10(x); }
double ak_cbrt(double x) { return cbrt(x); }
double ak_atan2(double x, double y) { return atan2(x, y); }
double ak_pow(double x, double y) { return pow(x, y); }
double ak_hypot(double x, double y) { return hypot(x, y); }
