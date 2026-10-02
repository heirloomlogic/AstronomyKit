/* Development-only probe. The driver compiles isolated copies, never production edits. */
#include <stdio.h>
#include <stdlib.h>
#ifndef PLUTO_DIAGNOSTIC_SOURCE
#define PLUTO_DIAGNOSTIC_SOURCE "../../Sources/CLibAstronomy/astronomy.c"
#endif
#include PLUTO_DIAGNOSTIC_SOURCE

static void vector(terse_vector_t v)
{
    printf("[%.17g,%.17g,%.17g]", v.x, v.y, v.z);
}

int main(void)
{
    double tt;
    while (scanf("%lf", &tt) == 1)
    {
        if (!isfinite(tt) || tt < -58400 || tt > 58400) return 64;
        int index = (int)floor((tt + 730000) / PLUTO_TIME_STEP);
        if (tt == 58400) --index;
        major_bodies_t bary;
        body_state_t cached;
        if (CalcPluto(&cached, Astronomy_TerrestrialTime(tt), 1, 1) != ASTRO_SUCCESS) return 1;
        body_grav_calc_t f = CalcPlutoOneWay(&bary, &PlutoStateTable[index], tt, PLUTO_DT);
        body_grav_calc_t b = CalcPlutoOneWay(&bary, &PlutoStateTable[index+1], tt, -PLUTO_DT);
        MajorBodyBary(&bary, tt);
        terse_vector_t fp = f.r, bp = b.r;
        VecDecr(&fp, bary.Sun.r); VecDecr(&bp, bary.Sun.r);
        double ramp = (tt-PlutoStateTable[index].tt) / PLUTO_TIME_STEP;
        printf("{\"ttDays\":%.17g,\"cached\":", tt); vector(cached.r);
        printf(",\"forward\":"); vector(fp);
        printf(",\"backward\":"); vector(bp);
        printf(",\"directBlend\":"); vector(VecRamp(fp,bp,ramp));
        printf("}\n");
    }
    Astronomy_Reset();
    return ferror(stdin) ? 1 : 0;
}
