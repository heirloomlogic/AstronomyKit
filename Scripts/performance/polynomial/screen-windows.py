#!/usr/bin/env python3
"""Check downstream windows before spending time on the final timing campaign."""
import json
import subprocess
import sys
from run import ROOT, OUT, env, save
sys.path.append(str(ROOT/'Scripts/performance/native-math'))
from comparison import canonical,differences

report={}
for scenario in ['nyc-day','nyc-week','reykjavik-day']:
    path=OUT/f'{scenario}-screen-windows.json'
    p=subprocess.run([str(OUT/'scan-candidate'),scenario],env={**env(),'CHRONOLOGY_WINDOWS_PATH':str(path)},capture_output=True,text=True,check=True)
    reference=json.loads((OUT/f'{scenario}-baseline-1-windows.json').read_text())
    diff=differences(canonical(reference),canonical(json.loads(path.read_text())))
    assert not diff['discrete'],diff['discrete']
    failures=[]
    for field,delta in diff['numeric'].items():
        if field.startswith(('[]'+'.peakChartState.positions.','[]'+'.peakChartState.declinations.','[]'+'.peakChartState.speeds.')) or field in ('[].peakChartState.aspects[].orb','[].peakFlagInstances[].separation','[].peakFlagInstances[].distanceToSun'):
            limit=1e-8
        elif field=='[].peakFlagInstances[].angularStrength':limit=1e-12
        else:limit=0
        if delta['maxAbsoluteDifference']>limit:failures.append([field,delta])
    report[scenario]={'failures':failures,'differences':diff};save('window-screen.json',report)
    print(scenario,'failures',failures,flush=True)
assert not any(r['failures'] for r in report.values())
