/* Exercise the shipped dispatch, including the full-model fallback. */
#include "baseline.c"
#include "polynomial.h"

static body_state_t candidate_state(int body, double tt)
{
    double p[3], v[3];
    body_state_t result;
    if (!PolynomialPosition(body,tt,p,v)) return CalcVsopPosVel(&vsop[body],tt);
    result.tt=tt; result.r=VsopRotate(p); result.v=VsopRotate(v);
    return result;
}

static double budget(double a) { return fmax(1e-12,fabs(a)*1e-12); }

/* result: positions checked, maximum component budget ratio, maximum stencil ratio. */
void ak_check_seams(int body, double *result, unsigned char *invalid)
{
    const polynomial_model_t *m = &polynomial_models[body];
    int count=(int)ceil((POLYNOMIAL_STOP-POLYNOMIAL_START)/m->width);
    const double widths[]={.0007,.01,.02,.04};
    for (int i=0;i<=count;++i)
    {
        double tt=i==count ? POLYNOMIAL_STOP : POLYNOMIAL_START+i*m->width;
        double dates[]={nextafter(tt,-INFINITY),tt,nextafter(tt,INFINITY)};
        for (int j=0;j<3;++j)
        {
            body_state_t a=CalcVsopPosVel(&vsop[body],dates[j]);
            body_state_t b=candidate_state(body,dates[j]);
            double x[]={a.r.x,a.r.y,a.r.z,a.v.x,a.v.y,a.v.z};
            double y[]={b.r.x,b.r.y,b.r.z,b.v.x,b.v.y,b.v.z};
            for (int k=0;k<6;++k)
            {
                double ratio=fabs(x[k]-y[k])/budget(x[k]);
                result[1]=fmax(result[1],ratio);
                if (ratio>1 && dates[j]>=POLYNOMIAL_START && dates[j]<POLYNOMIAL_STOP)
                {
                    int segment=(int)((dates[j]-POLYNOMIAL_START)/m->width);
                    if (segment>0 && POLYNOMIAL_START+segment*m->width>dates[j]) --segment;
                    invalid[segment]=1;
                }
            }
            result[0]+=1;
        }
        for (int j=0;j<4;++j)
        {
            double w=widths[j];
            body_state_t a=CalcVsopPosVel(&vsop[body],tt-w/2), b=CalcVsopPosVel(&vsop[body],tt+w/2);
            body_state_t c=candidate_state(body,tt-w/2), d=candidate_state(body,tt+w/2);
            double lo[]={a.r.x,a.r.y,a.r.z},hi[]={b.r.x,b.r.y,b.r.z};
            double cl[]={c.r.x,c.r.y,c.r.z},ch[]={d.r.x,d.r.y,d.r.z};
            for (int k=0;k<3;++k)
                result[2]=fmax(result[2],fabs((hi[k]-lo[k])/w-(ch[k]-cl[k])/w)/((budget(lo[k])+budget(hi[k]))/w));
        }
    }
}
