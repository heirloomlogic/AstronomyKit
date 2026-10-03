# Full coefficient representation protocol

Issue #82 establishes whether the complete embedded coefficient representation can support the native Sun-path pilot. It does not implement that pilot or establish astronomical model accuracy. The representation includes every frozen polynomial coefficient and validity bit, all VSOP87B terms and series metadata, and all 77 nutation rows. Generated values must preserve binary64 bit patterns and flattened order; the compiled whole-model checksum is `0x0cd4295bc6da4d62`.

## Embedded representation

The current candidate packs each bounded UInt64 coefficient chunk into an ASCII7 `StaticString` literal: little-endian word bytes, a continuous least-significant-bit-first seven-bit stream, and zero padding only at the final code unit. Swift source escapes preserve every control character, backslash, and quote. Pure Swift code lazily decodes each payload once into an immutable UInt64 array, preserving the existing indexed access and flattened checksum. There are no external model files, network fetches, resource bundles, decoder libraries, or additional targets.

This representation introduces decoding and allocation on first access. It is not a zero-decode literal array. Fresh-process first access and the complete sweep must report that cost and resident memory, and #83 must still judge astronomical cold/warm request behavior against its unchanged gates. Independent archive/literal decoding and compiled checksums establish exact stored bits; neither establishes astronomical product accuracy.

## Measurement and comparison policy

For each Apple or Linux environment, first record a fresh C-backed package comparison baseline with the unchanged `Scripts/migration/performance_baseline.py` coordinator. Preserve the historical `performance-baseline.json` and `model-prototype-evidence.json` bytes. The fresh comparison record identifies its source revision, source hashes, measured OS, architecture, hardware, processor count, Swift and C toolchains, commands, workload, and three clean/incremental Release build trials. Its existing 1.5× build-cost and 1.1× stripped-size margins supply the applicable representation ceilings on that same environment. This is a supplementary comparison record; it does not claim that measurements on a changed compiler satisfy the historical environment's absolute ceilings.

The candidate coordinator requires three clean and three touched-source build trials in both Debug and Release, following one unrecorded preflight per configuration. Each clean trial removes its package scratch directory while compiler/package-manager caches remain warm. Incremental trials modify `ModelData.swift`'s timestamp, matching the baseline's touched-source protocol. Record wall-clock seconds and compiler peak resident bytes for every trial. A single successful preflight or a timeout cannot replace the complete trial counts.

The quantitative representation gates compare the slowest candidate clean and incremental Release builds with their matching comparison-baseline ceilings and compare stripped Release artifact bytes with the comparison baseline's size ceiling. Debug build time, compiler RSS, first-access latency, checksum-sweep latency, and their runtime RSS are measured observations: the original protocol did not prescribe matching numerical ceilings for them. Completed Debug trials, exact data checks, complete runtime samples, and clean consumer packaging remain mandatory regardless of those observations.

Collect five fresh-process first-access samples and five full-sweep samples. Each sample must return the expected mode, nonnegative elapsed nanoseconds, positive resident bytes, and expected coefficient or whole-model checksum. The full sweep deliberately touches every table and is distinct from an astronomical request workload. Its runtime memory and throughput do not establish or replace #83's latency, cold/warm throughput, or runtime-memory gates.

## Consumer and evidence integrity

Build and execute a fresh Release consumer against the prototype product using only the manifest and committed Sources, Tests, and Tools. Do not copy generation scripts, development-tooling sentinels, or runtime model resources. Verify the evaluated package has no network dependency, build plugin, or resource requirement, and verify the consumer's compiled whole-model checksum. The prototype sentinel enables the development-only product; ordinary downstream AstronomyKit dependencies retain the existing manifest contract.

Hash the actual generator, archives, generated manifest, copied source inputs, coordinator, workload, comparison baseline, historical baseline, executables, and retained raw command/time logs. Compare input snapshots before and after the campaign and reject changed inputs, a changed baseline, a changed environment, incomplete trials, nonfinite measurements, or mismatched checksums. The final offline check must recompute the reported evaluation and reject stale or altered evidence.

The focused Linux workflow explicitly enables the full prototype, checks generated sources, runs compiled Debug and Release tests, records its C comparison baseline, performs the complete candidate/consumer campaign on the same runner, and uploads source-bound records and raw logs. A successful ordinary Linux package test does not establish prototype feasibility. Keep the hosted tested revision and run identity with downloaded evidence.

## Pilot disposition

Select the representation for #83 only after both Apple and Linux records pass the applicable quantitative gates and complete every exact-data, Debug/Release, runtime-sample, and consumer criterion, with independent review of the final sources and evidence. #83 must still establish native Earth/Sun/horizon correctness, derivatives, cache and concurrency behavior, numerical seams/fallbacks, and all astronomical runtime budgets. No storage-contract change, model replacement, or budget relaxation is authorized by this protocol.
