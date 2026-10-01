# Engine migration foundation

Issue #80 freezes the patched C engine before the Swift engine is evaluated. This first chain link records the reference source and current contracts. The separate-process comparison archive, representative corpus, negative controls, measured performance baseline, and acceptance budgets belong to the next two links and remain open.

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
