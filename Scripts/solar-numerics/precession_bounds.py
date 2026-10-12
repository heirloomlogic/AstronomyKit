"""Rational Vondrak pole, normalization and angular-rate enclosures.

These bound the specified mathematical model, not physical precession error or
floating-point evaluation error. Harmonic intervals include Taylor remainders;
no sampled maximum is used as an enclosure.
"""
from fractions import Fraction as Q
from functools import lru_cache
import importlib.util
import math
import re

from intervals import Interval as I
from numerics import ROOT, ENGINE

PATHS = [
    'Scripts/solar-numerics/precession_bounds.py',
    'Scripts/generate-long-term-precession.py',
    ENGINE + 'Orientation/EnginePrecession.swift',
    ENGINE + 'Orientation/Generated/Vondrak2011Terms.swift',
    'Scripts/orientation-data/long-term/manifest.json',
    'Scripts/orientation-data/long-term/ltpecl.c',
    'Scripts/orientation-data/long-term/ltpequ.c',
]


def pi_interval():
    def arctan_inverse(n):
        total = sum(Q((-1)**k, (2*k+1)*n**(2*k+1)) for k in range(100))
        return I(total, total + Q(1, 201*n**201))
    return 16*arctan_inverse(5)-4*arctan_inverse(239)


def tables():
    spec = importlib.util.spec_from_file_location('vondrak_coefficients', ROOT / 'Scripts/generate-long-term-precession.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    generated = module.generate()  # Reject changes to the pinned archive.
    if (ROOT / (ENGINE + 'Orientation/Generated/Vondrak2011Terms.swift')).read_text() != generated:
        raise ValueError('Long-term precession coefficients differ from pinned source')
    return {label: [[[Q(x) for x in row] for row in block] for block in module.coefficients(name, prefix)]
            for label, name, prefix in [('equator','ltpequ.c','xy'), ('ecliptic','ltpecl.c','pq')]}


@lru_cache(maxsize=4096)
def trig(angle, cosine=False):
    # Degree 38 (cos) or 39 (sin). Taylor's theorem and |sin|,|cos| <= 1
    # bound the next derivative at every real point in the interval.
    terms = [(2*k if cosine else 2*k+1, (-1)**k) for k in range(20)]
    result = sum((sign * angle**power / math.factorial(power) for power,sign in terms), I(0))
    order = terms[-1][0] + 1
    remainder = angle.abs_upper()**order / math.factorial(order)
    return result + I(-remainder, remainder)


def dot(a, b):
    return sum((x*y for x,y in zip(a,b)), I(0))


def cross(a, b):
    return [a[(i+1)%3]*b[(i+2)%3]-a[(i+2)%3]*b[(i+1)%3] for i in range(3)]


def pole(box, table, pi):
    poly, periodic = table
    coordinates, derivatives = [], []
    t = box.abs_upper()
    for axis in range(2):
        value = sum((c*box**k for k,c in enumerate(poly[axis])), I(0))
        derivative = sum(k*abs(c)*t**(k-1) for k,c in enumerate(poly[axis]) if k)
        for period,cx,cy,sx,sy in periodic:
            c,s = (cx,sx) if axis == 0 else (cy,sy)
            angle = 2*pi*box/period
            value += c*trig(angle, True)+s*trig(angle)
            derivative += 2*pi.hi/period*(abs(c)+abs(s))
        coordinates.append(value*pi/648000)
        derivatives.append(derivative*pi.hi/648000)
    x,y = coordinates
    radicand = 1-x**2-y**2
    if radicand.lo <= 0:
        raise ValueError('Pole square-root radicand is not strictly positive')
    z = radicand.sqrt()
    # For q=(x,y,sqrt(1-x²-y²)), |q′| <= hypot(x′,y′)/z.
    speed = I(sum(d*d for d in derivatives)).sqrt().hi/z.lo
    return [x,y,z], speed, radicand.lo


def enclose(limit=Q('1.02'), width=Q('0.25'), data=None):
    if limit <= 0 or width <= 0:
        raise ValueError('Positive interval dimensions required')
    data = tables() if data is None else data
    pi = pi_interval()
    source = (ROOT/(ENGINE+'Orientation/EnginePrecession.swift')).read_text()
    eps0 = Q(re.search(r'obliquityAtJ2000 = ([0-9_.]+)', source)[1].replace('_',''))
    s, c = trig(eps0*pi/648000), trig(eps0*pi/648000, True)
    matrix_rate, obliquity_rate = Q(0), Q(0)
    minima = [Q(1), Q(1), Q(1)]
    count = 0
    start = -limit
    while start < limit:
        stop = min(start+width, limit)
        box = I(start, stop)
        equ, equ_rate, equ_rad = pole(box, data['equator'], pi)
        local, ecl_rate, ecl_rad = pole(box, data['ecliptic'], pi)
        p,q,w = local
        ecl = [p, -q*c-w*s, -q*s+w*c]
        v = cross(equ,ecl)
        norm2 = sum((value**2 for value in v), I(0))
        if norm2.lo <= 0:
            raise ValueError('Equinox cross product can contain zero')
        norm = norm2.sqrt().lo
        # Unit pole derivatives bound the cross derivative. Projection onto
        # the tangent plane of x=v/|v| cannot increase its norm.
        x_rate = (equ_rate+ecl_rate)/norm
        y_rate = equ_rate+x_rate
        # Frobenius norm bounds the rotation derivative's operator norm.
        matrix_rate = max(matrix_rate, I(x_rate*x_rate+y_rate*y_rate+equ_rate*equ_rate).sqrt().hi)
        # Angular distance between two unit vectors is Lipschitz in their
        # path lengths, wherever their cross product is nonzero.
        obliquity_rate = max(obliquity_rate, equ_rate+ecl_rate)
        minima = [min(a,b) for a,b in zip(minima, [equ_rad,ecl_rad,norm])]
        count += 1
        start = stop
    unit = 180/pi.lo/36525
    return {'precession':matrix_rate*unit, 'meanObliquity':obliquity_rate*unit,
            'equatorRadicandLower':minima[0], 'eclipticRadicandLower':minima[1],
            'crossNormLower':minima[2], 'centuriesLower':-limit, 'centuriesUpper':limit,
            'partitionWidthCenturies':width, 'partitionCount':count}
