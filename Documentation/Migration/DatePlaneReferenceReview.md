# Date-plane reference review

**Recommendation:** use pinned PyERFA `ecm06` on independent geometric ICRF vectors for the finite lunar-node and simultaneous heliocentric relative-longitude pilots. It supplies an independent, explicitly defined IAU 2006 mean ecliptic of date. Compare the public API against that reference while retaining the local frame/model approximation in the residual; do not describe the two implementations as bit-identical or subtract their difference after seeing a failure. This is a source review supporting [the qualification plan](AccuracyQualificationPlan.md), not an accuracy result, a shipping dependency change, or a guarantee of observed physical event times.

## What the independent transform means

The pinned [ERFA `ecm06` source](https://github.com/liberfa/erfa/blob/v2.0.1/src/ecm06.c) specifies a two-part TT date and the multiplication `E_date = R_ecm06 * P_ICRS`. Its input is a free vector, so the same orientation transform can be applied to an Earth-centered lunar vector or a Sun-centered planetary vector. It makes no assumption about parallax or aberration and does not add them. Use `ecm06(2451545.0, ttDaysSinceJ2000)` to preserve the epoch split.

The implementation composes the IAU 2006 mean-obliquity rotation with `pmat06`, which includes precession and frame bias. [ERFA `pmat06`](https://github.com/liberfa/erfa/blob/v2.0.1/src/pmat06.c) defines its output as a bias-precession matrix taking the GCRS-oriented triad to the mean equatorial triad of date. [ERFA `bp06`](https://github.com/liberfa/erfa/blob/v2.0.1/src/bp06.c) makes the distinction explicit: `B` maps GCRS axes to mean J2000, `P` maps mean J2000 to mean of date, and the combined matrix is `P*B`. Here GCRS describes the orientation of the celestial triad; this matrix operation does not introduce a geocentric origin or perform a full relativistic origin transformation on a heliocentric vector.

The IAU 2006 ecliptic is a conventional modeled mean plane. It is not the instantaneous osculating Earth orbit plane reconstructed from a single Earth position/velocity sample. Geometric center positions, body-center identities, simultaneous epochs and the conventional plane must remain separately specified. The broader [reference-convention note](PositionEventReferenceConventions.md) fixes the geometry/time/source recipe.

## Comparison with the local implementation

Local observations below refer to [astronomy.c](../../Sources/CLibAstronomy/astronomy.c), specifically `mean_obliq`, `precession_rot`, `nutation_rot`, `RotateEquatorialToEcliptic`, `Astronomy_EclipticGeoMoon`, `Astronomy_EclipticLongitude` and `VsopRotate`.

| Element | Local implementation | Independent ERFA source | Review result |
| --- | --- | --- | --- |
| Mean obliquity | Polynomial begins `84381.406 - 46.836769*T - 0.0001831*T² + 0.00200340*T³ - 0.000000576*T⁴ - 0.0000000434*T⁵`, in arcseconds | [`obl06`](https://github.com/liberfa/erfa/blob/v2.0.1/src/obl06.c) has the same coefficients | Same mathematical polynomial and TT-century argument; different angular units/evaluation details do not establish bit parity. |
| Precession | Equatorial rotation built from `epsilon0`, `psiA`, `omegaA`, `chiA`; `epsilon0=84381.406` arcseconds | [`p06e`](https://github.com/liberfa/erfa/blob/v2.0.1/src/p06e.c) contains the same P03 angle coefficients | Same IAU 2006 precession theory parameterization; compare the independently formed matrices to verify sign/storage convention. |
| J2000 epoch | `precession_rot` reduces to identity | `pmat06` retains frame bias through Fukushima–Williams bias-precession angles | Local precession is a mean-J2000-to-date operation, not the full ICRS-to-date operation. |
| Equatorial-to-ecliptic tail | Mean-to-true nutation then true-obliquity rotation | `ecm06` uses mean obliquity and no nutation | For the two selected invariant observables, local nutation simplifies as derived below; absolute longitude and stations need additional treatment. |
| Planetary input orientation | `VsopRotate` explicitly labels its output FK5 and uses the archived authors' rounded matrix | `ecm06` expects ICRS orientation | A frame-origin/model distinction remains. Do not call the raw local EQJ vector exactly ICRS or treat all local bodies as having identical frame provenance. |
| Lunar input orientation | `CalcMoon` produces mean-ecliptic-of-date coordinates; the node calculation transforms those coordinates directly | Independent Earth-center Moon ICRF `NONE` vector, transformed by `ecm06` | Same intended geometric center-crossing family and modeled date-plane class; numerical trajectory/frame differences remain in the physical comparison. |

[ERFA `p06e`](https://github.com/liberfa/erfa/blob/v2.0.1/src/p06e.c) distinguishes P03 precession angles from angles incorporating frame bias and describes the agreement of alternative parameterizations as about one microarcsecond in the present era. That contextual statement is not a proved matrix-error or event-time bound over 1900–2130. Matching named theory or polynomial coefficients does not eliminate the separate local input-frame issue.

## Nutation cancellation, with explicit matrix direction

Use column vectors and define `M(epsilon)` as the active rotation mapping ecliptic components to equatorial components: `x'=x`, `y'=cos(epsilon)*y-sin(epsilon)*z`, `z'=sin(epsilon)*y+cos(epsilon)*z`. Its inverse `Q(epsilon)=M(epsilon)^T` maps equatorial components to ecliptic components. Let `N` be the local mean-equator-to-true-equator nutation matrix and let `Z(psi)` rotate around the ecliptic pole by nutation in longitude, increasing longitude by `psi`.

Expanding the local `nutation_rot` coefficients gives the exact mathematical identity `Q(epsilonTrue) * N * M(epsilonMean) = Z(psi)`. Therefore the local EQJ-to-true-ecliptic path can be written `R_localECT(t) = Z(psi(t)) * Q(epsilonMean(t)) * P_local(t)`. The C rotation array stores coefficients in a convention that must be converted before treating it as a conventional row-major matrix; copying the displayed array directly into NumPy without checking multiplication direction risks a transpose error.

For a geometric lunar node, `Z` leaves the third ecliptic component and latitude unchanged. For a same-epoch longitude difference, it adds the same `psi` to both longitudes, which cancels after proper angle wrapping. Consequently these event equations can use a mean-ecliptic reference without needing to reproduce local IAU2000B nutation. The reduction is an algebraic consequence of the actual source; floating-point evaluation still needs an implementation check.

This cancellation does not make different poles equivalent. It removes a common longitude-zero rotation after choosing the same plane. It does not remove ICRS/mean-J2000 bias, FK5 provenance, different precession realizations, or different geometric trajectories. Absolute longitude retains `psi`; a longitude station retains its derivative. Solar longitude, apparent geocentric directions, station rates and observer-dependent events therefore do not acquire qualification from this review.

## Source-backed scales and their limits

The [`ecm06` documentation](https://github.com/liberfa/erfa/blob/v2.0.1/src/ecm06.c) describes the frame bias disturbing the mean-J2000 interpretation as less than 25 milliarcseconds. This describes the defined ICRS/mean-J2000 transform, not every FK5/ICRF/model discrepancy, and cannot alone supply a lunar-node or slow-alignment time allowance.

The [Horizons frame documentation](https://ssd.jpl.nasa.gov/horizons/manual.html#frames) says DE440/441 is thought to align with ICRF3 within 0.0002 arcseconds and ICRF is thought to differ from the older FK5/J2000 dynamical system by at most 0.02 arcseconds. Preserve the source's qualification, “thought,” rather than promoting these contextual alignment estimates to a deterministic whole-interval error certificate for the local rounded matrix or ephemeris.

For comparison, the official [`fk5hip` model](https://github.com/liberfa/erfa/blob/v2.0.1/src/fk5hip.c) contains rotation-vector components `(-19.9, -9.1, +22.9)` milliarcseconds and spin components `(-0.30, +0.60, +0.70)` milliarcseconds per Julian year. It models FK5-to-Hipparcos orientation/spin and omits FK5 zonal catalog errors. These are different model quantities from IAU frame bias; they are not interchangeable corrections to apply blindly to VSOP trajectories or the lunar series. No source reviewed here establishes an exact additional FK5-to-ICRS correction for all local body implementations.

## Which finite comparisons are justified

| Proposed comparison | Classification | Permitted conclusion |
| --- | --- | --- |
| Independent Moon `NONE` vector transformed by `ecm06`; root of its ecliptic `z` compared with public ascending/descending node times in TT | Independent nominal physical reference with local frame/model approximation retained | A finite event comparison against the defined IAU 2006 geometric date plane, including root precision, event identity/direction and all retained implementation differences. It is not exact frame parity or an observed crossing guarantee. |
| Independent Sun-center planet and Earth `NONE` vectors transformed by the same `ecm06`; root of the public direction-signed longitude difference | Independent nominal physical reference with local frame/model approximation retained | A finite comparison of simultaneous heliocentric alignments, including local orientation/model residual. It can address the existing public opposition/conjunction search definition. |
| Independent trajectories transformed through an independently implemented copy of the exact local date-plane equations | Independently sourced trajectory diagnostic under the local coordinate convention | Isolates trajectory versus transform effects when separately reviewed; shared equations cannot independently validate their physical frame choice. Do not substitute this for the physical-reference column after a failure. |
| Raw ICRF vector passed directly into local `Astronomy_Ecliptic` with no declared frame bridge | Unmatched coordinate diagnostic | Does not establish an exact common-frame angular comparison; it omits the ICRS/mean-J2000 distinction. |
| `ecm06` output compared with absolute local true longitude or a corrected apparent direction | Unmatched unless further corrections are specified | Does not establish the selected API's physical accuracy merely because both values are called ecliptic. |
| Horizons quantity 18 or 31 substituted for the selected geometric event equations | Unmatched observable diagnostic | Quantity 18 is emission-time heliocentric longitude; quantity 31 includes apparent corrections and a different date-frame realization. Retain the distinctions in [the earlier review](PositionEventReferenceConventions.md). |

For the recommended physical-reference columns, the local frame difference is part of the API's total discrepancy against the declared independent standard, not source numerical uncertainty to subtract away. Source ephemeris uncertainty, reference output precision, TT representation, interpolation and root solver error remain separate. Establish finite acceptance only when the strict `<60 seconds` rule and the angular metric are met after their adopted reference allowances; a small source-backed rotation does not imply a small time error at a shallow root. Root completeness, event pairing and direction remain necessary.

## Isolated dependency pin

As checked on 2026-10-03, the official latest [PyERFA release is `2.0.1.5`](https://github.com/liberfa/pyerfa/releases/tag/v2.0.1.5), released 2024-11-11, and the latest [ERFA release is `2.0.1`](https://github.com/liberfa/erfa/releases/tag/v2.0.1), published 2023-10-13. The official [SOFA current release page](https://www.iausofa.org/current-software) identifies issue 2023-10-11. ERFA is derived from SOFA with intended matching functionality; identify the evaluator as ERFA rather than claiming SOFA itself executed it.

Pin `pyerfa==2.0.1.5` in an isolated environment under `.context/` for the pilot. The [PyERFA tag](https://github.com/liberfa/pyerfa/tree/v2.0.1.5) resolves to commit `2b5cbbc1527d1a6c57968f1821eca4b1b780a73d`; its [`liberfa/erfa` submodule](https://github.com/liberfa/pyerfa/tree/v2.0.1.5/liberfa) is commit `9915ba38c9365f8b0738269b8c2ac1fdd5f8dee3`, also the peeled ERFA `v2.0.1` tag. The [PyPI release metadata](https://pypi.org/pypi/pyerfa/2.0.1.5/json) reports source artifact `pyerfa-2.0.1.5.tar.gz` SHA-256 `17d6b24fe4846c65d5e7d8c362dcb08199dc63b30a236aedd73875cc83e1f6c0`. That is the source artifact hash, not a hash of an architecture-specific wheel.

Record the artifact actually installed, its hash, `erfa.__version__`, `erfa.version.erfa_version`, Python and NumPy versions, platform, and whether the build used its bundled ERFA or a system library. Keep the dependency out of package/shipping manifests. A version pin alone does not prove runtime identity. This note did not install a dependency, edit a script, acquire new ephemeris archives or run an event-accuracy pilot.

## Review disposition

Proceed with `ecm06` for the two geometric pilots as a pinned independent IAU 2006 date-plane standard. The same geometric center/time family and nutation-invariant event equations justify a meaningful finite physical-reference comparison. Preserve exact-equivalence limitations and all numerical/source allowances in the report. Additional observed, apparent, absolute-longitude, station and observer-event families remain unqualified by this review; accepted requirements and production models remain unchanged.
