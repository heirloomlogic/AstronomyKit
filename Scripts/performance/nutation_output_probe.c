#include <math.h>
#include "astronomy.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint64_t bits(double value)
{
    uint64_t result;
    memcpy(&result, &value, sizeof(result));
    return result;
}

static astro_time_t raw_time(double tt, double metadata)
{
    astro_time_t time;
    time.ut = metadata;
    time.tt = tt;
    time.psi = NAN;
    time.eps = NAN;
    time.st = -metadata;
    return time;
}

int main(void)
{
    static const double epochs[] = {-40000.25, -0.0, 0.0, 12345.625, 40000.75};
    static const astro_body_t bodies[] = {BODY_MOON, BODY_MERCURY, BODY_MARS, BODY_JUPITER, BODY_PLUTO};
    astro_ecliptic_state_t state;
    astro_time_t time;
    double psi_rate;
    double eps_rate;
    astro_rotation_t rotation;
    unsigned i;

    for (i = 0; i < sizeof(epochs) / sizeof(epochs[0]); ++i)
    {
        time = raw_time(epochs[i], 100.0 + i);
        _Astronomy_Iau2000bRates(&time, &psi_rate, &eps_rate);
        printf("r %016llx %016llx %016llx %016llx %016llx %016llx %016llx\n",
            (unsigned long long)bits(time.ut),
            (unsigned long long)bits(time.tt),
            (unsigned long long)bits(time.st),
            (unsigned long long)bits(time.psi),
            (unsigned long long)bits(time.eps),
            (unsigned long long)bits(psi_rate),
            (unsigned long long)bits(eps_rate));

        state = Astronomy_GeoEclipticState(bodies[i], raw_time(epochs[i], 200.0 + i), ABERRATION);
        if (state.status != ASTRO_SUCCESS)
            return 1;
        printf("s %016llx %016llx %016llx %016llx %016llx %016llx %016llx %016llx %016llx\n",
            (unsigned long long)bits(state.elon),
            (unsigned long long)bits(state.elat),
            (unsigned long long)bits(state.dist),
            (unsigned long long)bits(state.elon_rate),
            (unsigned long long)bits(state.elat_rate),
            (unsigned long long)bits(state.dist_rate),
            (unsigned long long)bits(state.x),
            (unsigned long long)bits(state.vx),
            (unsigned long long)bits(state.t.ut));
    }

    time = raw_time(54321.125, -300.5);
    rotation = Astronomy_Rotation_EQJ_EQD(&time);
    if (rotation.status != ASTRO_SUCCESS)
        return 1;
    printf("a %016llx %016llx %016llx %016llx %016llx %016llx %016llx %016llx\n",
        (unsigned long long)bits(time.psi),
        (unsigned long long)bits(time.eps),
        (unsigned long long)bits(time.ut),
        (unsigned long long)bits(time.tt),
        (unsigned long long)bits(time.st),
        (unsigned long long)bits(rotation.rot[0][0]),
        (unsigned long long)bits(rotation.rot[1][2]),
        (unsigned long long)bits(rotation.rot[2][1]));
    return 0;
}
