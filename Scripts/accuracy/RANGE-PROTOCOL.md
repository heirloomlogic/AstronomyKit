# Broader model validation protocol v1

Selection frozen before evaluating the integrated candidate: every monthly
midpoint (15th at 12:00 TT) from January 1900 through December 2100, for Mercury,
Venus, Mars, Jupiter, Saturn, Uranus, Neptune, Pluto, Sun and Moon. All ordinary
Mercury–Saturn longitude stations in [1900-01-01 00:00 TT, 2101-01-01 00:00 TT)
are selected by independent Swiss Moshier apparent positions (flags 260).

Station definition: zero signed central difference of apparent tropical
longitude, width 0.02 TT day. Daily reference sampling identifies sign changes;
bisection narrows each local bracket to 0.01 seconds. Confirm each reference
station with widths 0.01 and 0.04 day; report their spread as sensitivity, not
an astronomical uncertainty bound. Preserve returned-speed comparisons only
as diagnostics. Do not alter the original 36 reference events or their gate.

Compare the candidate at common TT. Use the same finite-difference widths to
avoid attributing a numerical-method difference to the model. Report maximum,
quantiles and every station difference above 60 seconds. Monthly positions
report angular errors (longitude wrapped to ±180°), without converting them
into event timing or claiming complete search coverage. JPL-selected cross-checks
and independent reference uncertainty remain required for release qualification.

This protocol is a deterministic diagnostic population. Daily sign-change
sampling does not certify all exotic/tangent station behavior or the #369
search service. Native UTC results remain a separate comparison; TT agreement
does not certify historical/future UTC or Earth-orientation accuracy.
