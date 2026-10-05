# Engine migration foundation

Issue #80 freezes the patched C engine before the Swift engine is evaluated. The first chain link records the reference source and current contracts. The second link adds the separate-process comparison protocol and evidence archive. The third link separates the numerical evidence classes and records the measured performance baseline and pilot budgets.

[`IndependentReferenceEvidence.md`](IndependentReferenceEvidence.md) records the offline JPL, USNO, NASA, and EclipseWise reference archive, its evidence classes, mutation controls, known disagreements, and unsupported domains.

[`SeasonPhaseEvidence.md`](SeasonPhaseEvidence.md) applies the strict event target to every pinned season from 1900 through 2100 and every lunar quarter in the archive's decennial years, while retaining nominal failures, source-precision limits and the missing 2101–2130 coverage.

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

`--check` rebuilds both executables, replays all 18 cases, recovers all 7,746,010 downstream records, and rejects a stale archive or any undeclared C/Swift difference. Exact parsed JSON equality remains the default while the Swift surface delegates to the frozen C implementation. The Chiron case retains the three raw coordinate differences caused by #108's source-backed integration-step correction; its declaration names the exact permitted paths and independent evidence, and any missing or additional difference fails. The archive also proves that deliberate numeric, status, Delta T model, and event-order mutations are detected, and that invalid requests fail in both runner processes.

## Numerical evidence classes

[`numerical-evidence.json`](numerical-evidence.json) keeps exact contracts, numerical regression tolerances, independent astronomical accuracy limits, and mathematically derived bounds separate. Exact C/Swift JSON equality applies only while both runners call the same C engine. A native Swift candidate must preserve exact API, status, time-model, coefficient, event identity, and within-build replay contracts while meeting the existing regression budgets and independent JPL limits. It cannot widen tolerances, refresh frozen fixtures, or cite C agreement as independent accuracy evidence. The solar-altitude certificate must be re-derived from the shipped Swift expressions.

## Measured Release baseline and pilot budgets

[`performance-baseline.json`](performance-baseline.json) records three clean and touched-source incremental Release builds plus five fresh-process runtime and peak-memory trials. It hashes `Package.swift`, the coordinator, the benchmark runner, and every Swift and C input, including Swift sources in nested directories. The development-only `AstronomyMigrationPerformanceRunner` calls the public Swift API and is not a library product.

The baseline host was a Mac13,1 with macOS 27.0.1, Apple Swift 6.4, and Apple clang 21. The median representative request latency was 20,110.4 ns. Median cold and warm throughput were 13,255,128 and 14,133,277 operations per second. Maximum peak resident memory was 8,945,664 bytes, the stripped probe was 13,081,040 bytes, the slowest clean build took 28.600 seconds, and the slowest touched-source incremental build took 8.445 seconds.

The pure-Swift pilot must stay at or below 30,166 ns median latency, 11,182,080 bytes peak resident memory, 14,389,145 stripped bytes, 42.900 seconds for the slowest clean build, and 12.668 seconds for the slowest touched-source build. Cold and warm median throughput must stay at or above 10,604,102 and 11,306,621 operations per second. These figures give latency and build time 50% headroom, throughput 20%, peak memory 25%, and deterministic binary size 10%. Candidate measurement uses the same five runtime trials, three build trials, one build preflight, runner, host, and toolchain.

## Full Swift model representation prototype

[ModelRepresentation.md](ModelRepresentation.md) selects the lossless embedded ASCII7 representation after complete Apple and Linux qualification and independent review. Issue #82's engineering gate passes, permitting #83's Sun-path pilot to start. [ModelRepresentationProtocol.md](ModelRepresentationProtocol.md) defines the campaign and source-bound comparison policy. The historical array measurements below remain preserved; they do not qualify the new representation. Supplementary same-environment baselines preserve the original margins while accounting explicitly for toolchain drift, and all astronomical pilot gates remain unchanged.

### Historical literal-array experiment

The original #82 experiment generated a development-only immutable Swift representation from the pinned polynomial, VSOP87B, and IAU2000B archives. One hundred and one generated source units contained all 1,431,768 polynomial binary64 bit patterns, 36,712 validity bits including 413 disabled segments, 35,080 VSOP terms with 135 series index records, and 77 nutation rows. Polynomial array expressions were limited to 16,384 elements. The generator validated every input checksum, wrote raw `UInt64` bit patterns instead of reformatted floating-point literals, and recorded recursive input and output hashes in `Scripts/model-data/swift-prototype-manifest.json`.

The generated storage was split across one module per polynomial body plus VSOP and nutation modules. Smaller expressions lowered measured Release compiler peak RSS without changing the embedded data or runtime access path. A 26-target grouped-chunk experiment and a 90-target isolated-chunk experiment were rejected because the default Swift Build backend failed during graph initialization with `Unknown error parsing property list`; the deprecated native backend began compiling the 90-target graph, but it was outside the fixed protocol. That layout compiled in Release with whole-model FNV-1a checksum `0x0cd4295bc6da4d62`. The prototype targets remain available only when the ignored `.model-prototype` sentinel exists, so ordinary package builds do not compile the prototype.

[`model-prototype-evidence.json`](model-prototype-evidence.json) retains the 16,384-element layout's measurements on the historical Apple host and toolchain. Its 106 input hashes bind the historical measured package, protocol, runner, and prototype sources. Clean Release builds took 42.009, 35.986, and 38.394 seconds, passing the fixed 42.900-second gate. Touched-source Release builds took 2.350 to 2.681 seconds and passed the 12.668-second gate. Release compiler peak RSS was 1.347 to 1.365 GB, and the stripped runner passed at 12,540,528 bytes. Five fresh-process first accesses took 7,958 to 23,084 ns and used 5,963,776 to 5,996,544 bytes peak RSS. The full checksum sweep took 6.355 to 12.633 ms and used 18,284,544 to 18,300,928 bytes peak RSS; that sweep deliberately touches every table page and is not the issue #80 request workload.

The historical coordinator's isolated clean Debug build did not finish within its 180-second limit, and Linux measurements were absent. That record remains incomplete and did not unblock #83. Its bytes and measured failure remain preserved. Astronomical latency and throughput qualification still require #83's actual Sun-path calculation; neither this historical experiment nor the new representation campaign substitutes a table sweep for that workload.

### Current generation and verification

Regeneration and verification use the committed archives and need no network access:

```sh
python3 Scripts/generate-models.py --swift-prototype
python3 Scripts/generate-models.py --check-swift-prototype
python3 -m unittest discover -s Scripts/model-prototype -p 'test_*.py' -v
touch .model-prototype
swift package purge-cache
swift test -c release --filter ModelDataTests
python3 Scripts/model-prototype/measure.py --measure --baseline /path/to/comparison-baseline.json --output /path/to/representation-evidence.json
```

The committed generated sources let a clean prototype build run without Python, downloads, or runtime data files. Python is required only to regenerate or verify the source from the frozen archives. Remove `.model-prototype` and purge the package cache after prototype work.

```sh
python3 Scripts/migration/verify_performance_baseline.py
python3 Scripts/migration/performance_baseline.py --compare
python3 Scripts/migration/performance_candidate.py --write
python3 Scripts/migration/performance_candidate.py --check
python3 -m unittest Scripts/migration/test_performance.py -v
python3 -m unittest Scripts/migration/test_performance_candidate.py -v
```

The baseline was captured from a dirty working tree at recorded HEAD `9f7a92630c1192adfc323076b17aa4130df4962d`. Merged commit `fad9e9b5d8e3dd823d1ce1f25c51b80ac23b11ff` later committed the exact 43 recorded input files without changing their bytes. `verify_performance_baseline.py` validates the record, discovers every measured input in that immutable Git tree, verifies every recorded hash, derives the same fixed budgets, and evaluates the baseline against them without timing CI hardware or requiring a candidate checkout to retain the historical package manifest. `--compare` rebuilds and measures a candidate, rejects a different host or toolchain or measurement protocol, and reports every failed metric. After a passing comparison, `performance_candidate.py --write` repeats the protocol and records source-bound candidate evidence without changing the frozen baseline. Its `--check` mode accepts the original inputs directly or requires a matching candidate artifact that uses the frozen environment and protocol and passes every fixed budget. Hosted CI uses that evidence check so production source changes cannot pass with stale hashes or unrecorded measurements. The unit tests apply deliberate regressions to latency, both throughput workloads, peak memory, binary size, both build costs, and the frozen input binding, and reject stale or tampered candidate evidence.

Peak resident memory is the allocation/memory gate because it is available for the mixed Swift/C baseline and a native Swift candidate without profiler instrumentation. This record does not contain allocation counts. The build protocol runs one unrecorded preflight build, then deletes the package scratch directory before each recorded clean trial. It measures a scratch-clean build with compiler and package-manager caches warm, not first use of the toolchain on a host. Before the preflight was standardized, the first isolated diagnostic recorded clean trials of 47.927, 26.825, and 15.662 seconds; a repeat recorded 15.466, 10.569, and 10.312 seconds. These diagnostics are excluded from the baseline rather than selected as candidate evidence. The timings came from an otherwise ordinary shared development host, so process scheduling and thermal state remain limitations. A different host or toolchain needs its own reviewed baseline instead of reusing these absolute numbers.
