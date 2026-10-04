#include "ephemeris_time.h"
#include "erfa.h"
#include "erfam.h"

/* Geocentric observer: u=v=0 suppresses the topocentric part. */
double Astronomy_EphemerisTDBOffsetSeconds(double ttDaysSinceJ2000)
{
    return eraDtdb(ERFA_DJ00, ttDaysSinceJ2000, 0.0, 0.0, 0.0, 0.0);
}

double Astronomy_EphemerisTDBRate(double ttDaysSinceJ2000)
{
    /* A 0.01-day symmetric step resolves the periodic rate without cancellation.
       The annual-model truncation in the resulting near-unity factor is below 1e-16. */
    const double step = 0.01;
    return 1.0 + (Astronomy_EphemerisTDBOffsetSeconds(ttDaysSinceJ2000 + step)
                  - Astronomy_EphemerisTDBOffsetSeconds(ttDaysSinceJ2000 - step))
                 / (2.0 * step * ERFA_DAYSEC);
}

void Astronomy_EphemerisICRSToEQJ(const double input[3], double output[3])
{
    double bias[3][3];
    double result[3];
    int row;
    eraPmat06(ERFA_DJ00, 0.0, bias);
    for (row = 0; row < 3; ++row)
        result[row] = bias[row][0] * input[0] + bias[row][1] * input[1] + bias[row][2] * input[2];
    for (row = 0; row < 3; ++row)
        output[row] = result[row];
}
