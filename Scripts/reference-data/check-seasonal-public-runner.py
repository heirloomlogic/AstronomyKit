#!/usr/bin/env python3
"""Exercise the isolated seasonal endpoint and its rejected input boundaries."""
import importlib.util
import json
import subprocess
from pathlib import Path

SPEC=importlib.util.spec_from_file_location('seasonal',Path(__file__).with_name('qualify-seasonal-roots.py'))
S=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(S)
requests,results=S.public_results(S.Q.BINARY)
assert len(requests)==462
invalid=[{'operation':'seasonal-roots','year':year} for year in [1899,2131]]
invalid+=[{'operation':'seasonal-roots','year':2000,'deltaTModel':'invalid'}]
output=subprocess.check_output([str(S.Q.BINARY),'accuracy-batch'],input=''.join(json.dumps(r)+'\n' for r in invalid),text=True)
rows=[json.loads(line) for line in output.splitlines()]
assert len(rows)==len(invalid) and all(row['status']=='runner-error' for row in rows)
print('Public seasonal runner: both Delta-T models, 1848 events; out-of-domain years and unknown model rejected.')
