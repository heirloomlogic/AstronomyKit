# Aggregate Sun pilot RSS checkpoint evidence

## Decision

Issue [#83](https://github.com/heirloomlogic/AstronomyKit/issues/83) remains open. The finite hosted investigation observed repeatable candidate mapping-class growth at first access, fresh polynomial work, and fresh fallback work, but it did not establish an allocator owner, an additive component cost, or any removable source-owned pages. Every official uninstrumented Release trial still exceeded the unchanged 11,182,080-byte ceiling. The native Sun-only process also cannot run the original mixed astronomical latency and throughput workload, and independent review remains required.

## Source-bound campaign

The [frozen protocol](SunPilotAggregateRSSProtocol.md) was committed before measurement at source head `e7d243da9ee65dcb4ee5d4bb3ff6c1e45b939376`. [Workflow 37254182463](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37254182463) tested clean pull-request merge `5851bf0db558907843bc83431aad9016db188144` with Swift 6.2.1 on x86_64 Linux. The report binds the source head through `CI_HEAD_SHA`, the tested merge through `CI_TESTED_SHA`, the protocol SHA-256 `7a9c377b190f16e7d52b8e832155052fe11defed972ee6468613bade815fdf0a`, the evaluated source snapshot, and the candidate and C executable hashes.

The candidate and matched C oracle each ran five fresh one-process checkpoint trials. Every process used the frozen order `firstAccess`, `freshPolynomial`, `repeatedPolynomial`, `freshFallback`, and `repeatedFallback`, with operation counts 1, 200, 200, 200, and 200. Candidate trials reused one evaluator. All checkpoint and final checksums matched the corresponding uninstrumented binary, and the coordinator captured `status`, `smaps`, and `maps` only after observing the process blocked in `read` on standard input.

## Uninstrumented gate

| Process | Five-trial peak RSS range | Result |
| --- | ---: | --- |
| Release candidate, official aggregate gate | 12,292,096–12,513,280 bytes | All exceed the 11,182,080-byte ceiling |
| Matched C, corresponding aggregate workload | 2,965,504–3,088,384 bytes | Diagnostic reference only |

The Release maximum is 1,331,200 bytes above the ceiling. The report is `complete-evidence` and `qualified: false`; `peakResidentBytes` remains the exceeded fixed build, size, and memory observation. Successful evidence collection does not pass the memory gate.

## Instrumented checkpoints

Instrumented candidate external peaks were 12,341,248–12,451,840 bytes, with a 12,349,440-byte median. Matched C peaks were 2,985,984–3,112,960 bytes, with a 3,080,192-byte median. These values describe the instrumented processes and do not replace the uninstrumented gate.

| Transition | Candidate mapping classes with positive growth in all five trials, median bytes | Matched C mapping classes with positive growth in all five trials, median bytes |
| --- | --- | --- |
| `beforeWork` to `firstAccess` | anonymous 155,648; executable 249,856; heap 24,576; kernel-special 4,096; shared-library 270,336; Swift-runtime 655,360 | executable 278,528; kernel-special 4,096; shared-library 552,960 |
| `firstAccess` to `freshPolynomial` | heap 16,384 | none |
| `freshPolynomial` to `repeatedPolynomial` | none | none |
| `repeatedPolynomial` to `freshFallback` | anonymous 135,168; executable 327,680; heap 188,416; Swift-runtime 65,536 | executable 131,072 |
| `freshFallback` to `repeatedFallback` | none | none |

The candidate-specific heap, anonymous, and Swift-runtime class changes narrow where residency appeared in these processes. The matched C loader, shared-library, and executable changes show that a checkpoint transition can also make pages resident outside candidate-owned model state. Mapping names come from file paths in Linux `smaps`; they do not reveal allocator ownership, whether the pages are additive to another process, or whether changing candidate code can remove them.

The checkpoint protocol itself adds JSON records, pipes, acknowledgements, a timing wrapper, blocked reads, and proc inspection. Those operations can perturb residency. The report therefore records `mapping-class-growth-observed-without-removable-owner`, and no production model, cache, workload, or threshold change follows from this evidence.

## Retained evidence and reproduction

The tracked [report](SunPilotAggregateRSSEvidence/linux-report.json) has SHA-256 `bc0715c175008c2af43c018a5139776e5528d7f9551d51d5ff0782c2e153ae57`. The [hosted execution receipt](SunPilotAggregateRSSEvidence/linux-hosted-execution.json) records the source head, tested merge, and workflow URL. The [raw archive](SunPilotAggregateRSSEvidence/linux.tar.gz) retains 876 paths, including every proc checkpoint, command log, numerical row, evaluated input, timing record, compensation source, and IR file. Its [archive receipt](SunPilotAggregateRSSEvidence/linux-archive.json) records SHA-256 `0440d2430e844a0ac453a162baa3a2add925fdd3aa39310e62bb283492508de7`, lists every retained path, and records the hashes and sizes of the three executables omitted from Git. The original hosted artifact retains those executable bytes.

Run `python3 -m unittest Scripts/migration/test_sun_pilot.py -v` for coordinator and protocol controls. Run `python3 Scripts/migration/sun_pilot.py --output <empty-directory>` on Linux for a full source-bound campaign. The exact RSS values apply to the recorded hosted toolchain and five trials; later hosts can differ.
