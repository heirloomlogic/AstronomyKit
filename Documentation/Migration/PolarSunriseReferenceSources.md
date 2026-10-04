# Polar sunrise reference sources

Research date: 2026-10-03. Scope: primary-source conventions and acquisition provenance for [#124](https://github.com/heirloomlogic/AstronomyKit/issues/124), with the other three exact-pole crossings as controls. This note does not select a production model or change the 70.8-second archive allowance.

## Archive provenance and live USNO checks

The pinned Astronomy Engine acquisition instructions identify the USNO **yearly** rise/set service, originally `RS_OneYear.php`, subsequently `RS_OneYear`. The South Pole HTML preserves its original query URL and labels the table Universal Time. Its September 20 sunrise is `2152`; March 22 sunset is `1807`. The parser copies those hour/minute fields and appends `Z`; it performs no time-scale conversion or new rounding. Thus the archive originated in the yearly service, even though a fresh one-day query can reproduce it. [Pinned acquisition instructions](https://raw.githubusercontent.com/cosinekitty/astronomy/865d3da7d8112bbc7911238052c6af4aaf877181/generate/riseset/README.md), [pinned South Pole table](https://raw.githubusercontent.com/cosinekitty/astronomy/865d3da7d8112bbc7911238052c6af4aaf877181/generate/riseset/sun_2022_E0_S90.html), [pinned parser](https://raw.githubusercontent.com/cosinekitty/astronomy/865d3da7d8112bbc7911238052c6af4aaf877181/generate/riseset/parse_riseset.py).

The current one-day API documents dates from 1700 through 2100, latitude before longitude, north/east-positive coordinates, optional time zone/DST, and explicit continuously-above/below responses. Its time-zone definition is an offset from UT1. Fresh HTTPS requests succeeded at exact latitudes ±90°, longitude 0°, `tz=0`, `dst=false`, and returned API version `4.0.1` with the requested coordinates unchanged. [USNO API documentation](https://aa.usno.navy.mil/data/api).

| Archived source line | Location | Event | Archived UT minute | Live USNO one-day result |
| --- | --- | --- | --- | --- |
| 2922 | −90°, 0° | Sunset | 2022-03-22 18:07 | [18:07](https://aa.usno.navy.mil/api/rstt/oneday?date=2022-03-22&coords=-90,0&tz=0&dst=false) |
| 2923 | −90°, 0° | Sunrise | 2022-09-20 21:52 | [21:52](https://aa.usno.navy.mil/api/rstt/oneday?date=2022-09-20&coords=-90,0&tz=0&dst=false) |
| 5908 | +90°, 0° | Sunrise | 2022-03-18 13:02 | [13:02](https://aa.usno.navy.mil/api/rstt/oneday?date=2022-03-18&coords=90,0&tz=0&dst=false) |
| 5909 | +90°, 0° | Sunset | 2022-09-25 04:13 | [04:13](https://aa.usno.navy.mil/api/rstt/oneday?date=2022-09-25&coords=90,0&tz=0&dst=false) |

These are successful live API observations, not just examples from documentation. They support the archived minute values and exact-pole availability. They do not expose the underlying solar ephemeris, Earth-orientation parameters, unrounded roots, or rise/set implementation. The original South Pole yearly request is [preserved in the pinned table](https://raw.githubusercontent.com/cosinekitty/astronomy/865d3da7d8112bbc7911238052c6af4aaf877181/generate/riseset/sun_2022_E0_S90.html).

## Meaning and precision of sunrise

USNO's public definition specifies upper-limb contact with a level sea-level horizon under average conditions. Its computational description gives center zenith distance 90.8333°: average solar radius 16′ plus horizon refraction 34′. The same page warns that real atmospheric variation can produce errors of a minute or more, magnified at high latitudes. These are statements about observed sunrise, not an authorization to widen a deterministic regression threshold. [USNO rise/set definitions](https://aa.usno.navy.mil/faq/RST_defs).

Do not infer the exact yearly/one-day implementation from that abbreviated definition alone. A separate USNO service expressly documents numerical ray integration through a polytropic atmosphere, height-dependent refraction, a flat horizon without dip, and nearest-minute printing. It is a different endpoint, so this proves neither that the yearly/one-day services share that algorithm nor that they use a literal fixed 50′ threshold. [USNO major-body rise/set service notes](https://aa.usno.navy.mil/data/mrst).

The archive contains no seconds. If nearest-minute rounding applies, one printed minute corresponds to a ±30-second quantization interval; that is arithmetic conditional on the rounding convention, not a complete uncertainty bound. The pinned parser cannot recover missing seconds, and the captured yearly header does not specify how seconds were rounded. Do not treat `21:52` as a seconds-accurate observational timestamp.

The checked-in AstronomyKit source instead solves airless topocentric center altitude plus `asin(SUN_RADIUS_AU / distance)` against −34′ at sea level, using `SUN_RADIUS_KM = 695700`. This is a varying angular semidiameter. [Local altitude function](../../Sources/CLibAstronomy/astronomy.c), [local radius constant](../../Sources/CLibAstronomy/include/astronomy.h). Consequently fixed −50′ and varying semidiameter plus −34′ must be reported as distinct diagnostics; they must not be silently substituted.

## Horizons conventions

Horizons quantity 4 gives apparent topocentric center elevation, including light-time, gravitational deflection, aberration, precession/nutation; `AIRLESS` disables atmospheric refraction. Quantity 13 is disk diameter in arcseconds. Quantity 30 is TDB−UT; quantity 49 is UT1−UTC. After 1962 its `UT` means UTC. Earth sites use ITRF93/WGS84 geodetic coordinates and ellipsoid height, with EOP corrections including polar motion and measured nutation offsets. [Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html).

Inference: a physical ITRF93 geodetic pole includes an orientation correction relative to the idealized pole of an uncorrected equator-of-date calculation. Identical numeric latitude alone therefore does not establish identical local vertical. Near the slow polar crossing, even subarcsecond orientation differences can materially shift event times; their attribution requires controls rather than assumption.

Horizons automatic rise/set markers bracket events within the previous output step and use their own refraction/horizon convention. Its atmospheric estimate assumes 10°C and 1010 mbar and can be unreliable near the horizon. Use airless numeric elevations and explicit residual equations for this comparison, preserving the response's solar-radius, ephemeris and EOP headers. An ellipsoid height of zero is an explicit idealized choice, not a measured South Pole station or mean-sea-level realization. [Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html).

## Time alignment

USNO states that its Astronomical Applications data labeled UT use UT1, while the parser's appended `Z` does not establish UTC. UTC and UT1 can differ by up to 0.9 second. [USNO Universal Time explanation](https://aa.usno.navy.mil/faq/UT).

For the four 2022 events, TT−UTC is 69.184 seconds: TT−TAI is 32.184 seconds and TAI−UTC is 37 seconds. Thus TT−UT1 is `69.184 − DUT1`, with DUT1 = UT1−UTC. This is distinct from the archive harness's Espenak-Meeus estimated ΔT of roughly 73 seconds. Compare model positions at the same TT instant and retain each model's UT coordinate for the existing archive check. [USNO TT definition](https://aa.usno.navy.mil/faq/TT), [USNO leap-second offset effective January 2017](https://www.cnmoc.usff.navy.mil/Our-Commands/United-States-Naval-Observatory/Precise-Time-Department/Global-Positioning-System/USNO-GPS-Time-Transfer/Leap-Seconds/), [NIST leap-second history](https://www.nist.gov/pml/time-and-frequency-division/time-realization/leap-seconds).

## Reproducible query recommendation

Use `https://ssd.jpl.nasa.gov/api/horizons.api` with URL-encoded settings below. For each control, change the sign of latitude and date/window; bracket broadly first, then refine around the sign change. Request quantities 2,4,5,13,20,30,49 so apparent declination, elevation/rate, diameter, range and time offsets remain available. `TLIST` can replace the start/stop/step triplet for exact shared-TT instants. [Horizons API settings and time-list documentation](https://ssd-api.jpl.nasa.gov/doc/horizons.html).

```json
{
  "format": "json",
  "COMMAND": "'10'",
  "OBJ_DATA": "'YES'",
  "MAKE_EPHEM": "'YES'",
  "EPHEM_TYPE": "'OBSERVER'",
  "CENTER": "'coord@399'",
  "COORD_TYPE": "'GEODETIC'",
  "SITE_COORD": "'0,-90,0'",
  "START_TIME": "'2022-09-20 21:40:00'",
  "STOP_TIME": "'2022-09-20 22:00:00'",
  "STEP_SIZE": "'1200'",
  "TIME_TYPE": "'UT'",
  "TIME_DIGITS": "'FRACSEC'",
  "CAL_FORMAT": "'BOTH'",
  "CAL_TYPE": "'GREGORIAN'",
  "APPARENT": "'AIRLESS'",
  "QUANTITIES": "'2,4,5,13,20,30,49'",
  "ANG_FORMAT": "'DEG'",
  "EXTRA_PREC": "'YES'",
  "CSV_FORMAT": "'YES'",
  "ELEV_CUT": "'-90'",
  "SKIP_DAYLT": "'NO'"
}
```

The diagnostic equations are explicit engineering choices: `elevation + diameter/7200 + 34/60 = 0` reproduces the varying-limb/constant-refraction form; `elevation + 50/60 = 0` implements the fixed-average form. Use the actual response radius/range to verify semidiameter compatibility. Neither equation establishes the hidden USNO service algorithm. Keep the returned UTC/TT distinction, EOP orientation, geometric versus apparent center, height, refraction and disk-radius convention visible when comparing either production model.

Preserve full request settings, raw responses, retrieval time, hashes and output headers. A comparison using common event definition and common TT can rank these four sampled predictions against Horizons; agreement with a rounded USNO minute alone cannot establish which coefficient set is scientifically more accurate.
