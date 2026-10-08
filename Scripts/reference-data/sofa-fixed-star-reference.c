#include <math.h>
#include <stdio.h>
#include "sofa.h"

/*
 * Generates the fixed-star reference row from IAU SOFA release 2023-10-11.
 * The input coordinates, parallax, site and instant are copied from SOFA's
 * official astrometry example. AstronomyKit's fixed-star contract has no
 * proper-motion field, so this recipe sets both proper-motion components to
 * zero and retains the published values in the archived source for context.
 */

static double hours(double radians) { return iauAnp(radians) * 12.0 / acos(-1.0); }
static double degrees(double radians) { return radians * 180.0 / acos(-1.0); }

int main(void) {
    double rc, dc, utc1, utc2, tai1, tai2, tt1, tt2, ri, di, eo;
    double elong, phi, aob, zob, hob, dob, rob;
    double x, y, s, cirs[3], c2i[3][3], i2c[3][3], gcrs[3];
    double pnm[3][3], true_equator[3], dpsi, deps, eps, ecliptic[3];
    const double parallax = 0.16499;
    const double au_per_light_year = 63241.07708807546;

    iauTf2a(' ', 14, 34, 16.81183, &rc);
    iauAf2a('-', 12, 31, 10.3965, &dc);
    iauAf2a('-', 5, 41, 54.2, &elong);
    iauAf2a('-', 15, 57, 42.8, &phi);
    iauDtf2d("UTC", 2013, 4, 2, 23, 15, 43.55, &utc1, &utc2);
    iauUtctai(utc1, utc2, &tai1, &tai2);
    iauTaitt(tai1, tai2, &tt1, &tt2);

    /* Fixed-star semantics deliberately set the example's proper motion to zero. */
    iauAtci13(rc, dc, 0.0, 0.0, parallax, 0.0, tt1, tt2, &ri, &di, &eo);
    iauXys06a(tt1, tt2, &x, &y, &s);
    iauC2ixys(x, y, s, c2i);
    iauTr(c2i, i2c);
    iauS2c(ri, di, cirs);
    iauRxp(i2c, cirs, gcrs);

    iauPnm06a(tt1, tt2, pnm);
    iauRxp(pnm, gcrs, true_equator);
    iauNut06a(tt1, tt2, &dpsi, &deps);
    eps = iauObl06(tt1, tt2) + deps;
    ecliptic[0] = true_equator[0];
    ecliptic[1] = cos(eps) * true_equator[1] + sin(eps) * true_equator[2];
    ecliptic[2] = -sin(eps) * true_equator[1] + cos(eps) * true_equator[2];

    iauAtio13(ri, di, utc1, utc2, 0.0, elong, phi, 625.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, &aob, &zob, &hob, &dob, &rob);

    printf("utcJD %.17g\n", utc1 + utc2);
    printf("ttJD %.17g\n", tt1 + tt2);
    printf("rightAscensionHours %.17g\n", hours(rc));
    printf("declinationDegrees %.17g\n", degrees(dc));
    printf("distanceLightYears %.17g\n", (206264.80624709636 / parallax) / au_per_light_year);
    printf("j2000RAHours %.17g\n", hours(atan2(gcrs[1], gcrs[0])));
    printf("j2000DecDegrees %.17g\n", degrees(atan2(gcrs[2], hypot(gcrs[0], gcrs[1]))));
    printf("ofDateRAHours %.17g\n", hours(ri - eo));
    printf("ofDateDecDegrees %.17g\n", degrees(di));
    printf("eclipticLongitudeDegrees %.17g\n", degrees(iauAnp(atan2(ecliptic[1], ecliptic[0]))));
    printf("eclipticLatitudeDegrees %.17g\n", degrees(atan2(ecliptic[2], hypot(ecliptic[0], ecliptic[1]))));
    printf("azimuthDegrees %.17g\n", degrees(aob));
    printf("altitudeDegrees %.17g\n", 90.0 - degrees(zob));
    printf("topocentricRAHours %.17g\n", hours(rob - eo));
    printf("topocentricDecDegrees %.17g\n", degrees(dob));
    return 0;
}
