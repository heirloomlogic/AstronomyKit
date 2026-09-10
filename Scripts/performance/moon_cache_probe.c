#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

#include "astronomy.h"

static _Atomic uint64_t evaluation_count;

void counted_calc_moon_raw(void)
{
    atomic_fetch_add(&evaluation_count, 1);
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

static uint64_t count(void)
{
    return atomic_load(&evaluation_count);
}

static void reset_count(void)
{
    atomic_store(&evaluation_count, 0);
}

static int require_count(const char *label, uint64_t expected)
{
    uint64_t actual = count();
    if (actual == expected)
        return 0;
    fprintf(stderr, "%s: expected %llu raw evaluations, found %llu\n",
        label, (unsigned long long)expected, (unsigned long long)actual);
    return 1;
}

typedef struct
{
    double tt;
    int failed;
}
worker_context_t;

static void *thread_worker(void *context)
{
    worker_context_t *worker = context;
    int i;
    for (i = 0; i < 10; ++i)
    {
        astro_vector_t vector = Astronomy_GeoMoon(raw_time(worker->tt));
        if (vector.status != ASTRO_SUCCESS || !isfinite(vector.x + vector.y + vector.z))
            worker->failed = 1;
    }
    return NULL;
}

int main(void)
{
    static const int repeats = 12;
    static const int thread_count = 4;
    pthread_t threads[thread_count];
    worker_context_t workers[thread_count];
    astro_ecliptic_state_t state;
    astro_vector_t vector;
    astro_libration_t libration;
    int i;

    reset_count();
    for (i = 0; i < repeats; ++i)
    {
        state = Astronomy_MoonEclipticState(raw_time(91234.625));
        if (state.status != ASTRO_SUCCESS)
            return 1;
    }
    printf("same-time state calls: %llu evaluations for %d calls\n",
        (unsigned long long)count(), repeats);
    if (require_count("MoonEclipticState did not reuse three lunar samples", 3))
        return 1;

    reset_count();
    vector = Astronomy_GeoMoon(raw_time(91234.625));
    libration = Astronomy_Libration(raw_time(91234.625));
    if (vector.status != ASTRO_SUCCESS || !isfinite(libration.dist_km))
        return 1;
    if (require_count("lunar clients did not share the center sample", 0))
        return 1;

    reset_count();
    Astronomy_GeoMoon(raw_time(0.0));
    Astronomy_GeoMoon(raw_time(-0.0));
    Astronomy_GeoMoon(raw_time(0.0));
    Astronomy_GeoMoon(raw_time(-0.0));
    if (require_count("signed-zero keys were not cached separately", 2))
        return 1;

    reset_count();
    Astronomy_GeoMoon(raw_time(INFINITY));
    Astronomy_GeoMoon(raw_time(INFINITY));
    if (require_count("nonfinite keys entered the cache", 2))
        return 1;

    reset_count();
    for (i = 0; i < 33; ++i)
        Astronomy_GeoMoon(raw_time(120000.0 + i));
    Astronomy_GeoMoon(raw_time(120032.0));
    Astronomy_GeoMoon(raw_time(120000.0));
    if (require_count("32-slot FIFO eviction behavior changed", 34))
        return 1;

    reset_count();
    for (i = 0; i < thread_count; ++i)
    {
        workers[i].tt = 175000.25;
        workers[i].failed = 0;
        if (pthread_create(&threads[i], NULL, thread_worker, &workers[i]) != 0)
            return 1;
    }
    for (i = 0; i < thread_count; ++i)
    {
        if (pthread_join(threads[i], NULL) != 0 || workers[i].failed)
            return 1;
    }
    if (require_count("threads did not keep independent cache entries", thread_count))
        return 1;

    return 0;
}
