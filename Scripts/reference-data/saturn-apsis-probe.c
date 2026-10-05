#include <stdio.h>

/* Development-only controls access the full series without changing production evaluation. */
#include "../../Sources/CLibAstronomy/astronomy.c"

static double radius(double tt, int full)
{
    if (full)
    {
        double sphere[3];
        VsopCoords(&vsop[BODY_SATURN], tt / DAYS_PER_MILLENNIUM, sphere, NULL);
        return sphere[RAD_INDEX];
    }
    astro_func_result_t result = Astronomy_HelioDistance(BODY_SATURN, Astronomy_TerrestrialTime(tt));
    return result.status == ASTRO_SUCCESS ? result.value : NAN;
}

static double radial_rate(double tt, int full, double step)
{
    if (step > 0)
        return (radius(tt + step/2, full) - radius(tt - step/2, full)) / step;
    if (full)
    {
        double deriv[3];
        VsopDeriv(&vsop[BODY_SATURN], tt / DAYS_PER_MILLENNIUM, deriv, NULL);
        return deriv[RAD_INDEX] / DAYS_PER_MILLENNIUM;
    }
    double position[3], velocity[3];
    if (!PolynomialPosition(BODY_SATURN, tt, position, velocity))
        return radial_rate(tt, 1, 0);
    return (position[0]*velocity[0] + position[1]*velocity[1] + position[2]*velocity[2]) /
        sqrt(position[0]*position[0] + position[1]*position[1] + position[2]*position[2]);
}

static int root(double tt, int full, double step, double half_span, double tolerance_seconds,
                double *root_tt, double *width_seconds, int *direction, int *zero_evaluations)
{
    double lo = tt - half_span, hi = tt + half_span;
    double flo = radial_rate(lo, full, step), fhi = radial_rate(hi, full, step);
    if (!isfinite(flo) || !isfinite(fhi) || flo == 0 || fhi == 0) return 0;
    int crossings = 0;
    *zero_evaluations = 0;
    double previous = flo;
    /* A fixed local scan checks event identity independently of the bisection. */
    for (int i = 1; i <= 160; ++i)
    {
        double value = radial_rate(lo + (hi-lo)*i/160, full, step);
        if (!isfinite(value)) return 0;
        if (value == 0) { ++*zero_evaluations; continue; }
        if ((value > 0) != (previous > 0)) ++crossings;
        previous = value;
    }
    if (!isfinite(flo) || !isfinite(fhi) || crossings != 1 || (flo > 0) == (fhi > 0)) return 0;
    *direction = flo < 0 ? 1 : -1;
    for (int i = 0; i < 80 && (hi-lo)*86400 > tolerance_seconds; ++i)
    {
        double mid = lo + (hi-lo)/2;
        if (mid == lo || mid == hi) break;
        double value = radial_rate(mid, full, step);
        if (!isfinite(value)) return 0;
        if (value == 0) ++*zero_evaluations;
        if ((value > 0) == (flo > 0)) lo = mid;
        else hi = mid;
    }
    *root_tt = lo + (hi-lo)/2;
    *width_seconds = (hi-lo)*86400;
    return *width_seconds <= tolerance_seconds;
}

int main(void)
{
    double public_jd, reference_jd, half_span, tolerance;
    Astronomy_SetDeltaTFunction(Astronomy_DeltaT_JplHorizons);
    while (scanf("%lf %lf %lf %lf", &public_jd, &reference_jd, &half_span, &tolerance) == 4)
    {
        double tt = public_jd - 2451545.0, reference_tt = reference_jd - 2451545.0;
        if (!isfinite(tt) || !isfinite(reference_tt) || half_span != 10 || tolerance != 0.0001) return 64;
        astro_apsis_t event = Astronomy_SearchPlanetApsis(BODY_SATURN, Astronomy_TerrestrialTime(tt-half_span));
        if (event.status != ASTRO_SUCCESS) return 1;
        double polynomial[3];
        int covered = PolynomialPosition(BODY_SATURN, tt, polynomial, NULL);
        printf("{\"publicJulianDateTT\":%.17g,\"publicKind\":\"%s\",\"polynomialCovered\":%s,\"roots\":[",
            event.time.tt+2451545, event.kind == APSIS_PERICENTER ? "pericenter" : "apocenter", covered ? "true" : "false");
        for (int full = 0; full < 2; ++full)
        {
            const double steps[] = {0, 0.001, 0.01, 0.1};
            for (int i = 0; i < 4; ++i)
            {
                double root_tt, width;
                int direction, zeros;
                if (!root(tt, full, steps[i], half_span, tolerance, &root_tt, &width, &direction, &zeros)) return 1;
                printf("%s{\"evaluator\":\"%s\",\"method\":\"%s\",\"stepDays\":%.17g,\"julianDateTT\":%.17g,\"offsetFromArchivedPublicSeconds\":%.17g,\"bracketWidthSeconds\":%.17g,\"zeroSlopeEvaluations\":%d,\"kind\":\"%s\",\"rateAtArchivedPublicAUPerDay\":%.17g,\"rateAtArchivedReferenceAUPerDay\":%.17g}",
                    full == 0 && i == 0 ? "" : ",", full ? "full-series" : "production", i ? "finite-difference" : "analytic", steps[i], root_tt+2451545,
                    (root_tt-tt)*86400, width, zeros, direction == 1 ? "pericenter" : "apocenter", radial_rate(tt, full, steps[i]), radial_rate(reference_tt, full, steps[i]));
            }
        }
        printf("]}\n");
    }
    return ferror(stdin) ? 1 : 0;
}
