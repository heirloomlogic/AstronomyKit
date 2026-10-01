/* Evaluates the geometric solar altitude path for each input line.
 *
 * Input: five hexadecimal floating-point fields per line, parsed as binary64
 * so both builds start from identical values: tt ut latitude longitude height.
 * Output: one line per input with the engine status and the values below,
 * printed exactly (binary64 as %a, binary128 with 36 significant digits).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "astronomy.h"

#ifdef QUAD
#include <quadmath.h>
typedef __float128 real;
/* quadmath_snprintf accepts one conversion specification and nothing else,
   so the separating space is printed separately. */
static void print_real(real x)
{
    char buf[80];
    quadmath_snprintf(buf, sizeof buf, "%.36Qe", x);
    fputs(buf, stdout);
}
#else
typedef double real;
static void print_real(real x)
{
    printf("%a", x);
}
#endif

static void field(real x)
{
    putchar(' ');
    print_real(x);
}

int main(void)
{
    char line[1024];
    while (fgets(line, sizeof line, stdin))
    {
        char *cursor = line;
        double in[5];
        for (int i = 0; i < 5; ++i)
            in[i] = strtod(cursor, &cursor);

        astro_time_t time = Astronomy_TimeFromPair((real)in[1], (real)in[0], Astronomy_DeltaT_EspenakMeeus);
        astro_observer_t observer = Astronomy_MakeObserver((real)in[2], (real)in[3], (real)in[4]);
        astro_equatorial_t equ = Astronomy_Equator(BODY_SUN, &time, observer, EQUATOR_OF_DATE, ABERRATION);
        astro_horizon_t hor = Astronomy_Horizon(&time, observer, equ.ra, equ.dec, REFRACTION_NONE);
        astro_equatorial_t j2000 = Astronomy_Equator(BODY_SUN, &time, observer, EQUATOR_J2000, ABERRATION);
        astro_vector_t geo = Astronomy_GeoVector(BODY_SUN, time, ABERRATION);
        astro_vector_t earth = Astronomy_HelioVector(BODY_EARTH, time);
        real sidereal = Astronomy_SiderealTime(&time);
        real deltat = Astronomy_DeltaT_EspenakMeeus((real)in[1]);

        printf("%d", (int)equ.status);
        field(hor.altitude);
        field(hor.azimuth);
        field(equ.ra);
        field(equ.dec);
        field(equ.dist);
        field(j2000.ra);
        field(j2000.dec);
        field(geo.x);
        field(geo.y);
        field(geo.z);
        field(earth.x);
        field(earth.y);
        field(earth.z);
        field(sidereal);
        field(deltat);
        putchar('\n');
    }
    return 0;
}
