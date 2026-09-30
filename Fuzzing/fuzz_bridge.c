/*
    fuzz_bridge.c - libFuzzer harness for the vendored Astronomy Engine C library.

    Decodes the fuzz input into doubles, integers, and enum values, then calls
    the C entry points that the Swift layer forwards user-controlled numbers
    into. The oracle is "returns a status code, and a position that reports
    success is finite": a crash, sanitizer report, unknown status value,
    non-finite successful position, or timeout is a finding.

    See README.md in this directory for the input format, build modes, and
    how to reproduce a finding.
*/

#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "astronomy.h"

/* Reads fields from the fuzz input. Reading past the end yields zero bytes, so
   every input, including the empty one, decodes to a complete set of fields. */
typedef struct
{
    const uint8_t *data;
    size_t size;
    size_t pos;
}
reader_t;

static uint8_t TakeByte(reader_t *reader)
{
    return (reader->pos < reader->size) ? reader->data[reader->pos++] : 0;
}

static uint64_t TakeLittleEndian(reader_t *reader, int count)
{
    uint64_t value = 0;
    for (int i = 0; i < count; ++i)
        value |= (uint64_t)TakeByte(reader) << (8 * i);
    return value;
}

/* Values at the edges of the engine's domains: non-finite values, extremes,
   angle and hour boundaries, the ends of the Pluto state table and its crawl
   guard, and times where adding the rise/set step no longer changes a double. */
static const double SpecialValues[] =
{
    0.0, -0.0, 1.0, -1.0, 0.5,
    90.0, -90.0, 89.99999999999999, -89.99999999999999, 90.00000000000001,
    180.0, -180.0, 360.0, -360.0, 24.0, 23.999999999999996,
    NAN, -NAN, INFINITY, -INFINITY,
    DBL_MAX, -DBL_MAX, DBL_MIN, -DBL_MIN, 4.9406564584124654e-324, DBL_EPSILON,
    1.0e300, -1.0e300, 1.0e-300,
    9007199254740992.0, -9007199254740992.0, 1.0e16, -1.0e16,
    1.0e9, -1.0e9, 2147483647.0, -2147483648.0, 4294967296.0,
    -730000.0, 730000.0, -766525.0, 766525.0, -766525.5, 766525.5,
    36525.0, -36525.0, 3652500.0, -3652500.0,
    366.0, -366.0, 0.42, -0.42, 100000.0, -500.0, 100000.5, -500.5,
    3.141592653589793, 6.283185307179586, 1.0e-9, -1.0e-9, 1.0e-15,
    63241.07708426628, 0.9999999999999999, 1.0000000000000002,
};

#define NUM_SPECIAL_VALUES (sizeof(SpecialValues) / sizeof(SpecialValues[0]))

/* A double is one tag byte followed by its payload. The low two bits of the tag
   select the encoding; the rest of the tag is used by the special-value case so
   a single byte reaches every entry in the table. */
static double TakeDouble(reader_t *reader)
{
    uint8_t tag = TakeByte(reader);
    uint64_t bits;
    double value;

    switch (tag & 3)
    {
    case 0:     /* raw IEEE 754 bits, little-endian: any double, any NaN payload */
        bits = TakeLittleEndian(reader, 8);
        memcpy(&value, &bits, sizeof(value));
        return value;

    case 1:     /* an edge value */
        return SpecialValues[(tag >> 2) % NUM_SPECIAL_VALUES];

    case 2:     /* small signed value in steps of 1/256 */
        return (double)(int16_t)TakeLittleEndian(reader, 2) / 256.0;

    default:    /* signed 32-bit integer */
        return (double)(int32_t)TakeLittleEndian(reader, 4);
    }
}

/* Every body the engine defines, followed by values outside the enum. */
static const int BodyValues[] =
{
    BODY_MERCURY, BODY_VENUS, BODY_EARTH, BODY_MARS, BODY_JUPITER, BODY_SATURN,
    BODY_URANUS, BODY_NEPTUNE, BODY_PLUTO, BODY_SUN, BODY_MOON, BODY_EMB, BODY_SSB,
    BODY_STAR1, BODY_STAR2, BODY_STAR3, BODY_STAR4, BODY_STAR5, BODY_STAR6,
    BODY_STAR7, BODY_STAR8,
    BODY_INVALID, -2, BODY_SSB + 1, BODY_SSB + 2, BODY_STAR1 - 1, BODY_STAR8 + 1,
    BODY_STAR8 + 2, 255, 1000, INT_MIN, INT_MAX,
};

static astro_body_t TakeBody(reader_t *reader)
{
    return (astro_body_t)BodyValues[TakeByte(reader) % (sizeof(BodyValues) / sizeof(BodyValues[0]))];
}

/* For the two-valued enums astro_aberration_t and astro_equator_date_t:
   0 and 1 are valid, the rest are outside the enum. */
static int TakeEnum(reader_t *reader)
{
    static const int values[] = { 0, 1, 2, -2, INT_MIN, INT_MAX };
    return values[TakeByte(reader) % (sizeof(values) / sizeof(values[0]))];
}

static void CheckStatus(astro_status_t status, const char *function)
{
    /* The engine reports every failure through astro_status_t. Any value
       outside the enum means a result struct was returned uninitialized. */
    if ((int)status < (int)ASTRO_SUCCESS || (int)status > (int)ASTRO_INCONSISTENT_TIMES)
    {
        fprintf(stderr, "%s returned unknown status %d\n", function, (int)status);
        abort();
    }
}

/* Positions, distances, and apsides report ASTRO_BAD_TIME rather than
   success when their result is not finite (MAINTAINING.md, patch 16). */
static void CheckFiniteSuccess(astro_status_t status, double a, double b, double c, const char *function)
{
    CheckStatus(status, function);
    if (status == ASTRO_SUCCESS && !(isfinite(a) && isfinite(b) && isfinite(c)))
    {
        fprintf(stderr, "%s succeeded with a non-finite result\n", function);
        abort();
    }
}

/* The same check as Swift's Observer.validatedRaw(). Only the rise/set search
   is limited to it; see "Restrictions" in README.md. */
static int SwiftAcceptsObserver(astro_observer_t observer)
{
    return isfinite(observer.latitude) && isfinite(observer.longitude) && isfinite(observer.height)
        && observer.latitude >= -90.0 && observer.latitude <= 90.0;
}

/* The rise/set search evaluates the body's altitude every 0.42 days of its
   window, so a large finite limit is slow by design, not hung: 10^9 days is
   about 2.4 billion evaluations. Non-finite limits are still fuzzed, and so is
   every start time. 400 days covers the Swift default of 366. */
static int RiseSetWithinCostBound(double limit_days)
{
    return !isfinite(limit_days) || fabs(limit_days) <= 400.0;
}

/* Keeps results observable so the calls cannot be optimized away. */
static volatile double Sink;

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    reader_t reader = { data, size, 0 };
    uint8_t flags;
    double star_ra, star_dec, star_dist;
    astro_time_t time;
    astro_body_t body;
    astro_observer_t observer;
    astro_aberration_t geo_aberration, equator_aberration;
    astro_equator_date_t equdate;
    double constel_ra, constel_dec;
    astro_rotation_t rotation;
    int axis;
    double angle;
    astro_direction_t direction;
    double limit_days, meters_above_ground;

    /* Decode every field before calling anything, so skipping a call never
       shifts the fields after it. */
    flags = TakeByte(&reader);
    star_ra = TakeDouble(&reader);
    star_dec = TakeDouble(&reader);
    star_dist = TakeDouble(&reader);

    /* Process-wide state is reset on every input so a finding reproduces from
       its input alone, whatever ran before it. User-defined star 1 starts from
       a fixed definition and is then redefined from the input; stars 2 to 8
       stay undefined, which exercises the undefined-star error paths. */
    Astronomy_SetDeltaTFunction((flags & 2) ? Astronomy_DeltaT_JplHorizons : Astronomy_DeltaT_EspenakMeeus);
    CheckStatus(Astronomy_DefineStar(BODY_STAR1, 0.0, 0.0, 1000.0), "Astronomy_DefineStar");
    CheckStatus(Astronomy_DefineStar(BODY_STAR1, star_ra, star_dec, star_dist), "Astronomy_DefineStar");

    /* The Swift layer builds times from UT (AstroTime(ut:)) and from TT
       (AstroTime(tt:)), which goes through the TT-to-UT inverse. */
    if (flags & 1)
        time = Astronomy_TerrestrialTime(TakeDouble(&reader));
    else
        time = Astronomy_TimeFromDays(TakeDouble(&reader));

    body = TakeBody(&reader);
    observer.latitude = TakeDouble(&reader);
    observer.longitude = TakeDouble(&reader);
    observer.height = TakeDouble(&reader);
    geo_aberration = (astro_aberration_t)TakeEnum(&reader);
    equdate = (astro_equator_date_t)TakeEnum(&reader);
    equator_aberration = (astro_aberration_t)TakeEnum(&reader);
    constel_ra = TakeDouble(&reader);
    constel_dec = TakeDouble(&reader);
    rotation.status = (TakeByte(&reader) & 1) ? ASTRO_INVALID_PARAMETER : ASTRO_SUCCESS;
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j)
            rotation.rot[i][j] = TakeDouble(&reader);
    axis = (int)(int8_t)TakeByte(&reader);
    angle = TakeDouble(&reader);
    /* Swift's RiseSetDirection only produces these two; see README.md. */
    direction = (TakeByte(&reader) & 1) ? DIRECTION_SET : DIRECTION_RISE;
    limit_days = TakeDouble(&reader);
    meters_above_ground = TakeDouble(&reader);

    {
        astro_vector_t vector = Astronomy_HelioVector(body, time);
        CheckFiniteSuccess(vector.status, vector.x, vector.y, vector.z, "Astronomy_HelioVector");
        Sink = vector.x + vector.y + vector.z;

        vector = Astronomy_GeoVector(body, time, geo_aberration);
        CheckFiniteSuccess(vector.status, vector.x, vector.y, vector.z, "Astronomy_GeoVector");
        Sink = vector.x + vector.y + vector.z;

        /* Astronomy_Equator may fill in the time's cached nutation fields. */
        astro_time_t equator_time = time;
        astro_equatorial_t equ = Astronomy_Equator(body, &equator_time, observer, equdate, equator_aberration);
        CheckFiniteSuccess(equ.status, equ.ra, equ.dec, equ.dist, "Astronomy_Equator");
        Sink = equ.ra + equ.dec + equ.dist + equ.vec.x;
    }

    /* Searches and functions that step or wrap a value derived from the time
       or from a target angle. The pivot angle doubles as the target angle. */
    {
        astro_libration_t lib = Astronomy_Libration(time);    /* has no status */
        Sink = lib.elon + lib.elat + lib.mlon + lib.dist_km;

        astro_node_event_t node = Astronomy_SearchMoonNode(time);
        CheckStatus(node.status, "Astronomy_SearchMoonNode");
        Sink = node.time.ut;

        astro_apsis_t apsis = Astronomy_SearchPlanetApsis(body, time);
        CheckFiniteSuccess(apsis.status, apsis.time.ut, apsis.dist_au, apsis.dist_km, "Astronomy_SearchPlanetApsis");
        Sink = apsis.time.ut + apsis.dist_au;

        astro_search_result_t sunlon = Astronomy_SearchSunLongitude(angle, time, limit_days);
        CheckStatus(sunlon.status, "Astronomy_SearchSunLongitude");
        Sink = sunlon.time.ut;

        astro_search_result_t rlon = Astronomy_SearchRelativeLongitude(body, angle, time);
        CheckStatus(rlon.status, "Astronomy_SearchRelativeLongitude");
        Sink = rlon.time.ut;
    }

    {
        astro_constellation_t constel = Astronomy_Constellation(constel_ra, constel_dec);
        CheckStatus(constel.status, "Astronomy_Constellation");
        if (constel.status == ASTRO_SUCCESS)
        {
            /* Reading the strings lets ASan check the returned pointers. */
            Sink = (double)(strlen(constel.symbol) + strlen(constel.name));
            Sink = constel.ra_1875 + constel.dec_1875;
        }
    }

    {
        astro_rotation_t pivoted = Astronomy_Pivot(rotation, axis, angle);
        CheckStatus(pivoted.status, "Astronomy_Pivot");
        Sink = pivoted.rot[0][0] + pivoted.rot[1][1] + pivoted.rot[2][2];
    }

    /* The issue's Astronomy_SearchRiseSet is a header macro that calls
       Astronomy_SearchRiseSetEx with metersAboveGround = 0. */
    if (SwiftAcceptsObserver(observer) && RiseSetWithinCostBound(limit_days))
    {
        astro_search_result_t result = Astronomy_SearchRiseSetEx(
            body, observer, direction, time, limit_days, meters_above_ground);
        CheckStatus(result.status, "Astronomy_SearchRiseSetEx");
        Sink = result.time.ut;
    }

    return 0;
}
