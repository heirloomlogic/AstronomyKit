#include <math.h>
#include <stdio.h>

#include "sofa.h"

int main(void)
{
    double date, vector[3];
    while (scanf("%lf %lf %lf %lf", &date, &vector[0], &vector[1], &vector[2]) == 4) {
        double matrix[3][3], true_equatorial[3], dpsi, deps;
        iauPnm80(2451545.0, date - 2451545.0, matrix);
        iauRxp(matrix, vector, true_equatorial);
        iauNut80(2451545.0, date - 2451545.0, &dpsi, &deps);
        double obliquity = iauObl80(2451545.0, date - 2451545.0) + deps;
        double y = true_equatorial[1] * cos(obliquity) + true_equatorial[2] * sin(obliquity);
        double longitude = atan2(y, true_equatorial[0]) * 180.0 / 3.14159265358979323846;
        if (longitude < 0.0) {
            longitude += 360.0;
        }
        printf("%.17g %.17g\n", date, longitude);
    }
    return ferror(stdin) || ferror(stdout);
}
