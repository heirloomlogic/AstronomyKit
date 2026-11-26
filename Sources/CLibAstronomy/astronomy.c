/*
    VENDORING NOTE (AstronomyKit)

    Vendored from: https://github.com/cosinekitty/astronomy (source/c/astronomy.c)
    Upstream commit: 826e26ff3a6dc03ee46658b1138fef582d96c5d9 (2025-01-27)

    Local patches not in upstream:
      - pthread mutex (pluto_cache_mutex) protecting the Pluto orbit cache:
        CalcPluto holds the lock across segment lookup and use, and
        Astronomy_Reset takes it before freeing the cache.
      - C11 _Atomic on the DeltaTFunc function pointer (stdatomic.h):
        Astronomy_SetDeltaTFunction stores with release ordering and
        TerrestrialTime loads with acquire ordering, so the Delta T model
        can be swapped while calculations run on other threads.
      - Compute denial-of-service guard (PLUTO_MAX_CRAWL_DAYS) in CalcPluto:
        times more than ~100 years outside the PlutoStateTable range return
        ASTRO_BAD_TIME instead of triggering an unbounded step-integration.
      - Extreme-input guards, marked "extreme-input guards" at each site.
        CalcPluto rejects a non-finite TT before GetSegment, whose ClampIndex
        converted NaN to int. Astronomy_TerrestrialTime returns a NaN time
        for a non-finite TT and stops iterating after 128 steps.
      - Exact TT inverse, marked "exact TT inverse" at each site.
        Astronomy_TerrestrialTime returns the TT it was given for every
        finite TT. Where the Delta T model steps forward, no UT has a TT
        inside the step; there it stops when its iterates alternate between
        the UTs on either side, after about four steps instead of 128, and
        keeps the UT it stopped on.
      - Accepted time range, marked "accepted time range" at each site. The
        ephemeris evaluators return ASTRO_BAD_TIME unless |TT| <= 1,461,000
        days (EPHEMERIS_MAX_TT_DAYS, 4000 Julian years from J2000), which
        also rejects a non-finite TT: CalcVsop, Astronomy_GravSimInit, and
        Astronomy_GravSimUpdate. Results inside the range are bit-identical;
        Pluto keeps its narrower range.
      - TT-continuous offsets, marked "TT-continuous offsets" at each site.
        Astronomy_AddTerrestrialDays adds a span to both UT and TT.
      - Observed Delta T: Astronomy_DeltaT_Observed, a
        yearly IERS table joined continuously to Espenak-Meeus before it and
        to the long-term parabola after it, is the initial value of DeltaTFunc
        in place of Astronomy_DeltaT_EspenakMeeus.
      - Longer planet series: the VSOP87 tables for Mercury through Neptune
        hold 1262 terms where upstream kept 466. Every upstream term is
        kept; the rest come unchanged from the published VSOP87B files.
        MAINTAINING.md gives the selection.
      - Series cosine, marked "series cosine": SeriesSum adds up a planet
        series two terms at a time with the inline cosine and sine of
        SERIES_ADD_COS, SERIES_ADD_SIN_COS and SeriesSinCos, which stand in
        for the C library's cos and sin, and SERIES_WRAP stands in for fmod
        (VsopCoords, VsopHelioDistance, VsopSphereToRect, CalcVsopPosVel).
        VsopCoordsAndRates replaces upstream's VsopDeriv. They pay for the
        longer series, and need the vector types of GCC and clang. Their
        macros, always_inline functions and the four pairs of terms a pass
        takes when __OPTIMIZE__ is not defined are for builds without
        optimisation, and give the same results as an optimised build. A
        build without optimisation that defines
        ASTRONOMYKIT_SERIES_ACCELERATE, as Package.swift does for Debug
        builds on Apple platforms, sums the longer series through the
        Accelerate framework instead (SeriesSumAccelerate), and its results
        differ in rounding.
      - Nutation series, marked "nutation series": iau2000b sums all 77
        terms of the IAU 2000B series where upstream kept the five largest,
        whose rate left the stations of the planets seconds to tens of
        minutes out. nut_term is the published table. The routine takes the
        cosine and sine of the five angles with the series cosine's
        polynomials and builds every term's from them by the angle addition
        formulas, and reduces the angles with rint in place of fmod. It
        moved below the series cosine, which it uses.

    When updating from upstream, re-apply the patches above (or verify
    upstream has adopted equivalent thread-safety fixes), then refresh the
    commit hash in this note.
*/
/*
    Astronomy Engine for C/C++.
    https://github.com/cosinekitty/astronomy

    MIT License

    Copyright (c) 2019-2025 Don Cross <cosinekitty@gmail.com>

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
*/

#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined(ASTRONOMY_ENGINE_NO_CURRENT_TIME)
#if defined(__unix__) || defined(__unix) || (defined(__APPLE__) && defined(__MACH__))
#include <sys/time.h>
#elif defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <time.h>
#endif
#endif

#include "astronomy.h"

/* AstronomyKit local patch (series cosine): see SeriesSumAccelerate */
#if defined(ASTRONOMYKIT_SERIES_ACCELERATE) && !defined(__OPTIMIZE__)
#include <Accelerate/Accelerate.h>
#define SERIES_USE_ACCELERATE
#endif

#ifdef __FAST_MATH__
#error Astronomy Engine does not support "fast math" optimization because it causes incorrect behavior. See: https://github.com/cosinekitty/astronomy/issues/245
#endif

#ifdef __cplusplus
extern "C" {
#endif

/** @cond DOXYGEN_SKIP */
#define PI      3.14159265358979323846

#define PLUTO_NUM_STATES  51
#define PLUTO_TIME_STEP   29200
#define PLUTO_DT          146

#define PLUTO_NSTEPS      201

/* AstronomyKit local patch: bound the uncached CalcPlutoOneWay crawl to ~100
   years beyond the PlutoStateTable range so a far-off time cannot trigger an
   unbounded step-integration (a compute denial-of-service). */
#define PLUTO_MAX_CRAWL_DAYS 36525.0

/* AstronomyKit local patch (accepted time range): the ephemeris models are
   evaluated only for TT within 4000 Julian years of J2000 (years about -2000
   to +6000), roughly the validity VSOP87 states. Far outside it they return
   absurd values (negative distances from about 10^10 days) and then NaN.
   Pluto keeps its own narrower range (PLUTO_MAX_CRAWL_DAYS above). */
#define EPHEMERIS_MAX_TT_DAYS 1461000.0


typedef struct
{
    double x;
    double y;
    double z;
}
terse_vector_t;

typedef struct
{
    double          tt;   /* J2000 terrestrial time [days] */
    terse_vector_t  r;    /* position [au] */
    terse_vector_t  v;    /* velocity [au/day] */
    terse_vector_t  a;    /* acceleration [au/day^2] */
}
body_grav_calc_t;

typedef struct
{
    body_grav_calc_t   step[PLUTO_NSTEPS];
}
body_segment_t;

typedef struct
{
    double          tt;  /* Terrestrial Time in J2000 days */
    terse_vector_t  r;   /* position [au] */
    terse_vector_t  v;   /* velocity [au/day] */
}
body_state_t;

typedef struct
{
    body_state_t Sun;
    body_state_t Jupiter;
    body_state_t Saturn;
    body_state_t Uranus;
    body_state_t Neptune;
}
major_bodies_t;

typedef struct
{
    astro_time_t      time;
    body_state_t      gravitators[1 + BODY_SUN];
    body_grav_calc_t *bodies;
}
gravsim_endpoint_t;

struct astro_grav_sim_s
{
    astro_body_t        originBody;
    int                 numBodies;
    gravsim_endpoint_t  endpoint[2];
    gravsim_endpoint_t *prev;
    gravsim_endpoint_t *curr;
};

/** @endcond */

static const terse_vector_t VecZero = { 0.0, 0.0, 0.0 };

static terse_vector_t VecAdd(terse_vector_t a, terse_vector_t b)
{
    terse_vector_t c;
    c.x = a.x + b.x;
    c.y = a.y + b.y;
    c.z = a.z + b.z;
    return c;
}

static void VecIncr(terse_vector_t *target, terse_vector_t source)
{
    target->x += source.x;
    target->y += source.y;
    target->z += source.z;
}

static void VecDecr(terse_vector_t *target, terse_vector_t source)
{
    target->x -= source.x;
    target->y -= source.y;
    target->z -= source.z;
}

static terse_vector_t VecMul(double s, terse_vector_t v)
{
    terse_vector_t p;
    p.x = s * v.x;
    p.y = s * v.y;
    p.z = s * v.z;
    return p;
}

static void VecScale(terse_vector_t *target, double scalar)
{
    target->x *= scalar;
    target->y *= scalar;
    target->z *= scalar;
}

static terse_vector_t VecRamp(terse_vector_t a, terse_vector_t b, double ramp)
{
    terse_vector_t c;
    c.x = (1-ramp)*a.x + ramp*b.x;
    c.y = (1-ramp)*a.y + ramp*b.y;
    c.z = (1-ramp)*a.z + ramp*b.z;
    return c;
}

static terse_vector_t VecMean(terse_vector_t a, terse_vector_t b)
{
    terse_vector_t c;
    c.x = (a.x + b.x) / 2;
    c.y = (a.y + b.y) / 2;
    c.z = (a.z + b.z) / 2;
    return c;
}

static astro_state_vector_t ExportState(body_state_t terse, astro_time_t time)
{
    astro_state_vector_t state;

    state.status = ASTRO_SUCCESS;
    state.x  = terse.r.x;
    state.y  = terse.r.y;
    state.z  = terse.r.z;
    state.vx = terse.v.x;
    state.vy = terse.v.y;
    state.vz = terse.v.z;
    state.t  = time;

    return state;
}

static astro_state_vector_t ExportGravCalc(body_grav_calc_t calc, astro_time_t time)
{
    astro_state_vector_t state;

    state.status = ASTRO_SUCCESS;
    state.x  = calc.r.x;
    state.y  = calc.r.y;
    state.z  = calc.r.z;
    state.vx = calc.v.x;
    state.vy = calc.v.y;
    state.vz = calc.v.z;
    state.t  = time;

    return state;
}

static const double DAYS_PER_TROPICAL_YEAR = 365.24217;
static const double SECONDS_PER_DAY = 24.0 * 3600.0;
static const double EARTH_MOON_MASS_RATIO = 81.30056;

/*
    Masses of the Sun and planets, used for:
    (1) Calculating the Solar System Barycenter
    (2) Integrating the movement of Pluto

    https://web.archive.org/web/20120220062549/http://iau-comm4.jpl.nasa.gov/de405iom/de405iom.pdf

    Page 10 in the above document describes the constants used in the DE405 ephemeris.
    The following are GM values (gravity constant * mass) in [au^3 / day^2].
    This side-steps issues of not knowing the exact values of G and masses M[i];
    the products GM[i] are known extremely accurately.
*/
static const double SUN_GM     = 0.2959122082855911e-03;
static const double MERCURY_GM = 0.4912547451450812e-10;
static const double VENUS_GM   = 0.7243452486162703e-09;
static const double EARTH_GM   = 0.8887692390113509e-09;
static const double MARS_GM    = 0.9549535105779258e-10;
static const double JUPITER_GM = 0.2825345909524226e-06;
static const double SATURN_GM  = 0.8459715185680659e-07;
static const double URANUS_GM  = 0.1292024916781969e-07;
static const double NEPTUNE_GM = 0.1524358900784276e-07;

#define MOON_GM   (EARTH_GM / EARTH_MOON_MASS_RATIO)

/** @cond DOXYGEN_SKIP */
#define ASTRO_ARRAYSIZE(x)    (sizeof(x) / sizeof(x[0]))
/** @endcond */

/* AstronomyKit local patch (accepted time range): nonzero when `time` is one
   the ephemeris models accept. False for a NaN TT, so a non-finite time is
   rejected too. */
static int EphemerisTimeOk(astro_time_t time)
{
    return fabs(time.tt) <= EPHEMERIS_MAX_TT_DAYS;
}

static astro_vector_t VecError(astro_status_t status, astro_time_t time)
{
    astro_vector_t vec;
    vec.x = vec.y = vec.z = NAN;
    vec.t = time;
    vec.status = status;
    return vec;
}

static astro_state_vector_t StateVecError(astro_status_t status, astro_time_t time)
{
    astro_state_vector_t vec;
    vec.x = vec.y = vec.z = NAN;
    vec.vx = vec.vy = vec.vz = NAN;
    vec.t = time;
    vec.status = status;
    return vec;
}

/**
 * @brief The default Delta T function used by Astronomy Engine.
 *
 * Espenak and Meeus use a series of piecewise polynomials to
 * approximate DeltaT of the Earth in their "Five Millennium Canon of Solar Eclipses".
 * See: https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html
 * This is the default Delta T function used by Astronomy Engine.
 * AstronomyKit defaults to #Astronomy_DeltaT_Observed instead.
 *
 * @param ut
 *      The floating point number of days since noon UTC on January 1, 2000.
 *
 * @returns
 *      The estimated difference TT-UT on the given date, expressed in seconds.
 */
double Astronomy_DeltaT_EspenakMeeus(double ut)
{
    double y, u, u2, u3, u4, u5, u6, u7;

    /*
        Fred Espenak writes about Delta-T generically here:
        https://eclipse.gsfc.nasa.gov/SEhelp/deltaT.html
        https://eclipse.gsfc.nasa.gov/SEhelp/deltat2004.html

        He provides polynomial approximations for distant years here:
        https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html

        They start with a year value 'y' such that y=2000 corresponds
        to the UTC Date 15-January-2000. Convert difference in days
        to mean tropical years.
    */

    y = 2000 + ((ut - 14) / DAYS_PER_TROPICAL_YEAR);

    if (y < -500)
    {
        u = (y - 1820) / 100;
        return -20 + (32 * u*u);
    }
    if (y < 500)
    {
        u = y / 100;
        u2 = u*u; u3 = u*u2; u4 = u2*u2; u5 = u2*u3; u6 = u3*u3;
        return 10583.6 - 1014.41*u + 33.78311*u2 - 5.952053*u3 - 0.1798452*u4 + 0.022174192*u5 + 0.0090316521*u6;
    }
    if (y < 1600)
    {
        u = (y - 1000) / 100;
        u2 = u*u; u3 = u*u2; u4 = u2*u2; u5 = u2*u3; u6 = u3*u3;
        return 1574.2 - 556.01*u + 71.23472*u2 + 0.319781*u3 - 0.8503463*u4 - 0.005050998*u5 + 0.0083572073*u6;
    }
    if (y < 1700)
    {
        u = y - 1600;
        u2 = u*u; u3 = u*u2;
        return 120 - 0.9808*u - 0.01532*u2 + u3/7129.0;
    }
    if (y < 1800)
    {
        u = y - 1700;
        u2 = u*u; u3 = u*u2; u4 = u2*u2;
        return 8.83 + 0.1603*u - 0.0059285*u2 + 0.00013336*u3 - u4/1174000;
    }
    if (y < 1860)
    {
        u = y - 1800;
        u2 = u*u; u3 = u*u2; u4 = u2*u2; u5 = u2*u3; u6 = u3*u3; u7 = u3*u4;
        return 13.72 - 0.332447*u + 0.0068612*u2 + 0.0041116*u3 - 0.00037436*u4 + 0.0000121272*u5 - 0.0000001699*u6 + 0.000000000875*u7;
    }
    if (y < 1900)
    {
        u = y - 1860;
        u2 = u*u; u3 = u*u2; u4 = u2*u2; u5 = u2*u3;
        return 7.62 + 0.5737*u - 0.251754*u2 + 0.01680668*u3 - 0.0004473624*u4 + u5/233174;
    }
    if (y < 1920)
    {
        u = y - 1900;
        u2 = u*u; u3 = u*u2; u4 = u2*u2;
        return -2.79 + 1.494119*u - 0.0598939*u2 + 0.0061966*u3 - 0.000197*u4;
    }
    if (y < 1941)
    {
        u = y - 1920;
        u2 = u*u; u3 = u*u2;
        return 21.20 + 0.84493*u - 0.076100*u2 + 0.0020936*u3;
    }
    if (y < 1961)
    {
        u = y - 1950;
        u2 = u*u; u3 = u*u2;
        return 29.07 + 0.407*u - u2/233 + u3/2547;
    }
    if (y < 1986)
    {
        u = y - 1975;
        u2 = u*u; u3 = u*u2;
        return 45.45 + 1.067*u - u2/260 - u3/718;
    }
    if (y < 2005)
    {
        u = y - 2000;
        u2 = u*u; u3 = u*u2; u4 = u2*u2; u5 = u2*u3;
        return 63.86 + 0.3345*u - 0.060374*u2 + 0.0017275*u3 + 0.000651814*u4 + 0.00002373599*u5;
    }
    if (y < 2050)
    {
        u = y - 2000;
        return 62.92 + 0.32217*u + 0.005589*u*u;
    }
    if (y < 2150)
    {
        u = (y-1820)/100;
        return -20 + 32*u*u - 0.5628*(2150 - y);
    }

    /* all years after 2150 */
    u = (y - 1820) / 100;
    return -20 + (32 * u*u);
}

/**
 * @brief A Delta T function that approximates the one used by the JPL Horizons tool.
 *
 * In order to support unit tests based on data generated by the JPL Horizons online
 * tool, I had to reverse engineer their Delta T function by generating a table that
 * contained it. The main difference between their tool and the Espenak/Meeus function
 * is that they stop extrapolating the Earth's deceleration after the year 2017.
 *
 * @param ut
 *      The floating point number of days since noon UTC on January 1, 2000.
 *
 * @returns
 *      The estimated difference TT-UT on the given date, expressed in seconds.
 */
double Astronomy_DeltaT_JplHorizons(double ut)
{
    if (ut > 17.0 * DAYS_PER_TROPICAL_YEAR)
        ut = 17.0 * DAYS_PER_TROPICAL_YEAR;

    return Astronomy_DeltaT_EspenakMeeus(ut);
}

/*
    Observed Delta T (AstronomyKit local patch). TT - UT1 in seconds at Julian
    epochs 1962.0, 1963.0, ..., that is at ut = 365.25 (year - 2000) days.
    From IERS EOP 20 C04 UT1-UTC through 2026-09-27 and IERS Bulletin A
    predictions after it, retrieved 2026-10-27: Delta T = 32.184 s + (TAI - UTC)
    - (UT1 - UTC), interpolated linearly between the daily values.
    Linear interpolation in this table stays within 0.09 s of the daily values.
*/
#define DELTAT_OBSERVED_FIRST_YEAR  1962
#define DELTAT_OBSERVED_FADE_YEARS  10.0
#define DELTAT_OBSERVED_JOIN_OFFSET 0.026074996595710331   /* DeltaTObserved[0] minus Espenak-Meeus at 1962.0 */
#define DELTAT_LONG_TERM_YEAR       2150.0

static const double DeltaTObserved[] =
{
    33.997, 34.474, 35.032, 35.742, 36.544, 37.433, 38.296, 39.204,     /* 1962 */
    40.181, 41.170, 42.231, 43.373, 44.485, 45.477, 46.459, 47.519,     /* 1970 */
    48.535, 49.586, 50.540, 51.380, 52.167, 52.957, 53.787, 54.343,     /* 1978 */
    54.870, 55.322, 55.820, 56.300, 56.855, 57.566, 58.310, 59.121,     /* 1986 */
    59.984, 60.786, 61.630, 62.295, 62.966, 63.468, 63.829, 64.091,     /* 1994 */
    64.300, 64.474, 64.574, 64.688, 64.845, 65.147, 65.458, 65.777,     /* 2002 */
    66.070, 66.325, 66.604, 66.907, 67.281, 67.644, 68.103, 68.592,     /* 2010 */
    68.968, 69.220, 69.361, 69.360, 69.295, 69.204, 69.175, 69.138,     /* 2018 */
    69.110, 69.308                                                      /* 2026 */
};

#define DELTAT_OBSERVED_COUNT  ((int)(sizeof(DeltaTObserved) / sizeof(DeltaTObserved[0])))

/* The long-term parabola of Espenak and Meeus, in Julian epoch years. */
static double DeltaTLongTerm(double year)
{
    double u = (year - 1820.0) / 100.0;
    return -20.0 + 32.0*u*u;
}

/**
 * @brief Delta T from observed Earth rotation, the default in AstronomyKit.
 *
 * From 1962 through 2027, Delta T interpolated linearly in a yearly table of
 * IERS values, within 0.09 seconds of the daily IERS series.
 *
 * Before 1962, #Astronomy_DeltaT_EspenakMeeus, shifted to meet the table:
 * the shift is 0.026 seconds at 1962 and fades linearly to zero by 1952.
 *
 * After 2027, the table's last yearly rate continues and blends, through a
 * smoothstep weight, into the long-term parabola -20 + 32 u^2 seconds,
 * u = (year - 1820) / 100, which applies alone from 2150. Delta T and its rate
 * are continuous at both ends of the blend. The Earth's rotation cannot be
 * predicted for more than a year or so: expect errors of about 0.5 seconds
 * three years past the table and a second or more after that.
 *
 * @param ut
 *      The floating point number of days since noon UTC on January 1, 2000.
 *
 * @returns
 *      The estimated difference TT-UT on the given date, expressed in seconds.
 */
double Astronomy_DeltaT_Observed(double ut)
{
    const int last = DELTAT_OBSERVED_COUNT - 1;
    double x = ut / 365.25 + (2000 - DELTAT_OBSERVED_FIRST_YEAR);   /* years since the first entry */

    if (isnan(x))
        return x;

    if (x < 0.0)
    {
        if (x <= -DELTAT_OBSERVED_FADE_YEARS)
            return Astronomy_DeltaT_EspenakMeeus(ut);
        return Astronomy_DeltaT_EspenakMeeus(ut) + (1.0 + x / DELTAT_OBSERVED_FADE_YEARS) * DELTAT_OBSERVED_JOIN_OFFSET;
    }

    if (x < last)
    {
        int i = (int)x;
        return DeltaTObserved[i] + (x - i) * (DeltaTObserved[i + 1] - DeltaTObserved[i]);
    }

    double year = x + DELTAT_OBSERVED_FIRST_YEAR;
    double parabola = DeltaTLongTerm(year);
    if (year >= DELTAT_LONG_TERM_YEAR)
        return parabola;

    double rate = DeltaTObserved[last] - DeltaTObserved[last - 1];
    double linear = DeltaTObserved[last] + (x - last) * rate;
    double s = (x - last) / (DELTAT_LONG_TERM_YEAR - DELTAT_OBSERVED_FIRST_YEAR - last);
    return linear + s*s*(3.0 - 2.0*s) * (parabola - linear);
}

static _Atomic(astro_deltat_func) DeltaTFunc = Astronomy_DeltaT_Observed;

/**
 * @brief Changes the function Astronomy Engine uses to calculate Delta T.
 *
 * Most programs should not call this function. It is for advanced use cases only.
 * By default, AstronomyKit uses the function #Astronomy_DeltaT_Observed
 * to estimate changes in the Earth's rotation rate over time.
 * However, for the sake of unit tests that compare calculations against
 * external data sources that use alternative models for Delta T,
 * it is sometimes useful to replace the Delta T model to match.
 * This function allows replacing the Delta T model with any other
 * desired model.
 *
 * @param func
 *      A pointer to a function to convert UT values to DeltaT values.
 */
void Astronomy_SetDeltaTFunction(astro_deltat_func func)
{
    /* AstronomyKit local patch: never store a NULL function pointer that TerrestrialTime would dereference. */
    if (func == NULL)
        func = Astronomy_DeltaT_EspenakMeeus;
    atomic_store_explicit(&DeltaTFunc, func, memory_order_release);
}

static double TerrestrialTime(double ut)
{
    astro_deltat_func func = atomic_load_explicit(&DeltaTFunc, memory_order_acquire);
    return ut + func(ut)/86400.0;
}

/**
 * @brief Converts a J2000 day value to an #astro_time_t value.
 *
 * This function can be useful for reproducing an #astro_time_t structure
 * from its `ut` field only.
 *
 * @param ut
 *      The floating point number of days since noon UTC on January 1, 2000.
 *      This time is based on UTC/UT1 civil time.
 *      See #Astronomy_TerrestrialTime if you instead want to create
 *      a time value based on atomic Terrestrial Time (TT).
 *
 * @returns
 *      An #astro_time_t value for the given `ut` value.
 */
astro_time_t Astronomy_TimeFromDays(double ut)
{
    astro_time_t  time;
    time.ut = ut;
    time.tt = TerrestrialTime(ut);
    time.psi = time.eps = time.st = NAN;
    return time;
}


/**
 * @brief Converts a terrestrial time value into an #astro_time_t value.
 *
 * This function can be used in rare cases where a time must be based
 * on Terrestrial Time (TT) rather than Universal Time (UT).
 * Most developers will want to call #Astronomy_TimeFromDays instead of
 * this function, because usually time is based on civil time adjusted
 * by leap seconds to match the Earth's rotation, rather than the uniformly
 * flowing TT used to calculate solar system dynamics. In rare cases
 * where the caller already knows TT, this function is provided to create
 * an #astro_time_t value that can be passed to Astronomy Engine functions.
 *
 * @param tt
 *      The floating point number of days of uniformly flowing
 *      Terrestrial Time since the J2000 epoch.
 *
 * @returns
 *      An #astro_time_t value for the given `tt` value.
 */
astro_time_t Astronomy_TerrestrialTime(double tt)
{
    /* Iterate to solve to find the correct ut for a given tt, and create an astro_time_t for that time. */
    astro_time_t time;
    double one_back_ut = NAN, two_back_ut = NAN;

    /* AstronomyKit local patch (extreme-input guards): a non-finite tt never
       converges, and a finite tt whose iterates oscillate between neighboring
       doubles never gets within 1e-12 days, so upstream's for(;;) could spin
       forever. Ordinary inputs converge in a few iterations, so their UT is
       unchanged; otherwise stop at the last iterate. */
    if (!isfinite(tt))
        return Astronomy_TimeFromDays(NAN);

    time = Astronomy_TimeFromDays(tt);
    for (int iteration = 0; iteration < 128; ++iteration)
    {
        double err = tt - time.tt;
        if (fabs(err) < 1.0e-12)
            break;
        /* AstronomyKit local patch (exact TT inverse): inside a forward
           Delta T step the iterates alternate between two UTs. */
        if (time.ut == two_back_ut)
            break;
        two_back_ut = one_back_ut;
        one_back_ut = time.ut;
        time = Astronomy_AddDays(time, err);
    }
    /* AstronomyKit local patch (exact TT inverse). */
    time.tt = tt;
    return time;
}

#if !defined(ASTRONOMY_ENGINE_NO_CURRENT_TIME)
/**
 * @brief Returns the computer's current date and time in the form of an #astro_time_t.
 *
 * Uses the computer's system clock to find the current UTC date and time.
 * Converts that date and time to an #astro_time_t value and returns the result.
 * Callers can pass this value to other Astronomy Engine functions to calculate
 * current observational conditions.
 *
 * On supported platforms (Linux/Unix, Mac, Windows), the time is measured with
 * microsecond resolution.
 *
 * On unsupported platforms, a compiler error will occur due to lack of
 * microsecond resolution support. However, if whole second resolution is good
 * enough for your application, you can define the preprocessor symbol
 * `ASTRONOMY_ENGINE_WHOLE_SECOND` to use the portable function `time(NULL)`.
 * Alternatively, if you do not need to use `Astronomy_CurrentTime`, you can
 * define the preprocessor symbol `ASTRONOMY_ENGINE_NO_CURRENT_TIME` to
 * exclude this function from your code.
 */
astro_time_t Astronomy_CurrentTime(void)
{
    astro_time_t t;
    double sec;         /* Seconds since midnight January 1, 1970. */

#if defined(__unix__) || defined(__unix) || (defined(__APPLE__) && defined(__MACH__))
    struct timeval tv;
    gettimeofday(&tv, NULL);
    sec = (double)tv.tv_sec + tv.tv_usec/1.0e+6;
#elif defined(_WIN32)
    FILETIME ft;
    ULARGE_INTEGER large;
    /* Get time in 100-nanosecond units from January 1, 1601. */
    GetSystemTimePreciseAsFileTime(&ft);
    large.u.LowPart  = ft.dwLowDateTime;
    large.u.HighPart = ft.dwHighDateTime;
    sec = (large.QuadPart - 116444736000000000ULL) / 1.0e+7;
#elif defined(ASTRONOMY_ENGINE_WHOLE_SECOND)
    sec = time(NULL);
#else
    #error Microsecond time resolution is not supported on this platform. Define ASTRONOMY_ENGINE_WHOLE_SECOND to use second resolution instead.
#endif

    /* Convert seconds to days, then subtract to get days since noon on January 1, 2000. */
    t.ut = (sec / SECONDS_PER_DAY) - 10957.5;
    t.tt = TerrestrialTime(t.ut);
    t.psi = t.eps = t.st = NAN;
    return t;
}
#endif

/**
 * @brief Creates an #astro_time_t value from a given calendar date and time.
 *
 * Given a UTC calendar date and time, calculates an #astro_time_t value that can
 * be passed to other Astronomy Engine functions for performing various calculations
 * relating to that date and time.
 *
 * It is the caller's responsibility to ensure that the parameter values are correct.
 * The parameters are not checked for validity,
 * and this function never returns any indication of an error.
 * Invalid values, for example passing in February 31, may cause unexpected return values.
 *
 * @param year      The UTC calendar year, e.g. 2019.
 * @param month     The UTC calendar month in the range 1..12.
 * @param day       The UTC calendar day in the range 1..31.
 * @param hour      The UTC hour of the day in the range 0..23.
 * @param minute    The UTC minute in the range 0..59.
 * @param second    The UTC floating-point second in the range [0, 60).
 *
 * @return  An #astro_time_t value that represents the given calendar date and time.
 */
astro_time_t Astronomy_MakeTime(int year, int month, int day, int hour, int minute, double second)
{
    astro_time_t time;
    int64_t y = (int64_t)year;
    int64_t m = (int64_t)month;
    int64_t d = (int64_t)day;
    int64_t f = (14 - m) / 12;

    /*
        This formula is adapted from NOVAS C 3.1 function julian_date(),
        which in turn comes from Henry F. Fliegel & Thomas C. Van Flendern:
        Communications of the ACM, Vol 11, No 10, October 1968, p. 657.
        See: https://dl.acm.org/doi/pdf/10.1145/364096.364097

        [Don Cross - 2023-02-25] I modified the formula so that it will
        work correctly with years as far back as -999999.
    */
    int64_t y2000 = (
        (d - 365972956)
        + (1461*(y + 1000000 - f))/4
        + (367*(m - 2 + 12*f))/12
        - (3*((y + 1000100 - f) / 100))/4
    );

    time.ut = (y2000 - 0.5) + (hour / 24.0) + (minute / 1440.0) + (second / 86400.0);
    time.tt = TerrestrialTime(time.ut);
    time.psi = time.eps = time.st = NAN;

    return time;
}

/**
 * @brief   Calculates the sum or difference of an #astro_time_t with a specified floating point number of days.
 *
 * Sometimes we need to adjust a given #astro_time_t value by a certain amount of time.
 * This function adds the given real number of days in `days` to the date and time in `time`.
 *
 * More precisely, the result's Universal Time field `ut` is exactly adjusted by `days` and
 * the Terrestrial Time field `tt` is adjusted correctly for the resulting UTC date and time,
 * according to the historical and predictive Delta-T model provided by the
 * [United States Naval Observatory](http://maia.usno.navy.mil/ser7/).
 *
 * The value stored in `time` will not be modified; it is passed by value.
 *
 * @param time  A date and time for which to calculate an adjusted date and time.
 * @param days  A floating point number of days by which to adjust `time`. May be negative, 0, or positive.
 * @return  A date and time that is conceptually equal to `time + days`.
 */
astro_time_t Astronomy_AddDays(astro_time_t time, double days)
{
    /*
        This is slightly wrong, but the error is tiny.
        We really should be adding to TT, not to UT.
        But using TT would require creating an inverse function for DeltaT,
        which would be quite a bit of extra calculation.
        I estimate the error is in practice on the order of 10^(-7)
        times the value of 'days'.
        This is based on a typical drift of 1 second per year between UT and TT.
    */

    astro_time_t sum;

    sum.ut = time.ut + days;
    sum.tt = TerrestrialTime(sum.ut);
    sum.eps = sum.psi = sum.st = NAN;

    return sum;
}

/**
 * @brief   Moves an #astro_time_t by a short span measured on both clocks at once.
 *
 * AstronomyKit local patch (TT-continuous offsets). #Astronomy_AddDays adds to UT and
 * recomputes TT from the Delta T model, so where the model's pieces meet with a step
 * (Espenak-Meeus steps back 0.088 seconds in January 1900), an offset that crosses the
 * join moves TT by `days` plus or minus the step. Numerical derivatives and the light
 * travel correction difference positions that depend on TT, and a step inside their span
 * corrupts them. This function adds `days` to both `ut` and `tt`, so TT moves by exactly
 * `days` and neither clock steps. Its UT differs from the Delta T model's inverse of the
 * new TT by Delta T's change over `days`, under 1e-7 of `days` for any model in use.
 *
 * Use it for offsets of about a day or less around a time that is then evaluated as a
 * whole; use #Astronomy_AddDays to step a search through civil time.
 *
 * @param time  The time to move.
 * @param days  The span in days. May be negative, 0, or positive.
 * @return  `time` with `days` added to both its UT and its TT.
 */
astro_time_t Astronomy_AddTerrestrialDays(astro_time_t time, double days)
{
    astro_time_t sum;

    sum.ut = time.ut + days;
    sum.tt = time.tt + days;
    sum.eps = sum.psi = sum.st = NAN;

    return sum;
}

/**
 * @brief   Creates an #astro_time_t value from a given calendar date and time.
 *
 * This function is similar to #Astronomy_MakeTime, only it receives a
 * UTC calendar date and time in the form of an #astro_utc_t structure instead of
 * as separate numeric parameters.  Astronomy_TimeFromUtc is the inverse of
 * #Astronomy_UtcFromTime.
 *
 * @param utc   The UTC calendar date and time to be converted to #astro_time_t.
 * @return  A value that can be used for astronomical calculations for the given date and time.
 */
astro_time_t Astronomy_TimeFromUtc(astro_utc_t utc)
{
    return Astronomy_MakeTime(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);
}

/**
 * @brief Determines the calendar year, month, day, and time from an #astro_time_t value.
 *
 * After calculating the date and time of an astronomical event in the form of
 * an #astro_time_t value, it is often useful to display the result in a human-readable
 * form. This function converts the linear time scales in the `ut` field of #astro_time_t
 * into a calendar date and time: year, month, day, hours, minutes, and seconds, expressed
 * in UTC.
 *
 * @param time  The astronomical time value to be converted to calendar date and time.
 * @return  A date and time broken out into conventional year, month, day, hour, minute, and second.
 */
astro_utc_t Astronomy_UtcFromTime(astro_time_t time)
{
    /* Adapted from the NOVAS C 3.1 function cal_date() */
    astro_utc_t utc;
    int64_t jd, k, m, n;
    double djd, x;
    const int64_t c = 2500;

    djd = time.ut + 2451545.5;
    jd = (int64_t)floor(djd);

    x = 24.0 * fmod(djd, 1.0);
    if (x < 0.0)
        x += 24.0;
    utc.hour = (int)x;
    x = 60.0 * fmod(x, 1.0);
    utc.minute = (int)x;
    utc.second = 60.0 * fmod(x, 1.0);

    /*
        This is my own adjustment to the NOVAS cal_date logic
        so that it can handle dates much farther back in the past.
        I add c*400 years worth of days at the front,
        then subtract c*400 years at the back,
        which avoids negative values in the formulas that mess up
        the calendar date calculations.
        Any multiple of 400 years has the same number of days,
        because it eliminates all the special cases for leap years.
    */
    k = jd + (68569 + c*146097);
    n = (4 * k) / 146097;
    k = k - (146097 * n + 3)/4;
    m = (4000 * (k+1)) / 1461001;
    k = k - (1461 * m)/4 + 31;

    utc.month = (int) ((80 * k) / 2447);
    utc.day = (int) (k - (2447*utc.month)/80);
    k = utc.month / 11;

    utc.month = (int) (utc.month + 2 - 12*k);
    utc.year = (int) (100 * (n - 49) + m + k - 400*c);

    return utc;
}


/**
 * @brief Formats an #astro_time_t value as an ISO 8601 string.
 *
 * Given an #astro_time_t value `time`, formats it as an ISO 8601
 * string to the resolution specified by the `format` parameter.
 * The result is stored in the `text` buffer whose capacity in bytes
 * is specified by `size`.
 *
 * @param time
 *      The date and time whose civil time `time.ut` is to be formatted as an ISO 8601 string.
 *      If the civil time is outside the year range -999999 to +999999, the function fails
 *      and returns `ASTRO_BAD_TIME`. Years prior to 1583 are treated as if they are
 *      using the modern Gregorian calendar, even when the Julian calendar was actually in effect.
 *      The year before 1 AD, commonly known as 1 BC, is represented by the value 0.
 *      The year 2 BC is represented by -1, etc.
 *
 * @param format
 *      Specifies the resolution to which the date and time should be formatted,
 *      as explained at #astro_time_format_t.
 *      If the value of `format` is not recognized, the function fails and
 *      returns `ASTRO_INVALID_PARAMETER`.
 *
 * @param text
 *      A pointer to a text buffer to receive the output.
 *      If `text` is `NULL`, this function returns `ASTRO_INVALID_PARAMETER`.
 *      If the function fails for any reason, and `text` is not `NULL`,
 *      and `size` is greater than 0, the `text` buffer is set to an empty string.
 *
 * @param size
 *      The size in bytes of the buffer pointed to by `text`. The buffer must
 *      be large enough to accomodate the output format selected by the
 *      `format` parameter, as specified at #astro_time_format_t.
 *      If `size` is too small to hold the string as specified by `format`,
 *      the `text` buffer is set to `""` (if possible)
 *      and the function returns `ASTRO_BUFFER_TOO_SMALL`.
 *      A buffer that is `TIME_TEXT_BYTES` (28) bytes or larger is always large enough for this function.
 *
 * @return `ASTRO_SUCCESS` on success; otherwise an error as described in the parameter notes.
 */
astro_status_t Astronomy_FormatTime(
    astro_time_t time,
    astro_time_format_t format,
    char *text,
    size_t size)
{
    int nprinted;
    double rounding;
    size_t min_size;
    astro_utc_t utc;
    char ytext[20];   /* worst case: "+999999" = 8 characters including terminal '\0'. But gcc 12.2 still complains! */

    if (text == NULL)
        return ASTRO_INVALID_PARAMETER;

    if (size == 0)
        return ASTRO_BUFFER_TOO_SMALL;

    text[0] = '\0';     /* initialize to empty string, in case an error occurs */

    /* Validate 'size' parameter and perform date/time rounding. */
    switch (format)
    {
    case TIME_FORMAT_DAY:
        min_size = 11;                          /* "2020-12-31" */
        rounding = 0.0;                         /* no rounding */
        break;

    case TIME_FORMAT_MINUTE:
        min_size = 18;                          /* "2020-12-31T15:47Z" */
        rounding = 0.5 / (24.0 * 60.0);         /* round to nearest minute */
        break;

    case TIME_FORMAT_SECOND:
        min_size = 21;                          /* "2020-12-31T15:47:59Z" */
        rounding = 0.5 / (24.0 * 3600.0);       /* round to nearest second */
        break;

    case TIME_FORMAT_MILLI:
        min_size = 25;                          /* "2020-12-31T15:47:59.123Z" */
        rounding = 0.5 / (24.0 * 3600000.0);    /* round to nearest millisecond */
        break;

    default:
        return ASTRO_INVALID_PARAMETER;
    }

    /* Perform rounding. */
    time.ut += rounding;

    /* Convert linear J2000 days to Gregorian UTC date/time. */
    utc = Astronomy_UtcFromTime(time);
    if (utc.year < -999999 || utc.year > +999999)
        return ASTRO_BAD_TIME;

    if (utc.year < 0)
    {
        snprintf(ytext, sizeof(ytext), "-%06d", -utc.year);
        min_size += 3;  /* '-' prefix and two extra year digits. */
    }
    else if (utc.year <= 9999)
    {
        snprintf(ytext, sizeof(ytext), "%04d", utc.year);
    }
    else
    {
        snprintf(ytext, sizeof(ytext), "+%06d", utc.year);
        min_size += 3;  /* '+' prefix and two extra year digits. */
    }

    /* Check for insufficient buffer size. */
    if (size < min_size)
        return ASTRO_BUFFER_TOO_SMALL;

    /* Format the string. */
    switch (format)
    {
    case TIME_FORMAT_DAY:
        nprinted = snprintf(text, size, "%s-%02d-%02d",
            ytext, utc.month, utc.day);
        break;

    case TIME_FORMAT_MINUTE:
        nprinted = snprintf(text, size, "%s-%02d-%02dT%02d:%02dZ",
            ytext, utc.month, utc.day,
            utc.hour, utc.minute);
        break;

    case TIME_FORMAT_SECOND:
        nprinted = snprintf(text, size, "%s-%02d-%02dT%02d:%02d:%02.0lfZ",
            ytext, utc.month, utc.day,
            utc.hour, utc.minute, floor(utc.second));
        break;

    case TIME_FORMAT_MILLI:
        nprinted = snprintf(text, size, "%s-%02d-%02dT%02d:%02d:%06.3lfZ",
            ytext, utc.month, utc.day,
            utc.hour, utc.minute, floor(1000.0 * utc.second) / 1000.0);
        break;

    default:
        /* We should have already failed for any unknown 'format' value. */
        return ASTRO_INTERNAL_ERROR;
    }

    if (nprinted < 0)
        return ASTRO_INTERNAL_ERROR;    /* should not be possible for snprintf to return a negative number */

    if ((size_t)(1+nprinted) != min_size)
        return ASTRO_INTERNAL_ERROR;    /* there must be a bug calculating min_size or formatting the string */

    return ASTRO_SUCCESS;
}


/* AstronomyKit local patch (nutation series): defined after the series cosine, which it uses. */
static void iau2000b(astro_time_t *time);

static double mean_obliq(double tt)
{
    double t = tt / 36525.0;
    double asec =
        (((( -  0.0000000434   * t
             -  0.000000576  ) * t
             +  0.00200340   ) * t
             -  0.0001831    ) * t
             - 46.836769     ) * t + 84381.406;

    return asec / 3600.0;
}

/** @cond DOXYGEN_SKIP */
typedef struct
{
    double tt;
    double dpsi;
    double deps;
    double ee;
    double mobl;
    double tobl;
}
earth_tilt_t;
/** @endcond */

static earth_tilt_t e_tilt(astro_time_t *time)
{
    earth_tilt_t et;

    /* There is no good answer for what to do if time==NULL. Callers must prevent! */

    iau2000b(time);
    et.dpsi = time->psi;
    et.deps = time->eps;
    et.mobl = mean_obliq(time->tt);
    et.tobl = et.mobl + (et.deps / 3600.0);
    et.tt = time->tt;
    et.ee = et.dpsi * cos(et.mobl * DEG2RAD) / 15.0;

    return et;
}

static double era(double ut)        /* Earth Rotation Angle */
{
    double thet1 = 0.7790572732640 + 0.00273781191135448 * ut;
    double thet3 = fmod(ut, 1.0);
    double theta = 360.0 * fmod(thet1 + thet3, 1.0);
    if (theta < 0.0)
        theta += 360.0;

    return theta;
}

/**
 * @brief Calculates Greenwich Apparent Sidereal Time (GAST).
 *
 * Given a date and time, this function calculates the rotation of the
 * Earth, represented by the equatorial angle of the Greenwich prime meridian
 * with respect to distant stars (not the Sun, which moves relative to background
 * stars by almost one degree per day).
 * This angle is called Greenwich Apparent Sidereal Time (GAST).
 * GAST is measured in sidereal hours in the half-open range [0, 24).
 * When GAST = 0, it means the prime meridian is aligned with the of-date equinox,
 * corrected at that time for precession and nutation of the Earth's axis.
 * In this context, the "equinox" is the direction in space where the Earth's
 * orbital plane (the ecliptic) intersects with the plane of the Earth's equator,
 * at the location on the Earth's orbit of the (seasonal) March equinox.
 * As the Earth rotates, GAST increases from 0 up to 24 sidereal hours,
 * then starts over at 0.
 * To convert to degrees, multiply the return value by 15.
 *
 * @param time
 *      The date and time for which to find GAST.
 *      The parameter is passed by address because it can be modified by the call:
 *      As an optimization, this function caches the sidereal time value in `time`,
 *      unless it has already been cached, in which case the cached value is reused.
 *      If the `time` pointer is NULL, this function returns a NAN value.
 *
 * @returns {number}
 */
double Astronomy_SiderealTime(astro_time_t *time)
{
    if (time == NULL)
        return NAN;

    if (isnan(time->st))
    {
        double t = time->tt / 36525.0;
        double eqeq = 15.0 * e_tilt(time).ee;    /* Replace with eqeq=0 to get GMST instead of GAST (if we ever need it) */
        double theta = era(time->ut);
        double st = (eqeq + 0.014506 +
            (((( -    0.0000000368   * t
                -    0.000029956  ) * t
                -    0.00000044   ) * t
                +    1.3915817    ) * t
                + 4612.156534     ) * t);

        double gst = fmod(st/3600.0 + theta, 360.0) / 15.0;
        if (gst < 0.0)
            gst += 24.0;

        time->st = gst;
    }

    return time->st;     /* return sidereal hours in the half-open range [0, 24). */
}


/*------------------ VSOP ------------------*/

/** @cond DOXYGEN_SKIP */
typedef struct
{
    double amplitude;
    double phase;
    double frequency;
}
vsop_term_t;

typedef struct
{
    int nterms;
    const vsop_term_t *term;
}
vsop_series_t;

typedef struct
{
    int nseries;
    const vsop_series_t *series;
}
vsop_formula_t;

typedef struct
{
    const vsop_formula_t formula[3];
}
vsop_model_t;

/** @endcond */

static const vsop_term_t vsop_lon_Mercury_0[] =
{
    { 4.40250710144, 0.00000000000, 0.00000000000 },
    { 0.40989414977, 1.48302034195, 26087.90314157420 },
    { 0.05046294200, 4.47785489551, 52175.80628314840 },
    { 0.00855346844, 1.16520322459, 78263.70942472259 },
    { 0.00165590362, 4.11969163423, 104351.61256629678 },
    { 0.00034561897, 0.77930768443, 130439.51570787099 },
    { 0.00007583476, 3.71348404924, 156527.41884944518 },
    { 0.00003559745, 1.51202675145, 1109.37855209340 },
    { 0.00001726011, 0.35832267096, 182615.32199101939 },
    { 0.00001803464, 4.10333184211, 5661.33204915220 },
    { 0.00001364681, 4.59918328256, 27197.28169366760 },
    { 0.00001589923, 2.99510423560, 25028.52121138500 },
    { 0.00001017332, 0.88031393824, 31749.23519072640 },
    { 0.00000714182, 1.54144862493, 24978.52458948080 },
    { 0.00000643759, 5.30266166599, 21535.94964451540 },
    { 0.00000404200, 3.28228953196, 208703.22513259358 },
    { 0.00000352442, 5.24156372447, 20426.57109242200 },
    { 0.00000343312, 5.76531703870, 955.59974160860 },
    { 0.00000339215, 5.86327825226, 25558.21217647960 },
    { 0.00000451137, 6.04989282259, 51116.42435295920 },
    { 0.00000325329, 1.33674488758, 53285.18483524180 },
    { 0.00000259588, 0.98732774234, 4551.95349705880 },
    { 0.00000345213, 2.79211954198, 15874.61759536320 },
    { 0.00000272948, 2.49451165014, 529.69096509460 },
    { 0.00000234831, 0.26672019191, 11322.66409830440 },
    { 0.00000238793, 0.11343914400, 1059.38193018920 },
    { 0.00000264336, 3.91705105199, 57837.13833230060 },
    { 0.00000216645, 0.65987085507, 13521.75144159140 },
    { 0.00000183358, 2.62878694178, 27043.50288318280 },
    { 0.00000175965, 4.53636943501, 51066.42773105500 },
    { 0.00000181629, 2.43413603252, 25661.30495069820 },
    { 0.00000208996, 2.09178645677, 47623.85278608960 },
    { 0.00000172642, 2.45200139206, 24498.83024629040 },
    { 0.00000142317, 3.36004060149, 37410.56723987860 },
    { 0.00000137943, 0.29098540695, 10213.28554621100 },
    { 0.00000118233, 2.78149967294, 77204.32749453338 },
    { 0.00000096860, 6.20398934398, 234791.12827416777 },
    { 0.00000125219, 3.72079967668, 39609.65458316560 },
    { 0.00000086819, 2.64218953915, 51646.11531805379 },
    { 0.00000086723, 1.95952945936, 46514.47423399620 },
    { 0.00000089987, 5.85243663953, 41962.52073693740 },
    { 0.00000084970, 4.33100839394, 79373.08797681599 },
    { 0.00000068493, 0.63424913908, 83925.04147387479 },
    { 0.00000056532, 5.11921332252, 73711.75592766379 },
    { 0.00000023656, 2.84171550782, 260879.03141574195 }
};

static const vsop_term_t vsop_lon_Mercury_1[] =
{
    { 26087.90313685529, 0.00000000000, 0.00000000000 },
    { 0.01131199811, 6.21874197797, 26087.90314157420 },
    { 0.00292242298, 3.04449355541, 52175.80628314840 },
    { 0.00075775081, 6.08568821653, 78263.70942472259 },
    { 0.00019676525, 2.80965111777, 104351.61256629678 },
    { 0.00005119883, 5.79432353574, 130439.51570787099 },
    { 0.00001336324, 2.47909947012, 156527.41884944518 }
};

static const vsop_series_t vsop_lon_Mercury[] =
{
    { 45, vsop_lon_Mercury_0 },
    { 7, vsop_lon_Mercury_1 }
};

static const vsop_term_t vsop_lat_Mercury_0[] =
{
    { 0.11737528961, 1.98357498767, 26087.90314157420 },
    { 0.02388076996, 5.03738959686, 52175.80628314840 },
    { 0.01222839532, 3.14159265359, 0.00000000000 },
    { 0.00543251810, 1.79644363964, 78263.70942472259 },
    { 0.00129778770, 4.83232503958, 104351.61256629678 },
    { 0.00031866927, 1.58088495658, 130439.51570787099 },
    { 0.00007963301, 4.60972126127, 156527.41884944518 },
    { 0.00002014189, 1.35324164377, 182615.32199101939 },
    { 0.00000513953, 4.37835406663, 208703.22513259358 }
};

static const vsop_term_t vsop_lat_Mercury_1[] =
{
    { 0.00274646065, 3.95008450011, 26087.90314157420 },
    { 0.00099737713, 3.14159265359, 0.00000000000 },
    { 0.00018772047, 0.05141288887, 78263.70942472259 },
    { 0.00023970726, 2.53272082947, 52175.80628314840 },
    { 0.00008097508, 3.20946389315, 104351.61256629678 }
};

static const vsop_series_t vsop_lat_Mercury[] =
{
    { 9, vsop_lat_Mercury_0 },
    { 5, vsop_lat_Mercury_1 }
};

static const vsop_term_t vsop_rad_Mercury_0[] =
{
    { 0.39528271651, 0.00000000000, 0.00000000000 },
    { 0.07834131818, 6.19233722598, 26087.90314157420 },
    { 0.00795525558, 2.95989690104, 52175.80628314840 },
    { 0.00121281764, 6.01064153797, 78263.70942472259 },
    { 0.00021921969, 2.77820093972, 104351.61256629678 },
    { 0.00004354065, 5.82894543774, 130439.51570787099 },
    { 0.00000918228, 2.59650562845, 156527.41884944518 },
    { 0.00000260033, 3.02817753901, 27197.28169366760 },
    { 0.00000289955, 1.42441937278, 25028.52121138500 },
    { 0.00000201855, 5.64725040577, 182615.32199101939 },
    { 0.00000201498, 5.59227727403, 31749.23519072640 },
    { 0.00000141980, 6.25264206514, 24978.52458948080 },
    { 0.00000100144, 3.73435615066, 21535.94964451540 },
    { 0.00000077561, 3.66972523786, 20426.57109242200 },
    { 0.00000063277, 4.29905566028, 25558.21217647960 },
    { 0.00000062951, 4.76588960835, 1059.38193018920 },
    { 0.00000066753, 2.52520325806, 5661.33204915220 },
    { 0.00000075500, 4.47428643135, 51116.42435295920 },
    { 0.00000048265, 6.06824353565, 53285.18483524180 },
    { 0.00000045748, 2.41480951848, 208703.22513259358 },
    { 0.00000035224, 1.05917819542, 27043.50288318280 },
    { 0.00000040815, 2.35882025197, 57837.13833230060 },
    { 0.00000044235, 1.21957279824, 15874.61759536320 },
    { 0.00000033873, 0.86381554218, 25661.30495069820 },
    { 0.00000037203, 0.51733923686, 47623.85278608960 },
    { 0.00000010612, 5.46555459994, 234791.12827416777 }
};

static const vsop_term_t vsop_rad_Mercury_1[] =
{
    { 0.00217347740, 4.65617158665, 26087.90314157420 },
    { 0.00044141826, 1.42385544001, 52175.80628314840 },
    { 0.00010094479, 4.47466326327, 78263.70942472259 },
    { 0.00002432805, 1.24226083323, 104351.61256629678 },
    { 0.00001624367, 0.00000000000, 0.00000000000 },
    { 0.00000603996, 4.29303116468, 130439.51570787099 }
};

static const vsop_series_t vsop_rad_Mercury[] =
{
    { 26, vsop_rad_Mercury_0 },
    { 6, vsop_rad_Mercury_1 }
};

;
static const vsop_term_t vsop_lon_Venus_0[] =
{
    { 3.17614666774, 0.00000000000, 0.00000000000 },
    { 0.01353968419, 5.59313319619, 10213.28554621100 },
    { 0.00089891645, 5.30650047764, 20426.57109242200 },
    { 0.00005477194, 4.41630661466, 7860.41939243920 },
    { 0.00003455741, 2.69964447820, 11790.62908865880 },
    { 0.00002372061, 2.99377542079, 3930.20969621960 },
    { 0.00001317168, 5.18668228402, 26.29831979980 },
    { 0.00001664146, 4.25018630147, 1577.34354244780 },
    { 0.00001438387, 4.15745084182, 9683.59458111640 },
    { 0.00001200521, 6.15357116043, 30639.85663863300 },
    { 0.00000761380, 1.95014701047, 529.69096509460 },
    { 0.00000707676, 1.06466702668, 775.52261132400 },
    { 0.00000584836, 3.99839888230, 191.44826611160 },
    { 0.00000769314, 0.81629615196, 9437.76293488700 },
    { 0.00000499915, 4.12340212820, 15720.83878487840 },
    { 0.00000326221, 4.59056477038, 10404.73381232260 },
    { 0.00000429498, 3.58642858577, 19367.18916223280 },
    { 0.00000326967, 5.67736584311, 5507.55323866740 },
    { 0.00000231937, 3.16251059356, 9153.90361602180 },
    { 0.00000179695, 4.65337908917, 1109.37855209340 },
    { 0.00000128263, 4.22604490814, 20.77539549240 },
    { 0.00000155464, 5.57043891690, 19651.04848109800 },
    { 0.00000127907, 0.96209781904, 5661.33204915220 },
    { 0.00000105547, 1.53721203088, 801.82093112380 },
    { 0.00000085722, 0.35589247720, 3154.68708489560 },
    { 0.00000099121, 0.83288208931, 213.29909543800 },
    { 0.00000098804, 5.39389623302, 13367.97263110660 },
    { 0.00000082094, 3.21597037872, 18837.49819713819 },
    { 0.00000088031, 3.88868864136, 9999.98645077300 },
    { 0.00000071577, 0.11145736657, 11015.10647733480 },
    { 0.00000056122, 4.24039842051, 7.11354700080 },
    { 0.00000070239, 0.67458825333, 23581.25817731760 },
    { 0.00000050796, 0.24531639097, 11322.66409830440 },
    { 0.00000046111, 5.31576442737, 18073.70493865020 },
    { 0.00000044576, 6.06281108312, 40853.14218484400 },
    { 0.00000042594, 5.32873395426, 2352.86615377180 },
    { 0.00000042635, 1.79955442721, 7084.89678111520 },
    { 0.00000041177, 0.36241012200, 382.89653222320 },
    { 0.00000035749, 2.70448479527, 10206.17199921020 },
    { 0.00000033893, 2.02347385644, 6283.07584999140 },
    { 0.00000029170, 3.59117396909, 22003.91463486980 },
    { 0.00000028479, 2.22375430133, 1059.38193018920 },
    { 0.00000029850, 4.02177029338, 10239.58386601080 },
    { 0.00000033252, 2.10025580495, 27511.46787353720 },
    { 0.00000030172, 4.94191918273, 13745.34623902240 },
    { 0.00000029252, 3.51392387787, 283.85931886520 },
    { 0.00000024424, 2.70177487840, 8624.21265092720 },
    { 0.00000020274, 3.79493777545, 14143.49524243060 },
    { 0.00000026260, 0.54067510171, 17298.18232732620 },
    { 0.00000019069, 6.12025555817, 29050.78374334920 },
    { 0.00000018269, 3.04740409161, 19999.97290154599 },
    { 0.00000017118, 3.51922693724, 31441.67756975680 }
};

static const vsop_term_t vsop_lon_Venus_1[] =
{
    { 10213.28554621638, 0.00000000000, 0.00000000000 },
    { 0.00095617813, 2.46406511110, 10213.28554621100 },
    { 0.00007787201, 0.62478482220, 20426.57109242200 }
};

static const vsop_series_t vsop_lon_Venus[] =
{
    { 52, vsop_lon_Venus_0 },
    { 3, vsop_lon_Venus_1 }
};

static const vsop_term_t vsop_lat_Venus_0[] =
{
    { 0.05923638472, 0.26702775812, 10213.28554621100 },
    { 0.00040107978, 1.14737178112, 20426.57109242200 },
    { 0.00032814918, 3.14159265359, 0.00000000000 },
    { 0.00001011392, 1.08946119730, 30639.85663863300 }
};

static const vsop_term_t vsop_lat_Venus_1[] =
{
    { 0.00287821243, 1.88964962838, 10213.28554621100 }
};

static const vsop_series_t vsop_lat_Venus[] =
{
    { 4, vsop_lat_Venus_0 },
    { 1, vsop_lat_Venus_1 }
};

static const vsop_term_t vsop_rad_Venus_0[] =
{
    { 0.72334820891, 0.00000000000, 0.00000000000 },
    { 0.00489824182, 4.02151831717, 10213.28554621100 },
    { 0.00001658058, 4.90206728031, 20426.57109242200 },
    { 0.00001632096, 2.84548795207, 7860.41939243920 },
    { 0.00001378043, 1.12846591367, 11790.62908865880 },
    { 0.00000498395, 2.58682193892, 9683.59458111640 },
    { 0.00000373958, 1.42314832858, 3930.20969621960 },
    { 0.00000263615, 5.52938716941, 9437.76293488700 },
    { 0.00000237454, 2.55136053886, 15720.83878487840 },
    { 0.00000221985, 2.01346696541, 19367.18916223280 },
    { 0.00000119466, 3.01975080538, 10404.73381232260 },
    { 0.00000125896, 2.72769850819, 1577.34354244780 },
    { 0.00000076176, 1.59574968674, 9153.90361602180 },
    { 0.00000085337, 3.98598666191, 19651.04848109800 },
    { 0.00000074347, 4.11957779786, 5507.55323866740 },
    { 0.00000041902, 1.64282225331, 18837.49819713819 },
    { 0.00000042494, 3.81864493274, 13367.97263110660 },
    { 0.00000039437, 5.39018702243, 23581.25817731760 },
    { 0.00000027555, 5.72392434415, 775.52261132400 },
    { 0.00000027288, 4.82140494620, 11015.10647733480 },
    { 0.00000031274, 2.31806719544, 9999.98645077300 },
    { 0.00000019811, 0.53189302682, 27511.46787353720 },
    { 0.00000011434, 4.56780914249, 29050.78374334920 },
    { 0.00000010653, 1.95585283247, 31441.67756975680 }
};

static const vsop_term_t vsop_rad_Venus_1[] =
{
    { 0.00034551041, 0.89198706276, 10213.28554621100 }
};

static const vsop_series_t vsop_rad_Venus[] =
{
    { 24, vsop_rad_Venus_0 },
    { 1, vsop_rad_Venus_1 }
};

;
static const vsop_term_t vsop_lon_Earth_0[] =
{
    { 1.75347045673, 0.00000000000, 0.00000000000 },
    { 0.03341656453, 4.66925680415, 6283.07584999140 },
    { 0.00034894275, 4.62610242189, 12566.15169998280 },
    { 0.00003417572, 2.82886579754, 3.52311834900 },
    { 0.00003497056, 2.74411783405, 5753.38488489680 },
    { 0.00003135899, 3.62767041756, 77713.77146812050 },
    { 0.00002676218, 4.41808345438, 7860.41939243920 },
    { 0.00002342691, 6.13516214446, 3930.20969621960 },
    { 0.00001273165, 2.03709657878, 529.69096509460 },
    { 0.00001324294, 0.74246341673, 11506.76976979360 },
    { 0.00000901854, 2.04505446477, 26.29831979980 },
    { 0.00001199167, 1.10962946234, 1577.34354244780 },
    { 0.00000857223, 3.50849152283, 398.14900340820 },
    { 0.00000779786, 1.17882681962, 5223.69391980220 },
    { 0.00000990250, 5.23268072088, 5884.92684658320 },
    { 0.00000753141, 2.53339052847, 5507.55323866740 },
    { 0.00000505267, 4.58292599973, 18849.22754997420 },
    { 0.00000492392, 4.20505711826, 775.52261132400 },
    { 0.00000356672, 2.91954114478, 0.06731030280 },
    { 0.00000284125, 1.89869240932, 796.29800681640 },
    { 0.00000242879, 0.34481445893, 5486.77784317500 },
    { 0.00000317087, 5.84901948512, 11790.62908865880 },
    { 0.00000271112, 0.31486255375, 10977.07880469900 },
    { 0.00000206217, 4.80646631478, 2544.31441988340 },
    { 0.00000205478, 1.86953770281, 5573.14280143310 },
    { 0.00000202318, 2.45767790232, 6069.77675455340 },
    { 0.00000126225, 1.08295459501, 20.77539549240 },
    { 0.00000155516, 0.83306084617, 213.29909543800 },
    { 0.00000115132, 0.64544911683, 0.98032106820 },
    { 0.00000102851, 0.63599845579, 4694.00295470760 },
    { 0.00000101724, 4.26679801980, 7.11354700080 },
    { 0.00000099206, 6.20992926918, 2146.16541647520 },
    { 0.00000132212, 3.41118292683, 2942.46342329160 },
    { 0.00000097607, 0.68101342359, 155.42039943420 },
    { 0.00000085128, 1.29870764804, 6275.96230299060 },
    { 0.00000074651, 1.75508913300, 5088.62883976680 },
    { 0.00000101895, 0.97569280312, 15720.83878487840 },
    { 0.00000084711, 3.67080093031, 71430.69561812909 },
    { 0.00000073547, 4.67926633877, 801.82093112380 },
    { 0.00000073874, 3.50319414955, 3154.68708489560 },
    { 0.00000078757, 3.03697458703, 12036.46073488820 },
    { 0.00000079637, 1.80791287082, 17260.15465469040 },
    { 0.00000085803, 5.98322631260, 161000.68573767410 },
    { 0.00000056963, 2.78430458592, 6286.59896834040 },
    { 0.00000061148, 1.81839892984, 7084.89678111520 },
    { 0.00000069627, 0.83297621398, 9437.76293488700 },
    { 0.00000056116, 4.38694865354, 14143.49524243060 },
    { 0.00000062449, 3.97763912806, 8827.39026987480 },
    { 0.00000051145, 0.28306832879, 5856.47765911540 },
    { 0.00000055577, 3.47006059924, 6279.55273164240 },
    { 0.00000041036, 5.36817592855, 8429.24126646660 },
    { 0.00000051605, 1.33282739866, 1748.01641306700 },
    { 0.00000051992, 0.18914947184, 12139.55350910680 },
    { 0.00000049000, 0.48735014197, 1194.44701022460 },
    { 0.00000039200, 6.16833020996, 10447.38783960440 },
    { 0.00000035570, 1.77596889200, 6812.76681508600 },
    { 0.00000036770, 6.04133863162, 10213.28554621100 },
    { 0.00000036596, 2.56957481827, 1059.38193018920 },
    { 0.00000033296, 0.59310278598, 17789.84561978500 },
    { 0.00000035954, 1.70875808777, 2352.86615377180 },
    { 0.00000040938, 2.39850938714, 19651.04848109800 },
    { 0.00000030047, 2.73975124088, 1349.86740965880 },
    { 0.00000030412, 0.44294464169, 83996.84731811189 },
    { 0.00000023663, 0.48473622521, 8031.09226305840 },
    { 0.00000023574, 2.06528133162, 3340.61242669980 },
    { 0.00000021089, 4.14825468851, 951.71840625060 },
    { 0.00000024738, 0.21484762138, 3.59042865180 },
    { 0.00000025352, 3.16470891653, 4690.47983635860 },
    { 0.00000022823, 5.22195230819, 4705.73230754360 },
    { 0.00000021419, 1.42563910473, 16730.46368959580 },
    { 0.00000021891, 5.55594302779, 553.56940284240 },
    { 0.00000017481, 4.56052900312, 135.06508003540 },
    { 0.00000019927, 5.22209149316, 12168.00269657460 },
    { 0.00000019860, 5.77470242235, 6309.37416979120 },
    { 0.00000020300, 0.37133792946, 283.85931886520 },
    { 0.00000016225, 5.98837767951, 11769.85369316640 },
    { 0.00000015077, 4.19567163370, 6256.77753019160 },
    { 0.00000019124, 3.82219958698, 23581.25817731760 },
    { 0.00000018888, 5.38626892076, 149854.40013480789 },
    { 0.00000017898, 2.21490566029, 13367.97263110660 },
    { 0.00000013621, 1.88934516495, 7632.94325965020 },
    { 0.00000008356, 4.53902748706, 25132.30339996560 },
    { 0.00000009802, 5.24413877132, 27511.46787353720 },
    { 0.00000007756, 2.95728422442, 23013.53953958720 },
    { 0.00000006762, 5.91131766896, 90955.55169449610 },
    { 0.00000006153, 1.45823347458, 233141.31440436149 },
    { 0.00000005307, 0.38216728132, 31441.67756975680 },
    { 0.00000003650, 1.08344142571, 88860.05707098669 },
    { 0.00000003520, 2.05559692878, 244287.60000722769 },
    { 0.00000002876, 6.02633318445, 154717.60988768269 },
    { 0.00000001390, 5.42888623322, 143571.32428481648 },
    { 0.00000001253, 2.79844902576, 167283.76158766549 },
    { 0.00000000603, 3.81378921927, 316428.22867391503 }
};

static const vsop_term_t vsop_lon_Earth_1[] =
{
    { 6283.07584999140, 0.00000000000, 0.00000000000 },
    { 0.00206058863, 2.67823455808, 6283.07584999140 },
    { 0.00004303419, 2.63512233481, 12566.15169998280 }
};

static const vsop_term_t vsop_lon_Earth_2[] =
{
    { 0.00008721859, 1.07253635559, 6283.07584999140 }
};

static const vsop_series_t vsop_lon_Earth[] =
{
    { 93, vsop_lon_Earth_0 },
    { 3, vsop_lon_Earth_1 },
    { 1, vsop_lon_Earth_2 }
};

static const vsop_term_t vsop_lat_Earth_1[] =
{
    { 0.00227777722, 3.41376620530, 6283.07584999140 },
    { 0.00003805678, 3.37063423795, 12566.15169998280 }
};

static const vsop_series_t vsop_lat_Earth[] =
{
    { 0, NULL },
    { 2, vsop_lat_Earth_1 }
};

static const vsop_term_t vsop_rad_Earth_0[] =
{
    { 1.00013988784, 0.00000000000, 0.00000000000 },
    { 0.01670699632, 3.09846350258, 6283.07584999140 },
    { 0.00013956024, 3.05524609456, 12566.15169998280 },
    { 0.00003083720, 5.19846674381, 77713.77146812050 },
    { 0.00001628463, 1.17387558054, 5753.38488489680 },
    { 0.00001575572, 2.84685214877, 7860.41939243920 },
    { 0.00000924799, 5.45292236722, 11506.76976979360 },
    { 0.00000542439, 4.56409151453, 3930.20969621960 },
    { 0.00000472110, 3.66100022149, 5884.92684658320 },
    { 0.00000328780, 5.89983686142, 5223.69391980220 },
    { 0.00000345969, 0.96368627272, 5507.55323866740 },
    { 0.00000306784, 0.29867139512, 5573.14280143310 },
    { 0.00000174844, 3.01193636733, 18849.22754997420 },
    { 0.00000243181, 4.27349530790, 11790.62908865880 },
    { 0.00000211836, 5.84714461348, 1577.34354244780 },
    { 0.00000185740, 5.02199710705, 10977.07880469900 },
    { 0.00000109835, 5.05510635860, 5486.77784317500 },
    { 0.00000098316, 0.88681311278, 6069.77675455340 },
    { 0.00000086500, 5.68956418946, 15720.83878487840 },
    { 0.00000085831, 1.27079125277, 161000.68573767410 },
    { 0.00000062917, 0.92177053978, 529.69096509460 },
    { 0.00000057056, 2.01374292245, 83996.84731811189 },
    { 0.00000064908, 0.27251341435, 17260.15465469040 },
    { 0.00000049384, 3.24501240359, 2544.31441988340 },
    { 0.00000055736, 5.24159799170, 71430.69561812909 },
    { 0.00000042520, 6.01110257982, 6275.96230299060 },
    { 0.00000046966, 2.57799853213, 775.52261132400 },
    { 0.00000038963, 5.36063832897, 4694.00295470760 },
    { 0.00000044666, 5.53715663816, 9437.76293488700 },
    { 0.00000035661, 1.67447135798, 12036.46073488820 },
    { 0.00000031922, 0.18368299942, 5088.62883976680 },
    { 0.00000031846, 1.77775642078, 398.14900340820 },
    { 0.00000033193, 0.24370221704, 7084.89678111520 },
    { 0.00000038245, 2.39255343973, 8827.39026987480 },
    { 0.00000028468, 1.21344887533, 6286.59896834040 },
    { 0.00000037486, 0.82961281844, 19651.04848109800 },
    { 0.00000036957, 4.90107587287, 12139.55350910680 },
    { 0.00000034537, 1.84270693281, 2942.46342329160 },
    { 0.00000026275, 4.58896863104, 10447.38783960440 },
    { 0.00000024596, 3.78660838036, 8429.24126646660 },
    { 0.00000023587, 0.26866098169, 796.29800681640 },
    { 0.00000027795, 1.89934427832, 6279.55273164240 },
    { 0.00000023927, 4.99598548145, 5856.47765911540 },
    { 0.00000020345, 4.65282190725, 2146.16541647520 },
    { 0.00000023287, 2.80783632869, 14143.49524243060 },
    { 0.00000017958, 0.19871369960, 6812.76681508600 },
    { 0.00000017178, 4.43322156854, 10213.28554621100 },
    { 0.00000016190, 5.23159323213, 17789.84561978500 },
    { 0.00000017315, 6.15224075188, 16730.46368959580 },
    { 0.00000018834, 0.67280058021, 149854.40013480789 },
    { 0.00000018330, 2.25348717053, 23581.25817731760 },
    { 0.00000013639, 3.68511810757, 4705.73230754360 },
    { 0.00000009654, 3.67583728703, 27511.46787353720 },
    { 0.00000006147, 3.02863936662, 233141.31440436149 },
    { 0.00000005625, 4.34052903053, 90955.55169449610 },
    { 0.00000003519, 3.62639325753, 244287.60000722769 },
    { 0.00000002157, 1.31395211105, 154717.60988768269 },
    { 0.00000001970, 4.36931551625, 167283.76158766549 },
    { 0.00000000603, 5.38458554802, 316428.22867391503 }
};

static const vsop_term_t vsop_rad_Earth_1[] =
{
    { 0.00103018607, 1.10748968172, 6283.07584999140 },
    { 0.00001721238, 1.06442300386, 12566.15169998280 },
    { 0.00000702217, 3.14159265359, 0.00000000000 }
};

static const vsop_term_t vsop_rad_Earth_2[] =
{
    { 0.00004359385, 5.78455133808, 6283.07584999140 }
};

static const vsop_series_t vsop_rad_Earth[] =
{
    { 59, vsop_rad_Earth_0 },
    { 3, vsop_rad_Earth_1 },
    { 1, vsop_rad_Earth_2 }
};

;
static const vsop_term_t vsop_lon_Mars_0[] =
{
    { 6.20347711581, 0.00000000000, 0.00000000000 },
    { 0.18656368093, 5.05037100270, 3340.61242669980 },
    { 0.01108216816, 5.40099836344, 6681.22485339960 },
    { 0.00091798406, 5.75478744667, 10021.83728009940 },
    { 0.00027744987, 5.97049513147, 3.52311834900 },
    { 0.00010610235, 2.93958560338, 2281.23049651060 },
    { 0.00012315897, 0.84956094002, 2810.92146160520 },
    { 0.00008926784, 4.15697846427, 0.01725365220 },
    { 0.00008715691, 6.11005153139, 13362.44970679920 },
    { 0.00006797556, 0.36462229657, 398.14900340820 },
    { 0.00007774872, 3.33968761376, 5621.84292321040 },
    { 0.00003575078, 1.66186505710, 2544.31441988340 },
    { 0.00004161108, 0.22814971327, 2942.46342329160 },
    { 0.00003075252, 0.85696614132, 191.44826611160 },
    { 0.00002628117, 0.64806124465, 3337.08930835080 },
    { 0.00002937546, 6.07893711402, 0.06731030280 },
    { 0.00002389414, 5.03896442664, 796.29800681640 },
    { 0.00002579844, 0.02996736156, 3344.13554504880 },
    { 0.00001528141, 1.14979301996, 6151.53388830500 },
    { 0.00001798806, 0.65634057445, 529.69096509460 },
    { 0.00001264357, 3.62275122593, 5092.15195811580 },
    { 0.00001286228, 3.06796065034, 2146.16541647520 },
    { 0.00001546404, 2.91579701718, 1751.53953141600 },
    { 0.00001024902, 3.69334099279, 8962.45534991020 },
    { 0.00000891566, 0.18293837498, 16703.06213349900 },
    { 0.00000858759, 2.40093811940, 2914.01423582380 },
    { 0.00000832715, 2.46418619474, 3340.59517304760 },
    { 0.00000832720, 4.49495782139, 3340.62968035200 },
    { 0.00000712902, 3.66335473479, 1059.38193018920 },
    { 0.00000748723, 3.82248614017, 155.42039943420 },
    { 0.00000723861, 0.67497311481, 3738.76143010800 },
    { 0.00000635548, 2.92182225127, 8432.76438481560 },
    { 0.00000655162, 0.48864064125, 3127.31333126180 },
    { 0.00000550474, 3.81001042328, 0.98032106820 },
    { 0.00000552750, 4.47479317037, 1748.01641306700 },
    { 0.00000425966, 0.55364317304, 6283.07584999140 },
    { 0.00000415131, 0.49662285038, 213.29909543800 },
    { 0.00000472167, 3.62547124025, 1194.44701022460 },
    { 0.00000306551, 0.38052848348, 6684.74797174860 },
    { 0.00000312141, 0.99853944405, 6677.70173505060 },
    { 0.00000293198, 4.22131299634, 20.77539549240 },
    { 0.00000302375, 4.48618007156, 3532.06069281140 },
    { 0.00000274027, 0.54222167059, 3340.54511639700 },
    { 0.00000281079, 5.88163521788, 1349.86740965880 },
    { 0.00000231183, 1.28242156993, 3870.30339179440 },
    { 0.00000283602, 5.76885434940, 3149.16416058820 },
    { 0.00000236117, 5.75503217933, 3333.49887969900 },
    { 0.00000274033, 0.13372524985, 3340.67973700260 },
    { 0.00000299395, 2.78323740866, 6254.62666252360 },
    { 0.00000204162, 2.82133445874, 1221.84856632140 },
    { 0.00000238866, 5.37153646326, 4136.91043351620 },
    { 0.00000188648, 1.49104066040, 9492.14631500480 },
    { 0.00000221228, 3.50466812198, 382.89653222320 },
    { 0.00000179196, 1.00561962003, 951.71840625060 },
    { 0.00000172117, 0.43943649536, 5486.77784317500 },
    { 0.00000193118, 3.35716641911, 3.59042865180 },
    { 0.00000144304, 1.41874112114, 135.06508003540 },
    { 0.00000160016, 3.94857092451, 4562.46099302120 },
    { 0.00000174072, 2.41361337725, 553.56940284240 },
    { 0.00000130989, 4.04491134956, 12303.06777661000 },
    { 0.00000138243, 4.30145122848, 7.11354700080 },
    { 0.00000128062, 1.80665816220, 5088.62883976680 },
    { 0.00000139898, 3.32595559208, 2700.71514038580 },
    { 0.00000128105, 2.20807538189, 1592.59601363280 },
    { 0.00000116944, 3.12806863456, 7903.07341972100 },
    { 0.00000110378, 1.05194545948, 242.72860397400 },
    { 0.00000113481, 3.70070432339, 1589.07289528380 },
    { 0.00000100099, 3.24340223714, 11773.37681151540 },
    { 0.00000095594, 0.53950648295, 20043.67456019880 },
    { 0.00000098947, 4.84558326403, 6681.24210705180 },
    { 0.00000104542, 0.78532737699, 8827.39026987480 },
    { 0.00000084186, 3.98971116025, 4399.99435688900 },
    { 0.00000086928, 2.20183965407, 11243.68584642080 },
    { 0.00000071438, 2.80307223477, 3185.19202726560 },
    { 0.00000072095, 5.84669532401, 5884.92684658320 },
    { 0.00000073482, 2.18421190324, 8429.24126646660 },
    { 0.00000098946, 2.81481171439, 6681.20759974740 },
    { 0.00000068413, 2.73834597183, 2288.34404351140 },
    { 0.00000086747, 1.02091867465, 7079.37385680780 },
    { 0.00000065316, 2.68114882713, 28.44918746780 },
    { 0.00000083745, 3.20254912006, 4690.47983635860 },
    { 0.00000075031, 0.76647765061, 6467.92575796160 },
    { 0.00000068983, 3.76403440528, 6041.32756708560 },
    { 0.00000066706, 0.73630288873, 3723.50895892300 },
    { 0.00000063313, 4.52771850220, 426.59819087600 },
    { 0.00000061684, 6.16831461502, 2274.11694950980 },
    { 0.00000052260, 0.89938935091, 9623.68827669120 },
    { 0.00000055485, 4.60622447136, 4292.33083295040 },
    { 0.00000051331, 4.14823934301, 3341.59274776800 },
    { 0.00000056633, 5.06250402329, 15.25247118500 },
    { 0.00000063376, 0.91293637746, 3553.91152213780 },
    { 0.00000045822, 0.78790300125, 1990.74501704100 },
    { 0.00000048553, 3.95677994023, 4535.05943692440 },
    { 0.00000041223, 6.02013764154, 3894.18182954220 },
    { 0.00000041941, 3.58309124437, 8031.09226305840 },
    { 0.00000056395, 1.68727941626, 6872.67311951120 },
    { 0.00000055907, 3.46261441099, 263.08392337280 },
    { 0.00000051677, 2.81307639242, 3339.63210563160 },
    { 0.00000040669, 3.13838566327, 9595.23908922340 },
    { 0.00000038111, 0.73396370751, 10025.36039844840 },
    { 0.00000039498, 5.63225741360, 3097.88382272579 },
    { 0.00000044175, 3.19530118759, 5628.95647021120 },
    { 0.00000036718, 2.63750919104, 692.15760122680 },
    { 0.00000045905, 0.28717581576, 5614.72937620960 },
    { 0.00000038351, 5.82880639987, 3191.04922956520 },
    { 0.00000038198, 2.34832438823, 162.46663613220 },
    { 0.00000032561, 0.48401318272, 6681.29216370240 },
    { 0.00000037135, 0.68510839331, 2818.03500860600 },
    { 0.00000031169, 3.98160436995, 20.35531939880 },
    { 0.00000032561, 0.89250965753, 6681.15754309680 },
    { 0.00000037749, 4.15481250779, 2803.80791460440 },
    { 0.00000033626, 6.11997987693, 6489.77658728800 },
    { 0.00000029007, 2.42707198395, 3319.83703120740 },
    { 0.00000038794, 1.35194224244, 10018.31416175040 },
    { 0.00000033149, 1.14024195200, 5.52292430740 },
    { 0.00000027583, 1.59721760699, 7210.91581849420 },
    { 0.00000028699, 5.72047550940, 7477.52286021600 },
    { 0.00000034039, 2.59525636978, 11769.85369316640 },
    { 0.00000025380, 0.52092092633, 10.63666534980 },
    { 0.00000026355, 1.34519007001, 3496.03282613400 },
    { 0.00000024555, 4.00321315879, 11371.70468975820 },
    { 0.00000025637, 0.24963503109, 522.57741809380 },
    { 0.00000027275, 4.55649766071, 3361.38782219220 },
    { 0.00000023766, 1.84063759173, 12832.75874170460 },
    { 0.00000022814, 3.52628452806, 1648.44675719740 },
    { 0.00000022272, 0.72111173236, 266.60704172180 },
    { 0.00000021201, 3.11823578369, 2957.71589447660 },
    { 0.00000020156, 3.67147308710, 1758.65307841680 },
    { 0.00000021530, 6.15388673691, 3264.34635542420 },
    { 0.00000020090, 1.08241387913, 7064.12138562280 },
    { 0.00000021344, 4.28178434496, 4032.77002792660 },
    { 0.00000027541, 6.08386421472, 6674.11130639880 },
    { 0.00000019842, 2.37674123073, 10713.99488132620 },
    { 0.00000025518, 3.43241978555, 3443.70520091840 },
    { 0.00000022542, 5.64861441506, 2388.89402044920 },
    { 0.00000024376, 0.97006548518, 632.78373931320 },
    { 0.00000023079, 4.74990771219, 3347.72597370060 },
    { 0.00000017708, 3.69743280195, 3344.20285535160 },
    { 0.00000022658, 3.95447568336, 4989.05918389720 },
    { 0.00000022600, 5.24085203262, 3205.54734666440 },
    { 0.00000016811, 5.48619684184, 3.88133535800 },
    { 0.00000018422, 4.22550249103, 2787.04302385740 },
    { 0.00000022735, 4.98523942294, 7632.94325965020 },
    { 0.00000016638, 2.52822534159, 14584.29827312060 },
    { 0.00000020963, 4.27879531719, 5099.26550511660 },
    { 0.00000015814, 3.13241857680, 59.37386191360 },
    { 0.00000018113, 3.25756742113, 3337.02199804800 },
    { 0.00000019295, 3.23912725911, 7.04623669800 },
    { 0.00000016777, 4.39731653353, 15643.68020330980 },
    { 0.00000017554, 4.09198247074, 74.78159856730 },
    { 0.00000013713, 2.54103541653, 4933.20844033260 },
    { 0.00000016007, 1.54673981973, 14054.60730802600 },
    { 0.00000014603, 3.45689862899, 7373.38245462640 },
    { 0.00000013547, 4.04141743525, 4929.68532198360 },
    { 0.00000014222, 0.59967781578, 23.87843774780 },
    { 0.00000013876, 5.40880274251, 10973.55568635000 },
    { 0.00000014026, 1.44210504015, 10404.73381232260 },
    { 0.00000016055, 3.79399064336, 2118.76386037840 },
    { 0.00000013717, 3.59037690181, 15113.98923821520 },
    { 0.00000018040, 4.25416134565, 2487.41604494780 },
    { 0.00000015846, 0.56902641445, 103.09277421860 },
    { 0.00000013402, 5.16918481175, 10213.28554621100 },
    { 0.00000016068, 2.36894092837, 3265.83082813250 },
    { 0.00000012197, 1.73028863618, 36.02786667740 },
    { 0.00000012283, 5.19941258642, 10021.85453375160 },
    { 0.00000012283, 3.16864076359, 10021.82002644720 },
    { 0.00000011749, 5.72731481869, 0.42007609361 },
    { 0.00000012340, 2.52148348822, 2906.90068882300 },
    { 0.00000010640, 3.44997335322, 639.89728631400 },
    { 0.00000010925, 0.60402475795, 5085.03841111500 },
    { 0.00000010573, 1.09027262515, 12168.00269657460 },
    { 0.00000009146, 1.10288559040, 9808.53818466140 },
    { 0.00000012732, 1.79880344270, 13745.34623902240 },
    { 0.00000012156, 4.42292535673, 14712.31711645800 },
    { 0.00000008805, 3.97132756722, 170.67287061920 },
    { 0.00000010040, 1.38291942087, 3583.34103067380 },
    { 0.00000010584, 0.89643083679, 23384.28698689860 }
};

static const vsop_term_t vsop_lon_Mars_1[] =
{
    { 3340.61242700512, 0.00000000000, 0.00000000000 },
    { 0.01457554523, 3.60433733236, 3340.61242669980 },
    { 0.00168414711, 3.92318567804, 6681.22485339960 },
    { 0.00020622975, 4.26108844583, 10021.83728009940 },
    { 0.00003452392, 4.73210393190, 3.52311834900 },
    { 0.00002586332, 4.60670058555, 13362.44970679920 },
    { 0.00000841535, 4.45864030426, 2281.23049651060 },
    { 0.00000537567, 5.01581256923, 398.14900340820 },
    { 0.00000520948, 4.99428054039, 3344.13554504880 },
    { 0.00000432635, 2.56070853083, 191.44826611160 },
    { 0.00000429655, 5.31645299471, 155.42039943420 },
    { 0.00000381751, 3.53878166043, 796.29800681640 },
    { 0.00000328530, 4.95632685192, 16703.06213349900 },
    { 0.00000205657, 4.56889279932, 2146.16541647520 }
};

static const vsop_term_t vsop_lon_Mars_2[] =
{
    { 0.00058152577, 2.04961712429, 3340.61242669980 },
    { 0.00013459579, 2.45738706163, 6681.22485339960 }
};

static const vsop_series_t vsop_lon_Mars[] =
{
    { 177, vsop_lon_Mars_0 },
    { 14, vsop_lon_Mars_1 },
    { 2, vsop_lon_Mars_2 }
};

static const vsop_term_t vsop_lat_Mars_0[] =
{
    { 0.03197134986, 3.76832042431, 3340.61242669980 },
    { 0.00298033234, 4.10616996305, 6681.22485339960 },
    { 0.00289104742, 0.00000000000, 0.00000000000 },
    { 0.00031365539, 4.44651053090, 10021.83728009940 },
    { 0.00003484100, 4.78812549260, 13362.44970679920 }
};

static const vsop_term_t vsop_lat_Mars_1[] =
{
    { 0.00217310991, 6.04472194776, 3340.61242669980 },
    { 0.00020976948, 3.14159265359, 0.00000000000 },
    { 0.00012834709, 1.60810667915, 6681.22485339960 }
};

static const vsop_series_t vsop_lat_Mars[] =
{
    { 5, vsop_lat_Mars_0 },
    { 3, vsop_lat_Mars_1 }
};

static const vsop_term_t vsop_rad_Mars_0[] =
{
    { 1.53033488271, 0.00000000000, 0.00000000000 },
    { 0.14184953160, 3.47971283528, 3340.61242669980 },
    { 0.00660776362, 3.81783443019, 6681.22485339960 },
    { 0.00046179117, 4.15595316782, 10021.83728009940 },
    { 0.00008109733, 5.55958416318, 2810.92146160520 },
    { 0.00007485318, 1.77239078402, 5621.84292321040 },
    { 0.00005523191, 1.36436303770, 2281.23049651060 },
    { 0.00003825160, 4.49407183687, 13362.44970679920 },
    { 0.00002306537, 0.09081579001, 2544.31441988340 },
    { 0.00001999396, 5.36059617709, 3337.08930835080 },
    { 0.00002484394, 4.92545639920, 2942.46342329160 },
    { 0.00001960195, 4.74249437639, 3344.13554504880 },
    { 0.00001167119, 2.11260868341, 5092.15195811580 },
    { 0.00001102816, 5.00908403998, 398.14900340820 },
    { 0.00000899066, 4.40791133207, 529.69096509460 },
    { 0.00000992252, 5.83861961952, 6151.53388830500 },
    { 0.00000807354, 2.10217065501, 1059.38193018920 },
    { 0.00000797915, 3.44839203899, 796.29800681640 },
    { 0.00000740975, 1.49906336885, 2146.16541647520 },
    { 0.00000692339, 2.13378874689, 8962.45534991020 },
    { 0.00000633144, 0.89353283242, 3340.59517304760 },
    { 0.00000725583, 1.24516810723, 8432.76438481560 },
    { 0.00000633140, 2.92430446399, 3340.62968035200 },
    { 0.00000574355, 0.82896244455, 2914.01423582380 },
    { 0.00000526166, 5.38292991236, 3738.76143010800 },
    { 0.00000629978, 1.28737486495, 1751.53953141600 },
    { 0.00000472775, 5.19850522346, 3127.31333126180 },
    { 0.00000348095, 4.83219199976, 16703.06213349900 },
    { 0.00000283713, 2.90692064724, 3532.06069281140 },
    { 0.00000279543, 5.25749685380, 6283.07584999140 },
    { 0.00000233857, 5.10545987572, 5486.77784317500 },
    { 0.00000219427, 5.58340231744, 191.44826611160 },
    { 0.00000269896, 3.76393625127, 5884.92684658320 },
    { 0.00000208335, 5.25476078693, 3340.54511639700 },
    { 0.00000275217, 2.90817482492, 1748.01641306700 },
    { 0.00000275506, 1.21767950614, 6254.62666252360 },
    { 0.00000239119, 2.03669934656, 1194.44701022460 },
    { 0.00000223189, 4.19861535147, 3149.16416058820 },
    { 0.00000182689, 5.08062725665, 6684.74797174860 },
    { 0.00000186207, 5.69871572410, 6677.70173505060 },
    { 0.00000176000, 5.95341919657, 3870.30339179440 },
    { 0.00000178617, 4.18423004741, 3333.49887969900 },
    { 0.00000208330, 4.84626439637, 3340.67973700260 },
    { 0.00000228126, 3.25526555588, 6872.67311951120 },
    { 0.00000144312, 0.21306219460, 5088.62883976680 },
    { 0.00000163527, 3.79888811958, 4136.91043351620 },
    { 0.00000133126, 1.53906679361, 7903.07341972100 },
    { 0.00000141755, 2.47792380112, 4562.46099302120 },
    { 0.00000114927, 4.31748869065, 1349.86740965880 },
    { 0.00000118789, 2.12168482244, 1589.07289528380 },
    { 0.00000102094, 6.18145185708, 9492.14631500480 },
    { 0.00000128570, 5.49884728795, 8827.39026987480 },
    { 0.00000111546, 0.55346108403, 11243.68584642080 },
    { 0.00000082498, 1.62220096558, 11773.37681151540 },
    { 0.00000083204, 0.61551135046, 8429.24126646660 },
    { 0.00000084463, 0.62274409931, 1592.59601363280 },
    { 0.00000086666, 1.74984525176, 2700.71514038580 },
    { 0.00000071813, 2.47494065480, 12303.06777661000 },
    { 0.00000085321, 1.61634750496, 4690.47983635860 },
    { 0.00000063641, 2.67334163937, 426.59819087600 },
    { 0.00000068601, 2.40188234283, 4399.99435688900 },
    { 0.00000058559, 4.72052839990, 213.29909543800 },
    { 0.00000062009, 1.10068565926, 1221.84856632140 },
    { 0.00000066499, 2.21296335919, 6041.32756708560 },
    { 0.00000055810, 1.23288066320, 3185.19202726560 },
    { 0.00000054969, 5.72695354791, 951.71840625060 },
    { 0.00000052430, 3.02368095530, 4292.33083295040 },
    { 0.00000055688, 5.44688671707, 3723.50895892300 },
    { 0.00000058959, 3.26242460622, 6681.24210705180 },
    { 0.00000044638, 2.01459444131, 8031.09226305840 },
    { 0.00000058959, 1.23165296790, 6681.20759974740 },
    { 0.00000042439, 2.26554261514, 155.42039943420 },
    { 0.00000051550, 5.72324451485, 7079.37385680780 },
    { 0.00000048940, 5.61613493545, 3553.91152213780 },
    { 0.00000045406, 5.43303278149, 6467.92575796160 },
    { 0.00000036438, 4.43922435395, 3894.18182954220 },
    { 0.00000035980, 1.15972378713, 2288.34404351140 },
    { 0.00000035268, 5.49032233898, 1990.74501704100 },
    { 0.00000042192, 1.63254827838, 5628.95647021120 },
    { 0.00000044292, 5.00344221303, 5614.72937620960 },
    { 0.00000033616, 5.17029030468, 20043.67456019880 },
    { 0.00000043256, 1.03722397198, 11769.85369316640 },
    { 0.00000039237, 1.24237030858, 3339.63210563160 },
    { 0.00000030352, 2.44163963455, 11371.70468975820 },
    { 0.00000029342, 4.06035002188, 3097.88382272579 },
    { 0.00000031967, 1.93969979134, 382.89653222320 }
};

static const vsop_term_t vsop_rad_Mars_1[] =
{
    { 0.01107433345, 2.03250524857, 3340.61242669980 },
    { 0.00103175887, 2.37071847807, 6681.22485339960 },
    { 0.00012877200, 0.00000000000, 0.00000000000 },
    { 0.00010815880, 2.70888095665, 10021.83728009940 },
    { 0.00001194550, 3.04702256206, 13362.44970679920 }
};

static const vsop_term_t vsop_rad_Mars_2[] =
{
    { 0.00044242249, 0.47930604954, 3340.61242669980 },
    { 0.00008138042, 0.86998389204, 6681.22485339960 }
};

static const vsop_series_t vsop_rad_Mars[] =
{
    { 86, vsop_rad_Mars_0 },
    { 5, vsop_rad_Mars_1 },
    { 2, vsop_rad_Mars_2 }
};

;
static const vsop_term_t vsop_lon_Jupiter_0[] =
{
    { 0.59954691494, 0.00000000000, 0.00000000000 },
    { 0.09695898719, 5.06191793158, 529.69096509460 },
    { 0.00573610142, 1.44406205629, 7.11354700080 },
    { 0.00306389205, 5.41734730184, 1059.38193018920 },
    { 0.00097178296, 4.14264726552, 632.78373931320 },
    { 0.00072903078, 3.64042916389, 522.57741809380 },
    { 0.00064263975, 3.41145165351, 103.09277421860 },
    { 0.00039806064, 2.29376740788, 419.48464387520 },
    { 0.00038857767, 1.27231755835, 316.39186965660 },
    { 0.00027964629, 1.78454591820, 536.80451209540 },
    { 0.00013589730, 5.77481040790, 1589.07289528380 },
    { 0.00008246349, 3.58227925840, 206.18554843720 },
    { 0.00008768704, 3.63000308199, 949.17560896980 },
    { 0.00007368042, 5.08101194270, 735.87651353180 },
    { 0.00006263150, 0.02497628807, 213.29909543800 },
    { 0.00006114062, 4.51319998626, 1162.47470440780 },
    { 0.00004905396, 1.32084470588, 110.20632121940 },
    { 0.00005305285, 1.30671216791, 14.22709400160 },
    { 0.00005305441, 4.18625634012, 1052.26838318840 },
    { 0.00004647248, 4.69958103684, 3.93215326310 },
    { 0.00003045023, 4.31676431084, 426.59819087600 },
    { 0.00002609999, 1.56667394063, 846.08283475120 },
    { 0.00002028191, 1.06376530715, 3.18139373770 },
    { 0.00001764763, 2.14148655117, 1066.49547719000 },
    { 0.00001722972, 3.88036268267, 1265.56747862640 },
    { 0.00001920945, 0.97168196472, 639.89728631400 },
    { 0.00001633223, 3.58201833555, 515.46387109300 },
    { 0.00001431999, 4.29685556046, 625.67019231240 },
    { 0.00000973272, 4.09764549134, 95.97922721780 },
    { 0.00000884457, 2.43700227469, 412.37109687440 },
    { 0.00000732853, 6.08535124451, 838.96928775040 },
    { 0.00000731094, 3.80592308125, 1581.95934828300 },
    { 0.00000691971, 6.13365277914, 2118.76386037840 },
    { 0.00000709166, 1.29274760330, 742.99006053260 },
    { 0.00000614482, 4.10850580886, 1478.86657406440 },
    { 0.00000495219, 3.75564106217, 323.50541665740 },
    { 0.00000581903, 4.53969579398, 309.27832265580 },
    { 0.00000375664, 4.70304250208, 1368.66025284500 },
    { 0.00000389876, 4.89706786539, 1692.16566950240 },
    { 0.00000341016, 5.71452379310, 533.62311835770 },
    { 0.00000440853, 2.95818598959, 454.90936652730 },
    { 0.00000417267, 1.03554397138, 2.44768055480 },
    { 0.00000244174, 5.22024286247, 728.76296653100 },
    { 0.00000261541, 1.87652515753, 0.96320784650 },
    { 0.00000256589, 3.72410394286, 199.07200143640 },
    { 0.00000261005, 0.82048379203, 380.12776796000 },
    { 0.00000220381, 1.65114584814, 543.91805909620 },
    { 0.00000201991, 1.80692992449, 1375.77379984580 },
    { 0.00000207336, 1.85463683689, 525.75881183150 },
    { 0.00000197061, 5.29255821015, 1155.36115740700 },
    { 0.00000235139, 1.22694468346, 909.81873305460 },
    { 0.00000174827, 5.90974976879, 956.28915597060 },
    { 0.00000149385, 4.37744775359, 1685.05212250160 },
    { 0.00000175197, 3.22647697998, 1898.35121793960 },
    { 0.00000175172, 3.72977441220, 942.06206196900 },
    { 0.00000157917, 4.36478445901, 1795.25844372100 },
    { 0.00000137898, 1.31800455202, 1169.58825140860 },
    { 0.00000117498, 2.50021486074, 1596.18644228460 },
    { 0.00000150504, 3.90624455135, 74.78159856730 },
    { 0.00000116786, 3.38920921060, 0.52126486180 },
    { 0.00000105894, 4.55439354032, 526.50957135690 },
    { 0.00000130540, 4.16876671917, 1045.15483618760 },
    { 0.00000141388, 3.13579930728, 491.55792945680 },
    { 0.00000099524, 1.42112622270, 532.87235883230 },
    { 0.00000096143, 1.18143253105, 117.31986822020 },
    { 0.00000091732, 0.85722451006, 1272.68102562720 },
    { 0.00000087704, 1.21730504350, 453.42489381900 },
    { 0.00000068531, 2.35201905890, 2.92076130680 },
    { 0.00000066111, 5.34380967040, 1471.75302706360 },
    { 0.00000077401, 4.42676354183, 39.35687591520 },
    { 0.00000072028, 4.23856425835, 2111.65031337760 },
    { 0.00000059423, 4.11122034593, 2001.44399215820 },
    { 0.00000062471, 0.51213142347, 220.41264243880 },
    { 0.00000066540, 2.98844410276, 2214.74308759620 },
    { 0.00000056014, 1.15477785231, 21.34064100240 },
    { 0.00000070461, 5.14178006023, 835.03713448730 },
    { 0.00000051903, 4.10065404719, 1258.45393162560 },
    { 0.00000058261, 5.86719898935, 5753.38488489680 },
    { 0.00000054583, 1.57071663540, 983.11585891360 },
    { 0.00000046910, 3.54638837922, 5.41662597140 },
    { 0.00000037895, 0.21140086073, 2648.45482547300 },
    { 0.00000035845, 4.61505536309, 2008.55753915900 },
    { 0.00000031581, 5.14178165108, 1788.14489672020 },
    { 0.00000029860, 5.34424466576, 2221.85663459700 },
    { 0.00000025821, 3.85920335036, 2317.83586181480 },
    { 0.00000033844, 1.00563073311, 9683.59458111640 },
    { 0.00000026212, 2.74456887801, 2531.13495725280 },
    { 0.00000022889, 3.85009333532, 2428.04218303420 }
};

static const vsop_term_t vsop_lon_Jupiter_1[] =
{
    { 529.69096508814, 0.00000000000, 0.00000000000 },
    { 0.00489503243, 4.22082939470, 529.69096509460 },
    { 0.00228917222, 6.02646855621, 7.11354700080 },
    { 0.00030099479, 4.54540782858, 1059.38193018920 },
    { 0.00020720920, 5.45943156902, 522.57741809380 },
    { 0.00012103653, 0.16994816098, 536.80451209540 },
    { 0.00006067987, 4.42422292017, 103.09277421860 },
    { 0.00005433968, 3.98480737746, 419.48464387520 },
    { 0.00004237744, 5.89008707199, 14.22709400160 },
    { 0.00002211974, 5.26766687382, 206.18554843720 },
    { 0.00001983502, 4.88600705699, 1589.07289528380 },
    { 0.00001295769, 5.55132752171, 3.18139373770 },
    { 0.00001163416, 0.51450634873, 3.93215326310 },
    { 0.00001007167, 0.46474690033, 735.87651353180 },
    { 0.00001174094, 5.84238857133, 1052.26838318840 },
    { 0.00000829822, 0.59345481695, 1066.49547719000 },
    { 0.00001003864, 3.14841622246, 426.59819087600 },
    { 0.00001098730, 5.30705242117, 515.46387109300 }
};

static const vsop_term_t vsop_lon_Jupiter_2[] =
{
    { 0.00047233601, 4.32148536482, 7.11354700080 },
    { 0.00030649436, 2.92977788700, 529.69096509460 },
    { 0.00014837605, 3.14159265359, 0.00000000000 }
};

static const vsop_series_t vsop_lon_Jupiter[] =
{
    { 88, vsop_lon_Jupiter_0 },
    { 18, vsop_lon_Jupiter_1 },
    { 3, vsop_lon_Jupiter_2 }
};

static const vsop_term_t vsop_lat_Jupiter_0[] =
{
    { 0.02268615702, 3.55852606721, 529.69096509460 },
    { 0.00109971634, 3.90809347197, 1059.38193018920 },
    { 0.00110090358, 0.00000000000, 0.00000000000 },
    { 0.00008101428, 3.60509572885, 522.57741809380 },
    { 0.00006043996, 4.25883108339, 1589.07289528380 },
    { 0.00006437782, 0.30627119215, 536.80451209540 }
};

static const vsop_term_t vsop_lat_Jupiter_1[] =
{
    { 0.00078203446, 1.52377859742, 529.69096509460 }
};

static const vsop_series_t vsop_lat_Jupiter[] =
{
    { 6, vsop_lat_Jupiter_0 },
    { 1, vsop_lat_Jupiter_1 }
};

static const vsop_term_t vsop_rad_Jupiter_0[] =
{
    { 5.20887429326, 0.00000000000, 0.00000000000 },
    { 0.25209327119, 3.49108639871, 529.69096509460 },
    { 0.00610599976, 3.84115365948, 1059.38193018920 },
    { 0.00282029458, 2.57419881293, 632.78373931320 },
    { 0.00187647346, 2.07590383214, 522.57741809380 },
    { 0.00086792905, 0.71001145545, 419.48464387520 },
    { 0.00072062974, 0.21465724607, 536.80451209540 },
    { 0.00065517248, 5.97995884790, 316.39186965660 },
    { 0.00029134542, 1.67759379655, 103.09277421860 },
    { 0.00030135335, 2.16132003734, 949.17560896980 },
    { 0.00023453271, 3.54023522184, 735.87651353180 },
    { 0.00022283743, 4.19362594399, 1589.07289528380 },
    { 0.00023947298, 0.27458037480, 7.11354700080 },
    { 0.00013032614, 2.96042965363, 1162.47470440780 },
    { 0.00009703360, 1.90669633585, 206.18554843720 },
    { 0.00012749023, 2.71550286592, 1052.26838318840 },
    { 0.00009161393, 4.41352953117, 213.29909543800 },
    { 0.00007894511, 2.47907592482, 426.59819087600 },
    { 0.00007057931, 2.18184839926, 1265.56747862640 },
    { 0.00006137703, 6.26418240033, 846.08283475120 },
    { 0.00005477001, 5.65729989857, 639.89728631400 },
    { 0.00003502493, 0.56532365822, 1066.49547719000 },
    { 0.00004136822, 2.72220872400, 625.67019231240 },
    { 0.00004169954, 2.01603822251, 515.46387109300 },
    { 0.00002499967, 4.55181655381, 838.96928775040 },
    { 0.00002616976, 2.00994012876, 1581.95934828300 },
    { 0.00001912009, 0.85621128851, 412.37109687440 },
    { 0.00002127681, 6.12755221002, 742.99006053260 },
    { 0.00001610567, 3.08871452594, 1368.66025284500 },
    { 0.00001479513, 2.68021307468, 1478.86657406440 },
    { 0.00001230630, 1.89052048109, 323.50541665740 },
    { 0.00001216895, 1.80176263029, 110.20632121940 },
    { 0.00000961113, 4.54876995367, 2118.76386037840 },
    { 0.00000998591, 2.87205397992, 309.27832265580 },
    { 0.00001014733, 1.38675822271, 454.90936652730 },
    { 0.00000821383, 1.59351544602, 1898.35121793960 }
};

static const vsop_term_t vsop_rad_Jupiter_1[] =
{
    { 0.01271801520, 2.64937512894, 529.69096509460 },
    { 0.00061661816, 3.00076460387, 1059.38193018920 },
    { 0.00053443713, 3.89717383175, 522.57741809380 },
    { 0.00031185171, 4.88276958012, 536.80451209540 },
    { 0.00041390269, 0.00000000000, 0.00000000000 }
};

static const vsop_series_t vsop_rad_Jupiter[] =
{
    { 36, vsop_rad_Jupiter_0 },
    { 5, vsop_rad_Jupiter_1 }
};

;
static const vsop_term_t vsop_lon_Saturn_0[] =
{
    { 0.87401354025, 0.00000000000, 0.00000000000 },
    { 0.11107659762, 3.96205090159, 213.29909543800 },
    { 0.01414150957, 4.58581516874, 7.11354700080 },
    { 0.00398379389, 0.52112032699, 206.18554843720 },
    { 0.00350769243, 3.30329907896, 426.59819087600 },
    { 0.00206816305, 0.24658372002, 103.09277421860 },
    { 0.00079271300, 3.84007056878, 220.41264243880 },
    { 0.00023990355, 4.66976924553, 110.20632121940 },
    { 0.00016573588, 0.43719228296, 419.48464387520 },
    { 0.00014906995, 5.76903183869, 316.39186965660 },
    { 0.00015820290, 0.93809155235, 632.78373931320 },
    { 0.00014609559, 1.56518472000, 3.93215326310 },
    { 0.00013160301, 4.44891291899, 14.22709400160 },
    { 0.00015053543, 2.71669915667, 639.89728631400 },
    { 0.00013005299, 5.98119023644, 11.04570026390 },
    { 0.00010725067, 3.12939523827, 202.25339517410 },
    { 0.00005863206, 0.23656938524, 529.69096509460 },
    { 0.00005227757, 4.20783365759, 3.18139373770 },
    { 0.00006126317, 1.76328667907, 277.03499374140 },
    { 0.00005019687, 3.17787728405, 433.71173787680 },
    { 0.00004592550, 0.61977744975, 199.07200143640 },
    { 0.00004005867, 2.24479718502, 63.73589830340 },
    { 0.00002953796, 0.98280366998, 95.97922721780 },
    { 0.00003873670, 3.22283226966, 138.51749687070 },
    { 0.00002461186, 2.03163875071, 735.87651353180 },
    { 0.00003269484, 0.77492638211, 949.17560896980 },
    { 0.00001758145, 3.26580109940, 522.57741809380 },
    { 0.00001640172, 5.50504453050, 846.08283475120 },
    { 0.00001391327, 4.02333150505, 323.50541665740 },
    { 0.00001580648, 4.37265307169, 309.27832265580 },
    { 0.00001123498, 2.83726798446, 415.55249061210 },
    { 0.00001017275, 3.71700135395, 227.52618943960 },
    { 0.00000848642, 3.19150170830, 209.36694217490 },
    { 0.00001087229, 4.18343257560, 2.44768055480 },
    { 0.00000956757, 0.50744342622, 1265.56747862640 },
    { 0.00000789205, 5.00745127508, 0.96320784650 },
    { 0.00000686999, 1.74714152638, 1052.26838318840 },
    { 0.00000748819, 2.14396789786, 853.19638175200 },
    { 0.00000633982, 2.29887419204, 412.37109687440 },
    { 0.00000743599, 5.25277685028, 224.34479570190 },
    { 0.00000852677, 3.42141279787, 175.16605980020 },
    { 0.00000579844, 3.09254750266, 74.78159856730 },
    { 0.00000624883, 0.97048087510, 210.11770170030 },
    { 0.00000529874, 4.44938991187, 117.31986822020 },
    { 0.00000542648, 1.51824981131, 9.56122755560 },
    { 0.00000474277, 5.47526482059, 742.99006053260 },
    { 0.00000448547, 1.28991363969, 127.47179660680 },
    { 0.00000546365, 2.12677911914, 350.33211960040 },
    { 0.00000478044, 2.96486700885, 137.03302416240 },
    { 0.00000354988, 3.01280169452, 838.96928775040 },
    { 0.00000451857, 1.04437293342, 490.33408917940 },
    { 0.00000347422, 1.53923267387, 340.77089204480 },
    { 0.00000343481, 0.24603836481, 0.52126486180 },
    { 0.00000309029, 3.49491017725, 216.48048917570 },
    { 0.00000322189, 0.96136528867, 203.73786788240 },
    { 0.00000372318, 2.27822895353, 217.23124870110 },
    { 0.00000321562, 2.57185176731, 647.01083331480 },
    { 0.00000330197, 0.24721738903, 1581.95934828300 },
    { 0.00000249142, 1.47004230445, 1368.66025284500 },
    { 0.00000286703, 2.37046001635, 351.81659230870 },
    { 0.00000220225, 4.20421716654, 200.76892246580 },
    { 0.00000277774, 0.40024010033, 211.81462272970 },
    { 0.00000204520, 6.01073368945, 265.98929347750 },
    { 0.00000207645, 0.48344140678, 1162.47470440780 },
    { 0.00000208650, 1.34533476508, 625.67019231240 },
    { 0.00000182459, 5.49122412646, 2.92076130680 },
    { 0.00000226601, 4.90997278296, 12.53017297220 },
    { 0.00000207666, 1.28298038875, 39.35687591520 },
    { 0.00000173914, 1.86305647242, 0.75075952540 },
    { 0.00000184698, 3.50349102817, 149.56319713460 },
    { 0.00000183509, 0.97260974474, 4.19278569400 },
    { 0.00000146074, 6.23107926975, 195.13984817330 },
    { 0.00000164541, 0.44004693949, 5.41662597140 },
    { 0.00000147544, 1.53530368067, 5.62907429250 },
    { 0.00000139690, 4.29463428594, 21.34064100240 },
    { 0.00000131292, 4.06829024226, 10.29494073850 },
    { 0.00000117326, 2.67913173095, 1155.36115740700 },
    { 0.00000149302, 5.73592320434, 52.69019803950 },
    { 0.00000122371, 1.97585460706, 4.66586644600 },
    { 0.00000113737, 5.59421876022, 1059.38193018920 },
    { 0.00000102689, 1.19754453191, 1685.05212250160 },
    { 0.00000118169, 5.34072820318, 554.06998748280 },
    { 0.00000109287, 3.43808188855, 536.80451209540 },
    { 0.00000110400, 0.16605133194, 1.48447270830 },
    { 0.00000124980, 6.27738701225, 1898.35121793960 },
    { 0.00000089916, 5.80394843417, 114.13847448250 },
    { 0.00000103968, 2.19185625957, 88.86568021700 },
    { 0.00000112430, 1.10510750315, 191.20769491020 },
    { 0.00000106578, 4.01153470635, 956.28915597060 },
    { 0.00000091425, 1.87523841598, 38.13303563780 },
    { 0.00000083763, 5.48810655641, 0.11187458460 },
    { 0.00000083489, 2.28927138986, 628.85158605010 },
    { 0.00000096973, 4.53662541679, 302.16477565500 },
    { 0.00000100634, 4.96513420321, 269.92144674060 },
    { 0.00000075496, 2.18005762811, 728.76296653100 },
    { 0.00000096330, 2.83319249226, 275.55052103310 },
    { 0.00000082386, 3.05482650543, 440.82528487760 },
    { 0.00000073896, 5.08917637074, 1375.77379984580 },
    { 0.00000071625, 5.10946423579, 65.22037101170 },
    { 0.00000069760, 3.71027033119, 14.97785352700 },
    { 0.00000088771, 3.86334160349, 278.51946644970 },
    { 0.00000068092, 0.73430499450, 1478.86657406440 },
    { 0.00000066481, 0.02658132849, 70.84944530420 },
    { 0.00000065694, 2.02147100289, 142.44965013380 },
    { 0.00000075752, 1.61413426010, 284.14854074220 },
    { 0.00000063138, 3.49495099319, 479.28838891550 },
    { 0.00000062557, 2.58733971413, 422.66603761290 },
    { 0.00000069300, 3.44002100885, 515.46387109300 },
    { 0.00000079010, 4.45159676932, 35.42472265210 },
    { 0.00000063664, 3.31747980190, 62.25142559510 },
    { 0.00000053017, 3.18475265559, 8.07675484730 },
    { 0.00000055159, 0.96792241728, 942.06206196900 },
    { 0.00000049320, 2.38666475800, 1471.75302706360 },
    { 0.00000061090, 1.50302054623, 210.85141488320 },
    { 0.00000060676, 2.68689407241, 388.46515523820 },
    { 0.00000045138, 0.93106348303, 2001.44399215820 },
    { 0.00000050125, 6.03152570850, 2214.74308759620 },
    { 0.00000054160, 0.78128719345, 191.95845443560 },
    { 0.00000047042, 4.59902370789, 437.64389113990 },
    { 0.00000039759, 1.63243208156, 1066.49547719000 },
    { 0.00000043405, 1.37360455570, 563.63121503840 },
    { 0.00000043913, 3.93075296633, 525.49817940060 },
    { 0.00000032668, 0.81193242653, 1795.25844372100 },
    { 0.00000037741, 3.69667138462, 1272.68102562720 },
    { 0.00000031825, 5.59208218558, 6069.77675455340 },
    { 0.00000023153, 2.10053945000, 1788.14489672020 },
    { 0.00000020659, 0.67095777002, 2317.83586181480 },
    { 0.00000020870, 5.79129638608, 2531.13495725280 },
    { 0.00000018486, 0.73172908046, 9999.98645077300 },
    { 0.00000016882, 0.72758125023, 2111.65031337760 }
};

static const vsop_term_t vsop_lon_Saturn_1[] =
{
    { 213.29909521690, 0.00000000000, 0.00000000000 },
    { 0.01297370862, 1.82834923978, 213.29909543800 },
    { 0.00564345393, 2.88499717272, 7.11354700080 },
    { 0.00093734369, 1.06311793502, 426.59819087600 },
    { 0.00107674962, 2.27769131009, 206.18554843720 },
    { 0.00040244455, 2.04108104671, 220.41264243880 },
    { 0.00019941774, 1.27954390470, 103.09277421860 },
    { 0.00010511678, 2.74880342130, 14.22709400160 },
    { 0.00006416106, 0.38238295041, 639.89728631400 },
    { 0.00004848994, 2.43037610229, 419.48464387520 },
    { 0.00004056892, 2.92133209468, 110.20632121940 },
    { 0.00003768635, 3.64965330780, 3.93215326310 },
    { 0.00003384691, 2.41694503459, 3.18139373770 },
    { 0.00003231693, 1.26149969158, 433.71173787680 },
    { 0.00003071405, 2.32739504783, 199.07200143640 },
    { 0.00001953179, 3.56378136497, 11.04570026390 },
    { 0.00001249468, 2.62810757084, 95.97922721780 },
    { 0.00000921350, 1.96069472334, 227.52618943960 }
};

static const vsop_term_t vsop_lon_Saturn_2[] =
{
    { 0.00116441330, 1.17988132879, 7.11354700080 },
    { 0.00091841837, 0.07325195840, 213.29909543800 },
    { 0.00036661728, 0.00000000000, 0.00000000000 },
    { 0.00015274496, 4.06493179167, 206.18554843720 },
    { 0.00010987259, 5.44479188310, 426.59819087600 }
};

static const vsop_series_t vsop_lon_Saturn[] =
{
    { 130, vsop_lon_Saturn_0 },
    { 18, vsop_lon_Saturn_1 },
    { 5, vsop_lon_Saturn_2 }
};

static const vsop_term_t vsop_lat_Saturn_0[] =
{
    { 0.04330678039, 3.60284428399, 213.29909543800 },
    { 0.00240348302, 2.85238489373, 426.59819087600 },
    { 0.00084745939, 0.00000000000, 0.00000000000 },
    { 0.00030863357, 3.48441504555, 220.41264243880 },
    { 0.00034116062, 0.57297307557, 206.18554843720 },
    { 0.00014734070, 2.11846596715, 639.89728631400 },
    { 0.00009916667, 5.79003188904, 419.48464387520 },
    { 0.00006993564, 4.73604689720, 7.11354700080 },
    { 0.00004807588, 5.43305312061, 316.39186965660 }
};

static const vsop_term_t vsop_lat_Saturn_1[] =
{
    { 0.00198927992, 4.93901017903, 213.29909543800 },
    { 0.00036947916, 3.14159265359, 0.00000000000 },
    { 0.00017966989, 0.51979431110, 426.59819087600 }
};

static const vsop_series_t vsop_lat_Saturn[] =
{
    { 9, vsop_lat_Saturn_0 },
    { 3, vsop_lat_Saturn_1 }
};

static const vsop_term_t vsop_rad_Saturn_0[] =
{
    { 9.55758135486, 0.00000000000, 0.00000000000 },
    { 0.52921382865, 2.39226219573, 213.29909543800 },
    { 0.01873679867, 5.23549604660, 206.18554843720 },
    { 0.01464663929, 1.64763042902, 426.59819087600 },
    { 0.00821891141, 5.93520042303, 316.39186965660 },
    { 0.00547506923, 5.01532618980, 103.09277421860 },
    { 0.00371684650, 2.27114821115, 220.41264243880 },
    { 0.00361778765, 3.13904301847, 7.11354700080 },
    { 0.00140617506, 5.70406606781, 632.78373931320 },
    { 0.00108974848, 3.29313390175, 110.20632121940 },
    { 0.00069006962, 5.94099540992, 419.48464387520 },
    { 0.00061053367, 0.94037691801, 639.89728631400 },
    { 0.00048913294, 1.55733638681, 202.25339517410 },
    { 0.00034143772, 0.19519102597, 277.03499374140 },
    { 0.00032401773, 5.47084567016, 949.17560896980 },
    { 0.00020936596, 0.46349251129, 735.87651353180 },
    { 0.00020839300, 1.52102476129, 433.71173787680 },
    { 0.00020746751, 5.33255457763, 199.07200143640 },
    { 0.00015298404, 3.05943814940, 529.69096509460 },
    { 0.00014296484, 2.60433479142, 323.50541665740 },
    { 0.00011993338, 5.98050967385, 846.08283475120 },
    { 0.00011380257, 1.73105427040, 522.57741809380 },
    { 0.00012884624, 1.64890652873, 138.51749687070 },
    { 0.00007752664, 5.85190720634, 95.97922721780 },
    { 0.00009796004, 5.20477537945, 1265.56747862640 },
    { 0.00006465823, 0.17732249942, 1052.26838318840 },
    { 0.00006770608, 3.00432308205, 14.22709400160 },
    { 0.00005850459, 1.45520063003, 415.55249061210 },
    { 0.00005307420, 0.59742200200, 63.73589830340 },
    { 0.00004695487, 2.14913875148, 227.52618943960 },
    { 0.00004044055, 1.64006628713, 209.36694217490 },
    { 0.00003688237, 0.78017261355, 412.37109687440 },
    { 0.00003376576, 3.69526804193, 224.34479570190 },
    { 0.00002885428, 1.38764476428, 838.96928775040 },
    { 0.00002975955, 5.68469131750, 210.11770170030 },
    { 0.00003419618, 4.94550542171, 1581.95934828300 },
    { 0.00003460944, 1.85088698050, 175.16605980020 },
    { 0.00003400702, 0.55385265588, 350.33211960040 },
    { 0.00002507656, 3.53854849756, 742.99006053260 },
    { 0.00002448261, 6.18411000897, 1368.66025284500 },
    { 0.00002406134, 2.96557066697, 117.31986822020 },
    { 0.00002881100, 0.17962517668, 853.19638175200 },
    { 0.00001888373, 0.02965674854, 3.93215326310 }
};

static const vsop_term_t vsop_rad_Saturn_1[] =
{
    { 0.06182981340, 0.25843511480, 213.29909543800 },
    { 0.00506577242, 0.71114625261, 206.18554843720 },
    { 0.00341394029, 5.79635741658, 426.59819087600 },
    { 0.00188491195, 0.47215589652, 220.41264243880 },
    { 0.00186261486, 3.14159265359, 0.00000000000 },
    { 0.00143891146, 1.40744822888, 7.11354700080 },
    { 0.00049621208, 6.01744279820, 103.09277421860 }
};

static const vsop_term_t vsop_rad_Saturn_2[] =
{
    { 0.00436902572, 4.78671677509, 213.29909543800 }
};

static const vsop_series_t vsop_rad_Saturn[] =
{
    { 43, vsop_rad_Saturn_0 },
    { 7, vsop_rad_Saturn_1 },
    { 1, vsop_rad_Saturn_2 }
};

;
static const vsop_term_t vsop_lon_Uranus_0[] =
{
    { 5.48129294297, 0.00000000000, 0.00000000000 },
    { 0.09260408234, 0.89106421507, 74.78159856730 },
    { 0.01504247898, 3.62719260920, 1.48447270830 },
    { 0.00365981674, 1.89962179044, 73.29712585900 },
    { 0.00272328168, 3.35823706307, 149.56319713460 },
    { 0.00070328461, 5.39254450063, 63.73589830340 },
    { 0.00068892678, 6.09292483287, 76.26607127560 },
    { 0.00061998615, 2.26952066061, 2.96894541660 },
    { 0.00061950719, 2.85098872691, 11.04570026390 },
    { 0.00026468770, 3.14152083966, 71.81265315070 },
    { 0.00025710476, 6.11379840493, 454.90936652730 },
    { 0.00021078850, 4.36059339067, 148.07872442630 },
    { 0.00017818647, 1.74436930289, 36.64856292950 },
    { 0.00014613507, 4.73732166022, 3.93215326310 },
    { 0.00011162509, 5.82681796350, 224.34479570190 },
    { 0.00010997910, 0.48865004018, 138.51749687070 },
    { 0.00009527478, 2.95516862826, 35.16409022120 },
    { 0.00007545601, 5.23626582400, 109.94568878850 },
    { 0.00004220241, 3.23328220918, 70.84944530420 },
    { 0.00004051900, 2.27755017300, 151.04766984290 },
    { 0.00003354596, 1.06549007380, 4.45341812490 },
    { 0.00002926718, 4.62903718891, 9.56122755560 },
    { 0.00003490340, 5.48306144511, 146.59425171800 },
    { 0.00003144069, 4.75199570434, 77.75054398390 },
    { 0.00002922333, 5.35235361027, 85.82729883120 },
    { 0.00002272788, 4.36600400036, 70.32818044240 },
    { 0.00002051219, 1.51773566586, 0.11187458460 },
    { 0.00002148602, 0.60745949945, 38.13303563780 },
    { 0.00001991643, 4.92437588682, 277.03499374140 },
    { 0.00001376226, 2.04283539351, 65.22037101170 },
    { 0.00001666902, 3.62744066769, 380.12776796000 },
    { 0.00001284107, 3.11347961505, 202.25339517410 },
    { 0.00001150429, 0.93343589092, 3.18139373770 },
    { 0.00001533221, 2.58594681212, 52.69019803950 },
    { 0.00001281604, 0.54271272721, 222.86032299360 },
    { 0.00001372139, 4.19641530878, 111.43016149680 },
    { 0.00001221029, 0.19900650030, 108.46121608020 },
    { 0.00000946181, 1.19253165736, 127.47179660680 },
    { 0.00001150989, 4.17898916639, 33.67961751290 },
    { 0.00001244347, 0.91614441731, 2.44768055480 },
    { 0.00001072013, 0.23566016888, 62.25142559510 },
    { 0.00001090463, 1.77501500531, 12.53017297220 },
    { 0.00000707935, 5.18291670033, 213.29909543800 },
    { 0.00000653376, 0.96587864431, 78.71375183040 },
    { 0.00000627570, 0.18209040157, 984.60033162190 },
    { 0.00000524485, 2.01275350435, 299.12639426920 },
    { 0.00000559396, 3.35768635981, 0.52126486180 },
    { 0.00000606847, 5.43209889250, 529.69096509460 },
    { 0.00000404897, 5.98690517582, 8.07675484730 },
    { 0.00000467183, 0.41482520325, 145.10977900970 },
    { 0.00000471311, 1.40661608158, 184.72728735580 },
    { 0.00000483226, 2.10553218341, 0.96320784650 },
    { 0.00000395569, 5.87037914022, 351.81659230870 },
    { 0.00000433527, 5.52141037763, 183.24281464750 },
    { 0.00000309843, 5.83301863492, 145.63104387150 },
    { 0.00000378642, 2.34989391811, 56.62235130260 },
    { 0.00000399033, 0.33796522578, 415.55249061210 },
    { 0.00000300392, 5.64355207373, 22.09140052780 },
    { 0.00000249230, 4.74621772167, 225.82926841020 },
    { 0.00000239311, 2.35072447972, 137.03302416240 },
    { 0.00000294103, 5.83919833199, 39.61750834610 },
    { 0.00000216450, 4.77807782477, 340.77089204480 },
    { 0.00000251784, 1.63692846797, 221.37585028530 },
    { 0.00000219624, 1.92233630317, 67.66805156650 },
    { 0.00000202019, 1.29693040688, 0.04818410980 },
    { 0.00000224105, 0.51589500446, 84.34282612290 },
    { 0.00000216563, 6.14217553245, 5.93789083320 },
    { 0.00000222605, 2.84314245655, 0.26063243090 },
    { 0.00000207907, 5.58012637880, 68.84370773410 },
    { 0.00000187520, 1.31927606520, 0.16005869440 },
    { 0.00000199306, 0.95648612651, 152.53214255120 },
    { 0.00000158075, 0.73795262538, 54.17467074780 },
    { 0.00000168606, 5.87865394974, 18.15924726470 },
    { 0.00000170326, 3.67712574811, 5.41662597140 },
    { 0.00000193647, 1.88800957346, 456.39383923560 },
    { 0.00000193051, 0.91616617785, 453.42489381900 },
    { 0.00000181991, 3.53625031273, 79.23501669220 },
    { 0.00000173102, 1.53869634445, 160.60889739850 },
    { 0.00000164483, 1.42390725018, 106.97674337190 },
    { 0.00000171940, 5.67948631369, 219.89137757700 },
    { 0.00000162805, 3.05027759814, 112.91463420510 },
    { 0.00000146659, 1.26296726443, 59.80374504030 },
    { 0.00000139276, 5.38697273752, 32.19514480460 },
    { 0.00000138636, 4.25998533357, 909.81873305460 },
    { 0.00000143058, 1.29980453870, 35.42472265210 },
    { 0.00000123986, 1.37489956563, 7.11354700080 },
    { 0.00000103295, 0.68145096277, 14.97785352700 },
    { 0.00000094957, 0.90678215577, 74.66972398270 },
    { 0.00000082948, 2.92800368384, 265.98929347750 },
    { 0.00000110403, 2.02666475709, 554.06998748280 },
    { 0.00000094433, 3.94271122207, 74.89347315190 },
    { 0.00000080072, 1.01583506701, 6.59228213900 },
    { 0.00000109576, 5.70572405893, 77.96299230500 },
    { 0.00000085946, 1.70581556772, 82.85835341460 },
    { 0.00000103799, 1.45794315266, 24.37902238820 },
    { 0.00000074661, 4.63178804642, 69.36497259590 },
    { 0.00000079813, 3.00965058125, 297.64192156090 },
    { 0.00000084490, 0.36886722094, 186.21176006410 },
    { 0.00000088657, 0.52498114072, 181.75834193920 },
    { 0.00000070368, 1.18984702891, 66.70484372000 },
    { 0.00000069971, 0.87463619381, 305.34616939270 },
    { 0.00000070082, 3.75845990682, 131.40394986990 },
    { 0.00000084350, 5.88592009032, 256.53994050650 },
    { 0.00000074493, 6.24238684280, 447.79581952650 },
    { 0.00000062454, 0.16868402018, 479.28838891550 },
    { 0.00000072904, 2.84891153624, 462.02291352810 },
    { 0.00000069205, 4.43939850837, 39.35687591520 },
    { 0.00000073423, 4.27591432865, 87.31177153950 },
    { 0.00000057315, 1.63007488533, 143.62530630140 },
    { 0.00000061674, 3.18616775231, 77.22927912210 },
    { 0.00000057668, 3.67128264895, 51.20572533120 },
    { 0.00000053720, 5.51853172042, 128.95626931510 },
    { 0.00000057895, 2.66869216910, 381.61224066830 },
    { 0.00000058089, 1.58635213310, 60.76695288680 },
    { 0.00000035508, 1.96672429313, 835.03713448730 },
    { 0.00000035373, 3.72274050162, 692.58748435350 },
    { 0.00000022706, 0.53057453120, 1514.29129671650 },
    { 0.00000029040, 0.17160028536, 528.20649238630 },
    { 0.00000015879, 0.98454960135, 6208.29425142410 },
    { 0.00000009108, 2.41055572869, 10138.50394764370 }
};

static const vsop_term_t vsop_lon_Uranus_1[] =
{
    { 74.78159860910, 0.00000000000, 0.00000000000 },
    { 0.00154332863, 5.24158770553, 74.78159856730 },
    { 0.00024456474, 1.71260334156, 1.48447270830 },
    { 0.00009258442, 0.42829732350, 11.04570026390 },
    { 0.00008265977, 1.50218091379, 63.73589830340 },
    { 0.00009150160, 1.41213765216, 149.56319713460 },
    { 0.00003899108, 0.46483579160, 3.93215326310 },
    { 0.00002277065, 4.17199181523, 76.26607127560 },
    { 0.00001927470, 0.52976188479, 2.96894541660 },
    { 0.00001232725, 1.58632088145, 70.84944530420 }
};

static const vsop_series_t vsop_lon_Uranus[] =
{
    { 120, vsop_lon_Uranus_0 },
    { 10, vsop_lon_Uranus_1 }
};

static const vsop_term_t vsop_lat_Uranus_0[] =
{
    { 0.01346277648, 2.61877810547, 74.78159856730 },
    { 0.00062341400, 5.08111189648, 149.56319713460 },
    { 0.00061601196, 3.14159265359, 0.00000000000 },
    { 0.00009963722, 1.61603805646, 76.26607127560 },
    { 0.00009926160, 0.57630380333, 73.29712585900 }
};

static const vsop_term_t vsop_lat_Uranus_1[] =
{
    { 0.00034101978, 0.01321929936, 74.78159856730 }
};

static const vsop_series_t vsop_lat_Uranus[] =
{
    { 5, vsop_lat_Uranus_0 },
    { 1, vsop_lat_Uranus_1 }
};

static const vsop_term_t vsop_rad_Uranus_0[] =
{
    { 19.21264847206, 0.00000000000, 0.00000000000 },
    { 0.88784984413, 5.60377527014, 74.78159856730 },
    { 0.03440836062, 0.32836099706, 73.29712585900 },
    { 0.02055653860, 1.78295159330, 149.56319713460 },
    { 0.00649322410, 4.52247285911, 76.26607127560 },
    { 0.00602247865, 3.86003823674, 63.73589830340 },
    { 0.00496404167, 1.40139935333, 454.90936652730 },
    { 0.00338525369, 1.58002770318, 138.51749687070 },
    { 0.00243509114, 1.57086606044, 71.81265315070 },
    { 0.00190522303, 1.99809394714, 1.48447270830 },
    { 0.00161858838, 2.79137786799, 148.07872442630 },
    { 0.00143706183, 1.38368544947, 11.04570026390 },
    { 0.00093192405, 0.17437220467, 36.64856292950 },
    { 0.00071424548, 4.24509236074, 224.34479570190 },
    { 0.00089806014, 3.66105364565, 109.94568878850 },
    { 0.00039009723, 1.66971401684, 70.84944530420 },
    { 0.00046677296, 1.39976401694, 35.16409022120 },
    { 0.00039025624, 3.36234773834, 277.03499374140 },
    { 0.00036755274, 3.88649278513, 146.59425171800 },
    { 0.00030348723, 0.70100838798, 151.04766984290 },
    { 0.00029156413, 3.18056336700, 77.75054398390 },
    { 0.00020471591, 1.55587964879, 202.25339517410 },
    { 0.00025620756, 5.25656086672, 380.12776796000 },
    { 0.00025785880, 3.78537709870, 85.82729883120 },
    { 0.00022637073, 0.72518687029, 529.69096509460 },
    { 0.00020473534, 2.79640244248, 70.32818044240 },
    { 0.00017901300, 0.55455066863, 2.96894541660 },
    { 0.00012328114, 5.96037276805, 127.47179660680 },
    { 0.00014701666, 4.90434516516, 108.46121608020 },
    { 0.00011494680, 0.43772043395, 65.22037101170 },
    { 0.00015502375, 5.35405396163, 38.13303563780 },
    { 0.00010792498, 1.42106296264, 213.29909543800 },
    { 0.00011695693, 3.29824190199, 3.93215326310 },
    { 0.00011959076, 1.75043392140, 984.60033162190 },
    { 0.00012896452, 2.62154084288, 111.43016149680 },
    { 0.00011852959, 0.99344161196, 52.69019803950 },
    { 0.00009111621, 4.99633582839, 62.25142559510 },
    { 0.00008420792, 5.25351368389, 222.86032299360 },
    { 0.00007448995, 0.79495503123, 351.81659230870 },
    { 0.00008402384, 5.03876467031, 415.55249061210 },
    { 0.00006046221, 5.67958564987, 78.71375183040 },
    { 0.00005524411, 3.11493320824, 9.56122755560 },
    { 0.00007329301, 3.97276588872, 183.24281464750 }
};

static const vsop_term_t vsop_rad_Uranus_1[] =
{
    { 0.01479896629, 3.67205697578, 74.78159856730 }
};

static const vsop_series_t vsop_rad_Uranus[] =
{
    { 43, vsop_rad_Uranus_0 },
    { 1, vsop_rad_Uranus_1 }
};

;
static const vsop_term_t vsop_lon_Neptune_0[] =
{
    { 5.31188633046, 0.00000000000, 0.00000000000 },
    { 0.01798475530, 2.90101273890, 38.13303563780 },
    { 0.01019727652, 0.48580922867, 1.48447270830 },
    { 0.00124531845, 4.83008090676, 36.64856292950 },
    { 0.00042064466, 5.41054993053, 2.96894541660 },
    { 0.00037714584, 6.09221808686, 35.16409022120 },
    { 0.00033784738, 1.24488874087, 76.26607127560 },
    { 0.00016482741, 0.00007727998, 491.55792945680 },
    { 0.00009198584, 4.93747051954, 39.61750834610 },
    { 0.00008994250, 0.27462171806, 175.16605980020 },
    { 0.00004216242, 1.98711875978, 73.29712585900 },
    { 0.00003364807, 1.03590060915, 33.67961751290 },
    { 0.00002284800, 4.20606949415, 4.45341812490 },
    { 0.00001433516, 2.78339802539, 74.78159856730 },
    { 0.00000900236, 2.07607168714, 109.94568878850 },
    { 0.00000744997, 3.19032509437, 71.81265315070 },
    { 0.00000506217, 5.74786069680, 114.39910691340 },
    { 0.00000399552, 0.34972342836, 1021.24889455140 },
    { 0.00000345189, 3.46185292806, 41.10198105440 },
    { 0.00000306338, 0.49684052934, 0.52126486180 },
    { 0.00000287322, 4.50523446022, 0.04818410980 },
    { 0.00000323003, 2.24814943701, 32.19514480460 },
    { 0.00000340303, 3.30376245107, 77.75054398390 },
    { 0.00000227079, 1.79713146385, 453.42489381900 },
    { 0.00000244722, 1.24693366148, 9.56122755560 },
    { 0.00000232888, 2.50459784128, 137.03302416240 },
    { 0.00000282170, 2.24565589980, 146.59425171800 },
    { 0.00000251941, 5.78166617117, 388.46515523820 },
    { 0.00000150188, 2.99706170691, 5.93789083320 },
    { 0.00000170404, 3.32390687638, 108.46121608020 },
    { 0.00000151401, 2.19153150087, 33.94024994380 },
    { 0.00000148305, 0.85949274408, 111.43016149680 },
    { 0.00000118672, 3.67706211426, 2.44768055480 },
    { 0.00000101821, 5.70539236951, 0.11187458460 },
    { 0.00000097873, 2.80518417596, 8.07675484730 },
    { 0.00000103059, 4.40432042649, 70.32818044240 },
    { 0.00000103305, 0.04078966679, 0.26063243090 },
    { 0.00000109299, 2.41599473953, 183.24281464750 },
    { 0.00000073938, 1.32805035282, 529.69096509460 },
    { 0.00000086312, 4.22838781137, 490.07345674850 },
    { 0.00000081558, 5.19840134548, 493.04240216510 },
    { 0.00000071503, 5.29530376008, 350.33211960040 },
    { 0.00000047728, 0.12906212459, 484.44438245600 },
    { 0.00000046858, 3.01699530311, 498.67147645760 },
    { 0.00000014588, 0.69766675400, 1550.93985964600 },
    { 0.00000005918, 2.57693824084, 10175.15251057320 }
};

static const vsop_term_t vsop_lon_Neptune_1[] =
{
    { 38.13303563957, 0.00000000000, 0.00000000000 },
    { 0.00016604172, 4.86323329249, 1.48447270830 },
    { 0.00015744045, 2.27887427527, 38.13303563780 },
    { 0.00001306261, 3.67285209620, 2.96894541660 }
};

static const vsop_series_t vsop_lon_Neptune[] =
{
    { 46, vsop_lon_Neptune_0 },
    { 4, vsop_lon_Neptune_1 }
};

static const vsop_term_t vsop_lat_Neptune_0[] =
{
    { 0.03088622933, 1.44104372644, 38.13303563780 },
    { 0.00027780087, 5.91271884599, 76.26607127560 },
    { 0.00027623609, 0.00000000000, 0.00000000000 },
    { 0.00015355489, 2.52123799551, 36.64856292950 },
    { 0.00015448133, 3.50877079215, 39.61750834610 }
};

static const vsop_series_t vsop_lat_Neptune[] =
{
    { 5, vsop_lat_Neptune_0 }
};

static const vsop_term_t vsop_rad_Neptune_0[] =
{
    { 30.07013205828, 0.00000000000, 0.00000000000 },
    { 0.27062259632, 1.32999459377, 38.13303563780 },
    { 0.01691764014, 3.25186135653, 36.64856292950 },
    { 0.00807830553, 5.18592878704, 1.48447270830 },
    { 0.00537760510, 4.52113935896, 35.16409022120 },
    { 0.00495725141, 1.57105641650, 491.55792945680 },
    { 0.00274571975, 1.84552258866, 175.16605980020 },
    { 0.00135134092, 3.37220609835, 39.61750834610 },
    { 0.00121801746, 5.79754470298, 76.26607127560 },
    { 0.00100896068, 0.37702724930, 73.29712585900 },
    { 0.00069791331, 3.79616637768, 2.96894541660 },
    { 0.00046687836, 5.74938034313, 33.67961751290 },
    { 0.00024594531, 0.50801745878, 109.94568878850 },
    { 0.00012012320, 1.92059384991, 1021.24889455140 },
    { 0.00007571796, 1.07149207335, 388.46515523820 }
};

static const vsop_series_t vsop_rad_Neptune[] =
{
    { 15, vsop_rad_Neptune_0 }
};

;

/** @cond DOXYGEN_SKIP */
#define VSOPFORMULA(x)    { ASTRO_ARRAYSIZE(x), x }
/** @endcond */

static const vsop_model_t vsop[] =
{
    { { VSOPFORMULA(vsop_lon_Mercury),  VSOPFORMULA(vsop_lat_Mercury),  VSOPFORMULA(vsop_rad_Mercury) } },
    { { VSOPFORMULA(vsop_lon_Venus),    VSOPFORMULA(vsop_lat_Venus),    VSOPFORMULA(vsop_rad_Venus)   } },
    { { VSOPFORMULA(vsop_lon_Earth),    VSOPFORMULA(vsop_lat_Earth),    VSOPFORMULA(vsop_rad_Earth)   } },
    { { VSOPFORMULA(vsop_lon_Mars),     VSOPFORMULA(vsop_lat_Mars),     VSOPFORMULA(vsop_rad_Mars)    } },
    { { VSOPFORMULA(vsop_lon_Jupiter),  VSOPFORMULA(vsop_lat_Jupiter),  VSOPFORMULA(vsop_rad_Jupiter) } },
    { { VSOPFORMULA(vsop_lon_Saturn),   VSOPFORMULA(vsop_lat_Saturn),   VSOPFORMULA(vsop_rad_Saturn)  } },
    { { VSOPFORMULA(vsop_lon_Uranus),   VSOPFORMULA(vsop_lat_Uranus),   VSOPFORMULA(vsop_rad_Uranus)  } },
    { { VSOPFORMULA(vsop_lon_Neptune),  VSOPFORMULA(vsop_lat_Neptune),  VSOPFORMULA(vsop_rad_Neptune) } }
};

/** @cond DOXYGEN_SKIP */
#define CalcEarth(time)     CalcVsop(&vsop[BODY_EARTH], (time))
#define LON_INDEX 0
#define LAT_INDEX 1
#define RAD_INDEX 2
/** @endcond */

/*
    AstronomyKit local patch (series cosine). The planet series below hold
    2.7 times the terms upstream kept, and the C library's cos, sin and fmod
    were most of the cost of evaluating them. These inline versions work on
    two angles at once and agree with the exact cosine and sine within
    1e-15.

    series_pair_t is two doubles that the compiler keeps in one vector
    register (a GCC and clang extension; arithmetic on it is elementwise).
    Nothing below branches on the angle, so the cost does not depend on it.

    SERIES_WRAP subtracts the nearest multiple of 2 pi, leaving y in
    [-pi, pi]. SERIES_TURNS is k, the count of that multiple: adding and
    subtracting SERIES_ROUND rounds to an integer without a library call, in
    the default rounding mode; in a directed mode k can be one off, and the
    results below are then good to 2e-7. SERIES_2PI_A holds the first 33
    bits of 2 pi, so k * SERIES_2PI_A is exact for |k| < 2^20; SERIES_2PI_B
    and SERIES_2PI_C hold the rest. It is valid for |x| < 2^20 * 2 pi, about
    6.5e6. A series argument is a phase plus a frequency of at most 316,429
    radians per millennium times at most 4 millennia (EPHEMERIS_MAX_TT_DAYS,
    the accepted time range patch, which every caller checks first), so it
    is below 1.3e6.

    With r = y/2, cos(x) = 2 cos(r)^2 - 1 and sin(x) = 2 sin(r) cos(r), which
    need no sign bookkeeping. SeriesHalfCos and SeriesHalfSinc are degree-8
    polynomials in y*y for cos(r) and sin(r)/r on |r| <= pi/2, interpolated
    at Chebyshev nodes; each is within 2.3e-16 of the function.

    Some of the shape below is for builds without optimisation, which is how
    SwiftPM's Debug configuration compiles C. Such a build inlines only what
    is marked always_inline (SERIES_INLINE) and keeps every variable and
    parameter in memory, and clang for arm64 reloads the constants at the
    top of every basic block. So SERIES_TURNS and SERIES_WRAP are macros,
    which repeat an expression where a function would store it and read it
    back; the two SERIES_ADD macros are plain blocks, so that several in a
    row stay in one basic block; and without optimisation SeriesSum takes
    four pairs in each pass of its loops. An optimising compiler merges the
    repeats and keeps the constants in registers, and gains nothing from the
    four pairs. Every form does the same operations in the same order, so
    this code sums a series to the same doubles in every build. A Debug build
    on an Apple platform sums the longer series with SeriesSumAccelerate
    instead, and its doubles are not these.
*/
/** @cond DOXYGEN_SKIP */
typedef double series_pair_t __attribute__((vector_size(16)));

#define SERIES_INLINE   static inline __attribute__((always_inline))

#define SERIES_INV_2PI  0x1.45F306DC9C883p-3
#define SERIES_2PI_A    0x1.921FB54400000p+2
#define SERIES_2PI_B    0x1.0B4611A600000p-32
#define SERIES_2PI_C    0x1.3198A2E037073p-67
#define SERIES_ROUND    0x1.8p52

#define SERIES_TURNS(x) (((x) * SERIES_INV_2PI + SERIES_ROUND) - SERIES_ROUND)
#define SERIES_WRAP(x) \
    ((((x) - SERIES_TURNS(x) * SERIES_2PI_A) - SERIES_TURNS(x) * SERIES_2PI_B) - SERIES_TURNS(x) * SERIES_2PI_C)
/** @endcond */

SERIES_INLINE series_pair_t SeriesHalfCos(series_pair_t w)      /* cos(y/2) for w = y*y */
{
    return 1.0 + w * (-0x1.ffffffffffffbp-4 + w * (0x1.55555555553c4p-9
        + w * (-0x1.6c16c16c09b4ep-16 + w * (0x1.a01a01994c338p-24
        + w * (-0x1.27e4f97932a13p-32 + w * (0x1.1eecdf3979d83p-41
        + w * (-0x1.9350a435543dbp-51 + w * 0x1.9f23c5f3847cbp-61)))))));
}

SERIES_INLINE series_pair_t SeriesHalfSinc(series_pair_t w)     /* sin(y/2) / (y/2) for w = y*y */
{
    return 1.0 + w * (-0x1.5555555555555p-5 + w * (0x1.11111111110bcp-11
        + w * (-0x1.a01a01a0147f4p-19 + w * (0x1.71de3a528d198p-27
        + w * (-0x1.ae6454d0761e5p-36 + w * (0x1.6123ccd995369p-45
        + w * (-0x1.ae439ef7766b1p-55 + w * 0x1.88386468b9715p-65)))))));
}

/* The sine and the cosine of each of two angles. */
SERIES_INLINE void SeriesSinCos(series_pair_t x, series_pair_t *sine, series_pair_t *cosine)
{
    series_pair_t y = SERIES_WRAP(x);
    series_pair_t w = y * y;
    series_pair_t c = SeriesHalfCos(w);
    *sine = y * SeriesHalfSinc(w) * c;
    *cosine = (c + c) * c - 1.0;
}

/** @cond DOXYGEN_SKIP */
/* Adds amplitude * cos(phase + t * frequency) of the terms a and b to the two cosine sums. */
#define SERIES_ADD_COS(cos_pair, a, b, t) \
    { \
        series_pair_t x = { (a).phase + (t) * (a).frequency, (b).phase + (t) * (b).frequency }; \
        series_pair_t y = SERIES_WRAP(x); \
        series_pair_t c = SeriesHalfCos(y * y); \
        series_pair_t amplitude = { (a).amplitude, (b).amplitude }; \
        (cos_pair) += amplitude * ((c + c) * c - 1.0); \
    }

/* As SERIES_ADD_COS, and adds amplitude * frequency * sin(phase + t * frequency) to the two sine sums. */
#define SERIES_ADD_SIN_COS(cos_pair, sin_pair, a, b, t) \
    { \
        series_pair_t x = { (a).phase + (t) * (a).frequency, (b).phase + (t) * (b).frequency }; \
        series_pair_t y = SERIES_WRAP(x); \
        series_pair_t w = y * y; \
        series_pair_t c = SeriesHalfCos(w); \
        series_pair_t amplitude = { (a).amplitude, (b).amplitude }; \
        series_pair_t rate = { (a).amplitude * (a).frequency, (b).amplitude * (b).frequency }; \
        (cos_pair) += amplitude * ((c + c) * c - 1.0); \
        (sin_pair) += rate * (y * SeriesHalfSinc(w) * c); \
    }
/** @endcond */

#ifdef SERIES_USE_ACCELERATE
/*
    AstronomyKit local patch (series cosine): SeriesSum for a series of
    SERIES_ACCELERATE_MIN to SERIES_ACCELERATE_MAX terms, in a build without
    optimisation on an Apple platform. Accelerate is optimised whatever this
    file is compiled with, and sums a long series in about a third of the
    time the inline code above takes unoptimised; below SERIES_ACCELERATE_MIN
    terms its calls cost more than they save. No series is longer than
    SERIES_ACCELERATE_MAX, the size of the buffers. Package.swift defines
    ASTRONOMYKIT_SERIES_ACCELERATE and links the framework for Debug builds
    on Apple platforms. No other build has this function.

    Accelerate's cosine and sine round differently from the inline ones, and
    the terms are added in another order. So such a build does not compute
    the doubles other builds do. At 100,001 instants spread over the accepted
    time range, the heliocentric positions of the eight planets were within
    9.4e-12 AU of an optimised arm64 build's, and the velocities within
    8.4e-14 AU per day.

    The strides of 3 step from one term's field to the next term's.
*/
/** @cond DOXYGEN_SKIP */
#define SERIES_ACCELERATE_MIN   8
#define SERIES_ACCELERATE_MAX   192
/** @endcond */

static double SeriesSumAccelerate(const vsop_series_t *series, double t, double *sin_sum)
{
    _Static_assert(sizeof(vsop_term_t) == 3 * sizeof(double), "the strides of 3 need a term of three doubles");
    double angle[SERIES_ACCELERATE_MAX];
    double cosine[SERIES_ACCELERATE_MAX];
    double sine[SERIES_ACCELERATE_MAX];
    const vsop_term_t *term = series->term;
    int n = series->nterms;
    double cos_sum;

    /* angle = phase + t * frequency */
    vDSP_vsmaD(&term->frequency, 3, &t, &term->phase, 3, angle, 1, (vDSP_Length)n);
    if (sin_sum == NULL)
    {
        vvcos(cosine, angle, &n);
    }
    else
    {
        /* the sum of amplitude * frequency * sine */
        vvsincos(sine, cosine, angle, &n);
        vDSP_vmulD(sine, 1, &term->frequency, 3, sine, 1, (vDSP_Length)n);
        vDSP_dotprD(&term->amplitude, 3, sine, 1, sin_sum, (vDSP_Length)n);
    }
    /* the sum of amplitude * cosine */
    vDSP_dotprD(&term->amplitude, 3, cosine, 1, &cos_sum, (vDSP_Length)n);
    return cos_sum;
}
#endif

/*
    The sum over a series of amplitude * cos(phase + t * frequency), and with
    sin_sum not NULL also of amplitude * frequency * sin(phase + t *
    frequency). Terms are taken two at a time, the even ones summed apart
    from the odd ones. A last term without a partner is paired with none,
    which adds zero.
*/
SERIES_INLINE double SeriesSum(const vsop_series_t *series, double t, double *sin_sum)
{
    static const vsop_term_t none = { 0.0, 0.0, 0.0 };
    const vsop_term_t *term = series->term;
    const vsop_term_t *end = term + series->nterms;
    series_pair_t cos_pair = { 0.0, 0.0 };
    series_pair_t sin_pair = { 0.0, 0.0 };

#ifdef SERIES_USE_ACCELERATE
    if (series->nterms >= SERIES_ACCELERATE_MIN && series->nterms <= SERIES_ACCELERATE_MAX)
        return SeriesSumAccelerate(series, t, sin_sum);
#endif

    if (sin_sum == NULL)
    {
#ifndef __OPTIMIZE__
        for (; end - term >= 8; term += 8)
        {
            SERIES_ADD_COS(cos_pair, term[0], term[1], t);
            SERIES_ADD_COS(cos_pair, term[2], term[3], t);
            SERIES_ADD_COS(cos_pair, term[4], term[5], t);
            SERIES_ADD_COS(cos_pair, term[6], term[7], t);
        }
#endif
        for (; end - term >= 2; term += 2)
            SERIES_ADD_COS(cos_pair, term[0], term[1], t);
        if (term < end)
            SERIES_ADD_COS(cos_pair, term[0], none, t);
    }
    else
    {
#ifndef __OPTIMIZE__
        for (; end - term >= 8; term += 8)
        {
            SERIES_ADD_SIN_COS(cos_pair, sin_pair, term[0], term[1], t);
            SERIES_ADD_SIN_COS(cos_pair, sin_pair, term[2], term[3], t);
            SERIES_ADD_SIN_COS(cos_pair, sin_pair, term[4], term[5], t);
            SERIES_ADD_SIN_COS(cos_pair, sin_pair, term[6], term[7], t);
        }
#endif
        for (; end - term >= 2; term += 2)
            SERIES_ADD_SIN_COS(cos_pair, sin_pair, term[0], term[1], t);
        if (term < end)
            SERIES_ADD_SIN_COS(cos_pair, sin_pair, term[0], none, t);
        *sin_sum = sin_pair[0] + sin_pair[1];
    }
    return cos_pair[0] + cos_pair[1];
}

/* x less the nearest multiple of 2 pi, for one value. */
SERIES_INLINE double SeriesWrapOne(double x)
{
    series_pair_t pair = { x, 0.0 };
    series_pair_t wrapped = SERIES_WRAP(pair);
    return wrapped[0];
}

/*
    AstronomyKit local patch (nutation series). Upstream kept the five
    largest of the 77 terms of the IAU 2000B nutation series (McCarthy and
    Luzum, 2003). This sums all 77.

    Each term's argument is a whole multiple of each of five angles: l and
    l', the mean anomalies of the Moon and the Sun; F, the Moon's mean
    argument of latitude; D, its mean elongation from the Sun; and Om, the
    mean longitude of its ascending node. The 77 arguments pair one of 14
    multiples of l and l' with one of 18 multiples of F, D and Om. So the
    cosine and sine of the five angles are found once, those of the 14 and
    the 18 follow from them by the angle addition formulas, and each term
    takes one more application of the formulas instead of a cosine and a
    sine of its own.

    A cosine and sine are kept together as { cosine, sine } in a
    series_pair_t, and NUT_MUL is the angle addition formulas: from the
    pairs of two angles it gives the pair of their sum. NUT_CONJ gives the
    pair of the angle negated. A term multiplies its pair by its
    coefficients into three sums, the terms at even and odd positions
    apart as in SeriesSum, and the cosine and sine parts are added together
    at the end. Nothing branches on an angle, so the cost is the same at
    every time, and a build without optimisation computes the same doubles
    as an optimised one. The result is within 4e-10 arcseconds of the
    published routine's, which takes a cosine and a sine for each term,
    over the accepted time range.

    NUT_TERM is a row of the published table: the multiples of l, l', F, D
    and Om, then the coefficients in units of 0.1 microarcsecond, and of
    that per Julian century for the two rates: longitude sine and its rate,
    longitude cosine, obliquity cosine and its rate, obliquity sine.
    NUT_ANOMALY and NUT_NODE turn the multiples into the places in the two
    arrays of pairs that iau2000b fills; it fills only the places the table
    uses.
*/
/** @cond DOXYGEN_SKIP */
typedef struct
{
    series_pair_t psi;          /* longitude: { cosine, sine } coefficients */
    series_pair_t eps;          /* obliquity: { cosine, sine } coefficients */
    series_pair_t rate;         /* per century: { obliquity cosine, longitude sine } */
    unsigned char anomaly;      /* NUT_ANOMALY of the multiples of l and l' */
    unsigned char node;         /* NUT_NODE of the multiples of F, D and Om */
}
nut_term_t;

/* l is -2 to 3 and lp -2 to 2; f is -2, 0 or 2, d -2 to 4 and om 0 to 2. */
#define NUT_ANOMALY(l, lp)      (((l) + 2) * 5 + (lp) + 2)
#define NUT_NODE(f, d, om)      ((((f) + 2) / 2 * 7 + (d) + 2) * 3 + (om))
#define NUT_ANOMALY_COUNT       30
#define NUT_NODE_COUNT          63

#define NUT_TERM(l, lp, f, d, om, ps, pst, pc, ec, ect, es) \
    { { pc, ps }, { ec, es }, { ect, pst }, NUT_ANOMALY(l, lp), NUT_NODE(f, d, om) }

#define NUT_MUL(a, b)   ((a) * (b)[0] + (series_pair_t){ -(a)[1], (a)[0] } * (b)[1])
#define NUT_CONJ(a)     ((series_pair_t){ (a)[0], -(a)[1] })

/* Turns of an angle given in arcseconds at J2000 and arcseconds per century; a turn is 1296000 arcseconds. */
#define NUT_TURNS(asec, rate)   ((asec) / 1296000.0 + t * ((rate) / 1296000.0))

/*
    The { cosine, sine } pairs of two angles given in turns. Taking the
    nearest whole number from each leaves at most half a turn, which is the
    range of SeriesHalfCos and SeriesHalfSinc, however large the angle.
*/
#define NUT_COS_SIN(first, second, turn_a, turn_b) \
    { \
        series_pair_t y = { (turn_a) - rint(turn_a), (turn_b) - rint(turn_b) }; \
        series_pair_t w, c, s; \
        y *= 2.0 * PI; \
        w = y * y; \
        c = SeriesHalfCos(w); \
        s = y * SeriesHalfSinc(w) * c; \
        c = (c + c) * c - 1.0; \
        (first) = (series_pair_t){ c[0], s[0] }; \
        (second) = (series_pair_t){ c[1], s[1] }; \
    }

/* Adds term k to three sums. */
#define NUT_ADD(k, psi_sum, eps_sum, rate_sum) \
    { \
        series_pair_t z = NUT_MUL(anomaly[nut_term[k].anomaly], node[nut_term[k].node]); \
        (psi_sum) += nut_term[k].psi * z; \
        (eps_sum) += nut_term[k].eps * z; \
        (rate_sum) += nut_term[k].rate * z; \
    }
/** @endcond */

static const nut_term_t nut_term[] =
{
    NUT_TERM( 0, 0, 0, 0, 1, -172064161, -174666,  33386,  92052331,  9086, 15377),
    NUT_TERM( 0, 0, 2,-2, 2,  -13170906,   -1675, -13696,   5730336, -3015, -4587),
    NUT_TERM( 0, 0, 2, 0, 2,   -2276413,    -234,   2796,    978459,  -485,  1374),
    NUT_TERM( 0, 0, 0, 0, 2,    2074554,     207,   -698,   -897492,   470,  -291),
    NUT_TERM( 0, 1, 0, 0, 0,    1475877,   -3633,  11817,     73871,  -184, -1924),
    NUT_TERM( 0, 1, 2,-2, 2,    -516821,    1226,   -524,    224386,  -677,  -174),
    NUT_TERM( 1, 0, 0, 0, 0,     711159,      73,   -872,     -6750,     0,   358),
    NUT_TERM( 0, 0, 2, 0, 1,    -387298,    -367,    380,    200728,    18,   318),
    NUT_TERM( 1, 0, 2, 0, 2,    -301461,     -36,    816,    129025,   -63,   367),
    NUT_TERM( 0,-1, 2,-2, 2,     215829,    -494,    111,    -95929,   299,   132),
    NUT_TERM( 0, 0, 2,-2, 1,     128227,     137,    181,    -68982,    -9,    39),
    NUT_TERM(-1, 0, 2, 0, 2,     123457,      11,     19,    -53311,    32,    -4),
    NUT_TERM(-1, 0, 0, 2, 0,     156994,      10,   -168,     -1235,     0,    82),
    NUT_TERM( 1, 0, 0, 0, 1,      63110,      63,     27,    -33228,     0,    -9),
    NUT_TERM(-1, 0, 0, 0, 1,     -57976,     -63,   -189,     31429,     0,   -75),
    NUT_TERM(-1, 0, 2, 2, 2,     -59641,     -11,    149,     25543,   -11,    66),
    NUT_TERM( 1, 0, 2, 0, 1,     -51613,     -42,    129,     26366,     0,    78),
    NUT_TERM(-2, 0, 2, 0, 1,      45893,      50,     31,    -24236,   -10,    20),
    NUT_TERM( 0, 0, 0, 2, 0,      63384,      11,   -150,     -1220,     0,    29),
    NUT_TERM( 0, 0, 2, 2, 2,     -38571,      -1,    158,     16452,   -11,    68),
    NUT_TERM( 0,-2, 2,-2, 2,      32481,       0,      0,    -13870,     0,     0),
    NUT_TERM(-2, 0, 0, 2, 0,     -47722,       0,    -18,       477,     0,   -25),
    NUT_TERM( 2, 0, 2, 0, 2,     -31046,      -1,    131,     13238,   -11,    59),
    NUT_TERM( 1, 0, 2,-2, 2,      28593,       0,     -1,    -12338,    10,    -3),
    NUT_TERM(-1, 0, 2, 0, 1,      20441,      21,     10,    -10758,     0,    -3),
    NUT_TERM( 2, 0, 0, 0, 0,      29243,       0,    -74,      -609,     0,    13),
    NUT_TERM( 0, 0, 2, 0, 0,      25887,       0,    -66,      -550,     0,    11),
    NUT_TERM( 0, 1, 0, 0, 1,     -14053,     -25,     79,      8551,    -2,   -45),
    NUT_TERM(-1, 0, 0, 2, 1,      15164,      10,     11,     -8001,     0,    -1),
    NUT_TERM( 0, 2, 2,-2, 2,     -15794,      72,    -16,      6850,   -42,    -5),
    NUT_TERM( 0, 0,-2, 2, 0,      21783,       0,     13,      -167,     0,    13),
    NUT_TERM( 1, 0, 0,-2, 1,     -12873,     -10,    -37,      6953,     0,   -14),
    NUT_TERM( 0,-1, 0, 0, 1,     -12654,      11,     63,      6415,     0,    26),
    NUT_TERM(-1, 0, 2, 2, 1,     -10204,       0,     25,      5222,     0,    15),
    NUT_TERM( 0, 2, 0, 0, 0,      16707,     -85,    -10,       168,    -1,    10),
    NUT_TERM( 1, 0, 2, 2, 2,      -7691,       0,     44,      3268,     0,    19),
    NUT_TERM(-2, 0, 2, 0, 0,     -11024,       0,    -14,       104,     0,     2),
    NUT_TERM( 0, 1, 2, 0, 2,       7566,     -21,    -11,     -3250,     0,    -5),
    NUT_TERM( 0, 0, 2, 2, 1,      -6637,     -11,     25,      3353,     0,    14),
    NUT_TERM( 0,-1, 2, 0, 2,      -7141,      21,      8,      3070,     0,     4),
    NUT_TERM( 0, 0, 0, 2, 1,      -6302,     -11,      2,      3272,     0,     4),
    NUT_TERM( 1, 0, 2,-2, 1,       5800,      10,      2,     -3045,     0,    -1),
    NUT_TERM( 2, 0, 2,-2, 2,       6443,       0,     -7,     -2768,     0,    -4),
    NUT_TERM(-2, 0, 0, 2, 1,      -5774,     -11,    -15,      3041,     0,    -5),
    NUT_TERM( 2, 0, 2, 0, 1,      -5350,       0,     21,      2695,     0,    12),
    NUT_TERM( 0,-1, 2,-2, 1,      -4752,     -11,     -3,      2719,     0,    -3),
    NUT_TERM( 0, 0, 0,-2, 1,      -4940,     -11,    -21,      2720,     0,    -9),
    NUT_TERM(-1,-1, 0, 2, 0,       7350,       0,     -8,       -51,     0,     4),
    NUT_TERM( 2, 0, 0,-2, 1,       4065,       0,      6,     -2206,     0,     1),
    NUT_TERM( 1, 0, 0, 2, 0,       6579,       0,    -24,      -199,     0,     2),
    NUT_TERM( 0, 1, 2,-2, 1,       3579,       0,      5,     -1900,     0,     1),
    NUT_TERM( 1,-1, 0, 0, 0,       4725,       0,     -6,       -41,     0,     3),
    NUT_TERM(-2, 0, 2, 0, 2,      -3075,       0,     -2,      1313,     0,    -1),
    NUT_TERM( 3, 0, 2, 0, 2,      -2904,       0,     15,      1233,     0,     7),
    NUT_TERM( 0,-1, 0, 2, 0,       4348,       0,    -10,       -81,     0,     2),
    NUT_TERM( 1,-1, 2, 0, 2,      -2878,       0,      8,      1232,     0,     4),
    NUT_TERM( 0, 0, 0, 1, 0,      -4230,       0,      5,       -20,     0,    -2),
    NUT_TERM(-1,-1, 2, 2, 2,      -2819,       0,      7,      1207,     0,     3),
    NUT_TERM(-1, 0, 2, 0, 0,      -4056,       0,      5,        40,     0,    -2),
    NUT_TERM( 0,-1, 2, 2, 2,      -2647,       0,     11,      1129,     0,     5),
    NUT_TERM(-2, 0, 0, 0, 1,      -2294,       0,    -10,      1266,     0,    -4),
    NUT_TERM( 1, 1, 2, 0, 2,       2481,       0,     -7,     -1062,     0,    -3),
    NUT_TERM( 2, 0, 0, 0, 1,       2179,       0,     -2,     -1129,     0,    -2),
    NUT_TERM(-1, 1, 0, 1, 0,       3276,       0,      1,        -9,     0,     0),
    NUT_TERM( 1, 1, 0, 0, 0,      -3389,       0,      5,        35,     0,    -2),
    NUT_TERM( 1, 0, 2, 0, 0,       3339,       0,    -13,      -107,     0,     1),
    NUT_TERM(-1, 0, 2,-2, 1,      -1987,       0,     -6,      1073,     0,    -2),
    NUT_TERM( 1, 0, 0, 0, 2,      -1981,       0,      0,       854,     0,     0),
    NUT_TERM(-1, 0, 0, 1, 0,       4026,       0,   -353,      -553,     0,  -139),
    NUT_TERM( 0, 0, 2, 1, 2,       1660,       0,     -5,      -710,     0,    -2),
    NUT_TERM(-1, 0, 2, 4, 2,      -1521,       0,      9,       647,     0,     4),
    NUT_TERM(-1, 1, 0, 1, 1,       1314,       0,      0,      -700,     0,     0),
    NUT_TERM( 0,-2, 2,-2, 1,      -1283,       0,      0,       672,     0,     0),
    NUT_TERM( 1, 0, 2, 2, 1,      -1331,       0,      8,       663,     0,     4),
    NUT_TERM(-2, 0, 2, 2, 2,       1383,       0,     -2,      -594,     0,    -2),
    NUT_TERM(-1, 0, 0, 0, 2,       1405,       0,      4,      -610,     0,     2),
    NUT_TERM( 1, 1, 2,-2, 2,       1290,       0,      0,      -556,     0,     0)
};

static void iau2000b(astro_time_t *time)
{
    if ((time != NULL) && isnan(time->psi))
    {
        double t = time->tt / 36525.0;
        series_pair_t l, lp, f2, d, om, d2, om2, f2d2, unused;
        series_pair_t anomaly[NUT_ANOMALY_COUNT], node[NUT_NODE_COUNT];
        series_pair_t psi0 = { 0.0, 0.0 }, eps0 = { 0.0, 0.0 }, rate0 = { 0.0, 0.0 };
        series_pair_t psi1 = { 0.0, 0.0 }, eps1 = { 0.0, 0.0 }, rate1 = { 0.0, 0.0 };
        int k;

        /* F appears only doubled. */
        NUT_COS_SIN(l, lp, NUT_TURNS(485868.249036, 1717915923.2178), NUT_TURNS(1287104.79305, 129596581.0481));
        NUT_COS_SIN(f2, d, 2.0 * NUT_TURNS(335779.526232, 1739527262.8478), NUT_TURNS(1072260.70369, 1602961601.2090));
        NUT_COS_SIN(om, unused, NUT_TURNS(450160.398036, -6962890.5431), 0.0);
        (void)unused;

        anomaly[NUT_ANOMALY(0, 0)] = (series_pair_t){ 1.0, 0.0 };
        anomaly[NUT_ANOMALY(1, 0)] = l;
        anomaly[NUT_ANOMALY(-1, 0)] = NUT_CONJ(l);
        anomaly[NUT_ANOMALY(2, 0)] = NUT_MUL(l, l);
        anomaly[NUT_ANOMALY(-2, 0)] = NUT_CONJ(anomaly[NUT_ANOMALY(2, 0)]);
        anomaly[NUT_ANOMALY(3, 0)] = NUT_MUL(anomaly[NUT_ANOMALY(2, 0)], l);
        anomaly[NUT_ANOMALY(0, 1)] = lp;
        anomaly[NUT_ANOMALY(0, -1)] = NUT_CONJ(lp);
        anomaly[NUT_ANOMALY(0, 2)] = NUT_MUL(lp, lp);
        anomaly[NUT_ANOMALY(0, -2)] = NUT_CONJ(anomaly[NUT_ANOMALY(0, 2)]);
        anomaly[NUT_ANOMALY(1, 1)] = NUT_MUL(l, lp);
        anomaly[NUT_ANOMALY(-1, -1)] = NUT_CONJ(anomaly[NUT_ANOMALY(1, 1)]);
        anomaly[NUT_ANOMALY(1, -1)] = NUT_MUL(l, anomaly[NUT_ANOMALY(0, -1)]);
        anomaly[NUT_ANOMALY(-1, 1)] = NUT_CONJ(anomaly[NUT_ANOMALY(1, -1)]);

        d2 = NUT_MUL(d, d);
        om2 = NUT_MUL(om, om);
        f2d2 = NUT_MUL(f2, NUT_CONJ(d2));       /* 2F - 2D */
        node[NUT_NODE(0, 0, 0)] = (series_pair_t){ 1.0, 0.0 };
        node[NUT_NODE(0, 0, 1)] = om;
        node[NUT_NODE(0, 0, 2)] = om2;
        node[NUT_NODE(2, 0, 0)] = f2;
        node[NUT_NODE(2, 0, 1)] = NUT_MUL(f2, om);
        node[NUT_NODE(2, 0, 2)] = NUT_MUL(f2, om2);
        node[NUT_NODE(0, 1, 0)] = d;
        node[NUT_NODE(0, 1, 1)] = NUT_MUL(d, om);
        node[NUT_NODE(0, 2, 0)] = d2;
        node[NUT_NODE(0, 2, 1)] = NUT_MUL(d2, om);
        node[NUT_NODE(0, -2, 1)] = NUT_MUL(NUT_CONJ(d2), om);
        node[NUT_NODE(2, -2, 1)] = NUT_MUL(f2d2, om);
        node[NUT_NODE(2, -2, 2)] = NUT_MUL(f2d2, om2);
        node[NUT_NODE(-2, 2, 0)] = NUT_CONJ(f2d2);
        node[NUT_NODE(2, 1, 2)] = NUT_MUL(node[NUT_NODE(2, 0, 2)], d);
        node[NUT_NODE(2, 2, 1)] = NUT_MUL(node[NUT_NODE(2, 0, 1)], d2);
        node[NUT_NODE(2, 2, 2)] = NUT_MUL(node[NUT_NODE(2, 0, 2)], d2);
        node[NUT_NODE(2, 4, 2)] = NUT_MUL(node[NUT_NODE(2, 2, 2)], d2);

        for (k = 0; k + 1 < (int)ASTRO_ARRAYSIZE(nut_term); k += 2)
        {
            NUT_ADD(k, psi0, eps0, rate0);
            NUT_ADD(k + 1, psi1, eps1, rate1);
        }
        if (k < (int)ASTRO_ARRAYSIZE(nut_term))
            NUT_ADD(k, psi0, eps0, rate0);
        psi0 += psi1;
        eps0 += eps1;
        rate0 += rate1;

        /* The two constants stand in for the planetary terms, as in the published routine. */
        time->psi = -0.000135 + ((psi0[0] + psi0[1] + t * rate0[1]) * 1.0e-7);
        time->eps = +0.000388 + ((eps0[0] + eps0[1] + t * rate0[0]) * 1.0e-7);
    }
}

static void VsopCoords(const vsop_model_t *model, double t, double sphere[3])
{
    int k, s;
    double incr;

    for (k=0; k < 3; ++k)
    {
        double tpower = 1.0;
        const vsop_formula_t *formula = &model->formula[k];
        sphere[k] = 0.0;
        for (s=0; s < formula->nseries; ++s)
        {
            /* AstronomyKit local patch (series cosine) */
            incr = tpower * SeriesSum(&formula->series[s], t, NULL);
            if (k == LON_INDEX)
                incr = SeriesWrapOne(incr);     /* improve precision for longitudes, which can be hundreds of radians */
            sphere[k] += incr;
            tpower *= t;
        }
    }
}


static terse_vector_t VsopRotate(const double ecl[3])
{
    terse_vector_t equ;

    /*
        X        +1.000000000000  +0.000000440360  -0.000000190919   X
        Y     =  -0.000000479966  +0.917482137087  -0.397776982902   Y
        Z FK5     0.000000000000  +0.397776982902  +0.917482137087   Z VSOP87A
    */

    equ.x = ecl[0] + 0.000000440360*ecl[1] - 0.000000190919*ecl[2];
    equ.y = -0.000000479966*ecl[0] + 0.917482137087*ecl[1] - 0.397776982902*ecl[2];
    equ.z = 0.397776982902*ecl[1] + 0.917482137087*ecl[2];

    return equ;
}


static void VsopSphereToRect(double lon, double lat, double radius, double pos[3])
{
    /* AstronomyKit local patch (series cosine): the pair is longitude, latitude */
    series_pair_t angle = { lon, lat };
    series_pair_t sine, cosine;
    SeriesSinCos(angle, &sine, &cosine);
    pos[0] = radius * cosine[1] * cosine[0];
    pos[1] = radius * cosine[1] * sine[0];
    pos[2] = radius * sine[1];
}

static const double DAYS_PER_MILLENNIUM = 365250.0;


static astro_vector_t CalcVsop(const vsop_model_t *model, astro_time_t time)
{
    double t = time.tt / DAYS_PER_MILLENNIUM;
    double sphere[3];       /* lon, lat, rad */
    double eclip[3];
    astro_vector_t vector;
    terse_vector_t pos;

    /* AstronomyKit local patch (accepted time range) */
    if (!EphemerisTimeOk(time))
        return VecError(ASTRO_BAD_TIME, time);

    /* Calculate the VSOP "B" trigonometric series to obtain ecliptic spherical coordinates. */
    VsopCoords(model, t, sphere);

    /* Convert ecliptic spherical coordinates to ecliptic Cartesian coordinates. */
    VsopSphereToRect(sphere[LON_INDEX], sphere[LAT_INDEX], sphere[RAD_INDEX], eclip);

    /* Convert ecliptic Cartesian coordinates to equatorial Cartesian coordinates. */
    pos = VsopRotate(eclip);

    /* Package the position as astro_vector_t. */
    vector.status = ASTRO_SUCCESS;
    vector.t = time;
    vector.x = pos.x;
    vector.y = pos.y;
    vector.z = pos.z;

    return vector;
}


/*
    AstronomyKit local patch (series cosine): upstream's VsopDeriv took the
    rates in a second pass over the series. This takes the coordinates and
    their rates in one pass, so each term's sine and cosine are found once.
*/
static void VsopCoordsAndRates(const vsop_model_t *model, double t, double sphere[3], double deriv[3])
{
    int k, s;

    for (k=0; k < 3; ++k)
    {
        double tpower = 1.0;        /* t^s */
        double dpower = 0.0;        /* t^(s-1) */
        const vsop_formula_t *formula = &model->formula[k];
        sphere[k] = 0.0;
        deriv[k] = 0.0;
        for (s=0; s < formula->nseries; ++s)
        {
            double sin_sum;
            double cos_sum = SeriesSum(&formula->series[s], t, &sin_sum);
            double incr = tpower * cos_sum;
            if (k == LON_INDEX)
                incr = SeriesWrapOne(incr);     /* as in VsopCoords */
            sphere[k] += incr;
            deriv[k] += (s * dpower * cos_sum) - (tpower * sin_sum);
            dpower = tpower;
            tpower *= t;
        }
    }
}


static body_state_t CalcVsopPosVel(const vsop_model_t *model, double tt)
{
    body_state_t state;
    double t = tt / DAYS_PER_MILLENNIUM;
    double sphere[3];   /* lon, lat, r */
    double deriv[3];    /* d(lon)/dt, d(lat)/dt, dr/dt */
    double eclip[3];
    double dr_dt, dlat_dt, dlon_dt;
    double r, coslat, coslon, sinlat, sinlon;
    series_pair_t angle, sine, cosine;

    state.tt = tt;
    /* AstronomyKit local patch (series cosine): one pass in place of VsopCoords and VsopDeriv */
    VsopCoordsAndRates(model, t, sphere, deriv);

    /* AstronomyKit local patch (series cosine): the sines and cosines of the longitude */
    /* and latitude, found once for the position and the velocity. The position is the */
    /* one VsopSphereToRect gives. */
    angle = (series_pair_t){ sphere[LON_INDEX], sphere[LAT_INDEX] };
    SeriesSinCos(angle, &sine, &cosine);
    coslon = cosine[0];
    sinlon = sine[0];
    coslat = cosine[1];
    sinlat = sine[1];
    r = sphere[RAD_INDEX];
    eclip[0] = r * coslat * coslon;
    eclip[1] = r * coslat * sinlon;
    eclip[2] = r * sinlat;
    state.r = VsopRotate(eclip);

    /* Use spherical coords and spherical derivatives to calculate */
    /* the velocity vector in rectangular coordinates. */

    dlon_dt = deriv[LON_INDEX];
    dlat_dt = deriv[LAT_INDEX];
    dr_dt   = deriv[RAD_INDEX];

    /* vx = dx/dt */
    eclip[0] = (dr_dt * coslat * coslon) - (r * sinlat * coslon * dlat_dt) - (r * coslat * sinlon * dlon_dt);

    /* vy = dy/dt */
    eclip[1] = (dr_dt * coslat * sinlon) - (r * sinlat * sinlon * dlat_dt) + (r * coslat * coslon * dlon_dt);

    /* vz = dz/dt */
    eclip[2] = (dr_dt * sinlat) + (r * coslat * dlat_dt);

    /* Rotate the velocity vector from ecliptic to equatorial coordinates. */
    state.v = VsopRotate(eclip);

    /* Convert speed units from [AU/millennium] to [AU/day]. */
    VecScale(&state.v, 1 / DAYS_PER_MILLENNIUM);

    return state;
}


static double VsopHelioDistance(const vsop_model_t *model, astro_time_t time)
{
    int s;
    double t = time.tt / DAYS_PER_MILLENNIUM;
    double distance = 0.0;
    double tpower = 1.0;
    const vsop_formula_t *formula = &model->formula[2];     /* [2] is the distance part of the formula */

    /*
        The caller only wants to know the distance between the planet and the Sun.
        So we only need to calculate the radial component of the spherical coordinates.
    */

    for (s=0; s < formula->nseries; ++s)
    {
        /* AstronomyKit local patch (series cosine) */
        distance += tpower * SeriesSum(&formula->series[s], t, NULL);
        tpower *= t;
    }

    return distance;
}


static void AdjustBarycenter(astro_vector_t *ssb, astro_time_t time, astro_body_t body, double planet_gm)
{
    astro_vector_t planet;
    double shift;

    shift = planet_gm / (planet_gm + SUN_GM);
    planet = CalcVsop(&vsop[body], time);
    ssb->x += shift * planet.x;
    ssb->y += shift * planet.y;
    ssb->z += shift * planet.z;
}


static astro_vector_t CalcSolarSystemBarycenter(astro_time_t time)
{
    astro_vector_t ssb;

    ssb.status = ASTRO_SUCCESS;
    ssb.t = time;
    ssb.x = ssb.y = ssb.z = 0.0;

    AdjustBarycenter(&ssb, time, BODY_JUPITER, JUPITER_GM);
    AdjustBarycenter(&ssb, time, BODY_SATURN,  SATURN_GM);
    AdjustBarycenter(&ssb, time, BODY_URANUS,  URANUS_GM);
    AdjustBarycenter(&ssb, time, BODY_NEPTUNE, NEPTUNE_GM);

    return ssb;
}

/*------------------ begin general gravity simulator ------------------*/

static terse_vector_t UpdatePosition(double dt, terse_vector_t r, terse_vector_t v, terse_vector_t a)
{
    r.x += (v.x + a.x*dt/2) * dt;
    r.y += (v.y + a.y*dt/2) * dt;
    r.z += (v.z + a.z*dt/2) * dt;
    return r;
}


static terse_vector_t UpdateVelocity(double dt, terse_vector_t v, terse_vector_t a)
{
    v.x += dt * a.x;
    v.y += dt * a.y;
    v.z += dt * a.z;
    return v;
}


static body_state_t AdjustBarycenterPosVel(body_state_t *ssb, double tt, astro_body_t body, double planet_gm)
{
    body_state_t planet;
    double shift;

    /*
        This function does 2 important things:
        1. Adjusts 'ssb' by the effect of one major body on the Solar System Barycenter.
        2, Returns the heliocentric position of that major body.
    */

    shift = planet_gm / (planet_gm + SUN_GM);
    planet = CalcVsopPosVel(&vsop[body], tt);
    VecIncr(&ssb->r, VecMul(shift, planet.r));
    VecIncr(&ssb->v, VecMul(shift, planet.v));

    return planet;
}


static void MajorBodyBary(major_bodies_t *bary, double tt)
{
    /* Initialize the Sun's position as a zero vector, then adjust it from pulls from the planets. */
    bary->Sun.tt = tt;
    bary->Sun.r = VecZero;
    bary->Sun.v = VecZero;

    /* Calculate heliocentric planet positions and SSB. */
    bary->Jupiter = AdjustBarycenterPosVel(&bary->Sun, tt, BODY_JUPITER, JUPITER_GM);
    bary->Saturn  = AdjustBarycenterPosVel(&bary->Sun, tt, BODY_SATURN,  SATURN_GM);
    bary->Uranus  = AdjustBarycenterPosVel(&bary->Sun, tt, BODY_URANUS,  URANUS_GM);
    bary->Neptune = AdjustBarycenterPosVel(&bary->Sun, tt, BODY_NEPTUNE, NEPTUNE_GM);

    /* Convert planet [pos, vel] from heliocentric to barycentric. */
    VecDecr(&bary->Jupiter.r, bary->Sun.r);  VecDecr(&bary->Jupiter.v, bary->Sun.v);
    VecDecr(&bary->Saturn.r,  bary->Sun.r);  VecDecr(&bary->Saturn.v,  bary->Sun.v);
    VecDecr(&bary->Uranus.r,  bary->Sun.r);  VecDecr(&bary->Uranus.v,  bary->Sun.v);
    VecDecr(&bary->Neptune.r, bary->Sun.r);  VecDecr(&bary->Neptune.v, bary->Sun.v);

    /* Convert heliocentric SSB to barycentric Sun. */
    VecScale(&bary->Sun.r, -1.0);
    VecScale(&bary->Sun.v, -1.0);
}


static void AddAcceleration(terse_vector_t *acc, terse_vector_t small_pos, double gm, terse_vector_t major_pos)
{
    double dx, dy, dz, r2, pull;

    dx = major_pos.x - small_pos.x;
    dy = major_pos.y - small_pos.y;
    dz = major_pos.z - small_pos.z;

    r2 = dx*dx + dy*dy + dz*dz;
    pull = gm / (r2 * sqrt(r2));

    acc->x += dx * pull;
    acc->y += dy * pull;
    acc->z += dz * pull;
}


static terse_vector_t SmallBodyAcceleration(terse_vector_t small_pos, const major_bodies_t *bary)
{
    terse_vector_t acc = VecZero;

    /* Use barycentric coordinates of the Sun and major planets to calculate gravitational accelerations. */
    AddAcceleration(&acc, small_pos, SUN_GM,     bary->Sun.r);
    AddAcceleration(&acc, small_pos, JUPITER_GM, bary->Jupiter.r);
    AddAcceleration(&acc, small_pos, SATURN_GM,  bary->Saturn.r);
    AddAcceleration(&acc, small_pos, URANUS_GM,  bary->Uranus.r);
    AddAcceleration(&acc, small_pos, NEPTUNE_GM, bary->Neptune.r);

    return acc;
}


body_grav_calc_t GravSim(           /* out: [pos, vel, acc] of the simulated body at time tt2 */
    major_bodies_t *bary2,          /* temp: work area for major body barycentric state */
    double tt2,                     /* in:  a target time to be calculated (either before or after tt1) */
    const body_grav_calc_t *calc1)  /* in:  [pos, vel, acc] of the simulated body at time tt1 */
{
    body_grav_calc_t calc2;
    terse_vector_t approx_pos;
    terse_vector_t acc;
    const double dt = tt2 - calc1->tt;

    /* Calculate where the major bodies (Sun, Jupiter...Neptune) will be at the next time step. */
    MajorBodyBary(bary2, tt2);

    /* Estimate position of small body as if current acceleration applies across the whole time interval. */
    /* approx_pos = pos1 + vel1*dt + (1/2)acc*dt^2 */
    approx_pos = UpdatePosition(dt, calc1->r, calc1->v, calc1->a);

    /* Calculate acceleration experienced by small body at approximate next location. */
    acc = SmallBodyAcceleration(approx_pos, bary2);

    /* Calculate the average acceleration of the endpoints. */
    /* This becomes our estimate of the mean effective acceleration over the whole interval. */
    acc = VecMean(acc, calc1->a);

    /* Refine the estimates of [pos, vel, acc] at tt2 using the mean acceleration. */
    calc2.r = UpdatePosition(dt, calc1->r, calc1->v, acc);
    calc2.v = UpdateVelocity(dt, calc1->v, acc);
    calc2.a = SmallBodyAcceleration(calc2.r, bary2);
    calc2.tt = tt2;
    return calc2;
}


static body_grav_calc_t GravFromState(major_bodies_t *bary, const body_state_t *state)
{
    body_grav_calc_t calc;

    MajorBodyBary(bary, state->tt);

    calc.tt = state->tt;
    calc.r  = VecAdd(state->r, bary->Sun.r);      /* convert heliocentric to barycentric */
    calc.v  = VecAdd(state->v, bary->Sun.v);      /* convert heliocentric to barycentric */
    calc.a  = SmallBodyAcceleration(calc.r, bary);

    return calc;
}


static void CalcSolarSystem(astro_grav_sim_t *sim)
{
    int body;
    double tt = sim->curr->time.tt;
    body_state_t *grav = sim->curr->gravitators;
    body_state_t *sun = &grav[BODY_SUN];

    /* Initialize the Sun's position/velocity as zero vectors, then adjust from pulls from the planets. */
    sun->tt = tt;
    sun->r  = VecZero;
    sun->v  = VecZero;

    /* Calculate the position of each planet, and adjust the SSB position accordingly. */
    grav[BODY_MERCURY] = AdjustBarycenterPosVel(sun, tt, BODY_MERCURY, MERCURY_GM);
    grav[BODY_VENUS  ] = AdjustBarycenterPosVel(sun, tt, BODY_VENUS,   VENUS_GM);
    grav[BODY_EARTH  ] = AdjustBarycenterPosVel(sun, tt, BODY_EARTH,   EARTH_GM + MOON_GM);
    grav[BODY_MARS   ] = AdjustBarycenterPosVel(sun, tt, BODY_MARS,    MARS_GM);
    grav[BODY_JUPITER] = AdjustBarycenterPosVel(sun, tt, BODY_JUPITER, JUPITER_GM);
    grav[BODY_SATURN ] = AdjustBarycenterPosVel(sun, tt, BODY_SATURN,  SATURN_GM);
    grav[BODY_URANUS ] = AdjustBarycenterPosVel(sun, tt, BODY_URANUS,  URANUS_GM);
    grav[BODY_NEPTUNE] = AdjustBarycenterPosVel(sun, tt, BODY_NEPTUNE, NEPTUNE_GM);

    /* Convert planet state vectors from heliocentric to barycentric. */
    for (body = BODY_MERCURY; body <= BODY_NEPTUNE; ++body)
    {
        VecDecr(&grav[body].r, sun->r);
        VecDecr(&grav[body].v, sun->v);
    }

    /* Convert heliocentric SSB to barycentric Sun. */
    VecScale(&sun->r, -1.0);
    VecScale(&sun->v, -1.0);
}


static void CalcBodyAccelerations(astro_grav_sim_t *sim)
{
    int i;
    const body_state_t *grav = sim->curr->gravitators;

    /* Calculate the gravitational acceleration experienced by the simulated bodies. */
    for (i = 0; i < sim->numBodies; ++i)
    {
        body_grav_calc_t *calc = &sim->curr->bodies[i];

        calc->a = VecZero;

        AddAcceleration(&calc->a, calc->r, SUN_GM,              grav[BODY_SUN    ].r);
        AddAcceleration(&calc->a, calc->r, MERCURY_GM,          grav[BODY_MERCURY].r);
        AddAcceleration(&calc->a, calc->r, VENUS_GM,            grav[BODY_VENUS  ].r);
        AddAcceleration(&calc->a, calc->r, EARTH_GM + MOON_GM,  grav[BODY_EARTH  ].r);
        AddAcceleration(&calc->a, calc->r, MARS_GM,             grav[BODY_MARS   ].r);
        AddAcceleration(&calc->a, calc->r, JUPITER_GM,          grav[BODY_JUPITER].r);
        AddAcceleration(&calc->a, calc->r, SATURN_GM,           grav[BODY_SATURN ].r);
        AddAcceleration(&calc->a, calc->r, URANUS_GM,           grav[BODY_URANUS ].r);
        AddAcceleration(&calc->a, calc->r, NEPTUNE_GM,          grav[BODY_NEPTUNE].r);
    }
}


static body_state_t *GravSimBodyStatePtr(astro_grav_sim_t *sim, astro_body_t body)
{
    /*
        Return a pointer to the place where we cache the barycentric
        state of the given body, or NULL if this body is not one
        that we use for calculating gravitational interactions.
    */

    if ((body == BODY_SUN) || (body >= BODY_MERCURY && body <= BODY_NEPTUNE))
        return &sim->curr->gravitators[body];

    return NULL;
}


static astro_state_vector_t GravSimOriginState(astro_grav_sim_t *sim)
{
    const body_state_t *optr;
    astro_time_t time = sim->curr->time;

    if (sim->originBody == BODY_SSB)
    {
        /* The barycentric state of the SSB is zero, by definition. */
        astro_state_vector_t state;
        state.status = ASTRO_SUCCESS;
        state.t  = time;
        state.x  = 0.0;
        state.y  = 0.0;
        state.z  = 0.0;
        state.vx = 0.0;
        state.vy = 0.0;
        state.vz = 0.0;
        return state;
    }

    optr = GravSimBodyStatePtr(sim, sim->originBody);
    if (optr != NULL)
        return ExportState(*optr, time);

    /* We only support the VSOP bodies, for efficiency. */
    return StateVecError(ASTRO_INVALID_BODY, time);
}


static void GravSimDuplicate(astro_grav_sim_t *sim)
{
    /* Copy the current state into the previous state, so that both become the same moment in time. */
    sim->prev->time = sim->curr->time;
    memcpy(sim->prev->gravitators, sim->curr->gravitators, sizeof(sim->prev->gravitators));
    memcpy(sim->prev->bodies, sim->curr->bodies, ((size_t)sim->numBodies) * sizeof(sim->prev->bodies[0]));
}


/**
 * @brief Allocate and initialize a gravity step simulator.
 *
 * Prepares to simulate a series of incremental time steps,
 * simulating the movement of zero or more small bodies through the Solar System
 * acting under gravitational attraction from the Sun and planets.
 *
 * After calling this function, you can call #Astronomy_GravSimUpdate
 * as many times as desired to advance the simulation by small time steps.
 *
 * If this function succeeds (returns `ASTRO_SUCCESS`), `sim`
 * will be set to a dynamically allocated object. The caller is
 * then responsible for eventually calling #Astronomy_GravSimFree
 * to release the memory.
 *
 * @param simOut
 *      The address of a pointer to store the newly allocated simulation object.
 *      The type #astro_grav_sim_t is an opaque type, so its internal structure is not documented.
 *
 * @param originBody
 *      Specifies the origin of the reference frame.
 *      All position vectors and velocity vectors will use `originBody`
 *      as the origin of the coordinate system.
 *      This origin applies to all the input vectors provided in the
 *      `bodyStateArray` parameter of this function, along with all
 *      output vectors returned by #Astronomy_GravSimUpdate.
 *      Most callers will want to provide one of the following:
 *      `BODY_SUN` for heliocentric coordinates,
 *      `BODY_SSB` for solar system barycentric coordinates,
 *      or `BODY_EARTH` for geocentric coordinates. Note that the
 *      gravity simulator does not correct for light travel time;
 *      all state vectors are tied to a Newtonian "instantaneous" time.
 *
 * @param time
 *      The initial time at which to start the simulation.
 *
 * @param numBodies
 *      The number of small bodies to be simulated. This may be any non-negative integer.
 *
 * @param bodyStateArray
 *      An array of initial state vectors (positions and velocities) of the small bodies to be simulated.
 *      The caller must know the positions and velocities of the small bodies at an initial moment in time.
 *      Their positions and velocities are expressed with respect to `originBody`, using J2000 mean equator orientation (EQJ).
 *      Positions are expressed in astronomical units (AU). Velocities are expressed in AU/day.
 *      All the times embedded within the state vectors must be exactly equal to `time`,
 *      or this function will fail with the error `ASTRO_INCONSISTENT_TIMES`.
 *
 * @return
 *      `ASTRO_SUCCESS` on success, with `*sim` set to a non-NULL value. Otherwise an error code with `*sim` set to NULL.
 */
astro_status_t Astronomy_GravSimInit(
    astro_grav_sim_t **simOut,
    astro_body_t originBody,
    astro_time_t time,
    int numBodies,
    const astro_state_vector_t *bodyStateArray)
{
    astro_grav_sim_t *sim;
    astro_status_t status;
    body_grav_calc_t *array;
    int i;

    /* Validate parameters before attempting to allocate memory. */

    if (simOut == NULL)
        return ASTRO_INVALID_PARAMETER;

    *simOut = NULL;

    if (numBodies < 0)
        return ASTRO_INVALID_PARAMETER;

    if (numBodies > 0 && bodyStateArray == NULL)
        return ASTRO_INVALID_PARAMETER;

    if (originBody < BODY_MERCURY || originBody > BODY_SSB)
        return ASTRO_INVALID_BODY;

    /* AstronomyKit local patch (accepted time range): the simulation places
       the Sun and planets with the VSOP models at every step. */
    if (!EphemerisTimeOk(time))
        return ASTRO_BAD_TIME;

    /* Verify that all the state vectors are valid and have matching times. */
    for (i = 0; i < numBodies; ++i)
    {
        if (bodyStateArray[i].status != ASTRO_SUCCESS)
            return ASTRO_INVALID_PARAMETER;

        /* AstronomyKit local patch: reject non-finite initial states to avoid NaN poisoning. */
        if (!isfinite(bodyStateArray[i].x) || !isfinite(bodyStateArray[i].y) || !isfinite(bodyStateArray[i].z) ||
            !isfinite(bodyStateArray[i].vx) || !isfinite(bodyStateArray[i].vy) || !isfinite(bodyStateArray[i].vz))
            return ASTRO_INVALID_PARAMETER;

        if (bodyStateArray[i].t.tt != time.tt)
            return ASTRO_INCONSISTENT_TIMES;
    }

    *simOut = sim = (astro_grav_sim_t *) calloc(1, sizeof(astro_grav_sim_t));
    if (sim == NULL)
        return ASTRO_OUT_OF_MEMORY;

    sim->originBody = originBody;
    sim->numBodies = numBodies;
    sim->prev = &(sim->endpoint[0]);
    sim->curr = &(sim->endpoint[1]);
    sim->curr->time = time;

    if (numBodies > 0)
    {
        sim->prev->bodies = (body_grav_calc_t *) calloc(numBodies, sizeof(body_grav_calc_t));
        sim->curr->bodies = (body_grav_calc_t *) calloc(numBodies, sizeof(body_grav_calc_t));
        if (sim->prev->bodies == NULL || sim->curr->bodies == NULL)
        {
            status = ASTRO_OUT_OF_MEMORY;
            goto fail;
        }
    }

    /* Remember the initial states of all the bodies as "current". */
    /* Convert from the public type astro_state_t to our internal type body_grav_calc_t. */
    array = sim->curr->bodies;
    for (i = 0; i < numBodies; ++i)
    {
        array[i].tt  = bodyStateArray[i].t.tt;
        array[i].r.x = bodyStateArray[i].x;
        array[i].r.y = bodyStateArray[i].y;
        array[i].r.z = bodyStateArray[i].z;
        array[i].v.x = bodyStateArray[i].vx;
        array[i].v.y = bodyStateArray[i].vy;
        array[i].v.z = bodyStateArray[i].vz;
    }

    /* Calculate the state of the Sun and planets. */
    CalcSolarSystem(sim);

    /*
        We need to do all the physics calculations in barycentric coordinates.
        But the caller can provide the input vectors with respect to any body.
        Correct the input body state vectors for the specified coordinate origin.
    */
    if (originBody != BODY_SSB)
    {
        /* Determine the barycentric state of the origin body. */
        astro_state_vector_t originState = GravSimOriginState(sim);
        if (originState.status != ASTRO_SUCCESS)
        {
            status = originState.status;
            goto fail;
        }

        /* Add barycentric origin to origin-centric body to obtain barycentric body. */
        for (i = 0; i < numBodies; ++i)
        {
            array[i].r.x += originState.x;
            array[i].r.y += originState.y;
            array[i].r.z += originState.z;
            array[i].v.x += originState.vx;
            array[i].v.y += originState.vy;
            array[i].v.z += originState.vz;
        }
    }

    /* Calculate the net acceleration experienced by the small bodies. */
    CalcBodyAccelerations(sim);

    /* To prepare for a possible swap operation, duplicate the current state into the previous state. */
    GravSimDuplicate(sim);

    return ASTRO_SUCCESS;

fail:
    Astronomy_GravSimFree(sim);
    *simOut = NULL;
    return status;
}


/**
 * @brief Advances a gravity simulation by a small time step.
 *
 * @param sim
 *      A simulation object that was created by a prior call to #Astronomy_GravSimInit.
 *
 * @param time
 *      A time that is a small increment away from the current simulation time.
 *      It is up to the developer to figure out an appropriate time increment.
 *      Depending on the trajectories, a smaller or larger increment
 *      may be needed for the desired accuracy. Some experimentation may be needed.
 *      Generally, bodies that stay in the outer Solar System and move slowly can
 *      use larger time steps.  Bodies that pass into the inner Solar System and
 *      move faster will need a smaller time step to maintain accuracy.
 *      The `time` value may be after or before the current simulation time
 *      to move forward or backward in time.
 *
 * @param numBodies
 *      The number of bodies whose state vectors are to be updated.
 *      This is the number of elements in the `bodyStateArray`.
 *      This parameter is passed as a sanity check, and must be equal
 *      to the value passed to #Astronomy_GravSimInit when `sim` was created.
 *
 * @param bodyStateArray
 *      An array big enough to hold `numBodies` state vectors, to receive
 *      the updated positions and velocities of the simulated small bodies.
 *      Alternatively, `bodyStateArray` may be NULL if the output of this
 *      simulation step is not needed. This makes the call slightly faster.
 *
 * @return
 *      `ASTRO_SUCCESS` if the calculation was successful.
 *      Otherwise, an error code if something went wrong, in which case
 *      the simulation should be considered "broken". This means there
 *      is no reliable output in `bodyStateArray` and that no more calculations
 *      can be performed with `sim`.
 */
astro_status_t Astronomy_GravSimUpdate(
    astro_grav_sim_t *sim,
    astro_time_t time,
    int numBodies,
    astro_state_vector_t *bodyStateArray)
{
    terse_vector_t acc;
    double dt;      /* terrestrial time increment */
    int i;

    if (sim == NULL)
        return ASTRO_INVALID_PARAMETER;

    /*
        The caller's understanding of the number of bodies must match the actual
        array size in `sim`, or we risk corrupting/accessing invalid memory.
    */
    if (numBodies != sim->numBodies)
        return ASTRO_INVALID_PARAMETER;

    /* AstronomyKit local patch (accepted time range), as in Astronomy_GravSimInit.
       Checked before the swap, so a rejected step leaves the simulation as it was. */
    if (!EphemerisTimeOk(time))
        return ASTRO_BAD_TIME;

    dt = time.tt - sim->curr->time.tt;

    if (dt == 0.0)
    {
        /*
            Special case: the time has not changed, so skip the usual physics calculations.
            This allows a way for the caller to query the current state if desired.
            It is also necessary to avoid dividing by `dt` if `dt` is zero.
            To prepare for a possible swap operation, duplicate the current state into the previous state.
        */
        GravSimDuplicate(sim);
    }
    else
    {
        /* Swap the current state and the previous state. Then calculate the new current state. */
        Astronomy_GravSimSwap(sim);

        /* Update the current time. This is the only place we have a full (tt,ut) pair. */
        /* All of the Newtonian dynamics are calculated using tt only. */
        sim->curr->time = time;

        /* Now that sim->time is set, it is safe to call `CalcSolarSystem`. */
        CalcSolarSystem(sim);

        for (i = 0; i < numBodies; ++i)
        {
            /*
                Estimate the positions of the small bodies as if their
                current accelerations apply across the whole time interval.
                approx_pos = pos1 + vel1*dt + (1/2)acc*dt^2
            */
            const body_grav_calc_t *prev = &sim->prev->bodies[i];
            sim->curr->bodies[i].r = UpdatePosition(dt, prev->r, prev->v, prev->a);
        }

        /*
            Calculate the acceleration experienced by the small bodies
            at their respective approximate next locations.
        */
        CalcBodyAccelerations(sim);

        for (i = 0; i < numBodies; ++i)
        {
            const body_grav_calc_t *prev = &sim->prev->bodies[i];
            body_grav_calc_t *curr = &sim->curr->bodies[i];

            /*
                Calculate the average of the acceleration vectors
                experienced by the previous body positions and
                their estimated next positions.
                These become estimates of the mean effective accelerations over the whole interval.
            */
            acc = VecMean(prev->a, curr->a);

            /*
                Refine the estimates of position and velocity at the next time step,
                using the mean acceleration as a better approximation of the
                continuously changing acceleration acting on each body.
            */
            curr->tt = time.tt;
            curr->r = UpdatePosition(dt, prev->r, prev->v, acc);
            curr->v = UpdateVelocity(dt, prev->v, acc);
        }

        /*
            Re-calculate accelerations experienced by each body.
            These will be needed for the next simulation step (if any).
            Also, they will be potentially useful if some day we add
            a function to query the acceleration vectors for the bodies.
        */
        CalcBodyAccelerations(sim);

        /* AstronomyKit local patch: reject non-finite states (e.g. coincident body collision) and restore prior state. */
        for (i = 0; i < numBodies; ++i)
        {
            const body_grav_calc_t *curr = &sim->curr->bodies[i];
            if (!isfinite(curr->r.x) || !isfinite(curr->r.y) || !isfinite(curr->r.z) ||
                !isfinite(curr->v.x) || !isfinite(curr->v.y) || !isfinite(curr->v.z) ||
                !isfinite(curr->a.x) || !isfinite(curr->a.y) || !isfinite(curr->a.z))
            {
                Astronomy_GravSimSwap(sim);
                return ASTRO_BAD_VECTOR;
            }
        }
    }

    /*
        Translate our internal calculations of body positions
        and velocities into state vectors that the caller can understand.
        But if the output buffer `bodyStateArray` is NULL, it means
        the caller wanted us to update the simulation state without
        returning any output.
    */
    if (bodyStateArray != NULL)
    {
        for (i = 0; i < numBodies; ++i)
            bodyStateArray[i] = ExportGravCalc(sim->curr->bodies[i], time);

        if (sim->originBody != BODY_SSB)
        {
            /* Determine the barycentric state of the origin body. */
            astro_state_vector_t originState = GravSimOriginState(sim);
            if (originState.status != ASTRO_SUCCESS)
                return originState.status;

            /* Subtract vectors to convert barycentric states to origin-centric states. */
            for (i = 0; i < numBodies; ++i)
            {
                bodyStateArray[i].x  -= originState.x;
                bodyStateArray[i].y  -= originState.y;
                bodyStateArray[i].z  -= originState.z;
                bodyStateArray[i].vx -= originState.vx;
                bodyStateArray[i].vy -= originState.vy;
                bodyStateArray[i].vz -= originState.vz;
            }
        }
    }

    return ASTRO_SUCCESS;
}


/**
 * @brief Get the position and velocity of a Solar System body included in the simulation.
 *
 * In order to simulate the movement of small bodies through the Solar System,
 * the simulator needs to calculate the state vectors for the Sun and planets.
 *
 * If an application wants to know the positions of one or more of the planets
 * in addition to the small bodies, this function provides a way to obtain
 * their state vectors. This is provided for the sake of efficiency, to avoid
 * redundant calculations.
 *
 * @param sim
 *      A gravity simulator object created by a successful call to #Astronomy_GravSimInit.
 *
 * @param body
 *      The Sun, Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, or Neptune.
 *
 * @return
 *      If the given body is part of the set of calculated bodies
 *      (Sun and planets), returns the current time step's state
 *      vector for that body, expressed in the coordinate system
 *      that was specified by the `originBody` parameter to #Astronomy_GravSimInit.
 *      Success is indicated by the returned structure's `status` field holding
 *      `ASTRO_SUCCESS`. Any other `status` value indicates an error, meaning
 *      the returned state vector is invalid.
 */
astro_state_vector_t Astronomy_GravSimBodyState(
    astro_grav_sim_t *sim,
    astro_body_t body)
{
    astro_state_vector_t state;
    body_state_t *bptr;

    bptr = GravSimBodyStatePtr(sim, body);
    if (bptr == NULL)
        return StateVecError(ASTRO_INVALID_BODY, sim->curr->time);

    state = GravSimOriginState(sim);
    if (state.status != ASTRO_SUCCESS)
        return state;

    /*
        Subtract the origin's state from the body's barycentric
        state to get the body in the desired reference frame.
        state.t and state.status are already initialized correctly.
    */

    state.x  = bptr->r.x - state.x;
    state.y  = bptr->r.y - state.y;
    state.z  = bptr->r.z - state.z;
    state.vx = bptr->v.x - state.vx;
    state.vy = bptr->v.y - state.vy;
    state.vz = bptr->v.z - state.vz;

    return state;
}


/**
 * @brief Exchange the current time step with the previous time step.
 *
 * Sometimes it is helpful to "explore" various times near a given
 * simulation time step, while repeatedly returning to the original
 * time step. For example, when backdating a position for light travel
 * time, the caller may wish to repeatedly try different amounts of
 * backdating. When the backdating solver has converged, the caller
 * wants to leave the simulation in its original state.
 *
 * This function allows a single "undo" of a simulation, and does so
 * very efficiently.
 *
 * Usually this function will be called immediately after a matching
 * call to #Astronomy_GravSimUpdate. It has the effect of rolling
 * back the most recent update. If called twice in a row, it reverts
 * the swap and thus has no net effect.
 *
 * #Astronomy_GravSimInit initializes the current state and previous
 * state to be identical. Both states represent the `time` parameter that was
 * passed into the initializer. Therefore, `Astronomy_GravSimSwap` will
 * have no effect from the caller's point of view when passed a simulator
 * that has not yet been updated by a call to #Astronomy_GravSimUpdate.
 *
 * @param sim
 *      A gravity simulator object that was created by a prior call to #Astronomy_GravSimInit.
 */
void Astronomy_GravSimSwap(astro_grav_sim_t *sim)
{
    gravsim_endpoint_t *swap = sim->prev;
    sim->prev = sim->curr;
    sim->curr = swap;
}


/**
 * @brief Returns the time of the current simulation step.
 *
 * @param sim
 *      A gravity simulator object that was created by a prior call to #Astronomy_GravSimInit.
 */
astro_time_t Astronomy_GravSimTime(const astro_grav_sim_t *sim)
{
    return sim->curr->time;
}


/**
 * @brief Returns the number of small bodies represented in this simulation.
 *
 * When a simulation is created by a call to #Astronomy_GravSimInit,
 * the caller specifies the number of small bodies.
 * This function returns that same number, which may be convenient for a caller,
 * so that it does not need to track the body count separately.
 *
 * @param sim
 *      A gravity simulator object that was created by a prior call to #Astronomy_GravSimInit.
 */
int Astronomy_GravSimNumBodies(const astro_grav_sim_t *sim)
{
    return sim->numBodies;
}


/**
 * @brief Returns the body whose center is the coordinate origin that small bodies are referenced to.
 *
 * When a simulation is created by a call to #Astronomy_GravSimInit,
 * the caller specifies an `originBody` to indicate the coordinate origin
 * used to represent the small bodies being simulated.
 * This function returns that same #astro_body_t value.
 *
 * @param sim
 *      A gravity simulator object that was created by a prior call to #Astronomy_GravSimInit.
 */
astro_body_t Astronomy_GravSimOrigin(const astro_grav_sim_t *sim)
{
    return sim->originBody;
}


/**
 * @brief Releases memory allocated to a gravity simulator object.
 *
 * To avoid memory leaks, any successful call to #Astronomy_GravSimInit
 * must be paired with a matching call to `Astronomy_GravSimFree`.
 *
 * @param sim
 *      A gravity simulator object that was created by a prior call to #Astronomy_GravSimInit.
 */
void Astronomy_GravSimFree(astro_grav_sim_t *sim)
{
    if (sim != NULL)
    {
        free(sim->endpoint[0].bodies);
        free(sim->endpoint[1].bodies);
        free(sim);
    }
}


/*------------------ begin Pluto integrator ------------------*/

static const body_state_t PlutoStateTable[] =
{
    {  -730000.0, {-26.118207232108, -14.376168177825,   3.384402515299}, { 1.6339372163656e-03, -2.7861699588508e-03, -1.3585880229445e-03} }
,   {  -700800.0, { 41.974905202127,  -0.448502952929, -12.770351505989}, { 7.3458569351457e-04,  2.2785014891658e-03,  4.8619778602049e-04} }
,   {  -671600.0, { 14.706930780744,  44.269110540027,   9.353698474772}, {-2.1000147999800e-03,  2.2295915939915e-04,  7.0143443551414e-04} }
,   {  -642400.0, {-29.441003929957,  -6.430161530570,   6.858481011305}, { 8.4495803960544e-04, -3.0783914758711e-03, -1.2106305981192e-03} }
,   {  -613200.0, { 39.444396946234,  -6.557989760571, -13.913760296463}, { 1.1480029005873e-03,  2.2400006880665e-03,  3.5168075922288e-04} }
,   {  -584000.0, { 20.230380950700,  43.266966657189,   7.382966091923}, {-1.9754081700585e-03,  5.3457141292226e-04,  7.5929169129793e-04} }
,   {  -554800.0, {-30.658325364620,   2.093818874552,   9.880531138071}, { 6.1010603013347e-05, -3.1326500935382e-03, -9.9346125151067e-04} }
,   {  -525600.0, { 35.737703251673, -12.587706024764, -14.677847247563}, { 1.5802939375649e-03,  2.1347678412429e-03,  1.9074436384343e-04} }
,   {  -496400.0, { 25.466295188546,  41.367478338417,   5.216476873382}, {-1.8054401046468e-03,  8.3283083599510e-04,  8.0260156912107e-04} }
,   {  -467200.0, {-29.847174904071,  10.636426313081,  12.297904180106}, {-6.3257063052907e-04, -2.9969577578221e-03, -7.4476074151596e-04} }
,   {  -438000.0, { 30.774692107687, -18.236637015304, -14.945535879896}, { 2.0113162005465e-03,  1.9353827024189e-03, -2.0937793168297e-06} }
,   {  -408800.0, { 30.243153324028,  38.656267888503,   2.938501750218}, {-1.6052508674468e-03,  1.1183495337525e-03,  8.3333973416824e-04} }
,   {  -379600.0, {-27.288984772533,  18.643162147874,  14.023633623329}, {-1.1856388898191e-03, -2.7170609282181e-03, -4.9015526126399e-04} }
,   {  -350400.0, { 24.519605196774, -23.245756064727, -14.626862367368}, { 2.4322321483154e-03,  1.6062008146048e-03, -2.3369181613312e-04} }
,   {  -321200.0, { 34.505274805875,  35.125338586954,   0.557361475637}, {-1.3824391637782e-03,  1.3833397561817e-03,  8.4823598806262e-04} }
,   {  -292000.0, {-23.275363915119,  25.818514298769,  15.055381588598}, {-1.6062295460975e-03, -2.3395961498533e-03, -2.4377362639479e-04} }
,   {  -262800.0, { 17.050384798092, -27.180376290126, -13.608963321694}, { 2.8175521080578e-03,  1.1358749093955e-03, -4.9548725258825e-04} }
,   {  -233600.0, { 38.093671910285,  30.880588383337,  -1.843688067413}, {-1.1317697153459e-03,  1.6128814698472e-03,  8.4177586176055e-04} }
,   {  -204400.0, {-18.197852930878,  31.932869934309,  15.438294826279}, {-1.9117272501813e-03, -1.9146495909842e-03, -1.9657304369835e-05} }
,   {  -175200.0, {  8.528924039997, -29.618422200048, -11.805400994258}, { 3.1034370787005e-03,  5.1393633292430e-04, -7.7293066202546e-04} }
,   {  -146000.0, { 40.946857258640,  25.904973592021,  -4.256336240499}, {-8.3652705194051e-04,  1.8129497136404e-03,  8.1564228273060e-04} }
,   {  -116800.0, {-12.326958895325,  36.881883446292,  15.217158258711}, {-2.1166103705038e-03, -1.4814420035990e-03,  1.7401209844705e-04} }
,   {   -87600.0, { -0.633258375909, -30.018759794709,  -9.171932874950}, { 3.2016994581737e-03, -2.5279858672148e-04, -1.0411088271861e-03} }
,   {   -58400.0, { 42.936048423883,  20.344685584452,  -6.588027007912}, {-5.0525450073192e-04,  1.9910074335507e-03,  7.7440196540269e-04} }
,   {   -29200.0, { -5.975910552974,  40.611809958460,  14.470131723673}, {-2.2184202156107e-03, -1.0562361130164e-03,  3.3652250216211e-04} }
,   {        0.0, { -9.875369580774, -27.978926224737,  -5.753711824704}, { 3.0287533248818e-03, -1.1276087003636e-03, -1.2651326732361e-03} }
,   {    29200.0, { 43.958831986165,  14.214147973292,  -8.808306227163}, {-1.4717608981871e-04,  2.1404187242141e-03,  7.1486567806614e-04} }
,   {    58400.0, {  0.678136763520,  43.094461639362,  13.243238780721}, {-2.2358226110718e-03, -6.3233636090933e-04,  4.7664798895648e-04} }
,   {    87600.0, {-18.282602096834, -23.305039586660,  -1.766620508028}, { 2.5567245263557e-03, -1.9902940754171e-03, -1.3943491701082e-03} }
,   {   116800.0, { 43.873338744526,   7.700705617215, -10.814273666425}, { 2.3174803055677e-04,  2.2402163127924e-03,  6.2988756452032e-04} }
,   {   146000.0, {  7.392949027906,  44.382678951534,  11.629500214854}, {-2.1932815453830e-03, -2.1751799585364e-04,  5.9556516201114e-04} }
,   {   175200.0, {-24.981690229261, -16.204012851426,   2.466457544298}, { 1.8193989149580e-03, -2.6765419531201e-03, -1.3848283502247e-03} }
,   {   204400.0, { 42.530187039511,   0.845935508021, -12.554907527683}, { 6.5059779150669e-04,  2.2725657282262e-03,  5.1133743202822e-04} }
,   {   233600.0, { 13.999526486822,  44.462363044894,   9.669418486465}, {-2.1079296569252e-03,  1.7533423831993e-04,  6.9128485798076e-04} }
,   {   262800.0, {-29.184024803031,  -7.371243995762,   6.493275957928}, { 9.3581363109681e-04, -3.0610357109184e-03, -1.2364201089345e-03} }
,   {   292000.0, { 39.831980671753,  -6.078405766765, -13.909815358656}, { 1.1117769689167e-03,  2.2362097830152e-03,  3.6230548231153e-04} }
,   {   321200.0, { 20.294955108476,  43.417190420251,   7.450091985932}, {-1.9742157451535e-03,  5.3102050468554e-04,  7.5938408813008e-04} }
,   {   350400.0, {-30.669992302160,   2.318743558955,   9.973480913858}, { 4.5605107450676e-05, -3.1308219926928e-03, -9.9066533301924e-04} }
,   {   379600.0, { 35.626122155983, -12.897647509224, -14.777586508444}, { 1.6015684949743e-03,  2.1171931182284e-03,  1.8002516202204e-04} }
,   {   408800.0, { 26.133186148561,  41.232139187599,   5.006401326220}, {-1.7857704419579e-03,  8.6046232702817e-04,  8.0614690298954e-04} }
,   {   438000.0, {-29.576740229230,  11.863535943587,  12.631323039872}, {-7.2292830060955e-04, -2.9587820140709e-03, -7.0824296450300e-04} }
,   {   467200.0, { 29.910805787391, -19.159019294000, -15.013363865194}, { 2.0871080437997e-03,  1.8848372554514e-03, -3.8528655083926e-05} }
,   {   496400.0, { 31.375957451819,  38.050372720763,   2.433138343754}, {-1.5546055556611e-03,  1.1699815465629e-03,  8.3565439266001e-04} }
,   {   525600.0, {-26.360071336928,  20.662505904952,  14.414696258958}, {-1.3142373118349e-03, -2.6236647854842e-03, -4.2542017598193e-04} }
,   {   554800.0, { 22.599441488648, -24.508879898306, -14.484045731468}, { 2.5454108304806e-03,  1.4917058755191e-03, -3.0243665086079e-04} }
,   {   584000.0, { 35.877864013014,  33.894226366071,  -0.224524636277}, {-1.2941245730845e-03,  1.4560427668319e-03,  8.4762160640137e-04} }
,   {   613200.0, {-21.538149762417,  28.204068269761,  15.321973799534}, {-1.7312117409010e-03, -2.1939631314577e-03, -1.6316913275180e-04} }
,   {   642400.0, { 13.971521374415, -28.339941764789, -13.083792871886}, { 2.9334630526035e-03,  9.1860931752944e-04, -5.9939422488627e-04} }
,   {   671600.0, { 39.526942044143,  28.939897360110,  -2.872799527539}, {-1.0068481658095e-03,  1.7021132888090e-03,  8.3578230511981e-04} }
,   {   700800.0, {-15.576200701394,  34.399412961275,  15.466033737854}, {-2.0098814612884e-03, -1.7191109825989e-03,  7.0414782780416e-05} }
,   {   730000.0, {  4.243252837090, -30.118201690825, -10.707441231349}, { 3.1725847067411e-03,  1.6098461202270e-04, -9.0672150593868e-04} }
};

static body_segment_t *pluto_cache[PLUTO_NUM_STATES-1];
static pthread_mutex_t pluto_cache_mutex = PTHREAD_MUTEX_INITIALIZER;

static int ClampIndex(double frac, int nsteps)
{
    int index = (int) floor(frac);
    if (index < 0)
        return 0;
    if (index >= nsteps)
        return nsteps-1;
    return index;
}


/* The caller must hold pluto_cache_mutex, and must keep holding it while
   reading the returned cache segment, so that Astronomy_Reset cannot free
   the segment out from under the reader. */
static astro_status_t GetSegment(int *seg_index, body_segment_t *cache[], double tt)
{
    int i;
    body_segment_t reverse;
    body_segment_t *seg;
    major_bodies_t bary;
    double step_tt, ramp;

    if (tt < PlutoStateTable[0].tt || tt > PlutoStateTable[PLUTO_NUM_STATES-1].tt)
    {
        /* We don't bother calculating a segment. Let the caller crawl backward/forward to this time. */
        *seg_index = -1;
        return ASTRO_SUCCESS;
    }

    /* See if we have a segment that straddles the requested time. */
    /* If so, return it. Otherwise, calculate it and return it. */

    *seg_index = ClampIndex((tt - PlutoStateTable[0].tt) / PLUTO_TIME_STEP, PLUTO_NUM_STATES-1);

    if (cache[*seg_index] == NULL)
    {
        /* Allocate memory for the segment (about 11K each). */
        seg = cache[*seg_index] = (body_segment_t *) calloc(1, sizeof(body_segment_t));
        if (seg == NULL)
            return ASTRO_OUT_OF_MEMORY;

        /* Calculate the segment. */
        /* Pick the pair of bracketing body states to fill the segment. */

        /* Each endpoint is exact. */
        seg->step[0] = GravFromState(&bary, &PlutoStateTable[*seg_index]);
        seg->step[PLUTO_NSTEPS-1] = GravFromState(&bary, &PlutoStateTable[*seg_index + 1]);

        /* Simulate forwards from the lower time bound. */
        step_tt = seg->step[0].tt;
        for (i=1; i < PLUTO_NSTEPS-1; ++i)
            seg->step[i] = GravSim(&bary, step_tt += PLUTO_DT, &seg->step[i-1]);

        /* Simulate backwards from the upper time bound. */
        step_tt = seg->step[PLUTO_NSTEPS-1].tt;
        reverse.step[PLUTO_NSTEPS-1] = seg->step[PLUTO_NSTEPS-1];
        for (i=PLUTO_NSTEPS-2; i > 0; --i)
            reverse.step[i] = GravSim(&bary, step_tt -= PLUTO_DT, &reverse.step[i+1]);

        /* Fade-mix the two series so that there are no discontinuities. */
        for (i=PLUTO_NSTEPS-2; i > 0; --i)
        {
            ramp = (double)i / (PLUTO_NSTEPS-1);
            seg->step[i].r = VecRamp(seg->step[i].r, reverse.step[i].r, ramp);
            seg->step[i].v = VecRamp(seg->step[i].v, reverse.step[i].v, ramp);
            seg->step[i].a = VecRamp(seg->step[i].a, reverse.step[i].a, ramp);
        }
    }

    return ASTRO_SUCCESS;
}


static body_grav_calc_t CalcPlutoOneWay(major_bodies_t *bary, const body_state_t *init_state, double target_tt, double dt)
{
    body_grav_calc_t calc;
    int i, n;

    calc = GravFromState(bary, init_state);
    n = (int) ceil((target_tt - calc.tt) / dt);
    for (i=0; i < n; ++i)
        calc = GravSim(bary, (i+1 == n) ? target_tt : (calc.tt + dt), &calc);

    return calc;
}


static astro_status_t CalcPluto(body_state_t *bstate, astro_time_t time, int helio)
{
    terse_vector_t acc, ra, rb, va, vb;
    major_bodies_t bary;
    const body_segment_t *seg;
    int seg_index, left;
    const body_grav_calc_t *s1;
    const body_grav_calc_t *s2;
    body_grav_calc_t calc;
    astro_status_t status;
    double ramp;

    memset(bstate, 0, sizeof(body_state_t));
    bstate->tt = time.tt;

    /* AstronomyKit local patch (extreme-input guards): a NaN TT fails both
       table-range comparisons in GetSegment, then reaches (int) floor(NaN)
       in ClampIndex, which is undefined behavior. */
    if (!isfinite(time.tt))
        return ASTRO_BAD_TIME;

    /* Hold the cache mutex across both the segment lookup and the
       interpolation that reads it, so Astronomy_Reset cannot free the
       segment while it is in use. */
    pthread_mutex_lock(&pluto_cache_mutex);
    status = GetSegment(&seg_index, pluto_cache, time.tt);
    if (status != ASTRO_SUCCESS)
    {
        pthread_mutex_unlock(&pluto_cache_mutex);
        return status;
    }

    if (seg_index < 0)
    {
        /* The crawl below never touches the cache. */
        pthread_mutex_unlock(&pluto_cache_mutex);
        /* AstronomyKit local patch: reject times far outside the table so the
           crawl below cannot run for an unbounded number of steps. */
        if (time.tt < PlutoStateTable[0].tt - PLUTO_MAX_CRAWL_DAYS ||
            time.tt > PlutoStateTable[PLUTO_NUM_STATES-1].tt + PLUTO_MAX_CRAWL_DAYS)
            return ASTRO_BAD_TIME;
        /* The target time is outside the year range 0000..4000. */
        /* Calculate it by crawling backward from 0000 or forward from 4000. */
        /* FIXFIXFIX - This is super slow. Could optimize this with extra caching if needed. */
        if (time.tt < PlutoStateTable[0].tt)
            calc = CalcPlutoOneWay(&bary, &PlutoStateTable[0], time.tt, -PLUTO_DT);
        else
            calc = CalcPlutoOneWay(&bary, &PlutoStateTable[PLUTO_NUM_STATES-1], time.tt, +PLUTO_DT);

        bstate->r  = calc.r;
        bstate->v  = calc.v;
    }
    else
    {
        seg = pluto_cache[seg_index];
        left = ClampIndex((time.tt - seg->step[0].tt) / PLUTO_DT, PLUTO_NSTEPS-1);
        s1 = &seg->step[left];
        s2 = &seg->step[left+1];

        /* Find mean acceleration vector over the interval. */
        acc = VecMean(s1->a, s2->a);

        /* Use Newtonian mechanics to extrapolate away from t1 in the positive time direction. */
        ra = UpdatePosition(time.tt - s1->tt, s1->r, s1->v, acc);
        va = UpdateVelocity(time.tt - s1->tt, s1->v, acc);

        /* Use Newtonian mechanics to extrapolate away from t2 in the negative time direction. */
        rb = UpdatePosition(time.tt - s2->tt, s2->r, s2->v, acc);
        vb = UpdateVelocity(time.tt - s2->tt, s2->v, acc);

        /* Use fade in/out idea to blend the two position estimates. */
        ramp = (time.tt - s1->tt)/PLUTO_DT;
        bstate->r = VecRamp(ra, rb, ramp);
        bstate->v = VecRamp(va, vb, ramp);

        /* The segment is no longer needed. */
        pthread_mutex_unlock(&pluto_cache_mutex);

        if (helio)
            MajorBodyBary(&bary, time.tt);
    }

    if (helio)
    {
        /* Convert barycentric coordinates back to heliocentric coordinates. */
        VecDecr(&bstate->r, bary.Sun.r);
        VecDecr(&bstate->v, bary.Sun.v);
    }

    return ASTRO_SUCCESS;
}

/*------------------ end Pluto integrator ------------------*/


/*---------- internal Swift-to-C bridge (transitional for Parts 3 & 4) ----------*/

void _Astronomy_Iau2000b(astro_time_t *time)
{
    if (time != NULL)
        iau2000b(time);
}

astro_vector_t _Astronomy_CalcVsop(astro_body_t body, astro_time_t time)
{
    if (body < BODY_MERCURY || body > BODY_NEPTUNE)
        return VecError(ASTRO_INVALID_BODY, time);
    return CalcVsop(&vsop[body], time);
}

astro_state_vector_t _Astronomy_CalcVsopPosVel(astro_body_t body, astro_time_t time)
{
    if (body < BODY_MERCURY || body > BODY_NEPTUNE)
        return StateVecError(ASTRO_INVALID_BODY, time);
    if (!EphemerisTimeOk(time))
        return StateVecError(ASTRO_BAD_TIME, time);
    return ExportState(CalcVsopPosVel(&vsop[body], time.tt), time);
}

double _Astronomy_VsopHelioDistance(astro_body_t body, astro_time_t time)
{
    if (body < BODY_MERCURY || body > BODY_NEPTUNE || !EphemerisTimeOk(time))
        return NAN;
    return VsopHelioDistance(&vsop[body], time);
}

astro_vector_t _Astronomy_CalcSolarSystemBarycenter(astro_time_t time)
{
    if (!EphemerisTimeOk(time))
        return VecError(ASTRO_BAD_TIME, time);
    return CalcSolarSystemBarycenter(time);
}

astro_state_vector_t _Astronomy_CalcPluto(astro_time_t time, int helio)
{
    body_state_t bstate;
    astro_status_t status = CalcPluto(&bstate, time, helio);
    if (status != ASTRO_SUCCESS)
        return StateVecError(status, time);
    return ExportState(bstate, time);
}

astro_state_vector_t _Astronomy_BaryMajorBody(astro_body_t body, astro_time_t time)
{
    major_bodies_t bary;
    if (!EphemerisTimeOk(time))
        return StateVecError(ASTRO_BAD_TIME, time);
    MajorBodyBary(&bary, time.tt);
    switch (body)
    {
    case BODY_SUN:      return ExportState(bary.Sun, time);
    case BODY_JUPITER:  return ExportState(bary.Jupiter, time);
    case BODY_SATURN:   return ExportState(bary.Saturn, time);
    case BODY_URANUS:   return ExportState(bary.Uranus, time);
    case BODY_NEPTUNE:  return ExportState(bary.Neptune, time);
    default:            return StateVecError(ASTRO_INVALID_BODY, time);
    }
}

/**
 * @brief Frees up all dynamic memory allocated by Astronomy Engine.
 *
 * Astronomy Engine uses dynamic memory allocation in only one place:
 * it makes calculation of Pluto's orbit more efficient by caching 11 KB
 * segments and recycling them. To force purging this cache and
 * freeing all the dynamic memory, you can call this function at any time.
 * It is always safe to call, although it will slow down the very next
 * calculation of Pluto's position for a nearby time value.
 * Calling this function before your program exits is optional, but
 * it will be helpful for leak-checkers like valgrind.
 */
void Astronomy_Reset(void)
{
    int i;
    pthread_mutex_lock(&pluto_cache_mutex);
    for (i=0; i < PLUTO_NUM_STATES-1; ++i)
    {
        free(pluto_cache[i]);
        pluto_cache[i] = NULL;
    }
    pthread_mutex_unlock(&pluto_cache_mutex);
}


#ifdef __cplusplus
}
#endif
