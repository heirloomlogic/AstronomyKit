#!/usr/bin/env python3
"""Compare current seasonal searches with retained epochs without relabeling history."""
import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("seasons", Path(__file__).with_name("qualify-seasonal-roots.py"))
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)

saved = json.loads(S.REPORT.read_text())
S.validate_report_semantics(saved)
current = S.assess(S.Q.BINARY)
S.validate_report_semantics(current)
output = ROOT / ".context/current-seasonal-search.json"
output.write_text(json.dumps(current, sort_keys=True, indent=2, allow_nan=False) + "\n")
# This checks epoch/residual/population semantics only. Historical source replay is
# separately rebuilt and authenticated by replay_historical_research.py.
S.validate_replay(saved, copy.deepcopy(current))
print(f"Current seasonal epoch/residual regression passed; actual current source and binary receipt: {output}")
