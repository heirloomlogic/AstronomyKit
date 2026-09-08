#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include "astronomy.h"

static uint64_t calls;
static volatile double sink;
double counted_cos(double x) { ++calls; return cos(x); }
double counted_sin(double x) { ++calls; return sin(x); }

int main(void)
{
    /* Neptune's complete grid qualifies. Every call uses a fresh epoch. */
    for (int i=0; i<64; ++i)
    {
        astro_time_t time = {0}; time.tt = 9000.125 + i*0.125;
        astro_vector_t p = Astronomy_HelioVector(BODY_NEPTUNE, time);
        astro_state_vector_t s = Astronomy_HelioState(BODY_NEPTUNE, time);
        astro_func_result_t d = Astronomy_HelioDistance(BODY_NEPTUNE, time);
        if (p.status || s.status || d.status || !isfinite(d.value)) return 2;
        sink += p.x + s.vx + d.value;
    }
    printf("64 fresh polynomial position/state/radius queries: %llu trig calls\n", (unsigned long long)calls);
    if (calls != 0)
    {
        fprintf(stderr, "Polynomial path evaluated the VSOP trigonometric series\n");
        return 1;
    }
    return sink == 0;
}
