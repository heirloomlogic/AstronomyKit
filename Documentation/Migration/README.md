# Engine migration foundation

Issue #80 freezes the patched C engine before the Swift engine is evaluated. The first chain link records the reference source and current contracts. The second link adds the separate-process comparison protocol and evidence archive. The third link separates the numerical evidence classes and records the measured performance baseline and pilot budgets.

## Frozen C oracle

[`oracle-lock.json`](../../Tools/Migration/Oracle/oracle-lock.json) pins AstronomyKit revision `cdb533dbe85c76b39a958ca92f9155d8bd55b392`, upstream Astronomy Engine revision `826e26ff3a6dc03ee46658b1138fef582d96c5d9`, 38 source and coefficient files, the oracle driver, their SHA-256 hashes, C build flags, and the recorded OS, architecture, compiler, Swift, and Xcode versions. The build script reads the engine files from the pinned Git object, copies the content-addressed driver into the temporary source tree, verifies every hash, and compiles the oracle outside the Swift package dependency graph.

```sh
Tools/Migration/Oracle/freeze-oracle.py --check
Tools/Migration/Oracle/build-oracle.sh .build/reference-oracle
.build/reference-oracle/astronomy-oracle --smoke
```

The build removes any prior executable and metadata before reading the lock or compiling, so a failed rebuild cannot leave an old oracle that appears usable. A successful build writes `build-metadata.json` beside the executable with the binary and lock hashes, actual and recorded environments, whether the relevant environment fields match, and the applied flags. Two builds in the recorded environment must produce the same executable hash.

## Contract inventory

[`contract-inventory.json`](contract-inventory.json) is generated from the compiler's public AstronomyKit symbol graph and the checked-in sources. It owns every public symbol, C function, typedef, constant, and struct field consumed by Swift, documented local patch, generated source or data artifact, cross-cutting contract, and Swift, Python, or shell test file. Public entries classify errors, optional results, serialization, supported-date behavior, and mutable state. Test files are classified by the evidence they provide: independent reference, regression fixture, invariant, or smoke coverage.

```sh
Scripts/migration/generate-contract-inventory.py --check
python3 -m unittest Scripts/migration/test_foundation.py -v
```

The generator fails when it finds an unowned Swift source, test file, generated artifact, C dependency, or patch group. Every run extracts the public symbol graph with the active Swift toolchain; compiler-synthesized ownership spelling is normalized so Swift 6.3 and 6.4 describe the same source API consistently. Updating a mapped surface requires assigning its migration issue and regenerating the inventory; changing the frozen revision requires inspecting and deliberately rewriting the oracle lock.

## Separate-process comparison

[`corpus.json`](../../Tools/Migration/Comparison/corpus.json) defines the hand-selected position, derivative, event, cold/warm, Delta T, fixed-star, Pluto, gravity, Chiron, and error cases. [`downstream-populations-lock.json`](../../Tools/Migration/Comparison/downstream-populations-lock.json) pins four request populations from commit `1add73ec6c117e9b6f3d26e745a3487262ff4c75` by path, compressed byte count, and SHA-256. The coordinator validates and reads every fixed-size record, archives counts and TT ranges, and selects the first active position and state request from each population for comparison.

The coordinator builds the content-addressed C oracle outside SwiftPM and the `AstronomyMigrationRunner` target in Release mode. That executable target is not part of the shipping `AstronomyKit` library product. Each case launches one fresh C process and one fresh Swift process. The checked-in [reference archive](../../Tools/Migration/Comparison/Artifacts/reference) records canonical inputs, parsed outputs, astronomical statuses, process exits, stderr, stdout hashes, source hashes, build metadata, environment, exact machine-readable differences, and downstream population provenance. The C oracle retains its raw executable hash. The Swift runner records a normalized content fingerprint after removing debug data and symbols plus the code signature and UUID from the host-built thin Mach-O; separate scratch paths produce the same fingerprint, while a code mutation changes it.

```sh
python3 Scripts/migration/run-comparison.py --check
python3 -m unittest Scripts/migration/test_comparison.py -v
```

`--check` rebuilds both executables, replays all 18 cases, recovers all 7,746,010 downstream records, and rejects a stale archive or any C/Swift difference. The archive also proves that deliberate numeric, status, Delta T model, and event-order mutations are detected, and that invalid requests fail in both runner processes. Its current comparison contract is exact parsed JSON equality because the Swift surface still delegates to the frozen C implementation.

## Numerical evidence classes

[`numerical-evidence.json`](numerical-evidence.json) keeps exact contracts, numerical regression tolerances, independent astronomical accuracy limits, and mathematically derived bounds separate. Exact C/Swift JSON equality applies only while both runners call the same C engine. A native Swift candidate must preserve exact API, status, time-model, coefficient, event identity, and within-build replay contracts while meeting the existing regression budgets and independent JPL limits. It cannot widen tolerances, refresh frozen fixtures, or cite C agreement as independent accuracy evidence. The solar-altitude certificate must be re-derived from the shipped Swift expressions.

## Measured Release baseline and pilot budgets

[`performance-baseline.json`](performance-baseline.json) records three clean and touched-source incremental Release builds plus five fresh-process runtime and peak-memory trials. It hashes `Package.swift`, the coordinator, the benchmark runner, and every Swift and C input, including Swift sources in nested directories. The development-only `AstronomyMigrationPerformanceRunner` calls the public Swift API and is not a library product.

The baseline host was a Mac13,1 with macOS 27.0.1, Apple Swift 6.4, and Apple clang 21. The median representative request latency was 20,110.4 ns. Median cold and warm throughput were 13,255,128 and 14,133,277 operations per second. Maximum peak resident memory was 8,945,664 bytes, the stripped probe was 13,081,040 bytes, the slowest clean build took 28.600 seconds, and the slowest touched-source incremental build took 8.445 seconds.

The pure-Swift pilot must stay at or below 30,166 ns median latency, 11,182,080 bytes peak resident memory, 14,389,145 stripped bytes, 42.900 seconds for the slowest clean build, and 12.668 seconds for the slowest touched-source build. Cold and warm median throughput must stay at or above 10,604,102 and 11,306,621 operations per second. These figures give latency and build time 50% headroom, throughput 20%, peak memory 25%, and deterministic binary size 10%. Candidate measurement uses the same five runtime trials, three build trials, one build preflight, runner, host, and toolchain.

## Full Swift model representation prototype

Issue #82 generated a development-only immutable Swift representation from the pinned polynomial, VSOP87B, and IAU2000B archives. Twenty-nine bounded source units contain all 1,431,768 polynomial binary64 bit patterns, 36,712 validity bits including 413 disabled segments, 35,080 VSOP terms with 135 series index records, and 77 nutation rows. The generator validates every input checksum, writes raw `UInt64` bit patterns instead of reformatted floating-point literals, and records recursive input and output hashes in `Scripts/model-data/swift-prototype-manifest.json`.

The generated storage is split across one module per polynomial body plus VSOP and nutation modules. A single module did not finish a bounded Release build after 129 seconds and sampled a 4.83 GB compiler process. The modular layout compiled, and the compiled whole-model FNV-1a checksum is `0x0cd4295bc6da4d62`. The prototype targets are available only when the ignored `.model-prototype` sentinel exists, so ordinary package builds do not compile the failed representation.

[`model-prototype-evidence.json`](model-prototype-evidence.json) preserves historical Apple-host measurements from the exact working-tree source hashes in that record. Those hashes identify an uncommitted snapshot rather than a Git commit, and they differ from the current PR head. Clean Release builds took 41.232, 42.647, and 51.130 seconds, so the slowest trial fails the fixed 42.900-second gate. Touched-source Release builds passed at 2.292 to 3.310 seconds, and the stripped runner passed at 12,513,696 bytes. Five fresh-process first accesses took 7,958 to 16,333 ns and used 5,931,008 bytes peak RSS. The full checksum sweep took 5.564 to 11.876 ms and used 18.252 to 18.285 MB peak RSS; that sweep deliberately touches every table page and is not the issue #80 request workload.

The builder's separate bounded Debug preflight did not finish within 180 seconds; the captured coordinator did not run that preflight. The repaired coordinator runs and identifies its own bounded Debug preflight, validates runner values and checksums, hashes its protocol and baseline, and finalizes failed runs as incomplete. No current-head performance run was captured during review repair. Linux measurements and the issue #80 astronomical latency and throughput workloads are absent. The representation therefore fails issue #82 and does not unblock the Sun-path pilot. No runtime-loaded storage alternative, budget change, or numerical-tolerance change was adopted.

Regeneration and verification use the committed archives and need no network access:

```sh
python3 Scripts/generate-models.py --swift-prototype
python3 Scripts/generate-models.py --check-swift-prototype
python3 -m unittest discover -s Scripts/model-prototype -p 'test_*.py' -v
touch .model-prototype
swift package purge-cache
swift test -c release --filter ModelDataTests
python3 Scripts/model-prototype/measure.py --measure
```

The committed generated sources let a clean prototype build run without Python, downloads, or runtime data files. Python is required only to regenerate or verify the source from the frozen archives. Remove `.model-prototype` and purge the package cache after prototype work.

```sh
python3 Scripts/migration/performance_baseline.py --check
python3 Scripts/migration/performance_baseline.py --compare
python3 -m unittest Scripts/migration/test_performance.py -v
```

`--check` validates the archive, source hashes, budget derivation, and baseline self-evaluation without timing CI hardware. `--compare` rebuilds and measures a candidate, rejects a different host or toolchain, and reports every failed metric. The unit tests apply deliberate regressions to latency, both throughput workloads, peak memory, binary size, and both build costs.

Peak resident memory is the allocation/memory gate because it is available for the mixed Swift/C baseline and a native Swift candidate without profiler instrumentation. This record does not contain allocation counts. The build protocol runs one unrecorded preflight build, then deletes the package scratch directory before each recorded clean trial. It measures a scratch-clean build with compiler and package-manager caches warm, not first use of the toolchain on a host. Before the preflight was standardized, the first isolated diagnostic recorded clean trials of 47.927, 26.825, and 15.662 seconds; a repeat recorded 15.466, 10.569, and 10.312 seconds. These diagnostics are excluded from the baseline rather than selected as candidate evidence. The timings came from an otherwise ordinary shared development host, so process scheduling and thermal state remain limitations. A different host or toolchain needs its own reviewed baseline instead of reusing these absolute numbers.
