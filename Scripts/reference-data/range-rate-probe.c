#include <math.h>
#include <stdio.h>
#include <string.h>
#include "astronomy.h"

/* Offline diagnostics use the production engine; reference values come only from archived Horizons data. */
static double range(astro_body_t body, const char *mode, astro_time_t time)
{
    astro_vector_t p = !strcmp(mode, "heliocentric") ? Astronomy_HelioVector(body, time) : Astronomy_GeoVector(body, time, NO_ABERRATION);
    return p.status == ASTRO_SUCCESS ? Astronomy_VectorLength(p) : NAN;
}

static double difference(astro_body_t body, const char *mode, astro_time_t time, double step)
{
    /* Keep TT and UT increments identical, holding the reception Delta T fixed. */
    astro_time_t before = Astronomy_TimeFromPair(time.ut-step, time.tt-step, Astronomy_DeltaT_JplHorizons);
    astro_time_t after = Astronomy_TimeFromPair(time.ut+step, time.tt+step, Astronomy_DeltaT_JplHorizons);
    return (range(body, mode, after)-range(body, mode, before))/(2*step);
}

int main(void)
{
    char name[32], mode[32];
    double tt;
    Astronomy_SetDeltaTFunction(Astronomy_DeltaT_JplHorizons);
    while (scanf("%31s %31s %lf", name, mode, &tt) == 3)
    {
        astro_body_t body = Astronomy_BodyCode(name);
        astro_time_t time = Astronomy_TerrestrialTime(tt);
        double rate, corrected = 0, radius;
        if (body == BODY_INVALID) return 64;
        if (!strcmp(mode, "heliocentric"))
        {
            astro_state_vector_t s = Astronomy_HelioState(body, time);
            if (s.status != ASTRO_SUCCESS) return 1;
            radius = hypot(hypot(s.x, s.y), s.z);
            rate = (s.x*s.vx+s.y*s.vy+s.z*s.vz)/radius;
        }
        else if (!strcmp(mode, "geocentric"))
        {
            astro_ecliptic_state_t s = Astronomy_GeoEclipticState(body, time, NO_ABERRATION);
            astro_ecliptic_state_t c = Astronomy_GeoEclipticState(body, time, ABERRATION);
            if (s.status != ASTRO_SUCCESS || c.status != ASTRO_SUCCESS) return 1;
            radius = s.dist;
            rate = s.dist_rate;
            corrected = c.dist_rate;
        }
        else return 64;
        double small = difference(body, mode, time, .001);
        double large = difference(body, mode, time, .002);
        if (!isfinite(rate) || !isfinite(radius) || !isfinite(corrected) || !isfinite(small) || !isfinite(large)) return 1;
        printf("{\"rangeAU\":%.17g,\"rateAUPerTTDay\":%.17g,\"correctedRateAUPerTTDay\":%.17g,\"centralDifferenceSmall\":%.17g,\"centralDifferenceLarge\":%.17g}\n", radius, rate, corrected, small, large);
    }
    return ferror(stdin) ? 1 : 0;
}
