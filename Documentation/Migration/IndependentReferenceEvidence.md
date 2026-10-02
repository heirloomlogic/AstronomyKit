# Independent reference evidence

This partial implementation for issue #81 replaces the former one-date audit prints and broad range assertions with an offline archive of 92 reference records. The generated archive is `Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json`; its manifest records every source URL, SHA-256, generator path, upstream revision, and archive SHA-256. The fixture's source catalog separately records source version, frame, origin, units, time scale, aberration, refraction, supported domain, license, URL, and reproduction recipe for each of ten source families.

## Evidence classes

| Family | Samples | Evidence claim |
| --- | --- | --- |
| Geocentric positions | Moon, Mars, and Pluto at 1900, 2000, and 2100; Mercury across a 2025 station | JPL comparison in the declared frames and correction modes, using the repository's existing one-arcminute target and 1.5 arcminutes for Pluto |
| Apsis distance | Lunar and Earth apsides at 2001, 2050, and 2100 | Third-party table parity using the upstream distance limits of 25 km and 0.000012 AU; the upstream apsis tables lack their original acquisition recipe, so this is not classified as independent accuracy evidence |
| JPL apparent range | Raw Moon, Mars, Pluto, and Mercury observer responses | Archived for follow-up, but not decoded into the generated fixture or asserted because no cited source establishes a scientific tolerance for AstronomyKit's apparent light-time-aberrated range; the independent-distance criterion in #81 remains unmet |
| Rates and stations | Three daily Mercury samples bracketing a station | Sampled one-day ecliptic motion, with a two-endpoint error bound derived from the positional tolerance; this is not an instantaneous-rate accuracy claim |
| Seasons and lunar quarters | 1800, 2000, and 2100 | Published event-table comparison using upstream time limits |
| Lunar nodes and apsides | 2001, 2050, and 2100 | Published event time, node position, and apsis distance comparisons using upstream limits |
| Rise and set | Regular and polar Sun and Moon cases from 1944 through 2026 | USNO-derived apparent-horizon event comparison using the upstream 1.18-minute limit |
| Eclipses | Lunar and global cases from 1800 through 2099; partial, total, and annular local contacts in 2024 | NASA and EclipseWise-derived event comparisons using the upstream time, location, duration, and altitude limits; lunar peaks use UT and global solar peaks use Terrestrial Dynamical Time |
| Planetary transits | Mercury and Venus cases from 2003 through 2125 | NASA catalog contact and separation comparisons using upstream limits |
| Jupiter moons | ICRF position and velocity for all four Galilean moons at 1900, 2000, and 2100 | JPL state comparison; the unchanged Astronomy Engine `9e-4` relative bound applies to the 2000 samples, while 1900 and 2100 are retained as unbounded diagnostics outside its published test interval |
| Chiron | Sun-centered geometric ICRF position at 1900, 2000, and 2100 | JPL reference with the repository's existing `0.01` AU component sanity threshold; this is not a scientific error bound |

## Negative controls

The suite proves that selecting equatorial-of-date for an ICRF/J2000 fixture, interpreting UTC as TDB, changing a vector-component sign, confusing AU with km, and selecting the next lunar quarter exceed the corresponding unchanged reference limits. Each control first verifies the unmodified comparison so a broken test oracle cannot satisfy the mutation alone.

## Known disagreements

The archive makes two independently bounded defects executable instead of hiding them behind wider limits. Chiron propagation at 1900 and 2100 produces implausible finite vectors and is tracked by [#108](https://github.com/heirloomlogic/AstronomyKit/issues/108). One 2100 lunar quarter and one 2099 lunar eclipse peak exceed the unchanged event-table limits and are tracked by [#110](https://github.com/heirloomlogic/AstronomyKit/issues/110). Swift Testing records these exact probes as known issues; the passing status does not claim that the discrepancies are resolved.

The Io edge comparisons remain diagnostic evidence. At 1900, position and velocity relative errors are `1.0829618e-3` and `1.0570498e-3`; at 2100 they are `1.0758769e-3` and `1.0416663e-3`. [#109](https://github.com/heirloomlogic/AstronomyKit/issues/109) originally treated these values as violations of Astronomy Engine's `9e-4` test threshold, but the source test covers only JD 2426545.0 through 2476545.0 (1931-07-22 through 2068-06-12). The archived edge vectors therefore do not carry that threshold.

## Limits

These fixtures establish sampled comparisons only. They do not certify continuous accuracy over AstronomyKit's accepted range of roughly 4000 Julian years on either side of J2000, and no cited source supports such a claim. The Galilean-moon threshold is an observed upstream test limit over 5,001 ten-day samples from 1931-07-22 through 2068-06-12, not a model guarantee outside that interval. Chiron's documented 1900–2150 range is especially unsupported away from its 2000–2040 anchors; #108 records the observed edge failure. JPL angular rates, apparent ranges, and range rates remain in the raw responses for later work. This change tests the public ecliptic state through endpoint motion because its rate convention differs from the JPL observer columns, and it makes no apparent-range claim because it lacks a sourced tolerance for that quantity.

Existing frozen-engine parity evidence covers unchanged behavior where independent sources do not cover the full domain. The lunar and Earth apsis distance tables in this archive are also parity evidence because their pinned upstream source lacks its original acquisition recipe. The JPL position archive and USNO Earth-apsis times provide compensating independent samples for distance-bearing calculations, but they do not turn the apsis distance comparisons into accuracy claims. Accepted-time guards prove rejection outside the declared engine range. `SolarAltitudeNumerics` supplies mathematical interval bounds only for its own solar-altitude work; those bounds do not apply to the reference families in this archive.

## Reproduction

Run `python3 Scripts/reference-data/build-fixtures.py --check`, `python3 -m unittest Scripts/reference-data/test_build_fixtures.py -v`, then `swift test --filter AuditValidationTests`. The pull request records the exact AstronomyKit commit tested and the complete command results. Regeneration instructions and source licenses are in `Scripts/reference-data/README.md`. Issue #81 remains open pending an independently sourced apparent-range tolerance and a corresponding assertion.
