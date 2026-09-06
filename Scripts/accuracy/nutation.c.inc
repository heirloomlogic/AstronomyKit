/* AstronomyKit: full 77-term IAU2000B, replacing the upstream 5-term truncation. */
#include "generated/iau2000b_full.h"

static void iau2000b(astro_time_t *time)
{
    if ((time != NULL) && isnan(time->psi))
    {
        const double t = time->tt / 36525.0;
        /* Simon et al. fundamental arguments; IAU2000B uses the linear terms. */
        const double args[5] = {
            fmod(485868.249036 + t * 1717915923.2178, ASEC360) * ASEC2RAD,
            fmod(1287104.79305 + t * 129596581.0481, ASEC360) * ASEC2RAD,
            fmod(335779.526232 + t * 1739527262.8478, ASEC360) * ASEC2RAD,
            fmod(1072260.70369 + t * 1602961601.2090, ASEC360) * ASEC2RAD,
            fmod(450160.398036 + t * -6962890.5431, ASEC360) * ASEC2RAD
        };
        double dp = 0.0, de = 0.0;
        /* Sum smallest terms first, in a fixed order on every platform. */
        for (int i = 76; i >= 0; --i)
        {
            double arg = 0.0;
            for (int j = 0; j < 5; ++j)
                arg += iau2000b_terms[i].n[j] * args[j];
            const double sarg = sin(arg);
            const double carg = cos(arg);
            const double *c = iau2000b_terms[i].c;
            dp += (c[0] + c[1]*t)*sarg + c[2]*carg;
            de += (c[3] + c[4]*t)*carg + c[5]*sarg;
        }
        /* 0.1 microarcseconds -> arcseconds, with fixed planetary offsets. */
        time->psi = -0.000135 + dp * 1.0e-7;
        time->eps = +0.000388 + de * 1.0e-7;
    }
}

