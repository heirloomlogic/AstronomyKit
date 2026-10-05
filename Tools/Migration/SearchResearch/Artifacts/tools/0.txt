/* Development-only, source-bound callback transcript adapter. */
#include "astronomy.c"
#include <stdint.h>
#include <string.h>

static int visits, cap, error_visit, first_error, initial, current;
static double base_ut, stamp, p[4];
static const char *fixture, *mutation;
static astro_deltat_func model_func(int model) { return model ? Astronomy_DeltaT_JplHorizons : Astronomy_DeltaT_EspenakMeeus; }
static const char *model_name(int model) { return model ? "jpl-horizons" : "espenak-meeus"; }
static void scalar(double x) {
    uint64_t bits;
    if (isnan(x)) printf("\"nan\"");
    else if (isinf(x)) printf("\"%sinf\"", signbit(x) ? "-" : "+");
    else { memcpy(&bits, &x, sizeof bits); printf("\"f64:%016llx\"", (unsigned long long)bits); }
}
static void time_json(astro_time_t t) {
    const char *name = t.deltat_func == model_func(0) ? model_name(0) : t.deltat_func == model_func(1) ? model_name(1) : "unidentified";
    printf("{\"ut\":"); scalar(t.ut); printf(",\"tt\":"); scalar(t.tt);
    printf(",\"model\":\"%s\",\"expectedCapturedTT\":", name);
    scalar(Astronomy_TimeFromDaysWithDeltaT(t.ut, model_func(initial)).tt); printf("}");
}
static double value(double u) {
    if (!strcmp(fixture,"linear")) return u - (p[0] + (!strcmp(mutation,"event-selection") ? 0.25 : 0));
    if (!strcmp(fixture,"descending")) return p[0]-u;
    if (!strcmp(fixture,"constant")) return p[0];
    if (!strcmp(fixture,"quadratic")) return u*u-p[0];
    if (!strcmp(fixture,"two-roots")) return (u-p[0])*(u-p[1]);
    if (!strcmp(fixture,"cubic")) return ((u-p[0])*(u-p[0]))*(u-p[0]);
    if (!strcmp(fixture,"step")) return u<p[0] ? -1 : 1;
    if (!strcmp(fixture,"scaled")) return (u-p[0])*p[1];
    abort();
}
static astro_time_t visit(astro_time_t t) {
    ++visits;
    if (visits>cap) { printf("{\"event\":\"research-cap\",\"visit\":%d}\n",visits); fflush(stdout); _Exit(75); }
    if (!strcmp(mutation,"time-default")) t=Astronomy_TimeFromDays(t.ut);
    printf("{\"event\":\"callback\",\"visit\":%d,\"time\":",visits); time_json(t);
    printf(",\"defaultBefore\":\"%s\",",model_name(current));
    current = visits%2 ? !initial : initial;
    Astronomy_SetDeltaTFunction(model_func(current));
    printf("\"defaultAfter\":\"%s\",\"result\":",model_name(current));
    return t;
}
static int raised(void) { if (visits==error_visit) { first_error=visits; printf("{\"kind\":\"raise\",\"visit\":%d}}\n",visits); return strcmp(mutation,"swallow-error")!=0; } return 0; }
static astro_func_result_t root(void *unused, astro_time_t t) {
    (void)unused; t=visit(t);
    if (raised()) return (astro_func_result_t){ASTRO_INTERNAL_ERROR,0};
    double x=value(t.ut-base_ut);
    if (visits!=error_visit) { printf("{\"kind\":\"scalar\",\"value\":"); scalar(x); printf("}}\n"); }
    return (astro_func_result_t){ASTRO_SUCCESS,x};
}
static astro_vector_t vector(void *unused, astro_time_t t) {
    (void)unused; t=visit(t);
    if (raised()) return (astro_vector_t){ASTRO_INTERNAL_ERROR,0,0,0,t};
    double x=p[0], y=p[1], z=p[2];
    if (!strcmp(fixture,"moving")) { x=p[0]+p[1]*(t.ut-base_ut); y=p[2]; z=p[3]; }
    if (!strcmp(fixture,"alternating")) { x=visits%2 ? 0 : 1; y=0; z=0; }
    astro_time_t supplied=Astronomy_AddDays(t,stamp);
    if (visits!=error_visit) { printf("{\"kind\":\"vector\",\"xyz\":["); scalar(x); printf(","); scalar(y); printf(","); scalar(z); printf("],\"suppliedTime\":"); time_json(supplied); printf("}}\n"); }
    return (astro_vector_t){ASTRO_SUCCESS,x,y,z,supplied};
}
int main(int argc, char **argv) {
    if (argc!=16) return 64;
    initial=!strcmp(argv[1],"jpl-horizons"); current=initial;
    fixture=argv[3]; base_ut=strtod(argv[4],0); error_visit=atoi(argv[8]); stamp=strtod(argv[9],0); cap=atoi(argv[10]); mutation=argv[11];
    for (int i=0;i<4;i++) p[i]=strtod(argv[12+i],0);
    Astronomy_SetDeltaTFunction(model_func(initial));
    astro_time_t base=Astronomy_TimeFromDaysWithDeltaT(base_ut,model_func(initial));
    astro_time_t start=Astronomy_AddDays(base,strtod(argv[5],0)), end=Astronomy_AddDays(base,strtod(argv[6],0));
    printf("{\"event\":\"begin\",\"initialModel\":\"%s\",\"start\":",model_name(initial)); time_json(start); printf(",\"end\":"); time_json(end); printf("}\n");
    if (!strcmp(argv[2],"root")) {
        astro_search_result_t r=Astronomy_Search(root,0,start,end,strtod(argv[7],0));
        const char *outcome=r.status==ASTRO_SUCCESS ? "value" : r.status==ASTRO_SEARCH_FAILURE ? "absent" : first_error && r.status==ASTRO_INTERNAL_ERROR ? "callback-error" : "algorithm-error";
        printf("{\"event\":\"terminal\",\"outcome\":\"%s\",\"rawStatus\":%d,\"visits\":%d,\"firstErrorVisit\":%d",outcome,r.status,visits,first_error);
        if (r.status==ASTRO_SUCCESS) { printf(",\"time\":"); time_json(r.time); } printf("}\n");
    } else {
        astro_vector_t r=Astronomy_CorrectLightTravel(0,vector,start);
        const char *outcome=r.status==ASTRO_SUCCESS ? "value" : first_error && r.status==ASTRO_INTERNAL_ERROR ? "callback-error" : "algorithm-error";
        printf("{\"event\":\"terminal\",\"outcome\":\"%s\",\"rawStatus\":%d,\"visits\":%d,\"firstErrorVisit\":%d",outcome,r.status,visits,first_error);
        if (r.status==ASTRO_SUCCESS) { printf(",\"xyz\":["); scalar(r.x); printf(","); scalar(r.y); printf(","); scalar(r.z); printf("],\"time\":"); time_json(r.t); } printf("}\n");
    }
    return 0;
}
