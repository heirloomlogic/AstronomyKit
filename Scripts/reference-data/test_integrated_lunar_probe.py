"""Native TT/frame integration and event enumeration controls."""
import importlib.util
import json
import subprocess
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'Tools/Migration/LunarIntegratedProbe/main.swift'
BINARY=ROOT/'.context/accuracy-qualification/integrated-lunar/probe'
PAYLOAD=ROOT/'.context/accuracy-qualification/folded-moon-earth.bin'
SPEC=importlib.util.spec_from_file_location('geometry',Path(__file__).with_name('qualify-geometric-events.py'))
G=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(G)

class IntegratedLunarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SOURCE.exists(): raise AssertionError('native integrated lunar probe missing')
        if not BINARY.exists(): raise AssertionError('build the integrated lunar development executable')

    def request(self,requests):
        output=subprocess.check_output([str(BINARY),'batch',str(PAYLOAD)],input=''.join(json.dumps(r)+'\n' for r in requests),text=True)
        rows=[json.loads(line) for line in output.splitlines()]
        self.assertEqual(len(rows),len(requests));return rows

    def test_native_time_conversion_and_date_plane(self):
        for jd in [2415020.5,2451545.,2456165.901182685,2499391.4999]:
            req={'operation':'state','julianDateTT':jd};row=self.request([req])[0]
            self.assertEqual(row['request'],req);self.assertEqual(row['status'],'success')
            expected=G.erfa.dtdb(2451545.,jd-2451545.,0,0,0,0)
            self.assertAlmostEqual(row['tdbMinusTTSeconds'],expected,delta=1e-12)
            matrix=G.date_plane(jd)
            for a in range(3):
                for b in range(3): self.assertAlmostEqual(row['datePlane'][a][b],float(matrix[a][b]),delta=1e-14)
            self.assertEqual(len(row['positionKm']),3);self.assertEqual(len(row['velocityKmPerTDBDay']),3)

    def test_full_window_enumeration_not_reference_seeded(self):
        for family,kinds in [('apsis',{'pericenter','apocenter'}),('node',{'ascending','descending'})]:
            req={'operation':'events','family':family,'startJulianDateTT':2451545.,'stopJulianDateTT':2451576.}
            row=self.request([req])[0];self.assertEqual(row['request'],req);self.assertEqual(row['status'],'success')
            self.assertGreaterEqual(len(row['events']),2)
            self.assertEqual({e['kind'] for e in row['events']},kinds)
            dates=[e['julianDateTT'] for e in row['events']];self.assertEqual(dates,sorted(dates))
            self.assertTrue(all(2451545.<=jd<2451576. for jd in dates))

    def test_invalid_window_family_type_and_domain_rejected(self):
        requests=[{'operation':'events','family':'unknown','startJulianDateTT':2451545.,'stopJulianDateTT':2451576.},
                  {'operation':'events','family':'node','startJulianDateTT':2451576.,'stopJulianDateTT':2451545.},
                  {'operation':'state','julianDateTT':2499391.5},{'operation':'state','julianDateTT':True},{'operation':'state','julianDateTT':2500000.},
                  {'operation':'events','family':'node','startJulianDateTT':2451545.,'stopJulianDateTT':2491545.}]
        self.assertTrue(all(row['status']=='error' for row in self.request(requests)))

if __name__=='__main__': unittest.main()
