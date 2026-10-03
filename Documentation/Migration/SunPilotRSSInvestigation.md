# Linux Sun pilot RSS investigation

## Decision

Issue #83 remains open. The final merged pilot evidence repeats the Linux RSS failure on two clean hosted merge revisions, while the matched C process remains below 3.2 MB. A successful workflow means the evidence campaign completed; both reports retain `qualified: false` and name `peakResidentBytes` as the exceeded fixed budget.

## Existing receipts

| Workflow | Source head | Tested merge | Swift 6.2.1 Release peak RSS | Matched C peak RSS | Result |
| --- | --- | --- | ---: | ---: | --- |
| [37088341082](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37088341082) | `24befa51bf66e5434ed4800fa7e321f2bf81bb38` | `3459e952c07d69efa8c5cb9443c3296a2539106e` | 21,409,792 bytes | 3,198,976 bytes | RSS fails; numerical campaign passes |
| [37088619287](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37088619287) | `f9d01dcac7c541fd1b7e742f1da34cad96f19c29` | `3405fbc0711b25a393af644a3b8692baf108cbba` | 21,397,504 bytes | 2,977,792 bytes | RSS fails; numerical campaign passes |

The fixed ceiling is 11,182,080 bytes from `performance-baseline.json` with SHA-256 `fb0be646199060b40860f858a210fa5f6b461ecf6aac06741ac0aa1ad027844a`. The two isolated-manifest runs use the same manifest bytes and source hashes; their peak difference is 12,288 bytes. This repeat establishes that the first result was not removed by the final documentation commit. It does not identify which runtime stage makes pages resident.

## Original hosted attribution result and correction

[Workflow 37125664455](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37125664455) tested clean merge revision `d38738b28af45e7af50904a7942d676ce1c0166e` for source head `5e5e5c7fb3b1b9e404dc2c59b32092d8792d2e0f` with Swift 6.2.1 on x86_64 Linux. Debug and Release each passed 67,240 numerical comparisons and the perturbation control. All 11 checks on that source head passed. The report remains `qualified: false`; peak RSS is the only exceeded fixed build, size, and memory observation.

| Fresh process stage | Swift Release RSS, five-trial range (median) | C RSS, five-trial range (median) |
| --- | ---: | ---: |
| Startup control | 17,592,320–17,776,640 (17,653,760) | 1,982,464–2,097,152 (2,035,712) |
| Fixed JSON serialization | 19,161,088–19,316,736 (19,243,008) | 2,039,808–2,088,960 (2,072,576) |
| Polynomial Earth | 18,599,936–18,722,816 (18,690,048) | 2,371,584–2,555,904 (2,486,272) |
| Full-series Earth | 19,050,496–19,255,296 (19,193,856) | 2,584,576–2,670,592 (2,625,536) |
| Polynomial cache | 18,833,408–19,046,400 (19,005,440) | 2,830,336–2,916,352 (2,850,816) |
| Fallback cache | 19,300,352–19,378,176 (19,337,216) | 2,764,800–2,846,720 (2,809,856) |
| First access | 19,169,280–19,357,696 (19,206,144) | 2,801,664–2,932,736 (2,809,856) |
| Fresh polynomial | 19,120,128–19,353,600 (19,283,968) | 2,801,664–2,904,064 (2,871,296) |
| Repeated polynomial | 19,099,648–19,419,136 (19,181,568) | 2,752,512–2,854,912 (2,768,896) |
| Fresh fallback | 19,505,152–19,697,664 (19,537,920) | 2,711,552–2,850,816 (2,781,184) |
| Repeated fallback | 19,525,632–19,656,704 (19,570,688) | 2,781,184–2,932,736 (2,867,200) |
| Aggregate | 21,139,456–21,278,720 (21,250,048) | 2,863,104–3,039,232 (2,895,872) |

The lowest Release startup control is 6,410,240 bytes above the 11,182,080-byte ceiling before the runner accesses model coefficients, evaluator caches, or astronomical workloads. The current Linux executable and runtime therefore fail the absolute gate before model-level optimization can decide the result. Complete-series evaluation and the larger workloads make additional pages resident, but they are not the primary cause of the absolute failure.

The original report's SHA-256 is `5420357ecb798ee85cb0d130e3cbea310a4283c53ab877152ffa73cdb843affd`. Its raw stdout reveals two measurement defects: the Swift polynomial and fallback Earth checksums were `0.19756834584757474` and `-1.0334993594907775`, while C produced `0.19759227388022271` and `-1.0334418720675367`; the aggregate Swift probe also created a new evaluator per mode instead of preserving the pre-attribution shared evaluator. The Earth-only and aggregate rows above describe the pre-fix binaries and are not matched fixed-head evidence. The startup, serialization, cache, and isolated workload rows remain measurements of their named pre-fix processes; the startup conclusion is independent of the two defects.

The raw `report.json`, stdout checksums, `/usr/bin/time` logs, binaries, source hashes, evaluated manifest, and compressed numerical rows are retained in the workflow artifact `native-sun-pilot-linux-37125664455-1`. The successful workflow establishes completed evidence collection at the tested merge revision. It does not pass the RSS gate. The corrected result is recorded below.

## Corrected hosted attribution result

[Workflow 37126885561](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37126885561) tested clean merge revision `3e48483ea4b1585c4be37b6ef0b843244978c649` for source head `32995d23156fb0ce76806d044ae5e4a34481ef59` with Swift 6.2.1 on x86_64 Linux. All 11 checks on that source head passed. Debug and Release each passed 67,240 numerical comparisons with zero failures and detected all eight perturbed fallback cases. Their largest coordinate difference was `1.1368683772161603e-13°` in altitude; every other recorded maximum was zero.

| Fresh process stage | Swift Release RSS, five-trial range (median) | C RSS, five-trial range (median) |
| --- | ---: | ---: |
| Startup control | 17,670,144–17,772,544 (17,694,720) | 1,904,640–2,088,960 (2,068,480) |
| Fixed JSON serialization | 19,181,568–19,329,024 (19,243,008) | 1,949,696–2,121,728 (2,064,384) |
| Polynomial Earth | 18,604,032–18,702,336 (18,681,856) | 2,392,064–2,543,616 (2,449,408) |
| Full-series Earth | 19,058,688–19,206,144 (19,156,992) | 2,584,576–2,777,088 (2,670,592) |
| Aggregate | 21,229,568–21,413,888 (21,315,584) | 2,805,760–3,043,328 (2,928,640) |

Every candidate polynomial Earth trial emitted `0.1975922738802227`, numerically equal as binary64 to the C output `0.19759227388022271`; both fallback Earth probes emitted `-1.0334418720675367`. The campaign's checksum validator passed. The aggregate measurement used the restored shared-evaluator lifecycle. The fixed-budget peak observation was 21,336,064 bytes, so `peakResidentBytes` remains the only exceeded fixed build, size, and memory observation.

The corrected report remains `complete-evidence` and `qualified: false`. Its SHA-256 is `820dee5e88fbf702a4ae8882218854935773f5eb9b22c02bdc67c6d202e97c3e`, and the raw artifact is `native-sun-pilot-linux-37126885561-1`. This later documentation update does not change the measured source revision or campaign inputs. The repaired receipt confirms the original startup-floor diagnosis and does not pass the memory or mixed-runtime gate.

## Attribution method

The coordinator runs each stage in a fresh process for the Swift Debug and Release candidates and the matched C oracle. Startup and fixed JSON output are minimal-runtime controls. Polynomial and fallback Earth probes interpret their epochs as UT, derive TT with the same captured Delta T model, and must produce numerically equal checksums. Two same-epoch observations record the cumulative process peak after caller-owned caches are populated. The five existing first-access, fresh/repeated polynomial, and fresh/repeated fallback workloads each run alone with a fresh evaluator. The aggregate candidate probe reuses one evaluator across the five modes, matching the pre-attribution runner lifecycle.

Every sample retains the external `/usr/bin/time` peak, scalar or JSON checksum output, command, configuration, platform, toolchain, source hashes, and tested revision. Five trials are required for a full campaign; quick mode records one diagnostic trial and cannot qualify the pilot. The matched C probes use the same epochs and operation counts. Numerical equivalence remains established by the separate 67,240-case comparison rather than by the RSS checksums.

Peak RSS is cumulative within each process. A stage difference shows that more pages were resident during that process; it does not prove an allocator owner, an additive component size, or a portable Swift-minus-C cost. Dynamic runtime and standard-library pages, executable mappings, loader behavior, allocator policy, generated coefficient pages, caches, and JSON output can all contribute. The hosted results therefore support bounded implementation work only when a specific stage adds material RSS above the startup/output controls.

## Bounded recommendation and remaining gates

The stage campaign does not replace the 11,182,080-byte ceiling. Before changing coefficients, caches, or evaluation code, a bounded follow-up should separate the same-toolchain Swift executable and runtime floor from pages made resident by linking the isolated pilot package. That check can identify whether any candidate-owned startup cost is removable under the frozen gate; it must preserve the current binary, model, and workload receipts as controls. If the floor remains above the ceiling, report the gate as unresolved rather than growing the budget.

The native Sun runner still cannot execute the frozen mixed workload containing other planets, lunar state, Pluto, and seasons, so its latency and throughput observations cannot pass that gate. Production integration remains blocked until the original memory and comparable-runtime criteria pass and independent review approves the evidence.
