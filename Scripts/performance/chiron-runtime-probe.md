# Chiron runtime probe

This probe records the runtime tradeoff introduced by issue #108's half-day gravity-solver steps. It measures a fresh propagation from the 2040 reference anchor to 2100, a nearby six-hour reverse update on the same computation-scoped simulation after that propagation, and a 2100 geocentric call whose light-time correction reuses one simulation. It is diagnostic evidence, not a performance gate or a replacement for the fixed migration budgets in `Documentation/Migration/performance-baseline.json`.

The recorded run used `issue-108-chiron-integration-steps` with `Sources/AstronomyKit/Chiron.swift` at SHA-256 `cd6aeb4e31cdf531cb43d827760f4e20c085172e2386c1346abdd53a7a4991f0`, based on `34fb319bf5a179a57c1a56349bfa37ea2cb0b24a`, on macOS 27.0.1 build 26A434 and a 10-core Mac13,1. The toolchain was Apple Swift 6.4 (`swiftlang-6.4.0.30.4`, target `arm64-apple-macosx27.0.0`) and Apple Clang 21.0.0 (`clang-2100.3.30.1`).

Build the testable Release library, compile the probe against it, and run it from the repository root:

```sh
swift test -c release --filter 'Chiron'
swiftc -parse-as-library -O -enable-testing -I .build/out/Products/Release -Xcc -fmodule-map-file=.build/out/Intermediates.noindex/GeneratedModuleMaps/CLibAstronomy.modulemap -Xcc -ISources/CLibAstronomy/include -L .build/out/Products/Release -lAstronomyKit Scripts/performance/chiron-runtime-probe.swift -o .build/chiron-runtime-probe
.build/chiron-runtime-probe
```

The 2026-10-02 run produced:

```text
trial=1 cold=0.512961333 seconds warm=1.625e-06 seconds lightTime=0.500969417 seconds
trial=2 cold=0.500072792 seconds warm=2.75e-06 seconds lightTime=0.499509417 seconds
trial=3 cold=0.510939625 seconds warm=1.583e-06 seconds lightTime=0.499698625 seconds
trial=4 cold=0.498478209 seconds warm=1.333e-06 seconds lightTime=0.501013625 seconds
trial=5 cold=0.499245959 seconds warm=1.25e-06 seconds lightTime=0.502305584 seconds
checksum=-230.62122006852528
```

Fresh 2100 propagation took 0.498–0.513 seconds in these samples. Nearby reused updates took 1.25–2.75 microseconds. Geocentric calls took 0.499–0.502 seconds, consistent with one long propagation plus nearby reused light-time iterations on this revision and host. These samples do not establish performance on other machines or an accuracy bound across the supported interval.
