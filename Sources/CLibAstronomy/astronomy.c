/*
    VENDORING NOTE (AstronomyKit)

    Vendored from: https://github.com/cosinekitty/astronomy (source/c/astronomy.c)
    Upstream commit: 826e26ff3a6dc03ee46658b1138fef582d96c5d9 (2025-01-27)

    Local patches not in upstream:
      - C11 _Atomic on the DeltaTFunc function pointer (stdatomic.h):
        Astronomy_SetDeltaTFunction stores with release ordering and
        TerrestrialTime loads with acquire ordering, so the Delta T model
        can be swapped while calculations run on other threads.
      - Extreme-input guards, marked "extreme-input guards" at each site.
        Astronomy_TerrestrialTime returns a NaN time for a non-finite TT
        and stops iterating after 128 steps.
      - Exact TT inverse, marked "exact TT inverse" at each site.
        Astronomy_TerrestrialTime returns the TT it was given for every
        finite TT. Where the Delta T model steps forward, no UT has a TT
        inside the step; there it stops when its iterates alternate between
        the UTs on either side, after about four steps instead of 128, and
        keeps the UT it stopped on.
      - TT-continuous offsets, marked "TT-continuous offsets" at each site.
        Astronomy_AddTerrestrialDays adds a span to both UT and TT.
      - Observed Delta T: Astronomy_DeltaT_Observed, a yearly IERS table
        joined continuously to Espenak-Meeus before it and to the long-term
        parabola after it, is the initial value of DeltaTFunc in place of
        Astronomy_DeltaT_EspenakMeeus.
      - Nutation series, marked "nutation series": iau2000b sums all 77
        terms of the IAU 2000B series where upstream kept the five largest.
        nut_term is the published table. The routine evaluates the five
        fundamental angles with SeriesHalfCos and SeriesHalfSinc and builds
        every term by angle addition, reducing angles with rint in place of
        fmod.

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

#ifdef __FAST_MATH__
#error Astronomy Engine does not support "fast math" optimization because it causes incorrect behavior. See: https://github.com/cosinekitty/astronomy/issues/245
#endif

#ifdef __cplusplus
extern "C" {
#endif

/** @cond DOXYGEN_SKIP */
#define PI      3.14159265358979323846

/** @endcond */

static const double DAYS_PER_TROPICAL_YEAR = 365.24217;
static const double SECONDS_PER_DAY = 24.0 * 3600.0;

/** @cond DOXYGEN_SKIP */
#define ASTRO_ARRAYSIZE(x)    (sizeof(x) / sizeof(x[0]))
/** @endcond */


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


/** @cond DOXYGEN_SKIP */
typedef double series_pair_t __attribute__((vector_size(16)));
#define SERIES_INLINE   static inline __attribute__((always_inline))
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


/*---------- internal Swift-to-C bridge (transitional for Part 4) ----------*/

void _Astronomy_Iau2000b(astro_time_t *time)
{
    if (time != NULL)
        iau2000b(time);
}

#ifdef __cplusplus
}
#endif
