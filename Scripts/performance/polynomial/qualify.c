/* Offline qualification against the native full-model reference. */
#include "baseline.c"
#include "qualify-runtime.h"

static double budget_ratio(double a, double b)
{
    return fabs(a-b) / fmax(1e-12, fabs(a)*1e-12);
}

/* 51 interior samples plus adjacent representable endpoint values. */
double ak_qualify_segment(int body, int segment, double *worst_tt)
{
    const polynomial_model_t *m = &polynomial_models[body];
    double start = POLYNOMIAL_START + segment*m->width;
    double stop = fmin(start+m->width, POLYNOMIAL_STOP);
    double largest = 0;
    for (int j=0; j<53; ++j)
    {
        double tt = j<51 ? start+(stop-start)*j/51 :
            (j==51 ? nextafter(start, stop) : nextafter(stop, start));
        double p[3], v[3];
        if (!PolynomialPosition(body,tt,p,v)) return -1;
        body_state_t ref = CalcVsopPosVel(&vsop[body],tt);
        terse_vector_t pos = VsopRotate(p), vel = VsopRotate(v);
        double actual[6] = {pos.x,pos.y,pos.z,vel.x,vel.y,vel.z};
        double expected[6] = {ref.r.x,ref.r.y,ref.r.z,ref.v.x,ref.v.y,ref.v.z};
        double ratio=0;
        for (int k=0;k<6;++k) ratio=fmax(ratio,budget_ratio(expected[k],actual[k]));
        astro_time_t time = {0}; time.tt=tt;
        double radius=sqrt(p[0]*p[0]+p[1]*p[1]+p[2]*p[2]);
        ratio=fmax(ratio,budget_ratio(VsopHelioDistance(&vsop[body],time),radius));
        if (ratio>largest) { largest=ratio; *worst_tt=tt; }
    }
    return largest;
}

/* Replay a frozen request population: 24-byte little-endian
 * {uint32 thread; int32 kind; int32 body; int32 active; double tt} records at their
 * exact consumed TT. Returns the number of records actually evaluated. */
long ak_qualify_requests(const unsigned char *records, long count, double max_ratio[8],
                         long failures[], double failure_ratio[], long capacity)
{
    long evaluated=0, found=0;
    for (long i=0; i<count; ++i)
    {
        const unsigned char *record = records + i*24;
        int kind, body; double tt;
        memcpy(&kind, record+4, sizeof kind);
        memcpy(&body, record+8, sizeof body);
        memcpy(&tt, record+16, sizeof tt);
        if (body<0 || body>7 || kind<0 || kind>2) continue;
        if (!(tt >= POLYNOMIAL_START && tt < POLYNOMIAL_STOP)) continue;
        const polynomial_model_t *m = &polynomial_models[body];
        int segment = (int)((tt-POLYNOMIAL_START)/m->width);
        /* Subtraction can round a predecessor of a boundary up to that boundary. */
        if (segment > 0 && POLYNOMIAL_START + segment*m->width > tt) --segment;
        double p[3], v[3];
        if (!PolynomialPosition(body,tt,p,v)) continue;
        double ratio=0;
        if (kind==2)
        {
            astro_time_t time = {0}; time.tt=tt;
            double radius=sqrt(p[0]*p[0]+p[1]*p[1]+p[2]*p[2]);
            ratio=budget_ratio(VsopHelioDistance(&vsop[body],time),radius);
        }
        else
        {
            body_state_t ref = CalcVsopPosVel(&vsop[body],tt);
            terse_vector_t pos = VsopRotate(p), vel = VsopRotate(v);
            double actual[6] = {pos.x,pos.y,pos.z,vel.x,vel.y,vel.z};
            double expected[6] = {ref.r.x,ref.r.y,ref.r.z,ref.v.x,ref.v.y,ref.v.z};
            for (int k=0; k<(kind==1?6:3); ++k) ratio=fmax(ratio,budget_ratio(expected[k],actual[k]));
        }
        ++evaluated;
        if (ratio>max_ratio[body]) max_ratio[body]=ratio;
        if (ratio>1 && found<capacity)
        {
            failures[found]=body*1000000L+segment;
            failure_ratio[found]=ratio;
            ++found;
        }
    }
    return evaluated;
}
