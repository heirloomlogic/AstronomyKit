/* Immutable polynomial approximation of the full VSOP87B model.
 * Exact TT, no initialization or allocation; full series outside qualified coverage. */
#include "generated/polynomial-data.h"

static int PolynomialPosition(int body, double tt, double p[3], double *v)
{
    if (!(tt >= POLYNOMIAL_START && tt < POLYNOMIAL_STOP)) return 0;
    const polynomial_model_t *model = &polynomial_models[body];
    int segment = (int)((tt-POLYNOMIAL_START)/model->width);
    /* Subtraction can round a predecessor of a boundary up to that boundary. */
    if (segment > 0 && POLYNOMIAL_START + segment*model->width > tt) --segment;
    if (!model->valid[segment]) return 0;
    double start = POLYNOMIAL_START + segment*model->width;
    double half = model->width/2;
    double x = (tt-start)/half-1;
    int n = model->degree+1;
    const double *coefficients = model->coefficients + segment*3*n;
    for (int axis=0; axis<3; ++axis)
    {
        const double *a = coefficients + axis*n;
        double b1=0, b2=0, d1=0, d2=0;
        for (int k=model->degree; k>=1; --k)
        {
            double b = 2*x*b1-b2+a[k];
            if (v)
            {
                double d = 2*b1+2*x*d1-d2;
                d2=d1; d1=d;
            }
            b2=b1; b1=b;
        }
        p[axis] = x*b1-b2+a[0];
        if (v) v[axis]=(b1+x*d1-d2)/half;
    }
    return 1;
}
