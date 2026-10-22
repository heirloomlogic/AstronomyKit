# Rules for coding agents

- AstronomyKit wraps Astronomy Engine and keeps its accuracy contract of about ±1 arcminute. Do not raise precision beyond that in this package. When a downstream test needs more, change the downstream test.
- The package stays small: tracked files total under 2 MiB and each under 600 KiB, enforced by the Package size workflow. Never add coefficient tables, ephemeris or source data files, evidence or qualification artifacts, or binary resources. The one approved exception is `DeltaTObserved` in `astronomy.c`, the yearly Delta T table behind `DeltaTModel.observed`: refresh its entries as MAINTAINING.md describes, but do not make it finer than yearly or add its source data. SwiftPM clones every tag and branch, so anything committed is downloaded by every consumer forever, even after it is removed from `main`.
- Do not change those limits, or the workflow that enforces them, without the owner's explicit approval.
- GitHub releases are the only change record. Do not add a changelog.
