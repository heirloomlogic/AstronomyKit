/* AstronomyKit bundled ephemeris evaluator. Data provenance: THIRD_PARTY_NOTICES. */
#include "ephemeris.h"
#include "ephemeris_time.h"
#include <math.h>
#include "EphemerisData/moon_data.inc"
#include "EphemerisData/pluto_barycenter.inc"
#include "EphemerisData/pluto_negative_sun.inc"
#include "EphemerisData/pluto_center_offset.inc"

#define TABLE(prefix, PREFIX) {PREFIX##_START_TDB - 2451545.0, PREFIX##_STEP_DAYS, \
    PREFIX##_RECORD_COUNT, PREFIX##_COEFFICIENT_COUNT, prefix##_coefficients}

static const astronomy_ephemeris_table_t moon = TABLE(moon_bundle, MOON_BUNDLE);
static const astronomy_ephemeris_table_t pluto_barycenter = TABLE(pluto_barycenter_bundle, PLUTO_BARYCENTER_BUNDLE);
static const astronomy_ephemeris_table_t sun = TABLE(pluto_negative_sun_bundle, PLUTO_NEGATIVE_SUN_BUNDLE);
static const astronomy_ephemeris_table_t pluto_relative = TABLE(pluto_center_offset_bundle, PLUTO_CENTER_OFFSET_BUNDLE);

int Astronomy_EphemerisEvaluate(const astronomy_ephemeris_table_t *table,
    double tdb_days, double position[3], double velocity[3])
{
    size_t record, axis, k;
    double interval, x;
    if (!table || !position || !velocity || !table->coefficients ||
        !isfinite(tdb_days) || !isfinite(table->start_tdb) ||
        !isfinite(table->step_days) || table->step_days <= 0 ||
        table->record_count == 0 || table->coefficient_count == 0)
        return 0;
    interval = (tdb_days - table->start_tdb) / table->step_days;
    if (tdb_days < table->start_tdb || !(interval >= 0 && interval < (double)table->record_count))
        return 0;
    record = (size_t)floor(interval);
    x = 2.0 * ((tdb_days - table->start_tdb) - record * table->step_days) / table->step_days - 1.0;
    for (axis = 0; axis < 3; ++axis)
    {
        const double *c = table->coefficients + (3 * record + axis) * table->coefficient_count;
        double b1 = 0, b2 = 0, d1 = 0, d2 = 0;
        for (k = table->coefficient_count - 1; k > 0; --k)
        {
            double b = 2*x*b1 - b2 + c[k];
            double d = 2*b1 + 2*x*d1 - d2;
            b2 = b1; b1 = b;
            d2 = d1; d1 = d;
        }
        position[axis] = c[0] + x*b1 - b2;
        velocity[axis] = (b1 + x*d1 - d2) * (2/table->step_days);
    }
    return 1;
}

double Astronomy_EphemerisWeight(double tt_days, double *rate)
{
    const double start = -36524.5, end = 47846.5, buffer = 32;
    double x, sign;
    *rate = 0;
    if (!isfinite(tt_days) || tt_days <= start-buffer || tt_days >= end+buffer)
        return 0;
    if (tt_days >= start && tt_days <= end)
        return 1;
    if (tt_days < start) { x = (tt_days - (start-buffer))/buffer; sign = 1; }
    else { x = (end+buffer-tt_days)/buffer; sign = -1; }
    *rate = sign * 30*x*x*(1-x)*(1-x)/buffer;
    return x*x*x*(10 + x*(-15 + 6*x));
}

static int SourceState(const astronomy_ephemeris_table_t *table, double tt_days,
    double position[3], double velocity[3])
{
    double tdb, rate;
    int k;
    if (!isfinite(tt_days)) return 0;
    tdb = tt_days + Astronomy_EphemerisTDBOffsetSeconds(tt_days)/86400;
    if (!Astronomy_EphemerisEvaluate(table, tdb, position, velocity)) return 0;
    rate = Astronomy_EphemerisTDBRate(tt_days);
    for (k = 0; k < 3; ++k) velocity[k] *= rate;
    Astronomy_EphemerisICRSToEQJ(position, position);
    Astronomy_EphemerisICRSToEQJ(velocity, velocity);
    return 1;
}

int Astronomy_BundledMoon(double tt_days, double position[3], double velocity[3])
{
    return SourceState(&moon, tt_days, position, velocity);
}

int Astronomy_BundledPluto(double tt_days, double position[3], double velocity[3])
{
    double sunp[3], sunv[3], relativep[3], relativev[3];
    int k;
    if (!SourceState(&pluto_barycenter, tt_days, position, velocity) ||
        !SourceState(&sun, tt_days, sunp, sunv) ||
        !SourceState(&pluto_relative, tt_days, relativep, relativev)) return 0;
    for (k = 0; k < 3; ++k) {
        position[k] = position[k] + sunp[k] + relativep[k];
        velocity[k] = velocity[k] + sunv[k] + relativev[k];
    }
    return 1;
}
