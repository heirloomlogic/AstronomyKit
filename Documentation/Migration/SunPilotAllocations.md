# Sun pilot decoded-allocation investigation

The streamed-storage experiment is rejected. It reduced aggregate Release RSS on both tested hosts but made the unchanged fresh-fallback workload 3.70 times slower on Apple and 2.43 times slower on Linux. Every Linux trial still exceeded the original 11,182,080-byte ceiling. Issue [#83](https://github.com/heirloomlogic/AstronomyKit/issues/83) remains open. The final PR restores the evaluator/model files and pilot tests to baseline `2376ee3df52f141f6394cb442243feb7cdbd6b86` and retains the protocol, comparison tooling, ownership inventory, and evidence.

## Experiment and binding

The [protocol](SunPilotAllocationProtocol.md) was committed before measurements at `2b57da09`. Baseline was clean `2376ee3df52f141f6394cb442243feb7cdbd6b86`; rejected source was `f93fc8dee058790fbf4b97f4e8a57f20cc9bd4e6`. [Hosted run 37291403029](https://github.com/heirloomlogic/AstronomyKit/actions/runs/37291403029) tested clean merge `58caa65c292794ac138f5d3928100a9fe3479afd` on x86_64 Linux with Swift 6.2.1. The Apple campaigns used Apple Swift 6.4 on arm64 macOS 27.0.1. All coordinators used CPython 3.14.7. The [hosted receipt](SunPilotAllocationEvidence/linux-hosted-execution.json), reports, and raw command logs bind the revisions, source/binary hashes, toolchains, input corpus, and frozen protocols.

The candidate removed the Earth pilot's persistent decoded hierarchy of 2,564 VSOP terms and the orientation pilot's decoded nutation row arrays. It read coefficient bits from the same generated storage and loaded nutation rows into fixed scalar fields. Expressions, order, compensation, workload counts/checksums, and aggregate evaluator lifetime were comparison controls. The source restoration hashes in [decision.json](SunPilotAllocationEvidence/decision.json) match the four baseline files exactly.

## Numerical controls

Baseline and candidate each passed all 67,240 frozen-oracle cases in Debug and Release on Apple and Linux. Each campaign detected the eight fallback perturbations in both configurations and passed actual-binary output delivery controls. Across each same-host pair, every uncompressed input, oracle, candidate, and perturbed output row matched exactly, as did workload operation counts and checksums. The experiment's focused tests also checked all archived nutation scalar bits, replayed decoded VSOP summation order, and retained the whole-model checksum; those candidate-specific tests were restored with the rejected source.

## Uninstrumented Release observations

| Host | Baseline five-trial aggregate RSS | Candidate five-trial aggregate RSS | Median reduction | Original ceiling |
| --- | ---: | ---: | ---: | --- |
| Apple | 7,208,960 bytes in every trial | 7,077,888 bytes in every trial | 131,072 bytes | Both below |
| Linux paired host | 12,152,832–12,308,480 bytes | 11,948,032–12,075,008 bytes | 151,552 bytes | Every trial above |

| Host | Baseline fresh-fallback median | Candidate fresh-fallback median | Candidate/baseline |
| --- | ---: | ---: | ---: |
| Apple | 10.502 ms | 38.894 ms | 3.70 |
| Linux paired host | 34.902 ms | 84.673 ms | 2.43 |

Each fresh-fallback timing covers the original 200 operations. The candidate Linux RSS samples are lower than every paired baseline sample, so the predeclared RSS improvement condition passes. That condition alone is insufficient to retain a change with the observed runtime regression. [decision.json](SunPilotAllocationEvidence/decision.json) records `sourceExperimentRetained: false` and the measured reason. These finite timings do not replace the original mixed astronomical latency/throughput gate.

Current schema 2 [Apple](SunPilotAllocationEvidence/apple-comparison.json) and [Linux](SunPilotAllocationEvidence/linux-comparison.json) comparison receipts name the memory-only field `rssRetentionConditionPassed`. The untouched [original Apple](SunPilotAllocationEvidence/apple-original-comparison.json) and [hosted Linux](SunPilotAllocationEvidence/linux-original-comparison.json) schema 1 receipts used `retainSourceExperiment`; that older field expressed the RSS screen and is not the final decision. Both report versions bind the validator used to produce them. Schema 2 was recomputed from retained raw evidence after renaming the field; no campaign observations or original receipts were rewritten.

The generated VSOP module exposes a checked scalar bit accessor, which the candidate calls repeatedly during each uncached series evaluation. This is a plausible source of cost to investigate through the existing representation owner; this combined experiment does not establish which change causes the slowdown. No further redesign was tested. Linux checkpoints remain instrumentation diagnostics, without causal allocator ownership or additive/removable component-cost claims.

## Evidence and reproduction

The four raw archives retain all numerical rows, evaluated inputs, commands, timing records, compensation source/IR, and Linux proc checkpoints. Each archive receipt lists retained paths and hashes/sizes for three executable files omitted from Git. The hosted artifact retains Linux stripped candidate binaries and the oracle; the local Apple raw directories retain the corresponding Apple files. The existing coordinator discards its temporary unstripped candidate binaries after recording their measured hashes. Reports record every original fixed-budget failure and qualification limitation.

| Campaign | Report | Raw archive | Archive receipt |
| --- | --- | --- | --- |
| Apple baseline | [report](SunPilotAllocationEvidence/apple-baseline-report.json) | [raw](SunPilotAllocationEvidence/apple-baseline.tar.gz) | [receipt](SunPilotAllocationEvidence/apple-baseline-archive.json) |
| Apple candidate | [report](SunPilotAllocationEvidence/apple-candidate-report.json) | [raw](SunPilotAllocationEvidence/apple-candidate.tar.gz) | [receipt](SunPilotAllocationEvidence/apple-candidate-archive.json) |
| Linux baseline | [report](SunPilotAllocationEvidence/linux-baseline-report.json) | [raw](SunPilotAllocationEvidence/linux-baseline.tar.gz) | [receipt](SunPilotAllocationEvidence/linux-baseline-archive.json) |
| Linux candidate | [report](SunPilotAllocationEvidence/linux-candidate-report.json) | [raw](SunPilotAllocationEvidence/linux-candidate.tar.gz) | [receipt](SunPilotAllocationEvidence/linux-candidate-archive.json) |

Reproduce the rejected experiment in detached worktrees at the baseline and rejected source revisions above, running each revision's `python3 Scripts/migration/sun_pilot.py --output <empty-directory>` on the same host. From the final tooling revision, run `python3 Scripts/migration/compare_sun_pilot_allocations.py --baseline <baseline-directory> --candidate <candidate-directory> --output <new-json>`. Temporary isolated SwiftPM root paths are normalized for graph comparison; every other compared graph field remains exact. Run `python3 -m unittest Scripts/migration/test_compare_sun_pilot_allocations.py -v` for validator rejection controls. The paired workflow job is manual-only; it compares the selected branch against the frozen baseline and establishes no standing qualification rule.

A separate hosted candidate qualification job also passed the numerical/control campaign and observed Release RSS of 12,054,528–12,292,096 bytes, again entirely above the ceiling; its [report](SunPilotAllocationEvidence/linux-qualification-report.json) remains separate from the paired result. Repository Apple Debug and Release suites passed 713 tests in 188 suites with the existing known South Pole USNO timing issue tracked in #124. Candidate source-head hosted package/platform tests, lint, thread sanitizer, and pilot qualification passed. Final documentation/tooling checks and independent correctness review are reported in the PR; implementation authorship and green CI are not independent review.

The original mixed astronomical workload and comparable-runtime acceptance remain unmet. Sampled parity does not certify intervals or release accuracy. This investigation does not qualify the pilot or authorize the full port.
