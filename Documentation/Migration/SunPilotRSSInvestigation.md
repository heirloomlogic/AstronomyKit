# Linux Sun pilot RSS investigation

## Decision

Issue #83 remains open. The final merged pilot evidence repeats the Linux RSS failure on two clean hosted merge revisions, while the matched C process remains below 3.2 MB. A successful workflow means the evidence campaign completed; both reports retain `qualified: false` and name `peakResidentBytes` as the exceeded fixed budget.

## Existing receipts

| Workflow | Source head | Tested merge | Swift 6.2.1 Release peak RSS | Matched C peak RSS | Result |
| --- | --- | --- | ---: | ---: | --- |
| [37088341082](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37088341082) | `24befa51bf66e5434ed4800fa7e321f2bf81bb38` | `3459e952c07d69efa8c5cb9443c3296a2539106e` | 21,409,792 bytes | 3,198,976 bytes | RSS fails; numerical campaign passes |
| [37088619287](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37088619287) | `f9d01dcac7c541fd1b7e742f1da34cad96f19c29` | `3405fbc0711b25a393af644a3b8692baf108cbba` | 21,397,504 bytes | 2,977,792 bytes | RSS fails; numerical campaign passes |

The fixed ceiling is 11,182,080 bytes from `performance-baseline.json` with SHA-256 `fb0be646199060b40860f858a210fa5f6b461ecf6aac06741ac0aa1ad027844a`. The two isolated-manifest runs use the same manifest bytes and source hashes; their peak difference is 12,288 bytes. This repeat establishes that the first result was not removed by the final documentation commit. It does not identify which runtime stage makes pages resident.

## Hosted attribution result

[Workflow 37125291926](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37125291926) tested clean merge revision `a73deaa064fac0b6f25e5070846ced69b40a0457` for source head `fe55f8e84d24c897332f3c46ec86cffe66728e77` with Swift 6.2.1 on x86_64 Linux. Debug and Release each passed 67,240 numerical comparisons and the perturbation control. The report remains `qualified: false`; peak RSS is the only exceeded fixed build, size, and memory observation. The stripped Release artifact is 14,260,208 bytes, 128,937 bytes below its unchanged ceiling.

| Fresh process stage | Swift Release RSS, five-trial range (median) | C RSS, five-trial range (median) |
| --- | ---: | ---: |
| Startup control | 17,764,352–17,915,904 (17,842,176) | 2,023,424–2,199,552 (2,105,344) |
| Fixed JSON serialization | 19,341,312–19,460,096 (19,390,464) | 2,043,904–2,125,824 (2,125,824) |
| Polynomial Earth | 18,677,760–18,898,944 (18,743,296) | 2,576,384–2,605,056 (2,580,480) |
| Full-series Earth | 19,283,968–19,456,000 (19,300,352) | 2,826,240–2,891,776 (2,838,528) |
| Polynomial cache | 18,976,768–19,197,952 (19,148,800) | 2,797,568–2,981,888 (2,981,888) |
| Fallback cache | 19,292,160–19,529,728 (19,365,888) | 2,904,064–3,035,136 (2,912,256) |
| First access | 19,222,528–19,451,904 (19,337,216) | 2,932,736–3,063,808 (3,026,944) |
| Fresh polynomial | 19,345,408–19,460,096 (19,431,424) | 2,912,256–3,035,136 (2,936,832) |
| Repeated polynomial | 19,304,448–19,488,768 (19,402,752) | 2,940,928–3,031,040 (2,945,024) |
| Fresh fallback | 19,705,856–19,881,984 (19,824,640) | 2,883,584–3,055,616 (3,031,040) |
| Repeated fallback | 19,673,088–19,861,504 (19,742,720) | 2,854,912–2,932,736 (2,863,104) |
| Aggregate | 21,372,928–21,499,904 (21,434,368) | 3,051,520–3,096,576 (3,063,808) |

The lowest Release startup control is 6,582,272 bytes above the 11,182,080-byte ceiling before the runner accesses model coefficients, evaluator caches, or astronomical workloads. The current Linux executable and runtime therefore fail the absolute gate before model-level optimization can decide the result. Complete-series evaluation and the larger workloads make additional pages resident, but they are not the primary cause of the absolute failure. The separate aggregate measurement used by the fixed-budget report peaked at 21,581,824 bytes and reaches the same conclusion.

The raw `report.json`, stdout checksums, `/usr/bin/time` logs, binaries, source hashes, evaluated manifest, and compressed numerical rows are retained in the workflow artifact `native-sun-pilot-linux-37125291926-1`. The successful workflow establishes completed evidence collection at the tested merge revision. It does not pass the RSS gate.

## Attribution method

The coordinator now runs each stage in a fresh process for the Swift Debug and Release candidates and the matched C oracle. Startup and fixed JSON output are minimal-runtime controls. Polynomial and fallback Earth probes separate generated polynomial access from lazy materialization of complete Earth VSOP triplets. Two same-epoch observations record the cumulative process peak after caller-owned caches are populated. The five existing first-access, fresh/repeated polynomial, and fresh/repeated fallback workloads each run alone, followed by the unchanged aggregate workload.

Every sample retains the external `/usr/bin/time` peak, scalar or JSON checksum output, command, configuration, platform, toolchain, source hashes, and tested revision. Five trials are required for a full campaign; quick mode records one diagnostic trial and cannot qualify the pilot. The matched C probes use the same epochs and operation counts. Numerical equivalence remains established by the separate 67,240-case comparison rather than by the RSS checksums.

Peak RSS is cumulative within each process. A stage difference shows that more pages were resident during that process; it does not prove an allocator owner, an additive component size, or a portable Swift-minus-C cost. Dynamic runtime and standard-library pages, executable mappings, loader behavior, allocator policy, generated coefficient pages, caches, and JSON output can all contribute. The hosted results therefore support bounded implementation work only when a specific stage adds material RSS above the startup/output controls.

## Bounded recommendation and remaining gates

The stage campaign does not replace the 11,182,080-byte ceiling. Before changing coefficients, caches, or evaluation code, a bounded follow-up should separate the same-toolchain Swift executable and runtime floor from pages made resident by linking the isolated pilot package. That check can identify whether any candidate-owned startup cost is removable under the frozen gate; it must preserve the current binary, model, and workload receipts as controls. If the floor remains above the ceiling, report the gate as unresolved rather than growing the budget.

The native Sun runner still cannot execute the frozen mixed workload containing other planets, lunar state, Pluto, and seasons, so its latency and throughput observations cannot pass that gate. Production integration remains blocked until the original memory and comparable-runtime criteria pass and independent review approves the evidence.
