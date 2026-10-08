"""Extended-precision geometric Sun model, composed from published definitions."""
import re
from functools import lru_cache
import reference as ref
from numerics import ROOT, ENGINE

mp = ref.mp


def polynomial(coefficients, t):
    return mp.fsum(mp.mpf(c) * t**i for i, c in enumerate(coefficients))


def r1(angle):
    c, s = mp.cos(angle), mp.sin(angle)
    return mp.matrix([[1, 0, 0], [0, c, s], [0, -s, c]])


def r3(angle):
    c, s = mp.cos(angle), mp.sin(angle)
    return mp.matrix([[c, s, 0], [-s, c, 0], [0, 0, 1]])


def obliquity(tt):
    return polynomial(['84381.406', '-46.836769', '-0.0001831', '0.00200340', '-0.000000576', '-0.0000000434'], tt / 36525) * mp.pi / 648000


def precession(tt):
    t = tt / 36525
    psi = polynomial(['0', '5038.481507', '-1.0790069', '-0.00114045', '0.000132851', '-0.0000000951'], t) * mp.pi / 648000
    omega = polynomial(['84381.406', '-0.025754', '0.0512623', '-0.00772503', '-0.000000467', '0.0000003337'], t) * mp.pi / 648000
    chi = polynomial(['0', '10.556403', '-2.3814292', '-0.00121197', '0.000170663', '-0.0000000560'], t) * mp.pi / 648000
    return r3(chi) * r1(-omega) * r3(-psi) * r1(mp.mpf('84381.406') * mp.pi / 648000)


def complementary(tt):
    t = tt / 36525
    coefficients = [
        ['485868.249036', '1717915923.2178', '31.8792', '0.051635', '-0.00024470'],
        ['1287104.793048', '129596581.0481', '-0.5532', '0.000136', '-0.00001149'],
        ['335779.526232', '1739527262.8478', '-12.7512', '-0.001037', '0.00000417'],
        ['1072260.703692', '1602961601.2090', '-6.3706', '0.006593', '-0.00003169'],
        ['450160.398036', '-6962890.5431', '7.4722', '0.007702', '-0.00005939'],
    ]
    angles = [polynomial(c, t) * mp.pi / 648000 for c in coefficients]
    angles += [mp.mpf('3.176146697') + mp.mpf('1021.3285546211') * t,
               mp.mpf('1.753470314') + mp.mpf('628.3075849991') * t,
               (mp.mpf('0.024381750') + mp.mpf('0.00000538691') * t) * t]
    text = (ROOT / (ENGINE + 'Orientation/Generated/EquinoxComplementaryTerms.swift')).read_text()
    rows = [[mp.mpf(value.strip().replace('_', '')) for value in row.split(',')]
            for row in re.findall(r'ComplementaryTerm\(([^)]+)\)', text)]
    if len(rows) != 34 or any(len(row) != 10 for row in rows):
        raise ValueError('Complementary-series table shape changed')
    terms = []
    for i, row in enumerate(rows):
        argument = mp.fsum(n*a for n,a in zip(row[:8], angles))
        terms.append((row[8] * mp.sin(argument) + row[9] * mp.cos(argument)) * (t if i == 33 else 1))
    return mp.fsum(terms) * mp.pi / 648000


def mean_sidereal(ut, tt):
    t = tt / 36525
    correction = polynomial(['0.014506', '4612.156534', '1.3915817', '-0.00000044', '-0.000029956', '-0.0000000368'], t) / 3600
    return (ref.era(ut) + correction) % 360


def orientation(ut, tt):
    psi, deps = [a * mp.pi / 180 for a in ref.nutation(tt)]
    mean = obliquity(tt)
    nutation = r1(-mean-deps) * r3(-psi) * r1(mean)
    sidereal = (mean_sidereal(ut, tt) + (psi * mp.cos(mean) + complementary(tt)) * 180 / mp.pi) % 360
    return nutation * precession(tt), sidereal


def equatorial_earth(position):
    x, y, z = position
    return [x + mp.mpf('0.000000440360') * y - mp.mpf('0.000000190919') * z,
            -mp.mpf('0.000000479966') * x + mp.mpf('0.917482137087') * y - mp.mpf('0.397776982902') * z,
            mp.mpf('0.397776982902') * y + mp.mpf('0.917482137087') * z]


class Solar:
    def __init__(self):
        self.earth = ref.Earth()

    def geocentric(self, ut, tt, model):
        backdated_ut, backdated_tt = ut, tt
        c = mp.mpf(299792458) * 86400 / 149597870700
        trace = []
        for _ in range(10):
            vector = [-v for v in equatorial_earth(self.earth.position(backdated_tt))]
            next_ut = ut - mp.sqrt(mp.fsum(v*v for v in vector)) / c
            next_tt = next_ut + ref.delta_t(next_ut, model) / 86400
            trace.append({'ut': backdated_ut, 'tt': backdated_tt, 'nextUT': next_ut, 'nextTT': next_tt})
            if abs(next_tt-backdated_tt) < mp.mpf('1e-9'):
                return {'vector': vector, 'trace': trace}
            backdated_ut, backdated_tt = next_ut, next_tt
        raise ValueError('Exact-model light-time iteration did not converge in ten evaluations')

    def altitude(self, ut, tt, model, observer):
        result = self.geocentric(ut, tt, model)
        rotation, sidereal = orientation(ut, tt)
        latitude, longitude, height = map(ref.exact, observer)
        phi = latitude * mp.pi / 180
        theta = (sidereal + longitude) * mp.pi / 180
        polar = 1 - 1 / mp.mpf('298.25642')
        coefficient = 1 / mp.sqrt(mp.cos(phi)**2 + polar**2 * mp.sin(phi)**2)
        radius = mp.mpf('6378.1366')
        au = mp.mpf('149597870.700')
        site = mp.matrix([(radius*coefficient + height/1000) * mp.cos(phi) * mp.cos(theta) / au,
                          (radius*coefficient + height/1000) * mp.cos(phi) * mp.sin(theta) / au,
                          (radius*polar**2*coefficient + height/1000) * mp.sin(phi) / au])
        direction = rotation * mp.matrix(result['vector']) - site
        north = [-mp.sin(phi)*mp.cos(theta), -mp.sin(phi)*mp.sin(theta), mp.cos(phi)]
        west = [mp.sin(theta), -mp.cos(theta), 0]
        zenith = [mp.cos(phi)*mp.cos(theta), mp.cos(phi)*mp.sin(theta), mp.sin(phi)]
        n, w, z = [mp.fsum(a*b for a,b in zip(axis,direction)) for axis in [north, west, zenith]]
        result['altitude'] = mp.atan2(z, mp.sqrt(n*n+w*w)) * 180 / mp.pi
        result['azimuth'] = (-mp.atan2(w,n) * 180 / mp.pi) % 360
        result['siderealDegrees'] = sidereal
        return result


def input_pair(value, scale, model, recorded_ut):
    return _input_pair(value, scale, model, recorded_ut, mp.mp.dps)


@lru_cache(maxsize=1024)
def _input_pair(value, scale, model, recorded_ut, precision):
    """Exact public scalar reference; recorded UT selects an inverse overlap branch."""
    with mp.workdps(precision):
        value = ref.exact(value)
        if scale == 'ut':
            return value, value+ref.delta_t(value,model)/86400
        if scale == 'date':
            civil = value/86400+mp.mpf('365.5')
            text = (ROOT/'Sources/AstronomyKit/UTCOffsetTable.swift').read_text()
            rows = [[mp.mpf(item) for item in row] for row in re.findall(r'Segment\(start: ([^,]+), offset: ([^,]+), rate: ([^)]+)\)',text)]
            applicable = [row for row in rows if row[0] <= civil]
            if not applicable:
                return civil, civil+ref.delta_t(civil,model)/86400
            start,offset,rate = applicable[-1]
            tt = civil+(offset+rate*(civil-start))/86400
        elif scale == 'tt':
            tt = value
        else:
            raise ValueError('Unknown public input reference')
        # Each smooth piece is strictly increasing on this measurement domain.
        # Bisect pieces separately, retaining both roots at negative overlaps.
        lower, upper = tt-mp.mpf('.02'), tt+mp.mpf('.02')
        cuts = [lower, upper]
        for year in [1860,1900,1920,1941,1961,1986,2005,2050,2150]:
            boundary = ref.year_start(year)
            if lower < boundary < upper and not (model == 'jplHorizons' and year > 2017):
                cuts.append(boundary)
        cuts.sort()
        roots = []
        for left,right in zip(cuts,cuts[1:]):
            forward = lambda u: u+ref.delta_t(u,model)/86400
            # Resolve a one-sided model endpoint with guard digits. At the
            # working precision, a tiny UT decrement can round back to the
            # boundary during decimal-year conversion and select its right piece.
            with mp.workdps(precision+30):
                inside_right = right-mp.eps*max(1,abs(right))*10000
                upper_value = forward(inside_right)
            if not forward(left) <= tt <= upper_value:
                continue
            for _ in range(4*precision+20):
                middle = (left+right)/2
                if middle == left or middle == right:
                    break
                if forward(middle) < tt:
                    left = middle
                else:
                    right = middle
            root = (left+right)/2
            if abs(forward(root)-tt) > mp.power(10,-precision+12):
                raise ValueError('Extended-precision inverse did not meet its residual check')
            roots.append(root)
        if not roots:
            return None
        return min(roots,key=lambda root:abs(root-ref.exact(recorded_ut))),tt
