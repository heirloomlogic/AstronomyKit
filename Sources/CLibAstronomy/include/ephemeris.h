#ifndef ASTRONOMY_BUNDLED_EPHEMERIS_H
#define ASTRONOMY_BUNDLED_EPHEMERIS_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Internal immutable type-2 Chebyshev table, record/axis/ascending-degree order.
 * Epochs are TDB days from J2000, positions AU, derivatives AU/TDB day.
 * The upper endpoint is exclusive; no extrapolation or endpoint clamping. */
typedef struct {
    double start_tdb;
    double step_days;
    size_t record_count;
    size_t coefficient_count;
    const double *coefficients;
} astronomy_ephemeris_table_t;

int Astronomy_EphemerisEvaluate(const astronomy_ephemeris_table_t *table,
    double tdb_days, double position[3], double velocity[3]);

/* Full model weight over 1900-01-01 through 2131-01-01 TT, with a C2
 * transition to the legacy model in the exterior 32 days on either side.
 * Returns weight; rate is its derivative per TT day. */
double Astronomy_EphemerisWeight(double tt_days, double *rate);

/* Internal source states: geometric body centers, EQJ, AU and AU/TT day.
 * Return zero outside physical table coverage or for nonfinite input. */
int Astronomy_BundledMoon(double tt_days, double position[3], double velocity[3]);
int Astronomy_BundledPluto(double tt_days, double position[3], double velocity[3]);
#ifdef __cplusplus
}
#endif
#endif
