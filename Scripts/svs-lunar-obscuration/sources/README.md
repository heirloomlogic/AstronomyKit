# Source snapshots

These files are byte-for-byte snapshots from AstronomyKit base revision `3c31e2d56eb4e887554ea185f5f75bdb78b3a674`. `source-receipts.json` records each original repository path, upstream URL, and SHA-256 digest. Keeping the bounded 159 KB input set here makes the issue #275 replay independent of later changes to shared evidence-owner directories.

`nasa-svs-5672.html` and `nasa-lunar-2001-2100.html` are NASA source pages retained for factual verification with attribution. The files under `horizons/` are NASA/JPL Horizons API query receipts and responses. `independent-overlap.json` and `native-captures.json` are AstronomyKit-generated comparison artifacts retained under the repository license.

The snapshots are evidence, not current-source mirrors. `.gitattributes` treats the upstream HTML as binary for diffs so its original whitespace remains byte-identical. Replacing one requires a reviewed receipt update and a regenerated `results.json`; `replay.py --check` rejects byte or semantic drift.
