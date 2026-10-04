"""Native candidate coefficient, derivative and malformed-input controls."""
import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'Tools/Migration/NativeLunarProbe/main.swift'

class NativeLunarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SOURCE.exists(): raise AssertionError('native lunar evaluator missing')
        cls.temp=tempfile.TemporaryDirectory();cls.directory=Path(cls.temp.name);cls.binary=cls.directory/'probe'
        subprocess.run(['swiftc','-O',str(SOURCE),'-o',str(cls.binary)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def payload(self, *, count=2, coefficients=None):
        if coefficients is None: coefficients=[1.,2.,3.,5.,0.,0.,0.,-2.,0.]*2
        return struct.pack('<8sQQdddd',b'MOONDEV1',count,3,2451545.,2.,2451545.,2451549.)+struct.pack('<'+'d'*len(coefficients),*coefficients)

    def run_probe(self,data,requests):
        file=self.directory/'coefficients.bin';file.write_bytes(data)
        return subprocess.run([str(self.binary),'states',str(file)],input=''.join(json.dumps(r)+'\n' for r in requests),text=True,capture_output=True)

    def test_polynomial_values_derivatives_and_split_epoch(self):
        requests=[{'tdb1':2451545.,'tdb2':x} for x in (0.,1.,2.,4.)]
        process=self.run_probe(self.payload(),requests);self.assertEqual(process.returncode,0,process.stderr)
        rows=[json.loads(line) for line in process.stdout.splitlines()]
        for row,request,s in zip(rows,requests,(-1.,0.,-1.,1.)):
            self.assertNotIn('error',row)
            self.assertEqual(row['request'],request)
            self.assertAlmostEqual(row['positionKm'][0],1+2*s+3*(2*s*s-1),places=12)
            self.assertAlmostEqual(row['velocityKmPerDay'][0],2+12*s,places=12)
            self.assertEqual(row['positionKm'][1],5.)
            self.assertAlmostEqual(row['positionKm'][2],-2*s,places=12)
            self.assertEqual(row['velocityKmPerDay'][2],-2.)

    def test_split_date_fraction_preserved_far_from_j2000(self):
        base=2451545.;part=-36525.123456789012;start=2415016.5;interval=4*86400
        coefficients=[1e5,2e5,3e5,0.,0.,0.,0.,0.,0.]*2
        data=struct.pack('<8sQQdddd',b'MOONDEV1',2,3,start,4.,2415019.5,2415024.5)+struct.pack('<18d',*coefficients)
        result=self.run_probe(data,[{'tdb1':base,'tdb2':part}]);self.assertEqual(result.returncode,0,result.stderr)
        row=json.loads(result.stdout)
        remainder=(((base-start)*86400)%interval+(part*86400)%interval)%interval
        s=2*remainder/interval-1
        self.assertAlmostEqual(row['positionKm'][0],1e5+2e5*s+3e5*(2*s*s-1),delta=1e-8)

    def test_outside_domain_and_malformed_requests_rejected(self):
        process=self.run_probe(self.payload(),[{'tdb1':2451545.,'tdb2':-1e-6},{'tdb1':2451549.,'tdb2':1e-6},{'tdb1':2451545.},{'tdb1':True,'tdb2':0}])
        self.assertEqual(process.returncode,0,process.stderr)
        rows=[json.loads(line) for line in process.stdout.splitlines()]
        self.assertEqual(len(rows),4)
        self.assertTrue(all('error' in row for row in rows))

    def test_bad_magic_length_overflow_and_nonfinite_coefficients_rejected(self):
        cases=[self.payload()[1:],b'BROKEN!!'+self.payload()[8:],self.payload(count=2**64-1),self.payload(coefficients=[float('nan')]+[0.]*17)]
        for data in cases:
            process=self.run_probe(data,[]);self.assertNotEqual(process.returncode,0)
            self.assertIn('invalid',process.stderr)

    def test_extreme_record_quotient_is_rejected_without_trap(self):
        start=2451545.;count=1000;interval=1e-12
        data=struct.pack('<8sQQdddd',b'MOONDEV1',count,1,start,interval,start,start+count*interval)+struct.pack('<3000d',*([0.]*3000))
        process=self.run_probe(data,[{'tdb1':start+1e7,'tdb2':-1e7}])
        self.assertEqual(process.returncode,0,process.stderr)
        self.assertIn('error',json.loads(process.stdout))

    def test_invalid_cli_rejected(self):
        process=subprocess.run([str(self.binary),'nonsense'],capture_output=True,text=True)
        self.assertEqual(process.returncode,64)

if __name__=='__main__': unittest.main()
