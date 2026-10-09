import copy
import importlib.util
import io
import hashlib
import os
import math
import re
from unittest import mock
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

def load(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'Scripts'/file)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

archive=load('global_archive_tests','capture-global-solar.py')
recorder=load('global_record_tests','record-global-solar-evidence.py')
g0=load('rp1301_g0_tests','assess-rp1301-g0.py')

class GlobalSolarArchiveTests(unittest.TestCase):
    def setUp(self):
        self.blobs={n:(archive.SOURCE/n).read_bytes() for n in archive.SOURCES}
        self.recipes={n:json.loads((archive.SOURCE/(n+'.query.json')).read_bytes()) for n in archive.SOURCES}
        self.catalog=archive.CATALOG.read_bytes()

    def test_replay(self):
        self.assertEqual(archive.encoded(archive.build(self.blobs,self.recipes,self.catalog)),archive.OUTPUT.read_bytes())

    def test_every_recipe_semantic_and_digest(self):
        for name in self.recipes:
            for field in self.recipes[name]:
                with self.subTest(name=name,field=field):
                    recipes=copy.deepcopy(self.recipes);recipes[name][field]='wrong'
                    with self.assertRaises(ValueError):archive.build(self.blobs,recipes,self.catalog)
            blobs=dict(self.blobs);blobs[name]+=b' altered'
            with self.assertRaises(ValueError):archive.build(blobs,self.recipes,self.catalog)

    def test_incomplete_and_catalog(self):
        blobs=dict(self.blobs);blobs.pop(next(iter(blobs)))
        with self.assertRaises(ValueError):archive.build(blobs,self.recipes,self.catalog)
        with self.assertRaises(ValueError):archive.build(self.blobs,self.recipes,self.catalog+b'bad')

    def test_download_failure_preserves_complete_archive(self):
        for fail_at in [1,len(archive.SOURCES)]:
            with tempfile.TemporaryDirectory() as tmp:
                source=Path(tmp)/'sources';source.mkdir();(source/'existing').write_text('retain')
                output=Path(tmp)/'fixture.json';output.write_text('retain')
                calls=[]
                def download(url,timeout):
                    calls.append(url)
                    if len(calls)==fail_at:raise OSError('request failed')
                    name=next(n for n,(u,_,_) in archive.SOURCES.items() if u==url)
                    return io.BytesIO(self.blobs[name])
                with self.assertRaises(OSError):archive.refresh(download,source,output)
                self.assertEqual({p.name:p.read_bytes() for p in source.iterdir()},{'existing':b'retain'})
                self.assertEqual(output.read_text(),'retain')

    def test_semantic_failure_preserves_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp)/'sources';source.mkdir();output=Path(tmp)/'fixture';output.write_text('retain')
            def download(url,timeout):return io.BytesIO(b'valid HTML but wrong event')
            with self.assertRaises(ValueError):archive.refresh(download,source,output)
            self.assertEqual(list(source.iterdir()),[]);self.assertEqual(output.read_text(),'retain')

    def test_publication_failure_preserves_complete_archive(self):
        for fail_at in [1, 2, 11]:
            with self.subTest(fail_at=fail_at), tempfile.TemporaryDirectory() as tmp:
                source=Path(tmp)/'sources';source.mkdir();output=Path(tmp)/'fixture.json'
                paths=[p for n in archive.SOURCES for p in [source/n,source/(n+'.query.json')]]+[output]
                for p in paths:p.write_bytes(b'old '+p.name.encode())
                original={p:p.read_bytes() for p in paths};count=0
                real_write=Path.write_bytes;real_replace=os.replace
                def write(p,data):
                    nonlocal count
                    if p in original:
                        count+=1
                        if count==fail_at:
                            real_write(p,b'truncated');raise OSError('injected publication failure')
                    return real_write(p,data)
                def replace(src,dst):
                    nonlocal count
                    if Path(dst) in original:
                        count+=1
                        if count==fail_at:raise OSError('injected publication failure')
                    return real_replace(src,dst)
                def download(url,timeout):return io.BytesIO(self.blobs[next(n for n,(u,_,_) in archive.SOURCES.items() if u==url)])
                with mock.patch.object(Path,'write_bytes',write), mock.patch.object(os,'replace',replace):
                    with self.assertRaises(OSError):archive.refresh(download,source,output)
                self.assertEqual({p:p.read_bytes() for p in paths},original)

    def test_1986_semantics_even_after_digest_refresh(self):
        cases=[('nasa-solar-1901.html',b' 1.0000  60N',b' 1.0001  60N'),
               ('nasa-solar-1901.html',b'   H   -t ',b'   A   -t '),
               ('rp1301-lunar-radius.html',b'beaded annular eclipse',b'beaded total eclipse')]
        for name,before,after in cases:
            with self.subTest(name=name,after=after):
                blobs=dict(self.blobs);self.assertIn(before,blobs[name]);blobs[name]=blobs[name].replace(before,after)
                sources=dict(archive.SOURCES);url,_,scale=sources[name];sources[name]=(url,hashlib.sha256(blobs[name]).hexdigest(),scale)
                with mock.patch.object(archive,'SOURCES',sources):
                    recipes={n:archive.recipe(n) for n in sources}
                    with self.assertRaises(ValueError):archive.build(blobs,recipes,self.catalog)

    def test_1986_row_and_claim_are_unique(self):
        name='nasa-solar-1901.html'
        line=next(line for line in self.blobs[name].splitlines(keepends=True) if b'>1986 Oct 03</a>  <a' in line)
        limb='rp1301-lunar-radius.html'
        claim=b'eclipse of 3 October 1986.'
        cases=[(name,self.blobs[name].replace(line,b'')),(name,self.blobs[name]+line),
               (limb,self.blobs[limb].replace(claim,b'eclipse of 4 October 1986.'))]
        for name,data in cases:
            blobs=dict(self.blobs);blobs[name]=data;sources=dict(archive.SOURCES)
            url,_,scale=sources[name];sources[name]=(url,hashlib.sha256(data).hexdigest(),scale)
            with mock.patch.object(archive,'SOURCES',sources):
                with self.assertRaises(ValueError):archive.build(blobs,{n:archive.recipe(n) for n in sources},self.catalog)

    def test_jsex_method_source_is_pinned_and_semantically_checked(self):
        self.assertIn('nasa-jsex-program.js',self.blobs)
        name='nasa-jsex-program.js';old=b'mid[38] = (mid[28] - mid[29]) / (mid[28] + mid[29])';new=b'mid[38] = (mid[28] + mid[29]) / (mid[28] - mid[29])'
        self.assertIn(old,self.blobs[name]);blobs=dict(self.blobs);blobs[name]=blobs[name].replace(old,new)
        sources=dict(archive.SOURCES);url,_,scale=sources[name];sources[name]=(url,hashlib.sha256(blobs[name]).hexdigest(),scale)
        with mock.patch.object(archive,'SOURCES',sources):
            with self.assertRaises(ValueError):archive.build(blobs,{n:archive.recipe(n) for n in sources},self.catalog)

class GlobalSolarPublicationTests(unittest.TestCase):
    def test_staging_failure_and_new_file_rollback(self):
        for phase in ['staging','publication']:
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);existing=root/'existing';created=root/'created'
                existing.write_bytes(b'original')
                real_write=Path.write_bytes;real_replace=os.replace;calls=0
                def write(path,data):
                    if phase=='staging' and path.name=='new-1':raise OSError('staging failed')
                    return real_write(path,data)
                def replace(src,dst):
                    nonlocal calls
                    calls+=1
                    if phase=='publication' and calls==2:raise OSError('publication failed')
                    return real_replace(src,dst)
                with mock.patch.object(Path,'write_bytes',write), mock.patch.object(os,'replace',replace):
                    with self.assertRaises(OSError):archive.publish({created:b'new',existing:b'changed'})
                self.assertEqual({p.name:p.read_bytes() for p in root.iterdir()},{'existing':b'original'})

    def test_rollback_failure_retains_backups(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);first=root/'first';second=root/'second'
            first.write_bytes(b'original first');second.write_bytes(b'original second')
            real_replace=os.replace;calls=0
            def replace(src,dst):
                nonlocal calls
                calls+=1
                if calls>=2:raise OSError('persistent device failure')
                return real_replace(src,dst)
            with mock.patch.object(os,'replace',replace):
                with self.assertRaisesRegex(RuntimeError,'backups retained'):archive.publish({first:b'changed',second:b'changed'})
            stages=list(root.glob('.global-solar-publish-*'));self.assertEqual(len(stages),1)
            self.assertEqual((stages[0]/'old-0').read_bytes(),b'original first')
            self.assertEqual((stages[0]/'old-1').read_bytes(),b'original second')

class GlobalSolarRadiusTests(unittest.TestCase):
    def test_discriminator_uses_the_native_au_conversion(self):
        constants=(ROOT/'Sources/AstronomyKit/Engine/Foundation/EngineConstants.swift').read_text()
        au=float(re.search(r'kilometersPerAU = ([\d_.]+)',constants).group(1).replace('_',''))
        vectors=json.loads((recorder.DATA/'radius-vectors.json').read_bytes())
        value=next(r for r in recorder.radii.build(vectors) if r['tt']==vectors[0]['tt'] and r['case']=='k2-959.63')
        distance=math.sqrt(math.fsum(x*x for x in vectors[0]['sunEQD']))
        expected=math.degrees(math.asin(au*math.sin(math.radians(959.63/3600))/distance))*3600
        self.assertAlmostEqual(value['sunGeoArcseconds'],expected,delta=4*math.ulp(expected))

    def test_replay_and_corruption(self):
        vectors=json.loads((recorder.DATA/'radius-vectors.json').read_bytes())
        rows=recorder.radii.build(vectors)
        self.assertEqual(rows,json.loads((recorder.DATA/'radius-comparison.json').read_bytes()))
        for change in ['epoch','rotation','radius']:
            data=copy.deepcopy(vectors)
            if change=='epoch':data[0]['tt']+=1
            if change=='rotation':data[0]['sunEQD'][0]+=10000
            if change=='radius':
                data[0]['sun']=[x*1.001 for x in data[0]['sun']]
                data[0]['sunEQD']=[x*1.001 for x in data[0]['sunEQD']]
            with self.assertRaises(ValueError):recorder.radii.build(data)

class RP1301G0Tests(unittest.TestCase):
    def setUp(self):
        self.references=json.loads(archive.OUTPUT.read_bytes())
        self.physical=json.loads((recorder.DATA/'radius-comparison.json').read_bytes())

    def test_replay_reproduces_published_magnitude(self):
        result=g0.build(self.references,self.physical)
        self.assertEqual(result,json.loads((recorder.DATA/'rp1301-g0-decomposition.json').read_bytes()))
        self.assertTrue(result['mixedMagnitudeInsidePrintInterval'])
        self.assertEqual(result['sourceLabel'],'Eclipse Magnitude')
        self.assertEqual(len(result['table4Controls']),2)

    def test_source_elements_and_physical_candidates_are_independent_controls(self):
        references=copy.deepcopy(self.references);references['rp1301']['besselian']['coefficients']['l2'][0]+=0.001
        with self.assertRaises(ValueError):g0.build(references,self.physical)
        physical=copy.deepcopy(self.physical);physical[0]['tt']+=1
        with self.assertRaises(ValueError):g0.build(self.references,physical)

    def test_all_physical_candidates_shifted_by_a_tenth_second_are_rejected(self):
        physical=copy.deepcopy(self.physical)
        for row in physical:
            if abs(row['tt']-self.references['rp1301']['greatestTT'])<1e-6:row['tt']+=0.1/86400
        with self.assertRaises(ValueError):g0.build(self.references,physical)

class GlobalSolarEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.captures=json.loads(recorder.CAPTURE.read_bytes())

    def test_recording_second_publication_failure_preserves_pair(self):
        with tempfile.TemporaryDirectory() as tmp:
            capture=Path(tmp)/'captures.json';output=Path(tmp)/'evidence.json'
            capture.write_bytes(b'old captures');output.write_bytes(b'old evidence')
            real_write=Path.write_bytes;real_replace=os.replace;failed=False
            def write(p,data):
                nonlocal failed
                if p==output and not failed:
                    failed=True;real_write(p,b'truncated');raise OSError('second write failed')
                return real_write(p,data)
            def replace(src,dst):
                nonlocal failed
                if Path(dst)==output and not failed:
                    failed=True;raise OSError('second replacement failed')
                return real_replace(src,dst)
            with mock.patch.object(recorder,'CAPTURE',capture), mock.patch.object(recorder,'OUTPUT',output), mock.patch.object(recorder,'capture',return_value=self.captures), mock.patch.object(recorder,'hashes',return_value={}), mock.patch('sys.argv',['record','--capture',tmp]), mock.patch.object(Path,'write_bytes',write), mock.patch.object(os,'replace',replace):
                with self.assertRaises(OSError):recorder.main()
            self.assertEqual(capture.read_bytes(),b'old captures')
            self.assertEqual(output.read_bytes(),b'old evidence')

    def test_recorded_replay(self):
        self.assertEqual(archive.encoded(recorder.evidence(self.captures,recorder.hashes())),recorder.OUTPUT.read_bytes())

    def test_objective_relations_reject_corruption(self):
        changes=[('published','ut',1.0),('published','tt',1.0),('published','sourceTT',1.0),('published','latitude',2.0),('published','obscuration',0.2),('published','physicalTT',1.0),('area','tt',1.0),('area','modelUT',1.0),('area','sourceUT',1.0),('area','sourceDeltaTSeconds',1.0),('area','obscuration',0.01),('area','sunRadiusRadians',0.001),('area','separationRadians',0.01)]
        for section,field,offset in changes:
            with self.subTest(section=section,field=field):
                values=copy.deepcopy(self.captures)
                # Alter both configurations to ensure parity alone cannot hide corrupted source relations.
                for config in ['debug','release']:values[config][section][0][field]+=offset
                with self.assertRaises(ValueError):recorder.evidence(values,{})

    def test_source_ut_cannot_replace_model_ut(self):
        for mutation in ['source-ut-as-model','wrong-model','g0-source']:
            values=copy.deepcopy(self.captures)
            for config in ['debug','release']:
                rows=values[config]['area']
                if mutation=='source-ut-as-model':rows[0]['modelUT']=rows[0]['sourceUT']
                elif mutation=='wrong-model':rows[0]['deltaTModel']='jplHorizons'
                else:rows[2]['sourceUT']=rows[2]['modelUT']
            with self.assertRaises(ValueError):recorder.evidence(values,{})

    def test_optionals_identity_and_g0(self):
        for mutation in ['partial','missing','g0']:
            values=copy.deepcopy(self.captures)
            for c in ['debug','release']:
                if mutation=='partial':next(r for r in values[c]['published'] if r['kind']=='partial')['latitude']=0
                if mutation=='missing':values[c]['published'].pop()
                if mutation=='g0':values[c]['area'][2]['tt']+=1
            with self.assertRaises(ValueError):recorder.evidence(values,{})
        result=recorder.evidence(self.captures,{})['annularArea']
        self.assertFalse(result['g0PhysicalAreaInsideSquaredMagnitudeInterval'])
        self.assertLess(result['nativeG0PhysicalArea'],result['sourceG0SquaredMagnitudeInterval'][0])

    def test_boundary_metadata_must_match_parsed_sources(self):
        refs=json.loads(recorder.archive.OUTPUT.read_bytes())
        for field,value in [('pathType','A'),('magnitude',1.1),('observedLimbKind','total'),('tt',0)]:
            values=copy.deepcopy(refs);values['boundary1986'][field]=value
            with self.subTest(field=field), tempfile.TemporaryDirectory() as tmp:
                output=Path(tmp)/'references.json';output.write_bytes(archive.encoded(values))
                with mock.patch.object(recorder.archive,'OUTPUT',output):
                    with self.assertRaises(ValueError):recorder.evidence(self.captures,{})
        self.assertEqual(recorder.evidence(self.captures,{})['boundary1986']['source'],refs['boundary1986'])

    def test_resource_build_and_bindings(self):
        for key,value in [('nextCount',98),('peakAfterColdBytes',-1),('coldSeconds',float('nan'))]:
            captures=copy.deepcopy(self.captures);captures['resources'][key]=value
            with self.assertRaises(ValueError):recorder.evidence(captures,{})
        captures=copy.deepcopy(self.captures);captures['buildReceipts']['debug']='not a completed build'
        with self.assertRaises(ValueError):recorder.evidence(captures,{})
        bindings=recorder.hashes()
        for path in ['Sources/AstronomyKit/Observer.swift','Sources/AstronomyKit/CelestialBody.swift','Sources/AstronomyKit/Engine/Eclipses/EngineGlobalSolarEvents.swift','Scripts/capture-global-solar.py']:
            self.assertIn(path,bindings)

if __name__=='__main__':unittest.main()
