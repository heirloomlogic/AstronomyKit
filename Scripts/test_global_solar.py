import copy
import importlib.util
import io
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

class GlobalSolarRadiusTests(unittest.TestCase):
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

class GlobalSolarEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.captures=json.loads(recorder.CAPTURE.read_bytes())

    def test_recorded_replay(self):
        self.assertEqual(archive.encoded(recorder.evidence(self.captures,recorder.hashes())),recorder.OUTPUT.read_bytes())

    def test_objective_relations_reject_corruption(self):
        changes=[('published','ut',1.0),('published','tt',1.0),('published','sourceTT',1.0),('published','latitude',2.0),('published','obscuration',0.2),('published','physicalTT',1.0),('area','tt',1.0),('area','ut',1.0),('area','obscuration',0.01),('area','sunRadiusRadians',0.001),('area','separationRadians',0.01)]
        for section,field,offset in changes:
            with self.subTest(section=section,field=field):
                values=copy.deepcopy(self.captures)
                # Alter both configurations to ensure parity alone cannot hide corrupted source relations.
                for config in ['debug','release']:values[config][section][0][field]+=offset
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
        self.assertFalse(result['g0InsideDerivedInterval'])
        self.assertLess(result['nativeG0Area'],result['sourceG0AreaInterval'][0])

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
