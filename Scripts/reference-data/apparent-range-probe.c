#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "astronomy.h"

static astro_body_t body_from_name(const char *name)
{
    if (strcmp(name, "moon") == 0) return BODY_MOON;
    if (strcmp(name, "mercury") == 0) return BODY_MERCURY;
    if (strcmp(name, "mars") == 0) return BODY_MARS;
    if (strcmp(name, "pluto") == 0) return BODY_PLUTO;
    return BODY_INVALID;
}

int main(int argc, char **argv)
{
    astro_body_t body;
    astro_time_t time;
    astro_vector_t vector;
    astro_aberration_t aberration;
    int year, month, day;

    if (argc != 8) return 64;
    body = body_from_name(argv[1]);
    if (body == BODY_INVALID) return 64;
    if (strcmp(argv[2], "jpl-horizons") == 0) {
        Astronomy_SetDeltaTFunction(Astronomy_DeltaT_JplHorizons);
    } else if (strcmp(argv[2], "espenak-meeus") == 0) {
        Astronomy_SetDeltaTFunction(Astronomy_DeltaT_EspenakMeeus);
    } else {
        return 64;
    }
    if (strcmp(argv[3], "corrected") == 0) {
        aberration = ABERRATION;
    } else if (strcmp(argv[3], "uncorrected") == 0) {
        aberration = NO_ABERRATION;
    } else {
        return 64;
    }
    year = atoi(argv[4]);
    month = atoi(argv[5]);
    day = atoi(argv[6]);
    time = Astronomy_MakeTime(year, month, day, 0, 0, atof(argv[7]));
    vector = Astronomy_GeoVector(body, time, aberration);
    if (vector.status != ASTRO_SUCCESS) return 1;
    printf("{\"distanceAU\":%.17g,\"tt\":%.17g,\"ut\":%.17g}\n",
        sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z),
        time.tt,
        time.ut);
    return 0;
}
