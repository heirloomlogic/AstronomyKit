"""Offline scientific and provenance checks for the isolated Pluto diagnosis."""
import copy
import importlib.util
import json
import math
from pathlib import Path
import re
import shutil
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('pluto_model_diagnostic',Path(__file__).with_name('pluto-model-diagnostic.py'))
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class PlutoDiagnosticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan=json.loads((m.EVIDENCE/'plan.json').read_text())
        cls.response=json.loads((m.EVIDENCE/'barycenter.json').read_text())

    def test_archived_reference_and_exact_epochs(self):
        self.assertEqual(len(m.references(self.plan,'barycenter')),25)
        self.assertEqual(len(m.references(self.plan,'body-center')),25)

    def test_rejects_wrong_frame_time_center_target_units_and_solution(self):
        for before,after in [('ICRF','FK5'),('JDTT','JDTDB'),('Sun (10)','Earth (399)'),('Pluto Barycenter (9)','Pluto (999)'),('AU-D','KM-S'),('DE441','DE440'),('GEOMETRIC cartesian states','APPARENT cartesian states')]:
            with self.subTest(before=before):
                bad=copy.deepcopy(self.response);bad['result']=bad['result'].replace(before,after)
                with self.assertRaises(ValueError):m.parse_response(bad,self.plan['epochsTTDays'],'barycenter')

    def test_rejects_signature_and_epoch_mutation(self):
        bad=copy.deepcopy(self.response);bad['signature']['version']='0'
        with self.assertRaises(ValueError):m.parse_response(bad,self.plan['epochsTTDays'],'barycenter')
        with self.assertRaises(ValueError):m.parse_response(self.response,self.plan['epochsTTDays'][:-1],'barycenter')

    def test_rejects_truncated_state_and_nonfinite_derived_values(self):
        bad=copy.deepcopy(self.response)
        before,tail=bad['result'].split('$$SOE');table,after=tail.split('$$EOE')
        lines=table.strip().splitlines();lines[0]=','.join(lines[0].split(',')[:5])
        bad['result']=before+'$$SOE\n'+'\n'.join(lines)+'\n$$EOE'+after
        with self.assertRaises(ValueError):m.parse_response(bad,self.plan['epochsTTDays'],'barycenter')
        for invalid in [float('nan'),float('inf'),float('-inf')]:
            with self.assertRaises(ValueError):m.validate_finite({'residuals':[{'radialKm':invalid}]})

    def test_rejects_wrong_recipe_even_with_unchanged_response_hash(self):
        with tempfile.TemporaryDirectory() as name:
            directory=Path(name)
            for suffix in ['.json','.query.json']:
                (directory/('barycenter'+suffix)).write_bytes((m.EVIDENCE/('barycenter'+suffix)).read_bytes())
            path=directory/'barycenter.query.json';query=json.loads(path.read_text());query['parameters']['TIME_TYPE']="'TDB'";path.write_text(json.dumps(query))
            with patch.object(m,'EVIDENCE',directory),self.assertRaises(ValueError):m.references(self.plan,'barycenter')

    def test_rejects_source_anchor_drift(self):
        with self.assertRaises(ValueError):m.variant_source('#define PLUTO_DT 147',73)
        with self.assertRaises(ValueError):m.relative_force_source('unrecognized source')

    def test_official_top2013_reproduces_stored_seed_positions_and_velocities(self):
        source=m.source_archive.read_bytes(m.ROOT, m.ROOT/'Sources/CLibAstronomy/astronomy.c').decode()
        report=json.loads((m.EVIDENCE/'top2013-report.json').read_text())
        for row in report['rows']:
            if row['ttDays'] in self.plan['seedTTDays']:
                match=re.search(r'\{\s*'+str(row['ttDays'])+r'\.0,\s*\{([^}]+)\},\s*\{([^}]+)\}',source)
                p=[float(v) for v in match[1].split(',')];v=[float(v) for v in match[2].split(',')]
                self.assertLess(math.dist(p,row['numericTTAsTDBPosition'])*m.AU,0.0002)
                self.assertLess(math.dist(v,row['numericTTAsTDBVelocity'])*m.AU/86400,2e-13)

    def test_modern_seed_replacement_is_exact_at_seeds(self):
        report=json.loads((m.EVIDENCE/'integration-report.json').read_text())
        for variant in report['variants']:
            if variant['seedModel']=='modern-barycenter':
                for row in variant['rows']:
                    if row['ttDays'] in self.plan['seedTTDays']:
                        self.assertLess(row['residuals']['cached']['barycenter']['vectorKm'],0.00001)

    def test_interpolation_sampling_really_is_off_grid(self):
        for stem in ['offgrid','phasegrid']:
            plan=json.loads((m.EVIDENCE/stem/'plan.json').read_text())
            for t in plan['epochsTTDays']:
                if t not in plan['seedTTDays']:
                    for step in plan['stepsDays']+[plan['additionalModernEightPlanetStepDays']]:
                        self.assertGreater(abs(t/step-round(t/step)),0.0001)

    def test_rejects_changed_transitive_polynomial_coefficients(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name)
            evidence=root/m.EVIDENCE.relative_to(m.ROOT)
            shutil.copytree(m.EVIDENCE,evidence)
            shutil.copytree(m.ROOT/'Sources/CLibAstronomy',root/'Sources/CLibAstronomy')
            shutil.copytree(m.ROOT/m.source_archive.ARCHIVE,root/m.source_archive.ARCHIVE)
            for source in m.source_paths():
                target=root/source.relative_to(m.ROOT)
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(source,target)
            with patch.object(m,'ROOT',root),patch.object(m,'EVIDENCE',evidence):
                m.seal()
                m.check()
                coefficients=root/'Sources/CLibAstronomy/generated/polynomial-data.h'
                coefficients.write_bytes(coefficients.read_bytes()+b'\n/* changed coefficients */\n')
                with self.assertRaisesRegex(ValueError,'manifest hash mismatch: Sources/CLibAstronomy/generated/polynomial-data.h'):
                    m.check()

    def test_manifest_and_recomputed_residuals(self):
        m.check()


if __name__=='__main__':unittest.main()
