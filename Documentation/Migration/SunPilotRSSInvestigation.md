# Linux Sun pilot RSS investigation

## Decision

Issue #83 remains open. The final merged pilot evidence repeats the Linux RSS failure on two clean hosted merge revisions, while the matched C process remains below 3.2 MB. A successful workflow means the evidence campaign completed; both reports retain `qualified: false` and name `peakResidentBytes` as the exceeded fixed budget.

## Existing receipts

| Workflow | Source head | Tested merge | Swift 6.2.1 Release peak RSS | Matched C peak RSS | Result |
| --- | --- | --- | ---: | ---: | --- |
| [37088341082](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37088341082) | `24befa51bf66e5434ed4800fa7e321f2bf81bb38` | `3459e952c07d69efa8c5cb9443c3296a2539106e` | 21,409,792 bytes | 3,198,976 bytes | RSS fails; numerical campaign passes |
| [37088619287](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37088619287) | `f9d01dcac7c541fd1b7e742f1da34cad96f19c29` | `3405fbc0711b25a393af644a3b8692baf108cbba` | 21,397,504 bytes | 2,977,792 bytes | RSS fails; numerical campaign passes |

The fixed ceiling is 11,182,080 bytes from `performance-baseline.json` with SHA-256 `fb0be646199060b40860f858a210fa5f6b461ecf6aac06741ac0aa1ad027844a`. The two isolated-manifest runs use the same manifest bytes and source hashes; their peak difference is 12,288 bytes. This repeat establishes that the first result was not removed by the final documentation commit. It does not identify which runtime stage makes pages resident.

## Attribution campaign

The coordinator now runs each stage in a fresh process for the Swift Debug and Release candidates and the matched C oracle. Startup and fixed JSON output are minimal-runtime controls. Polynomial and fallback Earth probes separate generated polynomial access from lazy materialization of complete Earth VSOP triplets. Two same-epoch observations record the cumulative process peak after caller-owned caches are populated. The five existing first-access, fresh/repeated polynomial, and fresh/repeated fallback workloads each run alone, followed by the unchanged aggregate workload.

Every sample retains the external `/usr/bin/time` peak, scalar or JSON checksum output, command, configuration, platform, toolchain, source hashes, and tested revision. Five trials are required for a full campaign; quick mode records one diagnostic trial and cannot qualify the pilot. The matched C probes use the same epochs and operation counts. Numerical equivalence remains established by the separate 67,240-case comparison rather than by the RSS checksums.

Peak RSS is cumulative within each process. A stage difference shows that more pages were resident during that process; it does not prove an allocator owner, an additive component size, or a portable Swift-minus-C cost. Dynamic runtime and standard-library pages, executable mappings, loader behavior, allocator policy, generated coefficient pages, caches, and JSON output can all contribute. The hosted results therefore support bounded implementation work only when a specific stage adds material RSS above the startup/output controls.

## Remaining gates

The stage campaign does not replace the 11,182,080-byte ceiling. The native Sun runner still cannot execute the frozen mixed workload containing other planets, lunar state, Pluto, and seasons, so its latency and throughput observations cannot pass that gate. The next decision must use the hosted stage receipt: reduce a demonstrated candidate-owned increment and rerun the unchanged checks, or record the platform/runtime floor as an unresolved failure. Either path keeps production integration blocked until the original acceptance criteria and independent review pass.
