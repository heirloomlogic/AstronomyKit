#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "astronomy.h"

static uint64_t bits(double value)
{
    uint64_t result;
    memcpy(&result, &value, sizeof(result));
    return result;
}

static void print_double(double value)
{
    printf(" %016llx", (unsigned long long)bits(value));
}

static void print_time(astro_time_t time)
{
    print_double(time.ut);
    print_double(time.tt);
    print_double(time.psi);
    print_double(time.eps);
    print_double(time.st);
}

int main(void)
{
    static const double epochs[] = {-40000.25, -0.0, 0.0, 12345.625, 40000.75};
    unsigned i;

    for (i = 0; i < sizeof(epochs) / sizeof(epochs[0]); ++i)
    {
        astro_time_t time = Astronomy_TimeFromDays(epochs[i]);
        astro_vector_t vector = Astronomy_GeoMoon(time);
        astro_spherical_t sphere = Astronomy_EclipticGeoMoon(time);
        astro_state_vector_t state = Astronomy_GeoMoonState(time);
        astro_ecliptic_state_t ecliptic_state = Astronomy_MoonEclipticState(time);
        astro_libration_t libration = Astronomy_Libration(time);
        astro_angle_result_t phase = Astronomy_MoonPhase(time);

        printf("%d", vector.status);
        print_double(vector.x); print_double(vector.y); print_double(vector.z); print_time(vector.t);
        printf(" %d", sphere.status);
        print_double(sphere.lon); print_double(sphere.lat); print_double(sphere.dist);
        printf(" %d", state.status);
        print_double(state.x); print_double(state.y); print_double(state.z);
        print_double(state.vx); print_double(state.vy); print_double(state.vz); print_time(state.t);
        printf(" %d", ecliptic_state.status);
        print_double(ecliptic_state.elon); print_double(ecliptic_state.elat); print_double(ecliptic_state.dist);
        print_double(ecliptic_state.elon_rate); print_double(ecliptic_state.elat_rate); print_double(ecliptic_state.dist_rate);
        print_double(ecliptic_state.x); print_double(ecliptic_state.y); print_double(ecliptic_state.z);
        print_double(ecliptic_state.vx); print_double(ecliptic_state.vy); print_double(ecliptic_state.vz);
        print_time(ecliptic_state.t);
        print_double(libration.elat); print_double(libration.elon);
        print_double(libration.mlat); print_double(libration.mlon);
        print_double(libration.dist_km); print_double(libration.diam_deg);
        printf(" %d", phase.status); print_double(phase.angle);
        putchar('\n');
    }
    return 0;
}
