# Native observer-event evidence

This archive qualifies the native hour-angle, altitude and rise/set searches added for #92. It does not switch the public C facades, close #124, establish new global event tolerances, or resolve the existing Jupiter, Uranus and Neptune apsis source gaps.

`reference-fixtures.json` comes from the adjacent-query-bound raw files under `sources/horizons` and `sources/usno`. Sixteen frozen Horizons rows cover the Sun, Moon, Mars and Jupiter at TT days -36524.5, 0, 8000 and 47846.5, at three geodetic sites. Altitude is airless apparent center altitude; hour angle is the apparent local hour angle, wrapped to [0,24) hours. Both comparisons retain the existing one-arcminute angular allowance. These are selected point checks, not a full-domain guarantee.

Horizons quantity 30 is TDB−UT1 before 1962 and TDB−UTC afterward; quantity 49 supplies UT1−UTC for the latter. The native input pairs store the source TT and reconstructed UT1. Derived event and light-time epochs retain the chosen Espenak-Meeus model, so this checks the composed native call and does not claim that the model reproduces measured or future Earth rotation. Horizons' future Earth orientation is a prediction or held value. The separate polar diagnostic instead constructs a consistent modeled pair from source TT before light-time iteration. At the exact pole, changing the spin angle does not change altitude; native and Horizons precession/nutation and reference-pole conventions still differ.

The native Sun rise/set limb uses 696,000 km. Three independent USNO navigation semidiameters, paired with Horizons distances, distinguish this optical convention from the 695,700 km nominal-radius control. The 0.000001-degree check is a comparison with printed values and their inferred convention, not a claim of physical solar-radius accuracy. A fourth site, a current USNO one-day result, and four airless polar points are retained as diagnostic provenance. [PolarSunriseReconciliation.md](../../Documentation/Migration/PolarSunriseReconciliation.md) explains the inference and its limits. The USNO rise/set implementation is not available.

`native-captures.json` records all 5,909 native USNO events in both build configurations, the sixteen observer points, three semidiameters, four polar diagnostics, a fresh-process Release workload, build receipts and executable size. `native-evidence.json` derives summaries and binds every engine source, test, fixture, recipe, tool and fuzz corpus file used by these checks. The two binary fuzz cases retain their exact source arguments, including the fixed-star input. Public C still rejects the valid short upper-domain window that the native final-step clipping now handles; #96 owns the public cutover.

Run these offline checks:

```sh
python3 -m unittest Scripts/test_observer_events.py -v
python3 Scripts/capture-observer-events.py --check
python3 Scripts/record-observer-event-evidence.py --check
swift test --filter 'EngineObserver(Events|Source)Tests'
```

Explicit `capture-observer-events.py --download` refreshes each publisher response using its recorded query and updates its adjacent digest. Normal execution regenerates only `reference-fixtures.json`; it does not modify the Swift generator directories. The recording tool owns only `native-captures.json` and `native-evidence.json`. Tests and checks never retrieve network data.

For fresh native captures, set `OBSERVER_EVENT_OUTPUT` to a separate directory for each Debug/Release test run. Each USNO stream writes a distinct file, so parallel tests cannot overwrite another stream. The source suite writes `points.json`, `semidiameters.json` and `polar.json`. Run `EngineObserverMeasurementTests` in a fresh Release process with both `OBSERVER_EVENT_MEASUREMENT=1` and its own output directory. The evidence recorder consumes those observations and complete build receipts; it does not impose host-independent runtime, RSS or binary-size ceilings.
