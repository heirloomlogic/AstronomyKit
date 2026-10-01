#define _POSIX_C_SOURCE 200809L

#include "astronomy.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_ITERATIONS 2000
#define DEFAULT_THREADS 8
#define CONSTELLATION_THREADS 64

typedef enum
{
    MODE_DELTA_T,
    MODE_PLUTO,
    MODE_COUNTERS,
    MODE_CONSTELLATION
}
probe_mode_t;

typedef struct
{
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    int arrived;
    int released;
    int total;
}
start_gate_t;

typedef struct
{
    start_gate_t *gate;
    probe_mode_t mode;
    int index;
    int iterations;
    int failed;
}
worker_context_t;

static start_gate_t constellation_gate;

static int StartGateInit(start_gate_t *gate, int total)
{
    memset(gate, 0, sizeof(*gate));
    gate->total = total;
    if (pthread_mutex_init(&gate->mutex, NULL) != 0)
        return 1;
    if (pthread_cond_init(&gate->condition, NULL) != 0)
    {
        pthread_mutex_destroy(&gate->mutex);
        return 1;
    }
    return 0;
}

static void StartGateDestroy(start_gate_t *gate)
{
    pthread_cond_destroy(&gate->condition);
    pthread_mutex_destroy(&gate->mutex);
}

static void StartGateRelease(start_gate_t *gate)
{
    pthread_mutex_lock(&gate->mutex);
    gate->released = 1;
    pthread_cond_broadcast(&gate->condition);
    pthread_mutex_unlock(&gate->mutex);
}

static int StartGateWait(start_gate_t *gate)
{
    if (pthread_mutex_lock(&gate->mutex) != 0)
        return 1;

    ++gate->arrived;
    if (gate->arrived == gate->total)
    {
        gate->released = 1;
        pthread_cond_broadcast(&gate->condition);
    }
    else
    {
        while (!gate->released)
        {
            if (pthread_cond_wait(&gate->condition, &gate->mutex) != 0)
            {
                pthread_mutex_unlock(&gate->mutex);
                return 1;
            }
        }
    }

    return pthread_mutex_unlock(&gate->mutex) != 0;
}

static double AlternateDeltaT(double ut)
{
    return Astronomy_DeltaT_EspenakMeeus(ut);
}

void AstronomyKit_ConstellationRaceHook(void)
{
    StartGateWait(&constellation_gate);
}

static void RunDeltaT(worker_context_t *context)
{
    int i;

    if (context->index == 0)
    {
        for (i = 0; i < context->iterations; ++i)
        {
            Astronomy_SetDeltaTFunction((i % 2) ? AlternateDeltaT : Astronomy_DeltaT_EspenakMeeus);
        }
    }
    else
    {
        for (i = 0; i < context->iterations; ++i)
            (void)Astronomy_TimeFromDays(10000.0 + i + context->index / 10.0);
    }
}

static void RunPluto(worker_context_t *context)
{
    int i;

    if (context->index == 0)
    {
        for (i = 0; i < context->iterations; ++i)
            Astronomy_Reset();
    }
    else
    {
        for (i = 0; i < context->iterations; ++i)
        {
            astro_time_t time = Astronomy_TimeFromDays(7300.0 + (i % 100));
            astro_vector_t vector = Astronomy_HelioVector(BODY_PLUTO, time);
            if (vector.status != ASTRO_SUCCESS)
            {
                context->failed = 1;
                return;
            }
        }
    }
}

static void RunCounters(worker_context_t *context)
{
    int i;

    for (i = 0; i < context->iterations; ++i)
    {
        astro_time_t time = Astronomy_TimeFromDays(20000.0 + context->index * context->iterations + i);
        astro_vector_t vector = Astronomy_GeoMoon(time);
        if (vector.status != ASTRO_SUCCESS)
        {
            context->failed = 1;
            return;
        }
    }
}

static void RunConstellation(worker_context_t *context)
{
    astro_constellation_t constellation = Astronomy_Constellation(5.92 + context->index / 1000.0, 7.41);
    if (constellation.status != ASTRO_SUCCESS)
        context->failed = 1;
}

static void *Worker(void *opaque)
{
    worker_context_t *context = (worker_context_t *)opaque;

    if (StartGateWait(context->gate))
    {
        context->failed = 1;
        return NULL;
    }

    switch (context->mode)
    {
    case MODE_DELTA_T:
        RunDeltaT(context);
        break;
    case MODE_PLUTO:
        RunPluto(context);
        break;
    case MODE_COUNTERS:
        RunCounters(context);
        break;
    case MODE_CONSTELLATION:
        RunConstellation(context);
        break;
    }

    return NULL;
}

static int RunThreads(probe_mode_t mode, int thread_count, int iterations)
{
    int i;
    int result = 0;
    int created = 0;
    pthread_t *threads = calloc((size_t)thread_count, sizeof(*threads));
    worker_context_t *contexts = calloc((size_t)thread_count, sizeof(*contexts));
    start_gate_t gate;

    if (threads == NULL || contexts == NULL || StartGateInit(&gate, thread_count))
    {
        fprintf(stderr, "failed to allocate or initialize probe state\n");
        free(threads);
        free(contexts);
        return 1;
    }

    if (mode == MODE_CONSTELLATION)
    {
        if (StartGateInit(&constellation_gate, thread_count))
        {
            fprintf(stderr, "failed to initialize constellation timing gate\n");
            StartGateDestroy(&gate);
            free(threads);
            free(contexts);
            return 1;
        }
    }

    for (i = 0; i < thread_count; ++i)
    {
        contexts[i].gate = &gate;
        contexts[i].mode = mode;
        contexts[i].index = i;
        contexts[i].iterations = iterations;
        if (pthread_create(&threads[i], NULL, Worker, &contexts[i]) != 0)
        {
            fprintf(stderr, "failed to create worker %d\n", i);
            result = 1;
            break;
        }
        ++created;
    }

    if (created != thread_count)
    {
        StartGateRelease(&gate);
        if (mode == MODE_CONSTELLATION)
            StartGateRelease(&constellation_gate);
    }

    for (i = 0; i < created; ++i)
    {
        if (pthread_join(threads[i], NULL) != 0 || contexts[i].failed)
            result = 1;
    }

    if (mode == MODE_CONSTELLATION)
        StartGateDestroy(&constellation_gate);

    StartGateDestroy(&gate);
    free(threads);
    free(contexts);
    Astronomy_SetDeltaTFunction(Astronomy_DeltaT_EspenakMeeus);
    Astronomy_Reset();
    return result;
}

static int ParseMode(const char *name, probe_mode_t *mode, int *thread_count, int *iterations)
{
    *thread_count = DEFAULT_THREADS;
    *iterations = DEFAULT_ITERATIONS;

    if (strcmp(name, "delta-t") == 0)
        *mode = MODE_DELTA_T;
    else if (strcmp(name, "pluto") == 0)
    {
        *mode = MODE_PLUTO;
        *iterations = 200;
    }
    else if (strcmp(name, "counters") == 0)
        *mode = MODE_COUNTERS;
    else if (strcmp(name, "constellation") == 0)
    {
        *mode = MODE_CONSTELLATION;
        *thread_count = CONSTELLATION_THREADS;
        *iterations = 1;
    }
    else
        return 1;

    return 0;
}

int main(int argc, char **argv)
{
    int thread_count;
    int iterations;
    probe_mode_t mode;

    if (argc != 2 || ParseMode(argv[1], &mode, &thread_count, &iterations))
    {
        fprintf(stderr, "usage: %s delta-t|pluto|counters|constellation\n", argv[0]);
        return 2;
    }

    return RunThreads(mode, thread_count, iterations);
}
