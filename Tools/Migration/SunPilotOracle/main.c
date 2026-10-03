/* Development driver compiled with the locked engine source, including its static primitives. */
#define _POSIX_C_SOURCE 200809L
#include "astronomy.c"
#include <time.h>
#include <stdio.h>
#include <string.h>

static const char *status_name(astro_status_t status)
{
    switch (status)
    {
        case ASTRO_SUCCESS: return "success";
        case ASTRO_BAD_TIME: return "bad-time";
        case ASTRO_INVALID_PARAMETER: return "invalid-parameter";
        case ASTRO_BAD_VECTOR: return "bad-vector";
        case ASTRO_NO_CONVERGE: return "no-converge";
        default: return "unexpected-oracle-status";
    }
}

static unsigned long long nanos(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (unsigned long long)t.tv_sec * 1000000000ULL + t.tv_nsec;
}

static double observation(double ut)
{
    astro_time_t t = Astronomy_TimeFromDaysWithDeltaT(ut, Astronomy_DeltaT_EspenakMeeus);
    astro_observer_t site = Astronomy_MakeObserver(35, -80, 100);
    astro_equatorial_t equ = Astronomy_Equator(BODY_SUN, &t, site, EQUATOR_OF_DATE, ABERRATION);
    astro_horizon_t hor = Astronomy_Horizon(&t, site, equ.ra, equ.dec, REFRACTION_NONE);
    return hor.altitude + equ.dist;
}

static void workload(const char *mode, int *operations, unsigned long long *elapsed, double *checksum)
{
    const int count = strcmp(mode, "firstAccess") == 0 ? 1 : 200;
    const double epoch = strstr(mode, "Fallback") ? 40000.0 : 9000.0;
    if (strncmp(mode, "repeated", 8) == 0) observation(epoch);
    unsigned long long start = nanos();
    double sum = 0.0;
    for (int i = 0; i < count; ++i)
        sum += observation(epoch + (strncmp(mode, "fresh", 5) == 0 ? i * 0.125 : 0.0));
    *operations = count;
    *elapsed = nanos() - start;
    *checksum = sum;
}

static int performance(void)
{
    const char *modes[] = {"firstAccess", "freshPolynomial", "repeatedPolynomial", "freshFallback", "repeatedFallback"};
    printf("{");
    for (int mode = 0; mode < 5; ++mode)
    {
        int operations;
        unsigned long long elapsed;
        double checksum;
        workload(modes[mode], &operations, &elapsed, &checksum);
        printf("%s\"%s\":{\"operations\":%d,\"elapsedNanoseconds\":%llu,\"checksum\":%.17g}", mode ? "," : "", modes[mode], operations, elapsed, checksum);
    }
    printf("}\n");
    return 0;
}

static int rss_stage(const char *stage)
{
    if (strcmp(stage, "startup") == 0)
    {
        printf("0\n");
        return 0;
    }
    if (strcmp(stage, "serialization") == 0)
    {
        printf("{\"operations\":0,\"elapsedNanoseconds\":0,\"checksum\":0}\n");
        return 0;
    }
    if (strcmp(stage, "polynomialEarth") == 0 || strcmp(stage, "fallbackEarth") == 0)
    {
        const double epoch = strcmp(stage, "fallbackEarth") == 0 ? 40000.0 : 9000.0;
        astro_time_t time = Astronomy_TimeFromDaysWithDeltaT(epoch, Astronomy_DeltaT_EspenakMeeus);
        astro_vector_t earth = CalcEarth(time);
        if (earth.status != ASTRO_SUCCESS) return 1;
        printf("%.17g\n", earth.x + earth.y + earth.z);
        return 0;
    }
    if (strcmp(stage, "polynomialCache") == 0 || strcmp(stage, "fallbackCache") == 0)
    {
        const double epoch = strcmp(stage, "fallbackCache") == 0 ? 40000.0 : 9000.0;
        printf("%.17g\n", observation(epoch) + observation(epoch));
        return 0;
    }
    if (strcmp(stage, "aggregate") == 0) return performance();
    const char *modes[] = {"firstAccess", "freshPolynomial", "repeatedPolynomial", "freshFallback", "repeatedFallback"};
    for (int mode = 0; mode < 5; ++mode)
    {
        if (strcmp(stage, modes[mode]) == 0)
        {
            int operations;
            unsigned long long elapsed;
            double checksum;
            workload(stage, &operations, &elapsed, &checksum);
            printf("%.17g\n", checksum);
            return 0;
        }
    }
    return 2;
}

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "--performance") == 0) return performance();
    if (argc == 3 && strcmp(argv[1], "--rss-stage") == 0) return rss_stage(argv[2]);
    char model[32], scale[16], value_text[64], lat_text[64], lon_text[64], height_text[64], ut_text[64];
    while (scanf("%31s %15s %63s %63s %63s %63s %63s", model, scale, value_text, lat_text, lon_text, height_text, ut_text) == 7)
    {
        astro_deltat_func func = strcmp(model, "jpl-horizons") == 0 ? Astronomy_DeltaT_JplHorizons : Astronomy_DeltaT_EspenakMeeus;
        double value = strtod(value_text, NULL);
        astro_time_t time = strcmp(scale, "pair") == 0 ? Astronomy_TimeFromPair(strtod(ut_text, NULL), value, func) : Astronomy_TimeFromDaysWithDeltaT(value, func);
        astro_observer_t site = Astronomy_MakeObserver(strtod(lat_text, NULL), strtod(lon_text, NULL), strtod(height_text, NULL));
        astro_vector_t earth = CalcEarth(time);
        astro_equatorial_t equ = Astronomy_Equator(BODY_SUN, &time, site, EQUATOR_OF_DATE, ABERRATION);
        astro_status_t status = earth.status != ASTRO_SUCCESS ? earth.status : equ.status;
        if (status != ASTRO_SUCCESS)
        {
            printf("{\"status\":\"%s\"}\n", status_name(status));
            continue;
        }
        astro_horizon_t horizon = Astronomy_Horizon(&time, site, equ.ra, equ.dec, REFRACTION_NONE);
        astro_time_t ltime = time;
        astro_vector_t sun;
        int iterations = 0, fallback_count = 0;
        double polynomial[3];
        int fallback = !PolynomialPosition(BODY_EARTH, time.tt, polynomial, NULL);
        for (int i = 0; i < 10; ++i)
        {
            astro_vector_t e = CalcEarth(ltime);
            fallback_count += !PolynomialPosition(BODY_EARTH, ltime.tt, polynomial, NULL);
            sun = e;
            sun.x = -e.x; sun.y = -e.y; sun.z = -e.z;
            double distance = Astronomy_VectorLength(sun);
            astro_time_t next = Astronomy_AddDays(time, -distance / C_AUDAY);
            iterations = i + 1;
            if (fabs(next.tt - ltime.tt) < 1e-9) break;
            ltime = next;
        }
        printf("{\"status\":\"success\",\"ut\":%.17g,\"tt\":%.17g,\"x\":%.17g,\"y\":%.17g,\"z\":%.17g,\"gx\":%.17g,\"gy\":%.17g,\"gz\":%.17g,\"ra\":%.17g,\"dec\":%.17g,\"distance\":%.17g,\"altitude\":%.17g,\"fallback\":%s,\"iterations\":%d,\"fallbackEvaluations\":%d}\n", time.ut, time.tt, earth.x, earth.y, earth.z, sun.x, sun.y, sun.z, equ.ra, equ.dec, equ.dist, horizon.altitude, fallback ? "true" : "false", iterations, fallback_count);
    }
    return 0;
}
