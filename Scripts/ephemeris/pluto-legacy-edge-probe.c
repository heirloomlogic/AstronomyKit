/* Development diagnostic. Compile against an explicitly archived legacy source. */
#include <stdio.h>
#ifndef PLUTO_LEGACY_SOURCE
#error Define PLUTO_LEGACY_SOURCE as the archived astronomy.c path.
#endif
#include PLUTO_LEGACY_SOURCE

int main(void)
{
    double jd;
    while (scanf("%lf", &jd) == 1)
    {
        body_state_t state;
        if (CalcPluto(&state, Astronomy_TerrestrialTime(jd - 2451545.0), 1, 1) != ASTRO_SUCCESS)
            return 1;
        printf("%.17g %.17g %.17g %.17g %.17g %.17g %.17g\n",
            jd, state.r.x, state.r.y, state.r.z, state.v.x, state.v.y, state.v.z);
    }
    Astronomy_Reset();
    return ferror(stdin) ? 1 : 0;
}
