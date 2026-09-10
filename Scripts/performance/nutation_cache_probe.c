#include <math.h>
#include "astronomy.h"

#include <stdint.h>
#include <stdio.h>

static uint64_t evaluation_count;
static volatile double result_sink;

void counted_iau2000b_eval(void)
{
    ++evaluation_count;
}

static astro_time_t raw_time(double tt)
{
    astro_time_t time;
    time.ut = tt - 0.0008;
    time.tt = tt;
    time.psi = NAN;
    time.eps = NAN;
    time.st = NAN;
    return time;
}

static int check_status(const char *label, astro_status_t status)
{
    if (status == ASTRO_SUCCESS)
        return 0;
    fprintf(stderr, "%s failed with astronomy status %d\n", label, status);
    return 1;
}

static void rates(double tt)
{
    astro_time_t time = raw_time(tt);
    double psi_rate;
    double eps_rate;
    _Astronomy_Iau2000bRates(&time, &psi_rate, &eps_rate);
    result_sink += time.psi + time.eps + psi_rate + eps_rate;
}

int main(void)
{
    static const int repeats = 12;
    astro_ecliptic_state_t state;
    astro_rotation_t rotation;
    astro_time_t time;
    int i;

    evaluation_count = 0;
    for (i = 0; i < repeats; ++i)
    {
        state = Astronomy_GeoEclipticState(BODY_MARS, raw_time(91234.625), ABERRATION);
        if (check_status("GeoEclipticState", state.status))
            return 1;
        result_sink += state.elon + state.elon_rate;
    }
    printf("same-time state calls: %llu evaluations for %d calls\n",
        (unsigned long long)evaluation_count, repeats);
    if (evaluation_count != 1)
    {
        fprintf(stderr, "GeoEclipticState did not reuse one nutation evaluation\n");
        return 1;
    }

    time = raw_time(-82345.75);
    rotation = Astronomy_Rotation_EQJ_EQD(&time);
    if (check_status("Rotation_EQJ_EQD", rotation.status))
        return 1;
    evaluation_count = 0;
    rates(-82345.75);
    if (evaluation_count != 0)
    {
        fprintf(stderr, "angle-only call did not warm the rate cache\n");
        return 1;
    }

    evaluation_count = 0;
    rates(0.0);
    rates(-0.0);
    rates(0.0);
    rates(-0.0);
    if (evaluation_count != 2)
    {
        fprintf(stderr, "signed-zero keys were not cached separately\n");
        return 1;
    }

    evaluation_count = 0;
    rates(INFINITY);
    rates(INFINITY);
    if (evaluation_count != 2)
    {
        fprintf(stderr, "nonfinite keys entered the cache\n");
        return 1;
    }

    evaluation_count = 0;
    for (i = 0; i < 33; ++i)
        rates(120000.0 + i);
    rates(120032.0);
    rates(120000.0);
    if (evaluation_count != 34)
    {
        fprintf(stderr, "32-slot FIFO eviction behavior changed\n");
        return 1;
    }

    return result_sink == 0.0;
}
