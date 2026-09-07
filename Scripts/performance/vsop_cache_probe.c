#include "ak_math.h"
#include "astronomy.h"

#include <stdint.h>
#include <stdio.h>

double ak_uncounted_cos(double x);
double ak_uncounted_sin(double x);

static uint64_t cos_calls;
static uint64_t sin_calls;
static volatile double result_sink;

double ak_cos(double x)
{
    ++cos_calls;
    return ak_uncounted_cos(x);
}

double ak_sin(double x)
{
    ++sin_calls;
    return ak_uncounted_sin(x);
}

static void reset_counts(void)
{
    cos_calls = 0;
    sin_calls = 0;
}

static uint64_t trig_calls(void)
{
    return cos_calls + sin_calls;
}

static astro_time_t raw_time(double tt)
{
    astro_time_t time;
    time.ut = tt - 0.0008;
    time.tt = tt;
    time.psi = 1.25;
    time.eps = -2.5;
    time.st = 3.75;
    return time;
}

static int check_status(const char *label, astro_status_t status)
{
    if (status == ASTRO_SUCCESS)
        return 0;
    fprintf(stderr, "%s failed with astronomy status %d\n", label, status);
    return 1;
}

int main(void)
{
    static const int repeats = 12;
    astro_time_t time;
    astro_vector_t vector;
    astro_state_vector_t state;
    astro_func_result_t radius;
    uint64_t position_calls;
    uint64_t state_calls;
    uint64_t radius_calls;
    int i;

    /* Prove the wrappers see a real cold VSOP evaluation. */
    reset_counts();
    vector = Astronomy_HelioVector(BODY_EARTH, raw_time(-91234.5));
    if (check_status("cold HelioVector", vector.status))
        return 1;
    if (trig_calls() < 100)
    {
        fprintf(stderr, "diagnostic trig wrappers observed only %llu cold calls\n",
            (unsigned long long)trig_calls());
        return 1;
    }

    time = raw_time(12345.625);
    vector = Astronomy_HelioVector(BODY_MARS, time);       /* warm position */
    if (check_status("warm HelioVector", vector.status))
        return 1;
    reset_counts();
    for (i=0; i < repeats; ++i)
    {
        vector = Astronomy_HelioVector(BODY_MARS, time);
        if (check_status("repeated HelioVector", vector.status))
            return 1;
        result_sink += vector.x;
    }
    position_calls = trig_calls();

    time = raw_time(-23456.75);
    state = Astronomy_HelioState(BODY_MERCURY, time);      /* warm coordinates and derivatives */
    if (check_status("warm HelioState", state.status))
        return 1;
    reset_counts();
    for (i=0; i < repeats; ++i)
    {
        state = Astronomy_HelioState(BODY_MERCURY, time);
        if (check_status("repeated HelioState", state.status))
            return 1;
        result_sink += state.x + state.vx;
    }
    state_calls = trig_calls();

    time = raw_time(34567.875);
    radius = Astronomy_HelioDistance(BODY_JUPITER, time);  /* warm radius */
    if (check_status("warm HelioDistance", radius.status))
        return 1;
    reset_counts();
    for (i=0; i < repeats; ++i)
    {
        radius = Astronomy_HelioDistance(BODY_JUPITER, time);
        if (check_status("repeated HelioDistance", radius.status))
            return 1;
        result_sink += radius.value;
    }
    radius_calls = trig_calls();

    printf("repeated calls (%d each): vector=%llu state=%llu radius=%llu trig calls\n",
        repeats,
        (unsigned long long)position_calls,
        (unsigned long long)state_calls,
        (unsigned long long)radius_calls);

    /* Cache hits retain only the fixed spherical-to-rectangular work. */
    if (position_calls > (uint64_t)(8 * repeats))
    {
        fprintf(stderr, "HelioVector repeated the VSOP position series\n");
        return 1;
    }
    if (state_calls > (uint64_t)(16 * repeats))
    {
        fprintf(stderr, "HelioState repeated the VSOP coordinate or derivative series\n");
        return 1;
    }
    if (radius_calls != 0)
    {
        fprintf(stderr, "HelioDistance repeated the VSOP radius series\n");
        return 1;
    }

    return result_sink == 0.0;
}
