#!/usr/bin/env python3
"""Build a development-only native lunar/ERFA integration executable."""
import argparse
import hashlib
import json
import re
import subprocess
import urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'.context/accuracy-qualification/integrated-lunar'
SOURCE=ROOT/'Tools/Migration/LunarIntegratedProbe/main.swift'
ORIGINAL=ROOT/'Tools/Migration/NativeLunarProbe/main.swift'
COMMIT='9915ba38c9365f8b0738269b8c2ac1fdd5f8dee3'
BASE='https://raw.githubusercontent.com/liberfa/erfa/'+COMMIT+'/'
LOCK=ROOT/'Documentation/Migration/integrated-lunar-erfa-source-lock.json'


def fetch(name):
    lock=json.loads(LOCK.read_bytes())
    if lock['commit']!=COMMIT or lock['baseURL']!=BASE or name not in lock['filesSHA256']: raise ValueError('uncatalogued official ERFA source/commit')
    expected=lock['filesSHA256'][name];file=BUILD/'erfa'/name
    if file.exists():
        if hashlib.sha256(file.read_bytes()).hexdigest()!=expected: raise ValueError('cached ERFA source differs from official byte lock')
    else:
        with urllib.request.urlopen(BASE+name,timeout=30) as response: data=response.read()
        if hashlib.sha256(data).hexdigest()!=expected: raise ValueError('downloaded ERFA source differs from official byte lock')
        file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(data)
    return file


def build():
    BUILD.mkdir(parents=True,exist_ok=True)
    fetch('LICENSE');header=fetch('src/erfa.h');fetch('src/erfam.h')
    pending=['Dtdb','Tttdb','Ecm06'];sources={}
    while pending:
        name=pending.pop()
        if name in sources: continue
        if not re.fullmatch('[A-Za-z0-9]+',name): raise ValueError('invalid ERFA function name')
        file=fetch('src/'+name.lower()+'.c');sources[name]=file
        code=re.sub(r'/\*.*?\*/','',file.read_text(),flags=re.S)
        pending.extend(set(re.findall(r'\bera([A-Z][A-Za-z0-9]+)\s*\(',code))-set(sources))
    prefix=ORIGINAL.read_text().split('func run() throws {',1)[0]
    if 'struct LunarCoefficients' not in prefix or 'func peakRSSBytes()' not in prefix: raise ValueError('native evaluator extraction boundary missing')
    common=BUILD/'LunarCoefficients.swift';common.write_text(prefix)
    commands=[];objects=[]
    for name,file in sorted(sources.items()):
        object_file=BUILD/(name+'.o');command=['clang','-c','-O3','-fno-fast-math','-ffp-contract=off','-I',str(header.parent),str(file),'-o',str(object_file)]
        subprocess.run(command,check=True);commands.append(command);objects.append(object_file)
    binary=BUILD/'probe';command=['swiftc','-O','-import-objc-header',str(header),str(common),str(SOURCE),*[str(p) for p in objects],'-o',str(binary)]
    subprocess.run(command,check=True);commands.append(command)
    paths=[LOCK,ORIGINAL,SOURCE,Path(__file__),common,binary]+list((BUILD/'erfa').rglob('*'))+objects
    manifest={'classification':'development-only-native-integration-not-shipping-dependency','erfaVersion':'2.0.1','erfaCommit':COMMIT,'sourceBaseURL':BASE,
              'filesSHA256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths) if p.is_file()},
              'commands':commands,'swiftVersion':subprocess.check_output(['swift','--version'],text=True).strip(),'clangVersion':subprocess.check_output(['clang','--version'],text=True).strip()}
    (BUILD/'build-manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    print('Built native integration with '+str(len(objects))+' pinned ERFA routines.')

if __name__=='__main__': build()
