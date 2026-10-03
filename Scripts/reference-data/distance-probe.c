#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Development-only access to the complete series for approximation diagnostics. */
#include "../../Sources/CLibAstronomy/astronomy.c"

int main(void)
{
    char name[32], mode[32];
    double tt;
    Astronomy_SetDeltaTFunction(Astronomy_DeltaT_JplHorizons);
    while (scanf("%31s %31s %lf", name, mode, &tt) == 3)
    {
        astro_body_t body = Astronomy_BodyCode(name);
        astro_time_t time = Astronomy_TerrestrialTime(tt);
        astro_vector_t p;
        double radius, approximation = 0;
        if (body == BODY_INVALID) return 64;
        if (!strcmp(mode, "heliocentric"))
        {
            p = Astronomy_HelioVector(body, time);
            astro_func_result_t r = Astronomy_HelioDistance(body, time);
            if (r.status != ASTRO_SUCCESS) return 1;
            radius = r.value;
            if (body >= BODY_MERCURY && body <= BODY_NEPTUNE)
            {
                double sphere[3], rect[3];
                VsopCoords(&vsop[body], tt / DAYS_PER_MILLENNIUM, sphere, NULL);
                VsopSphereToRect(sphere[0], sphere[1], sphere[2], rect);
                terse_vector_t full = VsopRotate(rect);
                approximation = hypot(hypot(p.x-full.x, p.y-full.y), p.z-full.z);
            }
        }
        else if (!strcmp(mode, "geocentric"))
        {
            p = Astronomy_GeoVector(body, time, NO_ABERRATION);
            radius = Astronomy_VectorLength(p);
        }
        else return 64;
        if (p.status != ASTRO_SUCCESS || !isfinite(radius)) return 1;
        printf("{\"positionAU\":[%.17g,%.17g,%.17g],\"rangeAU\":%.17g,\"approximationDifferenceAU\":%.17g}\n",
            p.x, p.y, p.z, radius, approximation);
    }
    return ferror(stdin) ? 1 : 0;
}
