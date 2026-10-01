# Engine migration foundation

Issue #80 freezes the patched C engine before the Swift engine is evaluated. The first chain link records the reference source and current contracts. The second link adds the separate-process comparison protocol and evidence archive. The measured performance baseline and acceptance budgets remain open for the third link.

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

The coordinator builds the content-addressed C oracle outside SwiftPM and the `AstronomyMigrationRunner` target in Release mode. That executable target is not part of the shipping `AstronomyKit` library product. Each case launches one fresh C process and one fresh Swift process. The checked-in [reference archive](../../Tools/Migration/Comparison/Artifacts/reference) records canonical inputs, parsed outputs, astronomical statuses, process exits, stderr, stdout hashes, source and executable hashes, build metadata, environment, exact machine-readable differences, and downstream population provenance.

```sh
python3 Scripts/migration/run-comparison.py --check
python3 -m unittest Scripts/migration/test_comparison.py -v
```

`--check` rebuilds both executables, replays all 18 cases, recovers all 7,746,010 downstream records, and rejects a stale archive or any C/Swift difference. The archive also proves that deliberate numeric, status, Delta T model, and event-order mutations are detected, and that invalid requests fail in both runner processes. Its current comparison contract is exact parsed JSON equality because the Swift surface still delegates to the frozen C implementation. Link 3 will define the separate numerical-regression and independent-accuracy contracts needed for a native Swift candidate.
