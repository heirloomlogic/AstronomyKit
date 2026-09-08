#include "astronomy.h"
#include <math.h>
#include <time.h>

static double seconds(struct timespec t) { return t.tv_sec + t.tv_nsec * 1e-9; }

/* Same epochs/bodies as the Swift probe; loops run entirely in native C. */
int ak_native_trial(int workload, double *result)
{
    static const astro_body_t bodies[] = { BODY_MERCURY, BODY_VENUS, BODY_MARS,
        BODY_JUPITER, BODY_SATURN, BODY_URANUS, BODY_NEPTUNE, BODY_SUN };
    struct timespec start, end, cpu_start, cpu_end;
    double checksum = 0;
    clock_gettime(CLOCK_MONOTONIC, &start);
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &cpu_start);
    for (int i=0; i<200; ++i) {
        double ut = workload == 0 ? 9000.0 + i*.125 :
                    workload == 1 ? 9000.0 + ((i*73)%200)*.125 :
                    workload == 2 ? 9000.0 + (i/20)*.125 + (i%20)*.00001 : 9000.0;
        astro_time_t t = Astronomy_TimeFromDays(ut);
        for (int b=0; b<8; ++b) {
            astro_vector_t v = Astronomy_GeoVector(bodies[b], t, ABERRATION);
            if (v.status != ASTRO_SUCCESS || !isfinite(v.x+v.y+v.z)) return 1;
            checksum += v.x+v.y+v.z;
        }
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &cpu_end);
    clock_gettime(CLOCK_MONOTONIC, &end);
    result[0] = seconds(end)-seconds(start);
    result[1] = seconds(cpu_end)-seconds(cpu_start);
    result[2] = checksum;
    return 0;
}
