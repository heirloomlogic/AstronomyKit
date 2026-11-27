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

#ifndef __ASTRONOMY_H
#define __ASTRONOMY_H

#include <stddef.h>     /* for size_t */

#ifdef __cplusplus
extern "C" {
#endif

/*---------- numeric constants ----------*/

#define DEG2RAD     0.017453292519943296

/*---------- types ----------*/

typedef enum
{
    ASTRO_SUCCESS,
    ASTRO_NOT_INITIALIZED,
    ASTRO_INVALID_BODY,
    ASTRO_NO_CONVERGE,
    ASTRO_BAD_TIME,
    ASTRO_BAD_VECTOR,
    ASTRO_SEARCH_FAILURE,
    ASTRO_EARTH_NOT_ALLOWED,
    ASTRO_NO_MOON_QUARTER,
    ASTRO_WRONG_MOON_QUARTER,
    ASTRO_INTERNAL_ERROR,
    ASTRO_INVALID_PARAMETER,
    ASTRO_FAIL_APSIS,
    ASTRO_BUFFER_TOO_SMALL,
    ASTRO_OUT_OF_MEMORY,
    ASTRO_INCONSISTENT_TIMES
}
astro_status_t;

typedef struct
{
    double ut;
    double tt;
    double psi;
    double eps;
    double st;
}
astro_time_t;

typedef struct
{
    int     year;
    int     month;
    int     day;
    int     hour;
    int     minute;
    double  second;
}
astro_utc_t;

typedef double (* astro_deltat_func) (double ut);

double Astronomy_DeltaT_EspenakMeeus(double ut);
double Astronomy_DeltaT_JplHorizons(double ut);
double Astronomy_DeltaT_Observed(double ut);

void Astronomy_SetDeltaTFunction(astro_deltat_func func);

typedef enum
{
    TIME_FORMAT_DAY,
    TIME_FORMAT_MINUTE,
    TIME_FORMAT_SECOND,
    TIME_FORMAT_MILLI
}
astro_time_format_t;

#define TIME_TEXT_BYTES  28

/*---------- functions ----------*/

#if !defined(ASTRONOMY_ENGINE_NO_CURRENT_TIME)
astro_time_t Astronomy_CurrentTime(void);
#endif
astro_time_t Astronomy_MakeTime(int year, int month, int day, int hour, int minute, double second);
astro_time_t Astronomy_TimeFromUtc(astro_utc_t utc);
astro_utc_t  Astronomy_UtcFromTime(astro_time_t time);
astro_status_t Astronomy_FormatTime(astro_time_t time, astro_time_format_t format, char *text, size_t size);
astro_time_t Astronomy_TimeFromDays(double ut);
astro_time_t Astronomy_TerrestrialTime(double tt);
astro_time_t Astronomy_AddDays(astro_time_t time, double days);
astro_time_t Astronomy_AddTerrestrialDays(astro_time_t time, double days);
double Astronomy_SiderealTime(astro_time_t *time);

/*---------- internal Swift-to-C bridge (transitional for Part 4) ----------*/

void _Astronomy_Iau2000b(astro_time_t *time);

#ifdef __cplusplus
}
#endif

#endif  /* ifndef __ASTRONOMY_H */
