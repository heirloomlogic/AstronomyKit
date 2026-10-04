#ifndef ASTRONOMY_EPHEMERIS_TIME_H
#define ASTRONOMY_EPHEMERIS_TIME_H

/* Official ERFA source notices are retained in each source file.
   Full license: Documentation/Migration/LunarBundledSources/ERFA-LICENSE. */

#ifdef __cplusplus
extern "C" {
#endif

/* Full ERFA geocentric periodic TDB-TT model, seconds, with a split TT date. */
double Astronomy_EphemerisTDBOffsetSeconds(double ttDaysSinceJ2000);

/* dTDB/dTT from the full periodic model; scale a TDB-day derivative to a TT-day derivative. */
double Astronomy_EphemerisTDBRate(double ttDaysSinceJ2000);

/* ICRS axes to the IAU 2006 mean equatorial J2000 triad. Supports in-place use. */
void Astronomy_EphemerisICRSToEQJ(const double input[3], double output[3]);

#ifdef __cplusplus
}
#endif
#endif
