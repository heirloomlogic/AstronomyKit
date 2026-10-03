# Sampled independent radial-rate evidence

Issue #81 remains open. This investigation adds 5,035 sampled radial-rate comparisons from existing independent Horizons archives, comprising 2,650 geometric observable matches and 2,385 received-light cases with unresolved derivative/origin conventions. It introduces no rate accuracy allowance, model change, or whole-domain accuracy claim. Geometric matching identifies the origin, correction and epoch; exact TT/TDB derivative scaling remains unresolved for all rows.

The [report](range-rate-investigation.json) retains every independent position, velocity and rate column, production rate, signed residual in km/s, local derivative diagnostic, convention classification, source hash and query provenance. It reuses the 131 characterization and 134 held-out epochs per body/observable from the frozen distance archive, with no residual-guided epoch selection or new downloads. Each phase contributes all 19 existing series. Dates span 1900–2100; Earth has only a heliocentric observable, the Moon only a geometric geocentric observable, and the Sun only a received-light geocentric observable. No old archive, tolerance or evidence file was replaced.

For geometric states, the independent radial rate is the signed projection `dot(position, velocity) / norm(position)`. AU/day converts to km/s using `149597870.7 / 86400`; positive means receding. Planetary heliocentric rows compare the public heliocentric state's velocity projection. Lunar rows compare the public geocentric ecliptic state's distanceRate with Earth-centered NONE vectors, matching the production instantaneous lunar exception. ICRF versus the local equatorial frame remains a vector limitation; scalar radial projection is invariant under an exact orthogonal frame rotation. These are sampled residual observations without an acceptance threshold.

| Geometric observable | Cases | Maximum absolute rate residual (km/s) |
| --- | ---: | ---: |
| Earth/heliocentric | 265 | 4.67124433e-06 |
| Jupiter/heliocentric | 265 | 0.00228935584 |
| Mars/heliocentric | 265 | 2.44914212e-06 |
| Mercury/heliocentric | 265 | 5.24492902e-06 |
| Moon/geocentric | 265 | 3.7157887e-05 |
| Neptune/heliocentric | 265 | 0.000942953203 |
| Pluto/heliocentric | 265 | 0.02402696 |
| Saturn/heliocentric | 265 | 0.00134482125 |
| Uranus/heliocentric | 265 | 0.000311044751 |
| Venus/heliocentric | 265 | 1.89263178e-06 |

The largest geometric residual is Pluto's 0.02402696 km/s. The existing public heliocentric state returns the integrator's interpolated physical velocity; the geocentric ecliptic state selects the separate exact derivative of Pluto's interpolated position. The diagnostic finds a maximum 0.000192629 km/s difference between the heliocentric velocity projection and a central derivative of radius, while the public geocentric distanceRate differs from its local central stencil by at most 1.38264e-7 km/s. The former API promises a state velocity rather than the latter API's explicit position-derivative semantics. This distinction is recorded without declaring a new defect or transferring a rate accuracy threshold. The original model-center and large radial discrepancy investigations remain separate.

Received-light rows retain raw residuals but are classified unmatched. AstronomyKit's `.none` geocentric state differentiates its fixed-heliocentric-origin light-time solution, including the emission-time chain factor, with Earth at reception. Horizons uses a moving barycentric Sun. Its archived VECTORS velocity and RR labels alone do not establish the same derivative convention. Simply subtracting Sun emission/reception positions is insufficient for rates: differentiating that bridge also requires the emission factor and the two Sun velocities. The bridge uses Horizons' emission epoch rather than resolving the fixed-Sun emission equation, adding another alignment limit. `.corrected` production rates are retained separately to expose the engine's backdated-observer approximation; they are not used to claim a match with independent received-light rates.

There is target-specific evidence for the Sun. In all 265 archived Sun LT rows, reconstruct Earth barycentric velocity as Earth heliocentric velocity plus reception Sun barycentric velocity. The archived Sun velocity agrees with emission Sun velocity minus reception Earth velocity to at most 1.04216e-13 km/s. Applying the reception light-time derivative chain factor instead changes the vector by up to 2.65748e-8 km/s. The report retains all reconstructed vectors and factors. This supports a retarded relative-velocity interpretation for these Sun rows; it is not generalized to other LT targets, and rounded emission TT remains explicit.

The [Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html#obsquan) specifies observer quantity 20's sign and units. The [original news payload](https://ssd.jpl.nasa.gov/dat/horizons_news.txt) dates the observer-quantity 19/20 projection change to August 25, 2007, version 3.32; the August 30, 2013 entry concerns LADEE. That observer-table statement is not a VECTORS derivative contract. [NAIF SPKEZR documentation](https://naif.jpl.nasa.gov/pub/naif/toolkit_docs/C/cspice/spkezr_c.html) records its own December 27, 2007 addition of light-time derivatives; the SPICE contract cannot be transferred to Horizons output. The archived TT labels describe a conversion from internal TDB and do not establish an exact TT velocity derivative. No TDB tag is silently treated as TT.

The production probe uses explicit TT and the captured JPL Delta T model. Central radius differences at half-widths 0.001 and 0.002 TT days hold reception Delta T fixed. Their difference is recorded as stencil sensitivity, not a continuous derivative bound. Moon velocity already uses a short central difference; Pluto interpolation kinks and polynomial/light-time stopping seams are not exhaustively covered by this finite set. Local derivative agreement checks implementation consistency, while independent residuals compare models; neither establishes the other's accuracy.

Run the following offline commands with CPython 3.14.7. The report retains the measurement compiler/platform and its source snapshot; its numerical replay is exact on the recorded host and does not promise portable bit identity. Swift replay checks use a numerical production-replay tolerance, distinct from the absence of any independent rate accuracy allowance.

```sh
python3 -m unittest Scripts/reference-data/test_range_rate_investigation.py -v
python3 Scripts/reference-data/investigate-range-rate.py --check
swift test --filter IndependentRangeRateTests
swift test -c release --filter IndependentRangeRateTests
```

The generator refuses to overwrite an existing report. A separate output path permits a new diagnostic without rebinding the historical report. Seven initial control identities cover signed projection/SI conversion, invalid Cartesian states, wrong sign/unit columns, TT/correction classification, the received-light chain factor, the moving-Sun bridge factor, and rejection of an accuracy-passed report. Two additional tests cover the complete archived population/Sun convention inference and detached source hashes/incomplete coverage. Their rounding and identity checks do not define an astronomical error budget. Public Swift tests replay all 5,035 production rates and independent column projections offline; the latter test does not assert independent residual accuracy.

This layer requires independent review of the derivative conventions and evidence claims. Acceptance of meaningful independent rate accuracy still needs an applicable owner-approved accuracy policy and convention-complete comparisons. Unsupported epochs, continuous maxima, future civil UTC, other bodies, and dense geometry/interpolation boundaries remain outside this sampled evidence. Existing #119 product-limit questions are unchanged.
