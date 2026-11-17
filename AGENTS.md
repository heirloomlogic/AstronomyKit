# Rules for coding agents

- AstronomyKit wraps Astronomy Engine and keeps its accuracy contract of about ±1 arcminute for positions. Do not raise positional precision beyond that in this package. When a downstream test needs more, change the downstream test.
- Event timing is the exception: stations, crossings, ingresses and equinoxes may be held tighter than the contract when the size and speed cost is small and measured, as #9 (planet series) and #10 (nutation series) did. Do not decline such a request on the contract alone. Prototype it, measure the size change and the Release and Debug cost, and report them to the owner, who decides.
- The package stays small: tracked files total under 2 MiB and each under 600 KiB, enforced by the Package size workflow. Never add ephemeris or source data files, evidence or qualification artifacts, or binary resources. Never add a coefficient table without the owner's explicit approval for that table. SwiftPM clones every tag and branch, so anything committed is downloaded by every consumer forever, even after it is removed from `main`.
- The approved tables in `astronomy.c` are:
  - `DeltaTObserved`, the yearly Delta T table behind `DeltaTModel.observed`. Refresh its entries as MAINTAINING.md describes, but do not make it finer than yearly or add its source data.
  - The VSOP87 planet series, with the terms MAINTAINING.md's "Selecting planet series terms" lists (#9). Do not commit VSOP87 files or selection scripts.
  - `nut_term`, the 77-term IAU 2000B nutation series (#10).
- Adding terms to an approved table needs the same approval as a new table.
- Do not change the size limits, or the workflow that enforces them, without the owner's explicit approval.
- GitHub releases are the only change record. Do not add a changelog.
