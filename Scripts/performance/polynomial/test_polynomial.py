"""Analytic checks of the actual candidate evaluator, including fallback edges."""
import ctypes as C
import math
from pathlib import Path
import subprocess
import tempfile
import unittest
from experiment import HERE, ROOT, START, STOP, SUFFIX


class PolynomialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary=tempfile.TemporaryDirectory()
        directory=Path(cls.temporary.name)
        # Two segments; second deliberately unqualified. Three exact quadratics
        # provide an independent analytic position/velocity oracle.
        (directory/'generated').mkdir()
        (directory/'generated/polynomial-data.h').write_text('''
#define POLYNOMIAL_START -1.0
#define POLYNOMIAL_STOP 3.0
typedef struct { int degree; double width; const double *coefficients;
                 const unsigned char *valid; } polynomial_model_t;
static const double c[]={3,2,5, -1,4,0, 2,0,-3, 0,0,0,0,0,0,0,0,0};
static const unsigned char valid[]={1,0};
static const polynomial_model_t polynomial_models[]={
    {2,2,c,valid},{2,2,c,valid},{2,2,c,valid},{2,2,c,valid},
    {2,2,c,valid},{2,2,c,valid},{2,2,c,valid},{2,2,c,valid}};
''')
        source=directory/'test.c'
        source.write_text('#include <stddef.h>\n#pragma STDC FP_CONTRACT OFF\n'+
                          (ROOT/'Sources/CLibAstronomy/polynomial.h').read_text()+
                          '\nint probe(int b,double tt,double *p,double *v) { return PolynomialPosition(b,tt,p,v); }\n')
        path=directory/('test'+SUFFIX)
        subprocess.run(['clang','-O2','-shared','-fPIC',str(source),'-o',str(path)],check=True)
        cls.lib=C.CDLL(str(path))
        cls.lib.probe.argtypes=[C.c_int,C.c_double,C.POINTER(C.c_double),C.POINTER(C.c_double)]
        cls.lib.probe.restype=C.c_int

    @classmethod
    def tearDownClass(cls): cls.temporary.cleanup()

    def test_position_and_analytic_derivative(self):
        for body in range(8):
            for tt in [-1.,-.875,-.5,0.,.5,math.nextafter(1.,0.)]:
                x=tt
                p=(C.c_double*3)(); v=(C.c_double*3)()
                self.assertEqual(self.lib.probe(body,tt,p,v),1)
                expected=[-2+2*x+10*x*x,-1+4*x,5-6*x*x]
                velocity=[2+20*x,4,-12*x]
                for a,b in zip(p,expected): self.assertAlmostEqual(a,b,places=13)
                for a,b in zip(v,velocity): self.assertAlmostEqual(a,b,places=13)
                q=(C.c_double*3)()
                self.assertEqual(self.lib.probe(body,tt,q,None),1)
                self.assertEqual(list(p),list(q))

    def test_invalid_segments_and_times_preserve_outputs(self):
        for tt in [-math.inf,-2.,math.nextafter(-1.,-math.inf),1.,2.,3.,math.inf,math.nan]:
            p=(C.c_double*3)(11,12,13); v=(C.c_double*3)(14,15,16)
            self.assertEqual(self.lib.probe(0,tt,p,v),0)
            self.assertEqual(list(p),[11,12,13]); self.assertEqual(list(v),[14,15,16])

    def test_coverage_is_1900_through_2100_tt(self):
        import datetime as dt
        epoch=dt.datetime(2000,1,1,12)
        self.assertEqual(START,(dt.datetime(1900,1,1)-epoch).total_seconds()/86400)
        self.assertEqual(STOP,(dt.datetime(2101,1,1)-epoch).total_seconds()/86400)


if __name__=='__main__': unittest.main()
