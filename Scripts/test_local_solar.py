import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[1]
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'Scripts'/file)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
archive=load('local_archive_test','capture-local-solar.py')

class LocalSolarArchiveTests(unittest.TestCase):
    def setUp(self):
        self.blobs={n:(archive.SOURCE/n).read_bytes() for n in archive.SOURCES}
        self.recipes={n:json.loads((archive.SOURCE/(n+'.query.json')).read_bytes()) for n in archive.SOURCES}

    def test_replay_and_direct_area(self):
        value=archive.build(self.blobs,self.recipes)
        self.assertEqual(archive.shared.encoded(value),archive.OUTPUT.read_bytes())
        self.assertEqual([r['obscuration'] for r in value['events']],[.421,.889])
        self.assertEqual([r['date'] for r in value['sequence']['events']],['2026-08-12','2028-01-26'])
        for row in value['events']:
            for c in row['contacts']:self.assertEqual(c['tt'],c['ut']+59.5/86400)

    def test_recipe_semantics_and_digest(self):
        for name,recipe in self.recipes.items():
            for field in recipe:
                recipes=copy.deepcopy(self.recipes);recipes[name][field]='wrong'
                with self.assertRaises(ValueError):archive.build(self.blobs,recipes)
            blobs=dict(self.blobs);blobs[name]+=b'wrong'
            with self.assertRaises(ValueError):archive.build(blobs,self.recipes)

    def test_semantics_survive_refreshed_digests(self):
        changes=[('rp1301-footnotes.html',b"greatest fraction of the Sun's diameter",b"greatest fraction of the Sun's area"),('rp1301-table8.html',b'10 MAY 1994',b'11 MAY 1994'),('rp1301-table8.html',b'U.T.',b'T.T.'),('rp1301-table8.html',b'16 51.0',b'16 52.0'),('rp1301-table10.html',b'ILLINOIS',b'WISCONSIN'),('nasa-washington.html',b'GMT -  5.0',b'GMT -  4.0'),('nasa-washington.html',b'2028 Jan 26',b'2027 Jan 26'),('nasa-washington.html',b'A:p   09:05',b'A:a   09:05'),('nasa-local-model.html',b'Newcomb, 1895',b'Newcomb, 1896')]
        for name,old,new in changes:
            with self.subTest(name=name,old=old):
                self.assertIn(old,self.blobs[name]);blobs=dict(self.blobs);blobs[name]=blobs[name].replace(old,new)
                sources=dict(archive.SOURCES);sources[name]=(sources[name][0],hashlib.sha256(blobs[name]).hexdigest())
                with mock.patch.dict(archive.SOURCES,sources,clear=True):
                    recipes={n:archive.recipe(n) for n in sources}
                    with self.assertRaises(ValueError):archive.build(blobs,recipes)

    def test_retrieval_and_semantic_failure_preserve_set(self):
        for fail_at in range(1,len(archive.SOURCES)+1):
            with tempfile.TemporaryDirectory() as tmp:
                source=Path(tmp)/'sources';source.mkdir();output=Path(tmp)/'refs';output.write_bytes(b'old');calls=[]
                def download(url,timeout):
                    calls.append(url)
                    if len(calls)==fail_at:raise OSError('request failed')
                    return io.BytesIO(self.blobs[next(n for n,(u,_) in archive.SOURCES.items() if u==url)])
                with self.assertRaises(OSError):archive.refresh(download,source,output)
                self.assertEqual(output.read_bytes(),b'old');self.assertEqual(list(source.iterdir()),[])
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp)/'sources';output=Path(tmp)/'refs';output.write_bytes(b'old')
            with self.assertRaises(ValueError):archive.refresh(lambda url,timeout:io.BytesIO(b'wrong'),source,output)
            self.assertEqual(output.read_bytes(),b'old');self.assertFalse(source.exists())

    def test_each_publication_failure_restores_mixed_existing_set(self):
        real_replace=os.replace
        for fail_at in range(1,2*len(archive.SOURCES)+2):
            with self.subTest(fail_at=fail_at),tempfile.TemporaryDirectory() as tmp:
                source=Path(tmp)/'sources';source.mkdir();output=Path(tmp)/'refs';output.write_bytes(b'old')
                (source/next(iter(archive.SOURCES))).write_bytes(b'previous')
                before={p.relative_to(tmp):p.read_bytes() for p in Path(tmp).rglob('*') if p.is_file()};calls=[]
                def replace(a,b):
                    calls.append((a,b))
                    if len(calls)==fail_at:raise OSError('publish failed')
                    return real_replace(a,b)
                def download(url,timeout):return io.BytesIO(self.blobs[next(n for n,(u,_) in archive.SOURCES.items() if u==url)])
                with mock.patch.object(archive.shared.os,'replace',side_effect=replace),self.assertRaises(OSError):archive.refresh(download,source,output)
                self.assertEqual({p.relative_to(tmp):p.read_bytes() for p in Path(tmp).rglob('*') if p.is_file()},before)



recorder=load('local_recorder_test','record-local-solar-evidence.py')

class LocalSolarEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.capture=json.loads(recorder.CAPTURE.read_bytes())
        self.refs=json.loads(archive.OUTPUT.read_bytes())

    def test_all_sections_replay(self):
        self.assertEqual(archive.shared.encoded(recorder.evidence(self.capture,recorder.hashes())),recorder.OUTPUT.read_bytes())

    def test_direct_input_bindings(self):
        bindings=recorder.hashes()
        for name in ['Observer.swift','CivilTime.swift','UTCOffsetTable.swift','CelestialBody.swift','Time.swift']:
            self.assertIn('Sources/AstronomyKit/'+name,bindings)
        for path in ['Tests/AstronomyKitTests/AuditValidationTests.swift','Scripts/reference-data/build-fixtures.py','Sources/CLibAstronomy/astronomy.c']:
            self.assertIn(path,bindings)

    def test_published_relations_without_relying_on_configuration_parity(self):
        for key,value in [('ut',1),('tt',1),('altitude',2),('sourceUT',1),('formerUTCResidualSeconds',1)]:
            rows=copy.deepcopy(self.capture['debug']['published']);rows[0]['contacts'][0][key]+=value
            with self.subTest(key=key),self.assertRaises(ValueError):recorder.published(rows)
        rows=copy.deepcopy(self.capture['debug']['published']);rows[0]['contacts'].reverse()
        with self.assertRaises(ValueError):recorder.published(rows)
        rows=copy.deepcopy(self.capture['debug']['published']);rows[0]['obscuration']=1.1
        with self.assertRaises(ValueError):recorder.published(rows)

    def test_report_source_anchor_geometry_and_contact_relations(self):
        for key,amount in [('sourceTT',.763/86400),('sourceUT',.763/86400),('modelUT',.763/86400),('sourceEpochObscuration',.01),('moonRadius',.0001),('separation',.0001)]:
            rows=copy.deepcopy(self.capture['debug']['report']);rows[0][key]+=amount
            with self.subTest(key=key),self.assertRaises(ValueError):recorder.report(rows,self.refs)
        for key in ['tt','ut','sourceUT','sourceTT','altitude']:
            rows=copy.deepcopy(self.capture['debug']['report']);rows[0]['contacts'][0][key]+=2
            with self.subTest(key=key),self.assertRaises(ValueError):recorder.report(rows,self.refs)

    def test_sequence_identity_and_time_relation(self):
        for key,value in [('tt',1),('ut',1),('gmtPeak',1),('altitude',-100),('obscuration',2)]:
            rows=copy.deepcopy(self.capture['debug']['sequence']);rows[0][key]+=value
            with self.subTest(key=key),self.assertRaises(ValueError):recorder.sequence(rows,self.refs)
        rows=list(reversed(self.capture['debug']['sequence']))
        with self.assertRaises(ValueError):recorder.sequence(rows,self.refs)

    def test_peak_definition_source_and_residual_relations(self):
        for key,value in [('sourceUT',1),('tt',1),('ut',1),('residualSeconds',1),('magnitude',2),('area',2)]:
            rows=copy.deepcopy(self.capture['debug']['peak-definition']);rows[0][key]+=value
            with self.subTest(key=key),self.assertRaises(ValueError):recorder.peak_definition(rows,self.refs)
        rows=list(reversed(self.capture['debug']['peak-definition']))
        with self.assertRaises(ValueError):recorder.peak_definition(rows,self.refs)

    def test_configuration_resource_and_metadata_checks(self):
        for key,value in [('nextCount',18),('coldSeconds',-1),('peakAfterColdBytes',0),('host','')]:
            data=copy.deepcopy(self.capture);data['resources'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):recorder.evidence(data,{})
        for key,value in [('runtimeBaseRevision','bad'),('releaseExecutableBytes',0),('releaseObjectBytes',{}),('toolchain','')]:
            data=copy.deepcopy(self.capture);data[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):recorder.evidence(data,{})
        data=copy.deepcopy(self.capture);data['release']['published'][0]['obscuration']+=.001
        with self.assertRaises(ValueError):recorder.evidence(data,{})
        data=copy.deepcopy(self.capture);data['debug']['published'][0]['obscuration']=float('nan')
        with self.assertRaises(ValueError):recorder.evidence(data,{})

    def test_two_output_publication_rollback(self):
        real_replace=os.replace
        with tempfile.TemporaryDirectory() as tmp:
            first=Path(tmp)/'capture';second=Path(tmp)/'evidence'
            first.write_bytes(b'old capture');second.write_bytes(b'old evidence');calls=[]
            def replace(a,b):
                calls.append((a,b))
                if len(calls)==2:raise OSError('second output failed')
                return real_replace(a,b)
            with mock.patch.object(archive.shared.os,'replace',side_effect=replace),self.assertRaises(OSError):archive.shared.publish({first:b'new capture',second:b'new evidence'})
            self.assertEqual(first.read_bytes(),b'old capture');self.assertEqual(second.read_bytes(),b'old evidence')

if __name__=='__main__':unittest.main()
