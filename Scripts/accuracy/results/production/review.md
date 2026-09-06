# Production integration review

Round 1 / ceiling 6. Two fresh Critics cover all four remits.
Target: root working tree vs origin/main, including untracked shipping sources,
generators/tests/docs; earlier archived diagnostic data are context. Paired
AstrologyKit worktree .context/AstrologyKit-migration vs its HEAD 85f2d4.

Task prod-core: correctness + spec/house rules for C full tables, time contract,
Swift API, generator provenance and numerical compatibility. Requested
Astra/high due subtle numerical/time inversion architecture. Escalations 0/1.
Task prod-integration: state/lifecycle + error paths for entire change, plus
correctness/spec of downstream observation integration and production gate.
Requested Astra/high due cross-repo reference/provenance state. Escalations 0/1.

Confinement instruction-only: Critics read-only, no file or tracker mutations.
Runtime model confirmation unavailable; usage unavailable. Capability retries 0.
Initial DIFF-SIZE to be supplied by Critics, excluding generated coefficient/data
volume separately. Existing pending long-running builds/range diagnostics are
outside source review; their .context logs may be read. No golden instrumentation
remains. No release or PR has been published.

Round 1 complete: prod-core blocking (1), prod-integration clean.
Merged blocker time-discontinuity: Date Unix 506140670.85679626 and
-282782416.0919621 map into 1986/1961 positive delta-T polynomial jumps;
128-step exact inverse oscillates then returns NaN for valid civil time.
Core scope handwritten DIFF-SIZE 662; broad integration handwritten 2729.
For convergence compare next fix's handwritten lines against 2729.
Generated/core input volume separately 72275 changed lines; no generated edits
are expected in the fix. No advisory findings. No escalation/capability retry.

Fix task prod-fix-1 reserved: requested gpt-5.6-sol/high, escalation0/1;
model confirmation and actual usage unavailable. Must preserve snapshots.

Additional round1 validation evidence: pre-fix TSan completed with no data-race
warnings but three assertions. prod-integration rechecked its lifecycle remit:
confirmed the finite-extreme inverse test incorrectly demands NaN under legacy
JPL (which can converge), and global DeltaT swaps contaminate unrelated parallel
suites. Added to same Fixer: model-independent extreme-input assertion and
--no-parallel CI/qualification; concurrent task groups within safety tests stay.
Eclipse equality failure is harness interference, not a proven eclipse regression.
Round count remains1. No escalation, no rejected findings yet.

Fix1 complete: confirmed time discontinuity and harness/test contract findings;
rejected0, reverted0. Snapshot before/after .context/accuracy/prod-fix-1.
DIFF-SIZE195 (+171/-24), six paths, smaller than2729. Failing-first8 assertions;
CivilTime11/11, debug590/176 including unchanged bit goldens.
Round2 reserved prod-review-2: fresh Astra/high, all four remits limited to Fix1
snapshot range. Highest previous tier floor Astra, escalation0/1, retries0.
Confinement instruction-only; confirmed model and usage unavailable.

Round2 complete BLOCKING1 category spec-gap: negative DeltaT at1900 makes
TT-seeded inverse select earlier branch, contrary to unconditional later-UT
documentation. ExactTT -36510.21703178009 givesUT -36510.21700051158; later
solution -36510.216999488424 also zero residual. No other findings/advisories.
Fix1 size195 verified; new category, no recurrence/non-convergence guard.
Fix2 reserved same Sol/high worker; escalation0/1, retries0, no reverts.
Scope clarify bounded deterministic TT-seeded inverse selection and test negative
DeltaT overlap; positive UTC table's later-civil choice is a separate contract.
Require snapshot and fix size<195. Round3 fresh Astra/high reserved afterfix.

Fix2 snapshotted: .context/accuracy/prod-fix-2/before -> after. Size49
(+37/-12), four paths, smaller than195. Solver behavior unchanged;
TT-seeded first fixedpoint solution documented, exact1900 both-roots
regression failed first for false laterbranch expectation. Focusedtest pending.
Round3 prod-review-3 reserved fresh Astra/high, allfourremits ONLYFix2;
escalation0/1, retries0, instruction-only, actualmodel/usageunavailable.

Round3 CLEAN, allfourremits, size49 verified, zero blockers/advisories.
Converged in3rounds. No escalations, retries, rejected findings or reverts.
Requested Critics Astra/high, Fixer Sol/high; confirmed model and usage unavailable.
Final Fix2 focused12/12 pass. TSan590/176 pass before comments/test-onlyFix2,
zero race warnings. Final release running againstFix2. Review source phase complete.
