# Independent reference archive

This directory builds the offline fixtures used by `AuditValidationTests`. Tests never contact a network service.

Run `python3 Scripts/reference-data/build-fixtures.py --refresh` to download the pinned Astronomy Engine source files and record fresh JPL Horizons responses. Run `python3 Scripts/reference-data/build-fixtures.py --check` to verify every archived source hash and confirm that the generated fixture and manifest are current. A normal generation run writes the fixture without downloading anything.

The JPL query recipes are stored beside each response under `sources/horizons`. Observer queries use Earth center `500@399`, ICRF/J2000 equatorial coordinates, true ecliptic and equinox of date for the ecliptic columns, UT/UTC calendar output, airless apparent coordinates, and AU distance. Vector queries use geometric ICRF states, TDB, AU and AU/day, with Sun center for Chiron and Jupiter center for the Galilean moons. Each response records the service version, target identity, ephemeris source, frame, origin, units, time scale, and correction modes returned by Horizons. The generated fixture's ten-entry `provenance` catalog records those fields plus source domain, license, URL, and reproduction recipe for every source family.

The event sources are pinned to Astronomy Engine revision `865d3da7d8112bbc7911238052c6af4aaf877181`. That repository transformed published USNO, NASA GSFC, AstroPixels, and EclipseWise records into stable test tables. The archive retains the upstream MIT license and exact source hashes. Source-table tolerances come from the matching upstream test harness at that revision; the generator does not derive tolerances from AstronomyKit output.

- Seasons, Earth apsis times, and lunar phases come from the pinned transformations of the USNO seasons and moon-phase APIs.
- Rise and set events come from the pinned transformation of the USNO Complete Sun and Moon Data for One Day service.
- Lunar nodes come from Fred Espenak's AstroPixels Node Passages of the Moon table and its pinned transformation.
- Global eclipse and planetary-transit records come from Fred Espenak's NASA GSFC catalogs. Lunar greatest-eclipse times and transit contacts use UT; global solar greatest-eclipse times use Terrestrial Dynamical Time as the catalog specifies.
- Local solar contacts come from the pinned EclipseWise table.
- Lunar and Earth apsis distances come from pinned Astronomy Engine validation tables whose original acquisition recipe is absent upstream. These records provide third-party parity evidence, not independent accuracy evidence; the JPL position archive and USNO Earth-apsis times provide compensating independent samples for distance-bearing calculations.

The source domains differ. The USNO rise/set service documents years 1700–2100 and apparent-horizon conventions that include standard refraction. NASA catalogs publish UT lunar peaks and transit contacts, and dynamical-time global solar peaks, over the ranges named by each catalog page. Mercury and Venus transit tables cover their published catalog intervals. JPL Horizons supplies the explicitly requested epochs. Chiron remains an AstronomyKit addition, and its `0.01` AU component threshold is the existing repository sanity threshold rather than a scientific accuracy bound.

NASA factual data is generally not subject to U.S. copyright; acknowledge NASA and do not imply endorsement. NASA eclipse records in this archive credit Fred Espenak and NASA GSFC. U.S. government USNO output is public domain. The transformed tables remain attributed to their named sources and Astronomy Engine; `sources/astronomy-engine-license.txt` contains the license that applies to the copied files and transformation code.

Do not replace a source tolerance with the largest observed AstronomyKit error. If a reference fails, preserve the fixture, verify the convention, and track the disagreement.
