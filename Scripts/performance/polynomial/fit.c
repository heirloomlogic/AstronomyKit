/* Offline diagnostic only. Include a frozen engine so static VSOP routines are
 * the source of truth; this translation unit is never shipped. */
#include "reference.c"
#include <time.h>

static void reference_rect(int body, double tt, double p[3], double v[3])
{
    double sphere[3], deriv[3];
    double t = tt / DAYS_PER_MILLENNIUM;
    VsopCoords(&vsop[body], t, sphere, NULL);
    VsopSphereToRect(sphere[0], sphere[1], sphere[2], p);
    if (v)
    {
        VsopDeriv(&vsop[body], t, deriv, NULL);
        double cl = cos(sphere[0]), sl = sin(sphere[0]);
        double cb = cos(sphere[1]), sb = sin(sphere[1]);
        double r = sphere[2], dr = deriv[2], db = deriv[1], dl = deriv[0];
        v[0] = ((dr*cb*cl)-(r*sb*cl*db)-(r*cb*sl*dl))/DAYS_PER_MILLENNIUM;
        v[1] = ((dr*cb*sl)+(r*cb*cl*dl)-(r*sb*sl*db))/DAYS_PER_MILLENNIUM;
        v[2] = ((dr*sb)+(r*cb*db))/DAYS_PER_MILLENNIUM;
    }
}

/* Coefficients are axis-major; c[0] already includes its half weight. */
void ak_poly_eval(const double *c, int degree, double x, double half,
                  double *p, double *v)
{
    for (int axis=0; axis<3; ++axis)
    {
        const double *a = c + axis*(degree+1);
        double b1=0, b2=0, d1=0, d2=0;
        for (int k=degree; k>=1; --k)
        {
            double b = 2*x*b1 - b2 + a[k];
            double d = 2*b1 + 2*x*d1 - d2;
            b2=b1; b1=b; d2=d1; d1=d;
        }
        p[axis] = x*b1-b2+a[0];
        v[axis] = (b1+x*d1-d2)/half;
    }
}

void ak_poly_fit_position(int body, double start, double width, int degree, double *c)
{
    double samples[100][3], center[3];
    int n=4*(degree+1);
    reference_rect(body, start+width/2, center, NULL);
    for (int j=0; j<n; ++j)
    {
        double x=cos(PI*(j+0.5)/n);
        reference_rect(body, start+(1+x)*(width/2), samples[j], NULL);
    }
    for (int axis=0; axis<3; ++axis)
        for (int k=0; k<=degree; ++k)
        {
            double sum=0;
            for (int j=0; j<n; ++j)
                sum += (samples[j][axis]-center[axis])*cos(PI*k*(j+0.5)/n);
            c[axis*(degree+1)+k] = sum*((k==0 ? 1.0 : 2.0)/n);
            if (k==0) c[axis*(degree+1)] += center[axis];
        }
}

/* Fit analytic velocity and integrate, anchoring position at the midpoint.
 * This avoids differentiating the full evaluator's position roundoff. The
 * runtime still evaluates one position polynomial and its exact derivative. */
void ak_poly_fit(int body, double start, double width, int degree, double *c)
{
    double samples[100][3], center[3], unused[3];
    int n=4*(degree+1), stride=degree+1;
    reference_rect(body, start+width/2, center, NULL);
    for (int j=0; j<n; ++j)
    {
        double x=cos(PI*(j+0.5)/n);
        reference_rect(body, start+(1+x)*(width/2), unused, samples[j]);
    }
    for (int axis=0; axis<3; ++axis)
    {
        double *a=c+axis*stride;
        for (int k=0; k<=degree; ++k) a[k]=0;
        for (int k=0; k<degree; ++k)
        {
            double sum=0;
            for (int j=0; j<n; ++j)
                sum += samples[j][axis]*cos(PI*k*(j+0.5)/n);
            double q=sum*((k==0 ? 1.0 : 2.0)/n)*(width/2);
            if (k==0) a[1]+=q;
            else if (k==1) a[2]+=q/4;
            else { a[k+1]+=q/(2*(k+1)); a[k-1]-=q/(2*(k-1)); }
        }
        double at_center=0;
        for (int k=2; k<=degree; k+=2) at_center += ((k/2)%2 ? -a[k] : a[k]);
        a[0]=center[axis]-at_center;
    }
}

/* Return maxima over the frozen sample population, plus sample count. */
void ak_poly_check(int body, double start, double width, int degree,
                   const double *c, double *errors)
{
    double dates[51];
    dates[0]=start; dates[1]=start+width;
    dates[2]=nextafter(start, INFINITY);
    dates[3]=nextafter(start+width, -INFINITY);
    for (int i=1; i<=31; ++i) dates[3+i]=start+width*i/32;
    uint32_t seed=20260907;
    for (int i=0; i<16; ++i)
    {
        seed=1664525*seed+1013904223;
        dates[35+i]=start+width*((seed+0.5)/4294967296.0);
    }
    errors[0]=errors[1]=0; errors[2]=51;
    for (int i=0; i<51; ++i)
    {
        double p[3],v[3],rp[3],rv[3];
        reference_rect(body, dates[i], rp, rv);
        ak_poly_eval(c, degree, (dates[i]-start)/(width/2)-1, width/2, p, v);
        for (int k=0; k<3; ++k)
        {
            double ep=fabs(p[k]-rp[k]), ev=fabs(v[k]-rv[k]);
            if (!isfinite(ep) || !isfinite(ev)) { errors[0]=errors[1]=INFINITY; return; }
            if (ep>errors[0]) errors[0]=ep;
            if (ev>errors[1]) errors[1]=ev;
        }
    }
}

double ak_poly_bench(int degree)
{
    double c[75],p[3],v[3];
    volatile double checksum=0;
    for (int i=0; i<75; ++i) c[i]=1.0/(1+i);
    clock_t start=clock();
    for (int i=0; i<200000; ++i)
    {
        ak_poly_eval(c,degree,(i%997)/498.0-1,4,p,v);
        checksum += p[0]+v[1];
    }
    return (double)(clock()-start)/CLOCKS_PER_SEC;
}
