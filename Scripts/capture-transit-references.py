#!/usr/bin/env python3
"""Replay existing primary archives into transit and consecutive-eclipse references."""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('global_archive',ROOT/'Scripts/capture-global-solar.py')
shared=importlib.util.module_from_spec(spec);spec.loader.exec_module(shared)
SOURCE=ROOT/'Scripts/reference-data/sources'
OUTPUT=ROOT/'Scripts/eclipse-data/transit-references.json'
MONTHS=dict(zip('Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split(),range(1,13)))
SOURCES={
 'mercury.html':('https://eclipse.gsfc.nasa.gov/transit/catalog/MercuryCatalog.html','UT'),
 'venus.html':('https://eclipse.gsfc.nasa.gov/transit/catalog/VenusCatalog.html','UT'),
 'nasa-oh2001.html':('https://eclipse.gsfc.nasa.gov/OH/OH2001.html','UT'),
 'solar_2001.html':('https://eclipse.gsfc.nasa.gov/SEcat5/SE2001-2100.html','TD'),
}
# Digests pin the existing archives, including their original Internet Archive wrappers.
DIGESTS={'mercury.html': 'e29ff3e1ada11eaee343032f0c5b927ccf9a9b2cacad8e006a2bd6b4fc71ba40', 'venus.html': 'c06f2f10efc8554328bb51ed1725d13f1ec53a5a82a0c25089dcf1104994ca7f', 'nasa-oh2001.html': '09a0c66a75942e594f7cd1d7b02c85a4e7f73594b8e64669a0a324926d6cb873', 'solar_2001.html': '820b7a9e4a04881ff212ee59603f03fb3ebdcb72e340414494b1fb84271efc9d'}

RADIUS_SOURCE=SOURCE/"transit"
RADII={'mercury': ('170d9f2d2ba7f7ae322c68d473ccb0b35ab94f4b4aca197bf74fe3b7e4e10f3f', 2439.7), 'venus': ('473c61da0bf7188764ec8ae5b12c0fdc9f922bccd9e3f6b47c885fef0723541c', 6051.8), 'sun': ('bcc186a518298636340e7975bf5a32da660cd656b90081f2e7c8aa7ec2b6561a', 695700.0)}

def radius_conventions(blobs,recipes):
    if set(blobs)!=set(RADII) or set(recipes)!=set(RADII):raise ValueError('radius source set')
    values={}
    for body,(digest,expected) in RADII.items():
        url='https://nssdc.gsfc.nasa.gov/planetary/factsheet/'+body+'fact.html'
        if recipes[body]!={'url':url,'method':'GET','sha256':digest,'subject':body+' volumetric mean radius','units':'km'} or hashlib.sha256(blobs[body]).hexdigest()!=digest:raise ValueError('radius source recipe/digest')
        text=shared.text(blobs[body])
        matches=re.findall(r'Volumetric mean radius \(km\)\s*([\d,.]+)',text)
        if len(matches)!=1:raise ValueError('radius field')
        value=float(matches[0].replace(',',''))
        if value!=expected:raise ValueError('radius value')
        values[body]={'radiusKilometers':value,'url':url,'sha256':digest,'convention':'NASA fact-sheet volumetric mean radius; engine spherical-disc approximation, not a claim about Meeus catalog constants'}
    return values

DIAGRAM_TRANSCRIPTION_SHA256='739f7b9c89107db68d86f3f76710b85d6b7d4fba71114d6c45911451f1ca73fd'

def diagram_contacts():
    raw=(RADIUS_SOURCE/'lunar-diagram-transcription.json').read_bytes()
    if hashlib.sha256(raw).hexdigest()!=DIAGRAM_TRANSCRIPTION_SHA256:raise ValueError('reviewed manual transcription differs')
    rows=json.loads(raw);result=[]
    for row in rows:
        pdf=(RADIUS_SOURCE/row['file']).read_bytes();recipe=json.loads((RADIUS_SOURCE/(row['file']+'.query.json')).read_bytes())
        expected={'url':row['url'],'method':'GET','sha256':row['sha256'],'timeScale':'UT contacts; TD and UT greatest eclipse both printed','subject':row['date']+' lunar eclipse diagram'}
        if recipe!=expected or hashlib.sha256(pdf).hexdigest()!=row['sha256']:raise ValueError('diagram provenance')
        if row['shadowRule']!='CdT (Danjon)' or row['ephemeris']!='VSOP87/ELP2000-85':raise ValueError('diagram model')
        contacts={name:shared.tt(row['date']+'T'+row[key]) for name,key in [('penumbralBegin','penumbralBeginUT'),('peak','greatestUT'),('penumbralEnd','penumbralEndUT')]}
        if not contacts['penumbralBegin']<contacts['peak']<contacts['penumbralEnd']:raise ValueError('diagram contact ordering')
        result.append({**row,'contactsUT':contacts,'timeToleranceSeconds':120.0})
    if [r['date'] for r in result]!=['2001-01-09','2001-07-05','2001-12-30']:raise ValueError('diagram identities')
    return result


def build(blobs):
    if set(blobs)!=set(SOURCES):raise ValueError('source set')
    for name,data in blobs.items():
        if hashlib.sha256(data).hexdigest()!=DIGESTS[name]:raise ValueError('source digest '+name)
    transits={}
    pattern=re.compile(r'^\s*(\d{4})\s+(\w{3})\s+(\d+)\s+(\d\d:\d\d)\s+(\S+)\s+(\d\d:\d\d)\s+(\S+)\s+(\d\d:\d\d)\s+([\d.]+)',re.M)
    for body in ['mercury','venus']:
        text=shared.text(blobs[body+'.html'])
        for phrase in ['geocentric Universal Time','externally tangent','internally tangent','closest to the center of the Sun as seen from the center of Earth','1989']:
            if phrase not in text:raise ValueError('transit semantic '+phrase)
        if not re.search(r'seconds of arc|arc-seconds|arcseconds',text,re.I):raise ValueError('separation unit')
        rows=[]
        for year,month,day,c1,c2,peak,c3,c4,sep in pattern.findall(text):
            if not 2000<=int(year)<=2130:continue
            date=f'{year}-{MONTHS[month]:02d}-{int(day):02d}'
            p=shared.tt(date+'T'+peak)
            a=shared.tt(date+'T'+c1);z=shared.tt(date+'T'+c4)
            if a>p:a-=1
            if z<p:z+=1
            rows.append({'date':date,'body':body,'startUT':a,'peakUT':p,'finishUT':z,'separationArcminutes':float(sep)/60,'timeToleranceSeconds':642.6 if body=='mercury' else 546.54,'separationToleranceArcminutes':.2121 if body=='mercury' else .6772})
        dates=[r['date'] for r in rows]
        wanted=['2003-05-07','2006-11-08'] if body=='mercury' else ['2012-06-06','2117-12-11','2125-12-08']
        begin=dates.index(wanted[0]);selected=rows[begin:begin+len(wanted)]
        if [r['date'] for r in selected]!=wanted:raise ValueError('consecutive transit identities')
        transits[body]=selected
    raw=blobs['nasa-oh2001.html'].decode('latin1');text=shared.text(blobs['nasa-oh2001.html'])
    for phrase in ['Newcomb','Improved Lunar Ephemeris','enlarged by 2%']:
        if phrase not in text:raise ValueError('lunar model semantics')
    lunar=[]
    labels={'Penumbral Eclipse Begins':'penumbralBegin','Greatest Eclipse':'peak','Penumbral Eclipse Ends':'penumbralEnd'}
    for month,day,kind,block in re.findall(r'name=LE2001(\w{3})(\d{2})([TPN])>.*?<pre>(.*?)</pre>',raw,re.S):
        date=f'2001-{MONTHS[month]:02d}-{day}'
        contacts={labels[label]:shared.tt(date+'T'+clock) for label,clock in re.findall(r'(Penumbral Eclipse Begins|Greatest Eclipse|Penumbral Eclipse Ends):\s*(\d\d:\d\d:\d\d) UT',block)}
        if set(contacts)!=set(labels.values()) or not contacts['penumbralBegin']<contacts['peak']<contacts['penumbralEnd']:raise ValueError('lunar contacts')
        lunar.append({'date':date,'kind':{'T':'total','P':'partial','N':'penumbral'}[kind],'contactsUT':contacts,'timeToleranceSeconds':120.0})
    if [r['date'] for r in lunar]!=['2001-01-09','2001-07-05','2001-12-30']:raise ValueError('annual lunar sequence')
    solar=[]
    text=shared.text(blobs['solar_2001.html'])
    if not re.search(r'TD of\s+Catalog\s+Calendar\s+Greatest',text):raise ValueError('solar time scale')
    for year,month,day,clock,kind in re.findall(r'^\s*\d+\s+(\d{4})\s+(\w{3})\s+(\d\d)\s+(\d\d:\d\d:\d\d)\s+-?\d+\s+\S+\s+\d+\s+([PATH])',text,re.M):
        date=f'{year}-{MONTHS[month]:02d}-{day}'
        solar.append({'date':date,'tt':shared.tt(date+'T'+clock),'kind':{'P':'partial','A':'annular','T':'total','H':'total'}[kind],'timeToleranceSeconds':453.6})
    dates=[r['date'] for r in solar];i=dates.index('2024-04-08');solar=solar[i:i+3]
    if [r['date'] for r in solar]!=['2024-04-08','2024-10-02','2025-03-29']:raise ValueError('solar sequence')
    return {'schemaVersion':1,'radiusConventions':radius_conventions({b:(RADIUS_SOURCE/(b+'fact.html')).read_bytes() for b in RADII},{b:json.loads((RADIUS_SOURCE/(b+'fact.html.query.json')).read_bytes()) for b in RADII}),'sources':{n:{'url':SOURCES[n][0],'timeScale':SOURCES[n][1],'sha256':DIGESTS[n]} for n in SOURCES},'transitSequences':transits,'lunarSequence':lunar,'danjonContacts':diagram_contacts(),'globalSequence':solar,'semantics':{'transits':'Geocentric UT; greatest transit is angular center separation minimum. External contacts I/IV. Source separation arcseconds converted to arcminutes. Meeus Transits (1989) Besselian elements; catalog does not disclose exact radii or apparent-direction corrections.','lunar':'OH2001 UT; Newcomb/Improved Lunar Ephemeris, umbral diameter enlarged 2 percent. Direct tabulated penumbral contacts, distinct from modern Danjon duration references.','global':'Published TD calendar arithmetic; consecutive complete-catalog rows.'}}


def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    result=shared.encoded(build({n:(SOURCE/n).read_bytes() for n in SOURCES}))
    if args.check:
        if OUTPUT.read_bytes()!=result:raise SystemExit('transit references differ')
    else:shared.publish({OUTPUT:result})
    print('transit and consecutive eclipse references match')
if __name__=='__main__':main()
