# Scientific evidence for independent distance allowances

Researched 2026-10-02 for issue #81. The literature supplies useful planetary distance accuracy scales, but no ready-made `allowedErrorKm` for AstronomyKit's apparent geocentric range. These scales can inform an explicit engineering acceptance budget; they do not establish a guaranteed maximum over the package's supported dates. This investigation does not close #81 or change test tolerances.

## Model actually being assessed

The local engine uses all archived VSOP87B terms for Mercury through Neptune, including Earth: heliocentric longitude, latitude, and radius in the dynamical J2000 ecliptic frame. This agrees with the authors' [CDS catalog description](https://cdsarc.cds.unistra.fr/viz-bin/ReadMe/VI/81?format=html&tex=true). Local provenance is in `Scripts/model-data/manifest.json`, the generated tables, and `MAINTAINING.md` patches 7 (full tables), 9 (polynomials), and 11 (compensated summation). This is materially different from upstream Astronomy Engine's reduced planetary series.

For qualified dates from 1900-01-01 through the end of 2100 TT, the production engine normally evaluates degree-12 Chebyshev approximations before falling back to the complete series. `Scripts/performance/polynomial/data/README.md` documents a sampled component regression budget of `max(1e-12 AU, abs(reference) * 1e-12)` against that series, tested on a 53-point grid per segment and recorded product requests. These are approximation agreement checks, not external astronomical accuracy evidence or a continuous interval certificate. For scale, `1e-12 AU` is approximately 0.15 mm; the relative term grows with the coordinate magnitude. An external distance allowance should account for this separately, even though it is far below the kilometre scales below.

## What the original planetary sources establish

[Bretagnon and Francou (1988), *Planetary theories in rectangular and spherical variables. VSOP87 solutions*, A&A 202, 309–315](https://articles.adsabs.harvard.edu/pdf/1988A%26A...202..309B), section 3 on p. 311, explicitly identifies Table 1's 1900–2100 values as **longitude precision**. In planet order Mercury, Venus, Earth/EMB, Mars, Jupiter, Saturn, Uranus, Neptune, these are 0.001, 0.006, 0.005, 0.023, 0.020, 0.100, 0.016, and 0.030 arcseconds. They are not radial-distance tolerances. Sections 3–4 describe improved long-term precision and equivalent derived representations; section 6 gives an approximate statistical estimate for further series truncation, not a maximum external range error. The integration constants were fitted to DE200.

The authors' [VSOP87 usage notice, precision section](https://ftp.imcce.fr/pub/ephem/planets/vsop87/vsop87.doc), gives approximate distance precision `p0 * a0 AU`, using semimajor axis `a0` and relative precision `p0`. It says “close by”, with no explicit interval for that table. Separately, one-arcsecond spans around J2000 are ±4000 years for Mercury/Venus/EMB/Mars, ±2000 for Jupiter/Saturn, and ±6000 for Uranus/Neptune. These are not kilometre guarantees.

The following are **unit conversions of the notice's approximate heliocentric distance scales**, not proposed pass/fail limits. Calculation: `scaleKm = a0 * p0Column * 1e-8 * 149597870.7`. The modern AU conversion is fixed at 149,597,870.700 km in [JPL's ephemeris export documentation](https://ssd.jpl.nasa.gov/planets/eph_export.html).

| Body | a0 (AU) | p0 column (units of 10⁻⁸) | Approximate distance scale (km) |
| --- | ---: | ---: | ---: |
| Mercury | 0.3871 | 0.6 | 0.347 |
| Venus | 0.7233 | 2.5 | 2.705 |
| Earth | 1.0000 | 2.5 | 3.740 |
| Mars | 1.5237 | 10.0 | 22.794 |
| Jupiter | 5.2026 | 35.0 | 272.404 |
| Saturn | 9.5547 | 70.0 | 1000.554 |
| Uranus | 19.2181 | 8.0 | 229.999 |
| Neptune | 30.1096 | 42.0 | 1891.819 |

Consequently, the sources support body-specific kilometre scales and explain why a single angular tolerance is inadequate. They do not substantiate one universal distance allowance. The local package accepts roughly ±4000 Julian years from J2000 for most ephemerides (`MAINTAINING.md`, patch 17), which also extends beyond the quoted Jupiter/Saturn one-arcsecond span. Restricting an initial acceptance budget to a named modern interval is scientifically more defensible than extrapolating these numbers across every accepted input.

## Why these scales are not yet apparent geocentric range limits

The following is a mathematical inference, not an additional published VSOP87 accuracy claim. At the same epoch, for consistently defined position vectors, the reverse triangle inequality gives `abs(norm(P - E) - norm(Pref - Eref)) <= norm(P - Pref) + norm(E - Eref)`. Thus independent geocentric range needs errors for both the target and Earth **vectors**. Heliocentric radius errors alone do not bound those vectors: a planet can retain its solar distance while its orbital direction changes enough to change its distance from Earth. Similarly, `range * angularError` estimates transverse displacement; it does not bound radial error.

If separate radial and direction limits are available, a sufficient vector limit is `epsilonR + 2 * radiusMax * sin(epsilonDirection / 2)`. The notice supplies approximate radial and angular scales, so it can guide such a budget, but it does not supply the hard inequalities needed to call this a guaranteed bound. An engineering tolerance may instead explicitly state that it is an empirical allowance informed by the literature and independent validation.

For apparent range, target position is evaluated at emission time and observer position at reception time. Iterated light time, the time-scale conversion, body-center versus system-barycenter selection, and any approximation used for aberration must agree with the reference or carry separate allowances. `Scripts/reference-data/README.md` and `apparent-range-investigation.json` already show that switching Astronomy Engine's aberration behavior changes the sampled range residuals. A tolerance selected to absorb that convention mismatch would conceal a different error source.

[Park et al. (2021), *The JPL Planetary and Lunar Ephemerides DE440 and DE441*, AJ 161, 105](https://ssd.jpl.nasa.gov/doc/Park.2021.AJ.DE440.pdf), describes newer observations, dynamics, and fits; DE440 spans 1550–2650 and uses TDB and an ICRF-aligned frame. This supports using a modern independent reference but does not provide a VSOP87-to-DE440 maximum. Its spacecraft and lunar ranging residuals characterize the reference fit, not AstronomyKit. DE200-based VSOP87 precision therefore needs an additional allowance or characterization when compared with modern Horizons output; agreement with the C port cannot establish that allowance.

## Moon and Pluto exclusions

The local lunar evaluator is a separate Brown-derived trigonometric model, not the VSOP87 planetary solution. Montenbruck and Pfleger's author code, distributed in the [official Springer companion archive](https://extras.springer.com/?query=978-3-540-67221-0), `APCe_v3_Pas.zip` → `MOON/MOON.PAS`, uses the corresponding lunar distance expression and states approximate one-arcsecond accuracy, but supplies no radial kilometre limit or associated accuracy interval. [Espenak (1989), NASA RP-1216, *Fifty Year Canon of Lunar Eclipses: 1986–2035*](https://ntrs.nasa.gov/api/citations/19900009026/downloads/19900009026.pdf), pp. 13–14, compares 260 full-moon positions over 1980–2000 with DE200, but reports angular right-ascension/declination statistics. Its lunar parallax term cutoff is a truncation selection rule, not a proven distance residual. Neither source establishes `allowedErrorKm` for AstronomyKit's lunar range.

The [Astronomy Engine author](https://github.com/cosinekitty/astronomy#why-i-created-this-thing) describes a custom Pluto gravity integrator verified against TOP2013. That is not an implementation of TOP2013 itself. Published accuracy for TOP2013 cannot be transferred to the custom integrator without quantified agreement over the chosen domain, then appropriate propagation to the range observable. The planetary VSOP87 table excludes Pluto entirely.

## Practical consequence for #81

A justified next step is a body-specific, explicitly empirical acceptance budget over a finite interval, such as 1900–2100: use the original VSOP87 distance scales as scientific context; obtain independent radial/vector residual evidence against a pinned modern ephemeris; match the observable, time scales, centers, and corrections; and add implementation/approximation allowances. Keep geometric heliocentric radius validation separate from apparent geocentric range validation so the evidence supports what each assertion measures. Moon and Pluto require their own provenance and budgets.

The tolerance should be declared before evaluating the assertions used for acceptance, supported by separate characterization data, and labeled accurately as an engineering test allowance rather than a certified sky-error bound. A safety multiplier chosen by the project is a policy choice; the papers do not prescribe it. The existing 12 diagnostic observer samples are useful leads but are too narrow to establish broad date-domain accuracy by themselves. A formal continuous maximum is only necessary if the project intends to promise one; #81 can use a scientifically motivated finite-fixture allowance with its scope and limitations stated.

The current evidence therefore supports a path to `allowedErrorKm`, but **does not yet supply the final apparent-range number**.

## Retrieval note

The 1988 paper is an image-only scan. Its [ADS alternate PDF endpoint](https://articles.adsabs.harvard.edu/cgi-bin/nph-iarticle_query?1988A%26A...202..309B&defaultprint=YES&filetype=.pdf) was retrieved and inspected with local OCR and page images under `.context/distance-literature/`; the original page numbers above refer to the printed journal pages. The IMCCE notice is plain text served with a document MIME type, so it was read directly after download rather than inferred from a secondary summary. Springer and NASA lunar provenance was independently retrieved and inspected in `.context/literature/` by the coordinating researcher.
