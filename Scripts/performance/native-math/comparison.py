"""Compare complete window/event payloads using the archived chronology rules."""
import collections
from datetime import datetime, timezone
import json
import re

UUID = re.compile(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')

def utc(s):
    d=datetime.fromisoformat(s.replace('Z','+00:00'))-datetime(1970,1,1,tzinfo=timezone.utc)
    return (d.days*86400+d.seconds)*1_000_000+d.microseconds

def canonical(value, path=''):
    # These three Codable arrays represent dictionaries with Planet keys.
    # members/appliers are declared Set<Planet>, not ordered lists.
    if isinstance(value,dict): return {k:canonical(v,path+'.'+k) for k,v in value.items()}
    if isinstance(value,list):
        if path in ['[].peakChartState.positions','[].peakChartState.speeds','[].peakChartState.declinations']:
            assert len(value)%2==0 and len(set(value[::2]))==len(value)//2
            return dict(zip(value[::2],value[1::2]))
        items=[canonical(v,path+'[]') for v in value]
        if path.endswith('.members') or path.endswith('.collection.appliers'): return sorted(items)
        return items
    return value

def differences(a,b,path='',out=None):
    if out is None: out={'numeric':{},'discrete':{},'ignoredRandomUUIDs':0}
    if isinstance(a,str) and isinstance(b,str) and UUID.fullmatch(a) and UUID.fullmatch(b):
        if a!=b:out['ignoredRandomUUIDs']+=1
    elif isinstance(a,dict) and isinstance(b,dict):
        if a.keys()!=b.keys():out['discrete'][path+'.keys']=out['discrete'].get(path+'.keys',0)+1
        for k in a.keys()&b.keys():differences(a[k],b[k],path+'.'+k,out)
    elif isinstance(a,list) and isinstance(b,list):
        if len(a)!=len(b):out['discrete'][path+'.length']=out['discrete'].get(path+'.length',0)+1
        for x,y in zip(a,b):differences(x,y,path+'[]',out)
    elif isinstance(a,(int,float)) and not isinstance(a,bool) and isinstance(b,(int,float)) and not isinstance(b,bool):
        if a!=b:
            r=out['numeric'].setdefault(path,{'count':0,'maxAbsoluteDifference':0})
            r['count']+=1;r['maxAbsoluteDifference']=max(r['maxAbsoluteDifference'],abs(a-b))
    elif a!=b:out['discrete'][path]=out['discrete'].get(path,0)+1
    return out

def spans(result,field):
    groups=collections.defaultdict(list)
    for r in result[field]:
        key=json.dumps(r['target'],sort_keys=True)+r.get('reason','')
        groups[key].append((utc(r['interval']['start']),utc(r['interval']['end'])))
    normalized={}
    for key,intervals in groups.items():
        merged=[]
        for a,b in sorted(intervals):
            if merged and a<=merged[-1][1]:merged[-1]=(merged[-1][0],max(b,merged[-1][1]))
            else:merged.append((a,b))
        normalized[key]=merged
    return normalized
