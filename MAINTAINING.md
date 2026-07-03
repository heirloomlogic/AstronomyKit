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

The vendored `astronomy.c` differs from upstream only by these thread-safety
patches. Upstream is single-threaded by design; AstronomyKit advertises
`Sendable` safety, so these are required. **After any upstream sync they must be
re-applied, or verified as adopted upstream.**

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

3. **Apply the upstream changes**, then **re-apply the three local patches**
   above (or, if upstream has adopted equivalent thread-safety fixes, confirm
   that and note it). The patch sites are marked in context by the vendoring
   note; search for `pluto_cache_mutex`, `DeltaTFunc`, and the counter names.

4. **Refresh the vendoring note** at the top of `astronomy.c`: update the
   upstream commit hash and date, and adjust the patch list if anything changed.

5. **Update `include/astronomy.h`** the same way if the header changed. Check
   whether any new/renamed C symbols need Swift wrappers or affect existing ones.

6. **Verify** (see below).

7. **Changelog & tag.** Add a `CHANGELOG.md` entry, then tag
   `X.Y.Z+upstream-A.B.C`.

## Verification

Run the full suite — the JPL/Audit accuracy tests are the correctness gate, and
the ThreadSanitizer run guards the local patches:

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
CI runs these jobs plus release-configuration and per-platform builds on every
pull request.
