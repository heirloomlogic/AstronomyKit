/* Observed Delta T (local patch 15): IERS UT1 from 1962, the Morrison-Stephenson-
 * Hohenkerk-Zawilski (2021) spline before it, and their long-term length-of-day model
 * outside both. Immutable tables, no initialization or allocation, so the function can
 * be the static initializer of DeltaTFunc. Included by astronomy.c below FP_CONTRACT OFF.
 *
 * Regimes, by UT1 days since J2000:
 *   - Observed and predicted: the generated daily rows at 0h UTC, IERS EOP 20 C04 then
 *     IERS Bulletin A rapid values and predictions. Each row's abscissa is its UT1,
 *     MJD - 51544.5 + (UT1-UTC)/86400, and Delta T is linear in UT1 between rows.
 *   - Historical: Table S15 v2020 from -720.0 to the first C04 row, in Julian epoch
 *     years, rebuilt by the generator as cubic Hermite segments through the mean
 *     one-sided value and rate at each knot, so it is C0 and C1 everywhere. The last
 *     segment ends on the first C04 value and the rate of the first C04 interval.
 *   - Extrapolated: before -720.0 and after the last prediction, the integral of
 *     lod = 1.72 t - 3.5 sin(2 pi (t + 0.75) / 14) ms, t in centuries from 1825.0, with
 *     its constant fixed by continuity at the join. HMNAO extrapolates the spline this
 *     way in both directions.
 */
#include "generated/deltat_iers.h"

#define DELTAT_IERS_FIRST_UT ((double)DELTAT_IERS_FIRST_MJD - 51544.5)

static double DeltaTIersYear(double ut)
{
    /* Julian epoch: J2000.0 is 2000-01-01 12h, so J1962.0 is 1962-01-01 0h. */
    return 2000.0 + ut / 365.25;
}

static double DeltaTIersRowUT(int row)
{
    return (DELTAT_IERS_FIRST_UT + row) + (deltat_iers_rows[row][1] / 1.0e7) / 86400.0;
}

/* The row at or before ut, for ut within the rows. */
static int DeltaTIersRow(double ut)
{
    int row = (int)floor(ut - DELTAT_IERS_FIRST_UT);
    if (row < 0)
        row = 0;
    if (row > DELTAT_IERS_COUNT - 2)
        row = DELTAT_IERS_COUNT - 2;
    /* Abscissae differ from whole UTC days by UT1-UTC, at most about a second. */
    while (row > 0 && DeltaTIersRowUT(row) > ut)
        --row;
    while (row < DELTAT_IERS_COUNT - 2 && DeltaTIersRowUT(row + 1) <= ut)
        ++row;
    return row;
}

static double DeltaTLodIntegral(double year)
{
    /* Seconds per (ms of lod x century): 36525 days x 1e-3 s. */
    double t = (year - DELTAT_LOD_EPOCH) / 100.0;
    double phase = 2.0 * PI * (t + DELTAT_LOD_PHASE) / DELTAT_LOD_PERIOD;
    return 36.525 * (0.5 * DELTAT_LOD_RATE * t * t + DELTAT_LOD_AMPLITUDE * DELTAT_LOD_PERIOD / (2.0 * PI) * cos(phase));
}

static double DeltaTSpline(double year)
{
    int low = 0, high = DELTAT_SPLINE_COUNT - 1;
    while (low < high)
    {
        int middle = (low + high + 1) / 2;
        if (deltat_spline[middle][0] <= year)
            low = middle;
        else
            high = middle - 1;
    }
    const double *row = deltat_spline[low];
    double t = (year - row[0]) / (row[1] - row[0]);
    return row[2] + t * (row[3] + t * (row[4] + t * row[5]));
}

/* HMNAO error estimates, linear in the year; quadratic growth about 1825.0 beyond them. */
static double DeltaTEpsilon(double year)
{
    const int last = DELTAT_EPSILON_COUNT - 1;
    if (year <= deltat_epsilon[0][0] || year >= deltat_epsilon[last][0])
    {
        const double *end = deltat_epsilon[year <= deltat_epsilon[0][0] ? 0 : last];
        double ratio = (year - DELTAT_LOD_EPOCH) / (end[0] - DELTAT_LOD_EPOCH);
        return end[1] * ratio * ratio;
    }
    int low = 0, high = last;
    while (high - low > 1)
    {
        int middle = (low + high) / 2;
        if (deltat_epsilon[middle][0] <= year)
            low = middle;
        else
            high = middle;
    }
    double f = (year - deltat_epsilon[low][0]) / (deltat_epsilon[high][0] - deltat_epsilon[low][0]);
    return deltat_epsilon[low][1] + f * (deltat_epsilon[high][1] - deltat_epsilon[low][1]);
}

/**
 * @brief Observed Delta T: IERS UT1 from 1962, the 2020 historical spline before it.
 *
 * @param ut
 *      UT1 days since noon on January 1, 2000.
 *
 * @returns
 *      TT - UT1 in seconds. NaN for NaN input; +infinity for infinite input.
 */
double Astronomy_DeltaT_IersObserved(double ut)
{
    if (isnan(ut))
        return NAN;
    if (isinf(ut))
        return INFINITY;

    double first = DeltaTIersRowUT(0);
    if (ut < first)
    {
        double year = DeltaTIersYear(ut);
        if (year >= deltat_spline[0][0])
            return DeltaTSpline(year);
        return deltat_spline[0][2] + (DeltaTLodIntegral(year) - DeltaTLodIntegral(deltat_spline[0][0]));
    }

    const int last = DELTAT_IERS_COUNT - 1;
    double final = DeltaTIersRowUT(last);
    if (ut > final)
        return deltat_iers_rows[last][0] / 1.0e7
            + (DeltaTLodIntegral(DeltaTIersYear(ut)) - DeltaTLodIntegral(DeltaTIersYear(final)));

    int row = DeltaTIersRow(ut);
    double start = DeltaTIersRowUT(row);
    double f = (ut - start) / (DeltaTIersRowUT(row + 1) - start);
    double before = deltat_iers_rows[row][0] / 1.0e7;
    double after = deltat_iers_rows[row + 1][0] / 1.0e7;
    return before + f * (after - before);
}

/**
 * @brief The stated uncertainty of #Astronomy_DeltaT_IersObserved, in seconds.
 *
 * Observed and predicted: the row's stated UT1-UTC error, linear between rows, plus
 * 4 f (1 - f) times the largest measured interpolation error, at fraction f of the day.
 * Historical: the HMNAO error estimate, but never less than the spline's largest
 * departure from C04 over 1962-2019. Extrapolated: the HMNAO estimate (quadratic growth
 * about 1825.0 beyond its -2000 and 2500 ends), never less than the last prediction's.
 * These are stated, sourced figures of about one standard error, not proved bounds.
 */
double Astronomy_DeltaTUncertainty_IersObserved(double ut)
{
    if (isnan(ut))
        return NAN;
    if (isinf(ut))
        return INFINITY;

    double first = DeltaTIersRowUT(0);
    if (ut < first)
    {
        double year = DeltaTIersYear(ut);
        double epsilon = DeltaTEpsilon(year);
        return year >= deltat_spline[0][0] ? fmax(epsilon, DELTAT_HISTORICAL_MISFIT) : epsilon;
    }

    const int last = DELTAT_IERS_COUNT - 1;
    if (ut > DeltaTIersRowUT(last))
        return fmax(DeltaTEpsilon(DeltaTIersYear(ut)), deltat_iers_rows[last][2] / 1.0e7);

    int row = DeltaTIersRow(ut);
    double start = DeltaTIersRowUT(row);
    double f = (ut - start) / (DeltaTIersRowUT(row + 1) - start);
    double before = deltat_iers_rows[row][2] / 1.0e7;
    double after = deltat_iers_rows[row + 1][2] / 1.0e7;
    return before + f * (after - before) + 4.0 * f * (1.0 - f) * DELTAT_IERS_INTERPOLATION_MAX;
}

/**
 * @brief Which source #Astronomy_DeltaT_IersObserved draws on at a UT.
 *
 * @returns
 *      #DELTAT_REGIME_UNDEFINED for NaN input.
 */
astro_deltat_regime_t Astronomy_DeltaTRegime_IersObserved(double ut)
{
    if (isnan(ut))
        return DELTAT_REGIME_UNDEFINED;
    if (ut < DeltaTIersRowUT(0))
        return DeltaTIersYear(ut) >= deltat_spline[0][0] ? DELTAT_REGIME_HISTORICAL : DELTAT_REGIME_EXTRAPOLATED_PAST;
    if (ut <= DeltaTIersRowUT(DELTAT_IERS_FIRST_PREDICTED - 1))
        return DELTAT_REGIME_OBSERVED;
    if (ut <= DeltaTIersRowUT(DELTAT_IERS_COUNT - 1))
        return DELTAT_REGIME_PREDICTED;
    return DELTAT_REGIME_EXTRAPOLATED_FUTURE;
}
