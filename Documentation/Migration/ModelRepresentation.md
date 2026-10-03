# Selected full coefficient representation

Issue #82 passes its engineering acceptance criteria. Select the development-only embedded ASCII7 representation for #83's Sun-path pilot. Both Apple and Linux completed the full measurement protocol, passed the applicable Release build and artifact-size ceilings, preserved every frozen coefficient/validity bit, and built and executed a clean consumer. This permits pilot implementation; astronomical accuracy, request performance, downstream acceptance, integration, and release qualification remain separate work.

## Representation and exact data

The [generator](../../Scripts/generate-models.py) creates 108 source units in the existing polynomial-body, VSOP, and nutation modules. Ninety-nine bounded coefficient payloads store 1,537,855 UInt64 words, including all 1,431,768 polynomial coefficients, 35,080 VSOP term triplets and all 77 nutation rows. Metadata retains 135 VSOP series, the TT grid bounds, 36,712 validity bits, and all 413 disabled polynomial segments. Polynomial and VSOP coefficient chunks contain at most 16,384 words; scalar access preserves triplets across every VSOP chunk seam.

Each payload is a StaticString containing the little-endian word bytes as a continuous least-significant-bit-first seven-bit stream with final zero padding. The encoded payload occupies 14,060,429 bytes; decoded words occupy 12,302,840 bytes. A pure Swift initializer decodes each chunk once into an immutable array. Source escaping preserves all control characters, quotes, and backslashes. Independent Python decoding of every actual generated literal matches the frozen archive bit-for-bit. Compiled Debug and Release tests retain whole-model FNV `0x0cd4295bc6da4d62` and first Earth word `0xbfd0eee034b80b58`.

There are no runtime model files, downloads, resource bundles, external decoding libraries, new targets, or shipping model/API changes. The `.model-prototype` sentinel enables the development-only product. Lazy decoding introduces allocation and first-access cost; the measured observations below expose that cost and do not constitute astronomical runtime qualification.

## Qualified source and review

The implementation is [fcf8539123cd1326fe0e93bf9ce18ac8ded4ed3e](https://github.com/heirloomlogic/AstronomyKit/commit/fcf8539123cd1326fe0e93bf9ce18ac8ded4ed3e), followed by whitespace-only distance-test formatting at [a7d0a870a314c7fe68959298319363b44fd7ab12](https://github.com/heirloomlogic/AstronomyKit/commit/a7d0a870a314c7fe68959298319363b44fd7ab12). Apple final measurements and compiled tests ran at `a7d0a870a314c7fe68959298319363b44fd7ab12`. Linux qualification ran at published PR head `1707e6dcc32cbbee7673e0ae047a5258738c1cab`, with tested PR merge revision `5e250825bfb3be8ab15c4b6638fcbf0fe4d5845c`. The intervening commit refreshes only the inventory's test-file hash; all 278 candidate input hashes match between Apple, Linux, and the final source tree.

[PR #117](https://github.com/heirloomlogic/AstronomyKit/pull/117) contains the completed engineering remediation and distance/model diagnosis, stacked on [PR #116](https://github.com/heirloomlogic/AstronomyKit/pull/116)'s earlier partial storage experiment. Both PRs remain open and unmerged at qualification; main is unchanged. [Hosted Linux qualification](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37071816533) passed, as did all eight [ordinary Tests workflow jobs](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37071816579) and [strict lint](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37071816534) at `1707e6dc`.

The independent read-only reviewer approved the generator and decoder, lossless archive/literal identity, measurement coordinator and negative controls, final Apple receipts, and final Linux receipts. Review was separate from generation, measurement, and documentation authorship. The archived receipts identify exact measured revisions, source hashes, protocol/workload hashes, command exits, timing/RSS logs, and compiled checksums. This review does not claim an independent astronomical accuracy result.

## Measurements

The [protocol](ModelRepresentationProtocol.md) was published before candidate judgment. Fresh C-backed comparison baselines use the unchanged foundation coordinator on each candidate's actual host/toolchain. The existing 1.5× Release build and 1.1× stripped-size margins are unchanged; the historical [baseline](performance-baseline.json) and incomplete [literal-array experiment](model-prototype-evidence.json) retain their original bytes and outcomes. New records do not reinterpret the historical compiler's absolute ceilings. Every #83 astronomical runtime gate remains unchanged.

Apple: Mac13,1 arm64, ten processors, macOS 27.0.1, Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), Apple clang 21. Linux: hosted x86_64, four processors, Linux 6.17/glibc 2.39, Swift 6.2.1 and clang 17. Exact environment strings are in the baseline and candidate JSON records.

| Quantitative engineering gate | Apple observation / ceiling | Linux observation / ceiling | Decision |
|---|---|---|---|
| Slowest clean Release build | 5.700 s / 14.745 s | 5.002 s / 16.701 s | Pass |
| Slowest touched-source Release build | 1.878 s / 4.864 s | 1.034 s / 4.755 s | Pass |
| Stripped Release artifact | 14,342,224 / 14,388,793 bytes | 14,237,432 / 14,474,012 bytes | Pass |

Each platform completed three clean and three touched-source trials in Debug and Release after one preflight per configuration, five fresh-process first-access samples, five full-sweep samples, and a fresh Release consumer build/execution. The consumer package contained no generation scripts or development plugins and required no model resources or network dependencies; it executed the exact whole-model checksum. Apple compiled tests passed 703 Debug tests in 186 suites and five focused Release tests. Linux passed the five coefficient tests in both configurations. All 43 prototype Python tests, deterministic regeneration, and the active-compiler inventory check passed.

| Measured observation; no invented numerical ceiling | Apple | Linux |
|---|---|---|
| Slowest clean Debug build | 6.270 s | 9.374 s |
| Slowest touched-source Debug build | 1.697 s | 0.799 s |
| Highest clean Debug compiler RSS | 286,998,528 bytes | 284,798,976 bytes |
| Highest clean Release compiler RSS | 283,082,752 bytes | 254,513,152 bytes |
| Fresh first access, five samples | 0.540–0.643 ms | 0.606–0.636 ms |
| First-access peak RSS | 6,340,608 bytes | 10,293,248 bytes |
| Complete sweep, five samples | 60.231–69.440 ms | 63.240–63.888 ms |
| Full-sweep peak RSS | 33,947,648 bytes | 36,622,336 bytes |

Apple artifact headroom is only 46,569 bytes; Linux headroom is 236,580 bytes. Future source/toolchain changes require fresh qualification. The complete sweep decodes and touches every table, so its memory/throughput observations cannot substitute for #83's Earth/Sun/horizon request workloads.

## Raw evidence and reproduction

[Apple evidence](ModelRepresentation/macos/) contains the paired comparison baseline, final candidate record, durable raw command/time logs, compiled-test source receipt, and Debug/Release test and checksum logs. [Linux evidence](ModelRepresentation/linux/) contains the same campaign evidence, compiled Debug/Release logs, C baseline log, and hosted execution identity. Records and logs are copied byte-for-byte from the measured runs; offline validation recomputes all hashes and decisions.

```sh
python3 Scripts/generate-models.py --check-swift-prototype
python3 -m unittest discover -s Scripts/model-prototype -p 'test_*.py' -v
python3 Scripts/model-prototype/measure.py --check --baseline Documentation/Migration/ModelRepresentation/macos/comparison-baseline-macos.json --output Documentation/Migration/ModelRepresentation/macos/representation-macos-final.json
python3 Scripts/model-prototype/measure.py --check --baseline Documentation/Migration/ModelRepresentation/linux/comparison-baseline-linux.json --output Documentation/Migration/ModelRepresentation/linux/representation-linux.json
```

Regenerate with `python3 Scripts/generate-models.py --swift-prototype`. For a new campaign, first acquire a fresh same-environment C baseline with the unchanged foundation coordinator, then use new explicit output paths. Never overwrite either historical baseline or a retained candidate. The focused workflow performs the baseline acquisition, compiled tests, candidate campaign, consumer check, and artifact retention together on Linux.

```sh
python3 - <<'PYBASELINE'
import importlib.util
import json
from pathlib import Path
spec = importlib.util.spec_from_file_location("performance_baseline", "Scripts/migration/performance_baseline.py")
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)
Path("comparison-baseline-new.json").write_text(json.dumps(baseline.measure(), indent=2, sort_keys=True) + "\n")
PYBASELINE
python3 Scripts/model-prototype/measure.py --measure --baseline comparison-baseline-new.json --output representation-new.json
```

Enable `.model-prototype` in an isolated checkout before `swift test --filter ModelDataTests` and `swift test -c release --filter ModelDataTests`; ordinary package consumers continue to use the shipping C-backed model. Python is needed for evidence generation/checking, not for the clean consumer's Swift build or execution.

## Remaining boundaries

Issue #83 may start the native Earth/Sun/time/orientation/altitude pilot using this representation. It must establish astronomical parity and independent correctness, derivatives, cache/concurrency behavior, numerical seams/fallbacks, and all request latency, cold/warm throughput, and runtime-memory budgets. A passing representation sweep proves none of those. Re-run affected checks after integration, as required by #79.

The separate distance/model diagnosis is complete as engineering evidence. Issues #81 and #119 remain open for their outstanding independent-distance/product/model decisions; no limits, supported dates, model replacement, or scientific acceptance were invented or relaxed. Those decisions do not form a native prerequisite for #83. This disposition closes #82's engineering gate only.
