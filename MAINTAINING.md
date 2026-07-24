# Maintaining AstronomyKit

This document is for maintainers. It describes how AstronomyKit vendors the
[Astronomy Engine](https://github.com/cosinekitty/astronomy) C library and how
to update that vendored copy. Day-to-day contribution guidance lives in
[CONTRIBUTING.md](CONTRIBUTING.md).

## What is vendored

AstronomyKit wraps a single-file C library. Two files are copied verbatim from
upstream (aside from the local patches listed below):

- `Sources/CLibAstronomy/astronomy.c` — the implementation
- `Sources/CLibAstronomy/include/astronomy.h` — the public C header

A third body of vendored C — the deterministic math subset in
`Sources/CLibAstronomy/detmath/` — comes from **musl**, not from the Astronomy
Engine. It is what makes ephemeris results bit-identical across host libms; see
[Deterministic math (detmath/)](#deterministic-math-detmath) below. Two small
headers glue it in: `Sources/CLibAstronomy/ak_detmath.h` (private redirection
header) and `Sources/CLibAstronomy/include/ak_math.h` (public declarations).

The Swift layer in `Sources/AstronomyKit/` is ours and is not part of the
vendored code.

The top of `astronomy.c` carries a **vendoring note** recording the exact
upstream commit and the local patches. That note is the source of truth; keep it
current when you update.

## Version & tag scheme

Release tags embed the bundled engine version:

```
X.Y.Z+upstream-A.B.C
```

- `X.Y.Z` is AstronomyKit's own [semantic version](https://semver.org).
- `+upstream-A.B.C` is the Astronomy Engine release the vendored `astronomy.c`
  corresponds to (see its `ASTRONOMY_ENGINE_VERSION` / upstream release notes).

Bumping the vendored library changes only the `+upstream-` suffix unless it also
changes AstronomyKit's public API or behavior, in which case bump `X.Y.Z` per
semver as usual.

## Local patches (must survive every update)

The vendored `astronomy.c` differs from upstream only by these thread-safety and
determinism patches. Upstream is single-threaded by design and links the host
libm; AstronomyKit advertises `Sendable` safety and pins bit-exact results, so
these are required. **After any upstream sync they must be re-applied, or
verified as adopted upstream.**

1. **Pluto orbit cache mutex.** A `pthread` mutex (`pluto_cache_mutex`) guards
   the Pluto segment cache. `CalcPluto` holds the lock across both the segment
   lookup and its use; `Astronomy_Reset` takes it before freeing the cache.
   Prevents a use-after-free between concurrent calculation and reset.

2. **Atomic Delta T function pointer.** `DeltaTFunc` is a C11 `_Atomic`
   (`stdatomic.h`). `Astronomy_SetDeltaTFunction` stores with release ordering;
   `TerrestrialTime` loads with acquire ordering. Lets the Delta T model be
   swapped safely while calculations run on other threads.

3. **Atomic performance counters.** The undocumented counters `_CalcMoonCount`,
   `_AltitudeDiffCallCount`, and `_FindAscentMaxRecursionDepth` are C11
   `_Atomic`, since concurrent Moon and rise/set calculations increment them.

4. **Constellation lazy-init `pthread_once`.** `Astronomy_Constellation` lazily
   builds a J2000→B1875 rotation matrix on first use. The state was
   function-local `static`s, so concurrent first calls raced. Initialization is
   now hoisted to file scope (`constel_init_once`, `constel_epoch2000`,
   `constel_rot`) behind a `pthread_once`.

5. **Pluto compute denial-of-service guard.** `CalcPluto`'s uncached
   `CalcPlutoOneWay` crawl for times outside the `PlutoStateTable` range costs
   time proportional to the distance from the table, so a far-off time could
   hang. It now returns `ASTRO_BAD_TIME` for times more than
   `PLUTO_MAX_CRAWL_DAYS` (~100 years) beyond the table.

6. **Deterministic transcendentals.** A single line —
   `#include "ak_detmath.h"` — is inserted immediately after
   `#include "astronomy.h"`. That header pins FP contraction off
   (`#pragma STDC FP_CONTRACT OFF`) for the rest of the translation unit and
   redirects every libm transcendental `astronomy.c` calls (`sin`, `cos`,
   `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log10`, `pow`, `cbrt`,
   `hypot`) to the `ak_`-prefixed implementations vendored from musl in
   `detmath/`. This removes the dependency on the host libm's last-ULP
   behavior, so ephemeris results are bit-identical across operating systems
   and architectures (issue #28). See
   [Deterministic math (detmath/)](#deterministic-math-detmath) for the full
   picture, including which functions deliberately stay on the host.

## Updating from upstream

1. **Pick the target upstream commit.** Note its full hash and date, and the
   corresponding `+upstream-A.B.C` engine version.

2. **Diff, don't blind-copy.** Fetch upstream `source/c/astronomy.c` and
   `astronomy.h` at the target commit and diff against the current vendored
   files so you can see exactly what changed and re-apply the local patches
   cleanly:

   ```sh
   # from a checkout of the upstream repo at the target commit
   diff -u path/to/upstream/source/c/astronomy.c \
           Sources/CLibAstronomy/astronomy.c
   ```

3. **Apply the upstream changes**, then **re-apply the local patches** above
   (or, if upstream has adopted equivalent thread-safety fixes, confirm that and
   note it). The patch sites are marked in context by the vendoring note; search
   for `pluto_cache_mutex`, `DeltaTFunc`, and the counter names. In particular,
   re-insert the deterministic-math include (patch 6) — the single line
   `#include "ak_detmath.h"` must go **immediately after**
   `#include "astronomy.h"`, so its `FP_CONTRACT OFF` pragma and macro
   redirects cover the whole translation unit.

4. **Refresh the vendoring note** at the top of `astronomy.c`: update the
   upstream commit hash and date, and adjust the patch list if anything changed.

5. **Update `include/astronomy.h`** the same way if the header changed. Check
   whether any new/renamed C symbols need Swift wrappers or affect existing ones.

6. **Verify** (see below).

7. **Changelog & tag.** Add a `CHANGELOG.md` entry, then tag
   `X.Y.Z+upstream-A.B.C`.

## Deterministic math (detmath/)

### Why it exists

Astronomy Engine calls the host C library's transcendental functions (`sin`,
`cos`, `pow`, …). Those are only *accurate*, not *identical*: their last unit
in the last place (last-ULP) results differ between libms — Apple's, glibc,
musl — and even between point releases of the same OS. That is fine for
±1-arcminute astronomy, but it means the same call on two machines can return
positions that differ in the final bits, and those differences compound through
the pipeline. Any downstream consumer that pins exact numeric outputs (notably
the AstrologyKit calibration corpus of expert-locked tests) would then see
"failures" that are really just the host libm changing under it. Issue #28
resolves this by removing the host libm from the transcendental path entirely,
so a given instant produces the same bits on every OS, architecture, and
toolchain, forever.

### What is vendored

`detmath/` contains a trimmed double-precision subset of **musl libc 1.2.5**'s
math sources. Every externally visible symbol is prefixed `ak_` so it can never
collide with, or be resolved to, the host libm at link time. Twelve entry
points are exposed (declared in `include/ak_math.h`):

`ak_sin`, `ak_cos`, `ak_tan`, `ak_asin`, `ak_acos`, `ak_atan`, `ak_atan2`,
`ak_exp`, `ak_log10`, `ak_pow`, `ak_cbrt`, `ak_hypot`

plus their internal kernels (`ak___rem_pio2`, `ak___sin`, `ak_scalbn`, the
`ak___math_*` error helpers, and the `ak___*_data` tables).

Deliberately **not** vendored — these stay on the host and are called
unprefixed: `sqrt`, `fmod`, `floor`, `ceil`, `fabs`, and `isnan`. The first
five are IEEE-754 correctly-rounded / exact operations, so every conforming libm
returns identical bits; there is nothing to pin. `isnan` is a `<math.h>` macro,
not a function — redefining it would break rather than redirect it. Keeping this
handful on the host avoids vendoring code that could never diverge.

### How determinism is pinned

- **FP contraction off.** `ak_detmath.h` and `detmath/ak_libm.h` each issue
  `#pragma STDC FP_CONTRACT OFF` at translation-unit scope. Without it the
  compiler may fuse `a*b+c` into a single fused-multiply-add, and whether it
  does is target- and compiler-dependent — enough to change the last bit even
  with identical source. This pragma is load-bearing: build logs confirm Xcode
  defaults to `-ffp-contract=on`, so the pragma is what actually holds
  contraction off.
- **`__FP_FAST_FMA` undef in `pow.c`.** musl's `pow` takes a different internal
  path when the compiler advertises a fast hardware FMA, and that path is taken
  on Apple Silicon but not on x86, which would diverge the two. `pow.c` does
  `#undef __FP_FAST_FMA` to force the single, FMA-free path everywhere.
- **No `unsafeFlags`, ever.** Determinism is pinned entirely in source
  (pragmas and `#undef`s), never through compiler flags in `Package.swift`.
  SwiftPM refuses to resolve a dependency package that uses `unsafeFlags`, so a
  flag-based approach would make AstronomyKit unusable as a dependency. Any
  future pinning must stay source-level for the same reason.

### Updating musl

Rare, but if you must:

1. **Pin a specific musl release** (e.g. a tagged `v1.2.x`). Never mix files
   from different releases.
2. **Re-apply the adaptations** to each source and to `ak_libm.h`: the `ak_`
   prefixing of every externally visible symbol, the `FP_CONTRACT OFF` pragmas,
   the `#undef __FP_FAST_FMA` in `pow.c`, and the trims noted in `ak_libm.h`'s
   header (long-double support, `TOINT_INTRINSICS`, signaling-NaN, `hidden`
   visibility). Keep `include/ak_math.h` and the `#define` redirects in
   `ak_detmath.h` in sync with the exposed set.
3. **Regenerate the golden constants** in `ReproducibilityTests` — the pinned
   values are specific to the musl release and will shift.
4. **Flag a downstream re-baseline in `CHANGELOG.md`.** A musl bump changes
   last-ULP outputs, so any consumer with position-baselined tests must
   re-baseline once (see the note in the 2.0.0 entry for the wording).

### Portability

This is standard C and works wherever Swift does. Linux (glibc host) is proven
by CI: the bit-exact `ReproducibilityTests` run there and must produce the same
constants as macOS. It works conceptually on Windows too — Swift-on-Windows
compiles C through clang, which honors the `STDC FP_CONTRACT` pragma the same
way. (MSVC ignores that pragma, but SwiftPM never invokes MSVC for C sources, so
that gap does not apply here.)

## Verification

Run the full suite — the JPL/Audit accuracy tests are the correctness gate, the
`ReproducibilityTests` are the bit-exactness gate, and the ThreadSanitizer run
guards the local patches:

```sh
touch .dev-tooling          # enable dev tooling for local builds
swift package resolve
swift build
swift test                  # all suites, incl. JPLValidationTests / AuditValidationTests
swift test --sanitize=thread  # exercises the Pluto / Delta T / counter patches
```

The accuracy suites (`JPLValidationTests`, `AuditValidationTests`) assert against
JPL Horizons and audit reference positions to roughly ±1 arcminute; a regression
there means the vendored math changed and needs investigation before release.

The bit-exactness suite (`ReproducibilityTests`) asserts that transcendental and
ephemeris outputs equal frozen golden constants to the last bit. It must pass in
**both debug and release configurations** and on **both macOS and Linux** CI — a
failure in any one means determinism has broken (a stray host-libm call, FP
contraction leaking back on, or a changed detmath source) and must be resolved
before release. CI also enforces this at the link level: an `nm` guard fails the
Linux build if the `astronomy.c` object references any host-libm transcendental
(`sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log10`, `pow`,
`cbrt`, `hypot`) or if any `detmath/` object leaks one of those or `fma` —
`sqrt`/`fmod`/`floor`/`ceil`/`fabs` remain allowed.

CI runs all of these jobs plus release-configuration and per-platform builds on
every pull request.
