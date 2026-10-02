# Independent reference evidence

Issue #81 replaces the former one-date audit prints and broad range assertions with an offline archive of 90 reference records. The generated archive is `Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json`; its manifest records every source URL, SHA-256, generator path, upstream revision, and archive SHA-256. The fixture's source catalog separately records source version, frame, origin, units, time scale, aberration, refraction, supported domain, license, URL, and reproduction recipe for each of ten source families.

## Evidence classes

| Family | Samples | Evidence claim |
| --- | --- | --- |
| Geocentric positions | Moon, Mars, and Pluto at 1900, 2000, and 2100; Mercury across a 2025 station | JPL comparison in the declared frames and correction modes, using the repository's existing one-arcminute target and 1.5 arcminutes for Pluto |
| Distance | Lunar and Earth apsides at 2001, 2050, and 2100 | Third-party table parity using the upstream distance limits of 25 km and 0.000012 AU; the upstream apsis tables lack their original acquisition recipe, so this is not classified as independent accuracy evidence |
| Rates and stations | Three daily Mercury samples bracketing a station | Sampled one-day ecliptic motion, with a two-endpoint error bound derived from the positional tolerance; this is not an instantaneous-rate accuracy claim |
| Seasons and lunar quarters | 1800, 2000, and 2100 | Published event-table comparison using upstream time limits |
| Lunar nodes and apsides | 2001, 2050, and 2100 | Published event time, node position, and apsis distance comparisons using upstream limits |
| Rise and set | Regular and polar Sun and Moon cases from 1944 through 2026 | USNO-derived apparent-horizon event comparison using the upstream 1.18-minute limit |
| Eclipses | Lunar and global cases from 1800 through 2099; partial, total, and annular local contacts in 2024 | NASA and EclipseWise-derived event comparisons using the upstream time, location, duration, and altitude limits; lunar peaks use UT and global solar peaks use Terrestrial Dynamical Time |
| Planetary transits | Mercury and Venus cases from 2003 through 2125 | NASA catalog contact and separation comparisons using upstream limits |
| Jupiter moons | ICRF position and velocity for all four Galilean moons at 1900, 2000, and 2100 | JPL state comparison using Astronomy Engine's `9e-4` relative bound |
| Chiron | Sun-centered geometric ICRF position at 1900, 2000, and 2100 | JPL reference with the repository's existing `0.01` AU component sanity threshold; this is not a scientific error bound |

## Negative controls

The suite proves that frame rotation, UTC/TDB interpretation, a vector-component sign change, AU/km confusion, and selection of the next lunar quarter exceed the corresponding unchanged reference limits. Each control first verifies the unmodified comparison so a broken test oracle cannot satisfy the mutation alone.

## Known disagreements

The archive makes three independent defects executable instead of hiding them behind wider limits. Chiron propagation at 1900 and 2100 produces implausible finite vectors and is tracked by [#108](https://github.com/heirloomlogic/AstronomyKit/issues/108). Io position and velocity at the two century-edge samples exceed the sourced `9e-4` bound and are tracked by [#109](https://github.com/heirloomlogic/AstronomyKit/issues/109). One 2100 lunar quarter and one 2099 lunar eclipse peak exceed the unchanged event-table limits and are tracked by [#110](https://github.com/heirloomlogic/AstronomyKit/issues/110). Swift Testing records these exact probes as known issues; the passing status does not claim that the discrepancies are resolved.

## Limits

These fixtures establish sampled comparisons only. They do not certify continuous accuracy over AstronomyKit's accepted range of roughly 4000 Julian years on either side of J2000, and no cited source supports such a claim. Chiron's documented 1900–2150 range is especially unsupported away from its 2000–2040 anchors; #108 records the observed edge failure. JPL angular rates and range rates are archived for later direct derivative work, but this change tests the public ecliptic state through endpoint motion because its rate convention differs from the JPL observer columns.

Existing frozen-engine parity evidence covers unchanged behavior where independent sources do not cover the full domain. The lunar and Earth apsis distance tables in this archive are also parity evidence because their pinned upstream source lacks its original acquisition recipe. The JPL position archive and USNO Earth-apsis times provide compensating independent samples for distance-bearing calculations, but they do not turn the apsis distance comparisons into accuracy claims. Accepted-time guards prove rejection outside the declared engine range. `SolarAltitudeNumerics` supplies mathematical interval bounds only for its own solar-altitude work; those bounds do not apply to the reference families in this archive.

## Reproduction

Run `python3 Scripts/reference-data/build-fixtures.py --check`, then `swift test --filter AuditValidationTests`. The pull request records the exact AstronomyKit commit tested and the complete command results. Regeneration instructions and source licenses are in `Scripts/reference-data/README.md`.
