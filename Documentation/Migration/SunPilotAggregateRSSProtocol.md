# Aggregate Sun pilot RSS checkpoint protocol

This protocol freezes a finite Linux investigation of the aggregate development Sun workload before hosted measurement. It does not change the production model, development model, coefficient tables, caches, workload order, operation counts, evaluator lifetime, checksums, or the approved 11,182,080-byte peak-resident ceiling. The generated report binds this file's SHA-256 value, the source snapshot, candidate and oracle binaries, environment, and tested revision.

## Campaign

The campaign builds the existing Release candidate and the matched frozen C oracle. It runs five fresh instrumented processes per binary. Each process blocks at six checkpoints in this order: `beforeWork`, `firstAccess`, `freshPolynomial`, `repeatedPolynomial`, `freshFallback`, and `repeatedFallback`. The first mode executes one operation; each remaining mode executes 200. The candidate creates one `PilotEvaluator` before the first checkpoint and reuses it through all five modes.

At each checkpoint, the process writes one JSON record and blocks reading an acknowledgement from standard input. The coordinator verifies the expected checkpoint identity, waits until `/proc/<pid>/syscall` shows the target blocked in the architecture-specific `read` syscall on file descriptor zero, and then copies `/proc/<pid>/status`, `/proc/<pid>/smaps`, and `/proc/<pid>/maps`. Acknowledgement releases the next mode. After the last acknowledgement, the process emits the complete five-mode workload report and exits.

The coordinator retains every workload's operation count, elapsed time, and checksum. Instrumented counts and checksums must match the same binary's five uninstrumented aggregate trials. The external `/usr/bin/time` peak, binary hashes, source hashes, raw proc files, command receipts, and checkpoint readiness observations remain in the raw artifact.

## Mapping classes

The coordinator sums each `smaps` `Rss` row into one of eight fixed classes: executable, heap, stack, anonymous, Swift runtime, shared library, other file-backed, or kernel-special. It reports a checkpoint-to-checkpoint class increase as reproducible only when the delta is positive in all five trials. Missing classes count as zero for that delta.

Mapping-class growth is correlation within the instrumented process. It does not identify an allocator owner, prove additive component cost, or show that a candidate change can remove the pages. The checkpoint JSON, pipes, timing wrapper, blocked reads, and proc inspection can perturb page residency.

## Official memory gate

The existing five fresh uninstrumented `--performance` processes remain the official fixed-budget observation for both candidate and C. Instrumented peaks and checkpoint snapshots do not replace or relax that gate. The report remains unqualified when any uninstrumented candidate trial exceeds 11,182,080 bytes or when another original issue gate remains unmet.

## Rejection and cleanup

The coordinator rejects a missing, duplicate, stale, malformed, oversized, or out-of-order checkpoint; changed operation count; nonfinite checksum; mismatch with final or uninstrumented output; invalid peak; missing proc memory fields; missing child; process failure; closed output; or timeout. Every error path kills and reaps the timing-wrapper process group so a blocked candidate or oracle cannot survive the campaign.

The campaign runs only on Linux with readable proc files and an architecture whose stdin-read syscall is known. Other platforms may run unit and binary protocol tests but cannot produce this evidence.
