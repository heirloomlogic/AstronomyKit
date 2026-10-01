#include "astronomy.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *status_name(astro_status_t status)
{
    switch (status)
    {
    case ASTRO_SUCCESS: return "success";
    case ASTRO_BAD_TIME: return "bad-time";
    case ASTRO_INVALID_BODY: return "invalid-body";
    case ASTRO_INVALID_PARAMETER: return "invalid-parameter";
    default: return "astronomy-error";
    }
}

static astro_deltat_func model_function(const char *name)
{
    if (strcmp(name, "espenak-meeus") == 0) return Astronomy_DeltaT_EspenakMeeus;
    if (strcmp(name, "jpl-horizons") == 0) return Astronomy_DeltaT_JplHorizons;
    return NULL;
}

static astro_time_t make_time(const char *scale, const char *value, astro_deltat_func model)
{
    double days = strtod(value, NULL);
    if (strcmp(scale, "tt") == 0) return Astronomy_TerrestrialTimeWithDeltaT(days, model);
    return Astronomy_TimeFromDaysWithDeltaT(days, model);
}

static void print_time(astro_time_t time)
{
    printf("{\"tt\":%.17g,\"ut\":%.17g}", time.tt, time.ut);
}

static int run_vector(const char *operation, int body, astro_time_t time, int repetitions, const char *model)
{
    int index;
    astro_status_t status = ASTRO_SUCCESS;
    printf("{\"model\":\"%s\",\"samples\":[", model);
    for (index = 0; index < repetitions; ++index)
    {
        if (index != 0) printf(",");
        if (strcmp(operation, "position") == 0)
        {
            astro_vector_t vector = Astronomy_HelioVector((astro_body_t)body, time);
            status = vector.status;
            if (status != ASTRO_SUCCESS) break;
            printf("{\"time\":");
            print_time(time);
            printf(",\"value\":{\"x\":%.17g,\"y\":%.17g,\"z\":%.17g}}", vector.x, vector.y, vector.z);
        }
        else if (strcmp(operation, "state") == 0)
        {
            astro_state_vector_t state = Astronomy_HelioState((astro_body_t)body, time);
            status = state.status;
            if (status != ASTRO_SUCCESS) break;
            printf("{\"time\":");
            print_time(time);
            printf(",\"value\":{\"vx\":%.17g,\"vy\":%.17g,\"vz\":%.17g,\"x\":%.17g,\"y\":%.17g,\"z\":%.17g}}", state.vx, state.vy, state.vz, state.x, state.y, state.z);
        }
        else
        {
            astro_func_result_t distance = Astronomy_HelioDistance((astro_body_t)body, time);
            status = distance.status;
            if (status != ASTRO_SUCCESS) break;
            printf("{\"time\":");
            print_time(time);
            printf(",\"value\":{\"distance\":%.17g}}", distance.value);
        }
    }
    if (status == ASTRO_SUCCESS) printf("],\"status\":\"success\"}\n");
    else printf("],\"status\":\"%s\"}\n", status_name(status));
    return 0;
}

static int run_seasons(int year, const char *model)
{
    astro_seasons_t seasons = Astronomy_Seasons(year);
    const char *names[] = {"March Equinox", "June Solstice", "September Equinox", "December Solstice"};
    astro_time_t times[] = {seasons.mar_equinox, seasons.jun_solstice, seasons.sep_equinox, seasons.dec_solstice};
    int index;
    printf("{\"events\":[");
    if (seasons.status == ASTRO_SUCCESS)
    {
        for (index = 0; index < 4; ++index)
        {
            if (index != 0) printf(",");
            printf("{\"name\":\"%s\",\"time\":", names[index]);
            print_time(times[index]);
            printf("}");
        }
    }
    printf("],\"model\":\"%s\",\"status\":\"%s\"}\n", model, status_name(seasons.status));
    return 0;
}

static int run_star(char **argv, const char *model)
{
    astro_time_t time = Astronomy_TimeFromDaysWithDeltaT(strtod(argv[2], NULL), model_function(model));
    astro_status_t status = Astronomy_DefineStar(BODY_STAR1, strtod(argv[3], NULL), strtod(argv[4], NULL), strtod(argv[5], NULL));
    astro_ecliptic_t ecliptic;
    double distance;
    if (status == ASTRO_SUCCESS) ecliptic = Astronomy_Ecliptic(Astronomy_GeoVector(BODY_STAR1, time, ABERRATION));
    if (status == ASTRO_SUCCESS) status = ecliptic.status;
    distance = status == ASTRO_SUCCESS ? sqrt(ecliptic.vec.x * ecliptic.vec.x + ecliptic.vec.y * ecliptic.vec.y + ecliptic.vec.z * ecliptic.vec.z) : 0.0;
    printf("{\"model\":\"%s\",\"samples\":[", model);
    if (status == ASTRO_SUCCESS)
    {
        printf("{\"time\":");
        print_time(time);
        printf(",\"value\":{\"distance\":%.17g,\"latitude\":%.17g,\"longitude\":%.17g}}", distance, ecliptic.elat, ecliptic.elon);
    }
    printf("],\"status\":\"%s\"}\n", status_name(status));
    return 0;
}

static int run_gravity(char **argv, const char *model)
{
    astro_deltat_func function = model_function(model);
    astro_time_t start = Astronomy_TimeFromDaysWithDeltaT(strtod(argv[2], NULL), function);
    astro_time_t target = Astronomy_TimeFromDaysWithDeltaT(strtod(argv[3], NULL), function);
    astro_state_vector_t state = {ASTRO_SUCCESS, strtod(argv[4], NULL), strtod(argv[5], NULL), strtod(argv[6], NULL), strtod(argv[7], NULL), strtod(argv[8], NULL), strtod(argv[9], NULL), start};
    astro_grav_sim_t *simulation = NULL;
    astro_status_t status = Astronomy_GravSimInit(&simulation, BODY_SUN, start, 1, &state);
    if (status == ASTRO_SUCCESS) status = Astronomy_GravSimUpdate(simulation, target, 1, &state);
    printf("{\"model\":\"%s\",\"samples\":[", model);
    if (status == ASTRO_SUCCESS)
    {
        printf("{\"time\":");
        print_time(target);
        printf(",\"value\":{\"vx\":%.17g,\"vy\":%.17g,\"vz\":%.17g,\"x\":%.17g,\"y\":%.17g,\"z\":%.17g}}", state.vx, state.vy, state.vz, state.x, state.y, state.z);
    }
    printf("],\"status\":\"%s\"}\n", status_name(status));
    if (simulation != NULL) Astronomy_GravSimFree(simulation);
    return 0;
}

static int run_chiron(char **argv, const char *model)
{
    astro_deltat_func function = model_function(model);
    astro_time_t epoch = Astronomy_TerrestrialTimeWithDeltaT(7304.5 + 69.184 / 86400.0, function);
    astro_time_t target = Astronomy_TimeFromDaysWithDeltaT(strtod(argv[2], NULL), function);
    astro_state_vector_t state = {ASTRO_SUCCESS, 18.74979015626275, 0.9060856547258316, 1.445166327129911, -5.188250744254794e-05, 2.988627504002276e-03, 9.318734038577373e-04, epoch};
    astro_grav_sim_t *simulation = NULL;
    astro_status_t status = Astronomy_GravSimInit(&simulation, BODY_SUN, epoch, 1, &state);
    if (status == ASTRO_SUCCESS) status = Astronomy_GravSimUpdate(simulation, target, 1, &state);
    printf("{\"model\":\"%s\",\"samples\":[", model);
    if (status == ASTRO_SUCCESS)
    {
        printf("{\"time\":");
        print_time(target);
        printf(",\"value\":{\"x\":%.17g,\"y\":%.17g,\"z\":%.17g}}", state.x, state.y, state.z);
    }
    printf("],\"status\":\"%s\"}\n", status_name(status));
    if (simulation != NULL) Astronomy_GravSimFree(simulation);
    return 0;
}

int main(int argc, char **argv)
{
    const char *operation;
    const char *model;
    astro_deltat_func function;
    if (argc == 2 && strcmp(argv[1], "--smoke") == 0)
    {
        astro_vector_t vector = Astronomy_HelioVector(BODY_EARTH, Astronomy_TimeFromDays(0.0));
        printf("%s %s\n", vector.status == ASTRO_SUCCESS ? "ASTRO_SUCCESS" : "ASTRO_FAILURE", isfinite(vector.x) && isfinite(vector.y) && isfinite(vector.z) ? "finite" : "nonfinite");
        return vector.status == ASTRO_SUCCESS && isfinite(vector.x) && isfinite(vector.y) && isfinite(vector.z) ? 0 : 1;
    }
    if (argc < 4)
    {
        fprintf(stderr, "invalid comparison request\n");
        return 64;
    }
    operation = argv[1];
    model = argv[argc - 1];
    function = model_function(model);
    if (function == NULL)
    {
        fprintf(stderr, "invalid delta-t model\n");
        return 64;
    }
    Astronomy_SetDeltaTFunction(function);
    if ((strcmp(operation, "position") == 0 || strcmp(operation, "state") == 0 || strcmp(operation, "distance") == 0) && argc == 7)
        return run_vector(operation, atoi(argv[2]), make_time(argv[3], argv[4], function), atoi(argv[5]), model);
    if (strcmp(operation, "seasons") == 0 && argc == 4) return run_seasons(atoi(argv[2]), model);
    if (strcmp(operation, "star") == 0 && argc == 7) return run_star(argv, model);
    if (strcmp(operation, "gravity") == 0 && argc == 11) return run_gravity(argv, model);
    if (strcmp(operation, "chiron") == 0 && argc == 4) return run_chiron(argv, model);
    fprintf(stderr, "invalid comparison request\n");
    return 64;
}
