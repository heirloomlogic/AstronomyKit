#include "astronomy.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    astro_time_t time;
    astro_vector_t vector;

    if (argc != 2 || strcmp(argv[1], "--smoke") != 0)
    {
        fprintf(stderr, "usage: astronomy-oracle --smoke\n");
        return 64;
    }

    time = Astronomy_TimeFromDays(0.0);
    vector = Astronomy_HelioVector(BODY_EARTH, time);
    printf(
        "%s %s\n",
        vector.status == ASTRO_SUCCESS ? "ASTRO_SUCCESS" : "ASTRO_FAILURE",
        isfinite(vector.x) && isfinite(vector.y) && isfinite(vector.z) ? "finite" : "nonfinite"
    );
    return vector.status == ASTRO_SUCCESS && isfinite(vector.x) && isfinite(vector.y) && isfinite(vector.z) ? 0 : 1;
}
