/* Diagnostic ABI only: not part of the shipping library. */
#include "astronomy.h"
#include <math.h>

static int sample_at(int body, astro_time_t time, int mode, double *output)
{
    astro_ecliptic_t e;
    if (body == BODY_MOON)
    {
        astro_spherical_t m = Astronomy_EclipticGeoMoon(time);
        output[0] = m.lon;
        output[1] = m.lat;
        output[2] = time.tt;
        return m.status;
    }
    else if (body == BODY_SUN)
        e = Astronomy_SunPosition(time);
    else
    {
        astro_vector_t v = Astronomy_GeoVector((astro_body_t)body, time, ABERRATION);
        if (v.status != ASTRO_SUCCESS) return v.status;
        if (mode == 1)
        {
            astro_rotation_t r = Astronomy_Rotation_EQJ_EQD(&time);
            v = Astronomy_RotateVector(r, v);
            /* AstrologyKit's production baseline uses fixed mean obliquity. */
            const double eps = 23.4393 * 0.017453292519943295;
            double y = cos(eps)*v.y + sin(eps)*v.z;
            double z = -sin(eps)*v.y + cos(eps)*v.z;
            output[0] = atan2(y, v.x) * 57.29577951308232;
            if (output[0] < 0) output[0] += 360;
            output[1] = atan2(z, hypot(v.x, y)) * 57.29577951308232;
            output[2] = time.tt;
            return v.status;
        }
        e = Astronomy_Ecliptic(v);
    }
    output[0] = e.elon;
    output[1] = e.elat;
    output[2] = time.tt;
    return e.status;
}

int ak_sample(int body, double ut, int mode, double *output)
{
    return sample_at(body, Astronomy_TimeFromDays(ut), mode, output);
}

int ak_sample_tt(int body, double tt, int mode, double *output)
{
    return sample_at(body, Astronomy_TerrestrialTime(tt), mode, output);
}

int ak_components(int body, double ut, int mode, double *output)
{
    astro_time_t time = Astronomy_TimeFromDays(ut);
    astro_vector_t v;
    if (mode <= 1)
        v = Astronomy_GeoVector((astro_body_t)body, time, mode == 0 ? ABERRATION : NO_ABERRATION);
    else
    {
        v = Astronomy_HelioVector((astro_body_t)body, time);
        if (mode == 2)
        {
            astro_vector_t earth = Astronomy_HelioVector(BODY_EARTH, time);
            if (earth.status != ASTRO_SUCCESS) return earth.status;
            v.x -= earth.x;
            v.y -= earth.y;
            v.z -= earth.z;
        }
    }
    if (v.status != ASTRO_SUCCESS) return v.status;
    astro_ecliptic_t e = Astronomy_Ecliptic(v);
    output[0] = e.elon;
    output[1] = e.elat;
    output[2] = time.tt;
    return e.status;
}

void ak_nutation(double tt, double *output)
{
    astro_time_t time = Astronomy_TimeFromDays(0);
    time.tt = tt;
    Astronomy_SiderealTime(&time); /* populates the time's nutation cache */
    output[0] = time.psi;
    output[1] = time.eps;
}
