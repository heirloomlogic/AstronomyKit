# Security Policy

## Supported Versions

AstronomyKit follows semantic versioning. Security fixes are applied to the latest minor release line. Older release lines are not maintained.

## Reporting a Vulnerability

If you believe you have found a security issue in AstronomyKit, please **do not** open a public GitHub issue. Instead, email astronomykit@heirloomlogic.com with:

- A description of the issue and its impact
- Steps to reproduce
- Any suggested remediation

You can expect an acknowledgement within a few business days. Once the issue is confirmed, we will coordinate a fix and a disclosure timeline with you.

## Scope

AstronomyKit is an on-device computation library. It performs no network I/O, reads no files, and does not process untrusted input beyond numeric arguments. Plausible issues include:

- Memory-safety bugs in unsafe pointer code within the computation engine (`Sources/AstronomyKit/Engine/`)
- Numerical inputs that cause crashes, infinite loops, or undefined behavior
- Thread-safety issues in shared state (e.g. the Pluto orbit cache or the Delta T model)

Reports on cosmetic issues, DocC content, or algorithmic limitations inherited from Astronomy Engine should be filed as regular GitHub issues.
