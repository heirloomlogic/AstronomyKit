#!/usr/bin/env python3
"""Source-bound rational derivation of the partial native solar-altitude budget."""
from fractions import Fraction as Q
import argparse
import ast
import json
import re

from intervals import Interval as I, DeltaT, equatorial_matrix, expression, year_start
from certify_light_time import constants as convergence_constants, C
from numerics import ROOT, ENGINE, record, earth_model, sqrt_interval, upward, downward, BINDINGS, source_hashes, check_hashes


def pi_interval():
    def arctan_inverse(n):
        total = Q(0)
        for k in range(100):
            total += Q((-1)**k, (2*k+1)*n**(2*k+1))
        remainder = Q(1, 201*n**201)
        return I(total, total+remainder)
    return 16*arctan_inverse(5)-4*arctan_inverse(239)


def coefficients(text):
    return [Q(value.strip().replace('_', '')) for value in text.split(',')]


def rate(poly, t):
    return sum(k*abs(value)*t**(k-1) for k,value in enumerate(poly) if k)


def frame_rates():
    pi = pi_interval().hi
    t = Q('1.02')
    text = (ROOT/(ENGINE+'Orientation/EnginePrecession.swift')).read_text()
    obliquity0 = re.search(r'obliquityAtJ2000 = ([0-9_.]+)', text)[1]
    polys = [coefficients(row.replace('obliquityAtJ2000', obliquity0)) for row in re.findall(r'coefficients: \[([^\]]+)\]', text) if row != 'Double']
    if len(polys) != 4:
        raise ValueError('Precession polynomial layout changed')
    obliquity = rate(polys[0], t)/3600/36525
    precession = sum(rate(poly,t) for poly in polys[1:])/3600/36525
    text = (ROOT/(ENGINE+'Orientation/EngineNutation.swift')).read_text()
    arguments = text.split('delaunayArguments:',1)[1].split('    ]',1)[0]
    frequencies = [coefficients(row)[1]*pi/648000 for row in re.findall(r'\(([-+0-9_., ]+)\)', arguments)]
    table = (ROOT/(ENGINE+'Orientation/Generated/IAU2000BTerms.swift')).read_text()
    terms = [coefficients(row) for row in re.findall(r'Term\(([^)]+)\)', table)]
    if len(frequencies) != 5 or len(terms) != 77:
        raise ValueError('Nutation data layout changed')
    longitude, oblique, amplitude = Q(0), Q(0), Q('.000135')/3600
    for row in terms:
        argument_rate = sum(abs(n*w) for n,w in zip(row[:5],frequencies))
        ps,pst,pc,ec,ect,es = row[5:]
        p = abs(ps)+abs(pst)*t+abs(pc)
        e = abs(ec)+abs(ect)*t+abs(es)
        longitude += (p*argument_rate+abs(pst))*Q('1e-7')/3600/36525
        oblique += (e*argument_rate+abs(ect))*Q('1e-7')/3600/36525
        amplitude += p*Q('1e-7')/3600
    text = (ROOT/(ENGINE+'Orientation/EngineEquationOfEquinoxes.swift')).read_text()
    argument_polys = [coefficients(row) for row in re.findall(r'= turn\(([^)]+)\)',text)]
    argument_rates = [rate(poly,t)*pi/648000 for poly in argument_polys]
    for name in ['ve','e']:
        match = re.search(r'\n            '+name+r' = fmod\([^+]+\+ ([0-9_.]+) \* t,',text)
        argument_rates.append(Q(match[1].replace('_','')))
    match = re.search(r'pa = \(([0-9_.]+) \+ ([0-9_.]+) \* t\) \* t',text)
    p0,p1 = [Q(value.replace('_','')) for value in match.groups()]
    argument_rates.append(p0+2*p1*t)
    table = (ROOT/(ENGINE+'Orientation/Generated/EquinoxComplementaryTerms.swift')).read_text()
    complementary = [coefficients(row) for row in re.findall(r'ComplementaryTerm\(([^)]+)\)',table)]
    if len(argument_rates) != 8 or len(complementary) != 34:
        raise ValueError('Complementary-series data layout changed')
    complement_rate = Q(0)
    for index,row in enumerate(complementary):
        amplitude_c = abs(row[8])+abs(row[9])
        frequency = sum(abs(n*w) for n,w in zip(row[:8],argument_rates))
        complement_rate += amplitude_c*(frequency*(t if index == 33 else 1)+(1 if index == 33 else 0))/3600/36525
    text = (ROOT/(ENGINE+'Orientation/EngineEarthRotation.swift')).read_text()
    polynomial = ' '.join(text.split('let precession =',1)[1].split('let degrees',1)[0].split())
    sidereal = expression(polynomial, {'t':I(-t,t)}, {'t':1}).abs_upper()/3600/36525
    return {'precession':precession, 'meanObliquity':obliquity, 'nutationLongitude':longitude,
            'nutationObliquity':oblique, 'complementary':complement_rate, 'siderealPolynomial':sidereal,
            'precessionNutation':precession+2*obliquity+longitude+oblique,
            'siderealTT':sidereal+longitude+amplitude*obliquity*pi/180+complement_rate}


def classification_guard():
    delta = DeltaT()
    bounds = [1898,1900,1920,1941,1961,1986,2005,2050,2102]
    majorants, derivatives, operation_counts = [], [], []
    for begin,end in zip(bounds,bounds[1:]):
        y = I(begin,end)
        derivatives.append(delta.derivative_at_year(y,begin).abs_upper())
        for stop,origin,result in delta.pieces:
            if begin < stop:
                u = expression(origin, {'y':y})
                text = re.sub(r'p\.u(\d+)',r'(u**\1)',result.replace('_',''))
                tree = ast.parse(text,mode='eval')
                def majorant(node):
                    if isinstance(node,ast.Constant):
                        return abs(Q(ast.get_source_segment(text,node)))
                    if isinstance(node,ast.Name):
                        return {'u':u.abs_upper(),'y':y.abs_upper()}[node.id]
                    if isinstance(node,ast.UnaryOp):
                        return majorant(node.operand)
                    if isinstance(node,ast.BinOp):
                        left,right = majorant(node.left),majorant(node.right)
                        if isinstance(node.op,(ast.Add,ast.Sub)): return left+right
                        if isinstance(node.op,ast.Mult): return left*right
                        if isinstance(node.op,ast.Pow): return left**int(right)
                        if isinstance(node.op,ast.Div) and isinstance(node.right,ast.Constant): return left/right
                    raise ValueError('Unsupported DeltaT majorant expression')
                majorants.append(majorant(tree.body))
                # Expanded powers require at most n multiplications, including
                # the input subtraction. Count every literal and tree operation.
                count = sum(1 for node in ast.walk(tree) if isinstance(node,(ast.Constant,ast.BinOp)))
                count += sum(node.right.value for node in ast.walk(tree) if isinstance(node,ast.BinOp) and isinstance(node.op,ast.Pow))
                count += 10  # origin arithmetic and the shared Powers products
                operation_counts.append(count)
                break
    if max(majorants) >= 5000 or max(derivatives) >= 20 or max(operation_counts) >= 100:
        raise ValueError('Native DeltaT classification guard assumptions changed')
    source = (ROOT/(ENGINE+'Foundation/EngineDeltaT.swift')).read_text()
    if 'min(decimal, (year + 1).nextDown)' not in source:
        raise ValueError('Decimal-year boundary clamp changed')
    expected_powers = ['u2 = u * u', 'u3 = u * u2', 'u4 = u2 * u2', 'u5 = u2 * u3', 'u6 = u3 * u3', 'u7 = u3 * u4']
    if any(line not in source for line in expected_powers):
        raise ValueError('DeltaT Powers multiplication graph changed')
    epsilon = Q(1,2**53)
    gamma100 = 100*epsilon/(1-100*epsilon)
    delta_error = gamma100*5000+20*Q('1e-12')+Q(20,365)*Q('2e-12')
    forward_error = delta_error/86400+epsilon*Q(5000,86400)+epsilon*(37000+Q(5000,86400))
    if delta_error >= Q('1e-10') or forward_error >= Q('5e-12'):
        raise ValueError('Classification guard no longer encloses forward TT')
    return {'guardDays':Q('1e-9'),'derivedForwardErrorDays':forward_error,
            'deltaTErrorSeconds':delta_error,'majorantSeconds':max(majorants),
            'derivativeSecondsPerYear':max(derivatives),'roundingFactors':max(operation_counts)}


def native_radius_guard(radius_upper, matrix, c):
    degree,width,start,stop,values = earth_model()
    if degree != 12 or width != 8:
        raise ValueError('Native polynomial radius guard requires degree12 and eight-day segments')
    source = (ROOT/(ENGINE+'Planets/EnginePlanetPolynomial.swift')).read_text()
    required = ['let x = (tt - start(ofSegment: segment)) / half - 1',
                'let b = 2 * x * b1 - b2 + coefficients[first + k]',
                'position[axis] = x * b1 - b2 + coefficients[first]',
                'if segment > 0, start(ofSegment: segment) > tt { segment -= 1 }']
    if any(line not in source for line in required):
        raise ValueError('Native polynomial normalization or recurrence changed')
    epsilon = Q(1,2**53)
    gamma = lambda n: n*epsilon/(1-n*epsilon)
    tiny = Q(1,2**1074)
    coefficients_upper = [max(abs(Q(value)) for value in values[k::degree+1]) for k in range(degree+1)]
    # A deliberately loose normalization error, using both subtraction operands.
    dx = gamma(3)*(Q(74000,4)+1)
    x_upper = 1+dx
    b1=b2=e1=e2=Q(0)
    for k in range(degree,0,-1):
        magnitude = 2*x_upper*b1+b2+coefficients_upper[k]
        error = 2*x_upper*e1+e2+2*dx*b1+gamma(4)*magnitude+8*tiny
        b1,b2 = magnitude*(1+gamma(4))+8*tiny,b1
        e1,e2 = error,e1
    magnitude = x_upper*b1+b2+coefficients_upper[0]
    error = x_upper*e1+e2+dx*b1+gamma(3)*magnitude+8*tiny
    component_upper = magnitude*(1+gamma(3))+8*tiny
    frame_errors = [sum(abs(coefficient) for coefficient in row)*(error+gamma(8)*component_upper)+8*tiny for row in matrix]
    error_length = sqrt_interval(sum(value*value for value in frame_errors))[1]
    actual_delay_upper = (radius_upper+error_length)*(1+gamma(8))/(c*(1-epsilon))
    if actual_delay_upper >= Q('.006'):
        raise ValueError('Native radius and norm rounding exceed the backdating classification interval')
    return {'positionErrorAU':error_length,'delayUpperDays':actual_delay_upper,'normalizationError':dx}


def derive():
    convergence = convergence_constants()
    light = json.loads((ROOT/'Scripts/solar-numerics/derived-light-convergence.json').read_text())
    check_hashes(ROOT, light['sourceSHA256'])
    guard = classification_guard()
    earth = json.loads((ROOT/'Scripts/solar-numerics/derived-earth.json').read_text())
    terms = {key:Q(value['rational']) for key,value in earth['terms'].items()}
    matrix = equatorial_matrix()
    gram = [[sum(matrix[k][i]*matrix[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    departure = max(sum(abs(value-(1 if i==j else 0)) for j,value in enumerate(row)) for i,row in enumerate(gram))
    norm_hi, norm_lo = Q('1.000001'), 1-departure
    rmin, rmax = terms['radiusMinimumAU']*norm_lo, terms['radiusMaximumAU']*norm_hi
    v, p = terms['speedAUPerTTDay']*norm_hi, terms['joinMaximumAU']*norm_hi
    radius_guard = native_radius_guard(rmax, matrix, C)
    a, m = 1+convergence['deltaTSlopeSecondsPerDay']/86400, 1-convergence['deltaTSlopeSecondsPerDay']/86400
    k = a*v/C
    delta = DeltaT()
    magnitude = max(delta.at_year(I(year,year+1),year).abs_upper() for year in range(1898,2102))
    source = (ROOT/(ENGINE+'Orientation/EngineObserver.swift')).read_text()
    observer_a = Q(re.search(r'equatorialRadiusKilometers = ([0-9_.]+)',source)[1].replace('_',''))
    constants_source = (ROOT/(ENGINE+'Foundation/EngineConstants.swift')).read_text()
    au = Q(re.search(r'kilometersPerAU = ([0-9_.]+)', constants_source)[1].replace('_',''))
    site = (observer_a+10)/au
    # This margin bounds all composed perturbations below; verify it after deriving them.
    rho = rmin-site-Q('.00001')
    deg_per_rad = 180/pi_interval().lo
    rates = frame_rates()
    era_source = (ROOT/(ENGINE+'Orientation/EngineEarthRotation.swift')).read_text().replace('_','')
    era_terms = re.search(r'let turns = ([0-9.]+) \+ ([0-9.]+) \* ut \+ fmod\(ut, 1.0\)', era_source)
    if not era_terms or 'Engine.normalized(360 * fmod(turns, 1.0), period: 360)' not in era_source:
        raise ValueError('ERA arithmetic expression changed')
    era_offset, era_rate = map(Q, era_terms.groups())
    omega = 360*(1+era_rate)
    ut_sensitivity = deg_per_rad*v*a/(1-k)/rho + omega*(1+site/rho)
    tt_sensitivity = rates['precessionNutation']*rmax/rho + rates['siderealTT']*(1+site/rho)
    u = Q(1,2**53)
    gamma = lambda n: n*u/(1-n*u)
    domain = Q(37000)
    forward = gamma(2)*(domain+magnitude/86400)
    tolerance = 4*u*domain
    inverse_residual = tolerance/(1-u)+forward
    inverse_days = inverse_residual/m
    inverse_jump_days = convergence['D']/m
    # Foundation adds its epoch offset, then civilDays subtracts J2000 and divides.
    civil = gamma(3)*(domain+Q(978307200+946728000,86400))
    table = (ROOT/'Sources/AstronomyKit/UTCOffsetTable.swift').read_text()
    segments = [coefficients(','.join(row)) for row in re.findall(r'Segment\(start: ([^,]+), offset: ([^,]+), rate: ([^)]+)\)',table)]
    civil_tt = Q(0)
    for start,offset,slope in segments:
        span = domain+abs(start)
        magnitude_offset = abs(offset)+abs(slope)*span
        error = gamma(8)*(domain+(magnitude_offset+abs(slope)*span)/86400)
        civil_tt = max(civil_tt, civil*(1+abs(slope)/86400)+error)
    delay_rounding = gamma(10)*rmax/C+u*(domain+rmax/C)/(1-u)
    stop = Q(float(1e-9))/(1-u)+Q('1e-9')
    light_days = (stop+forward+a*(delay_rounding+p/C))/(1-k)
    light_au = v*light_days+p
    light_jump_au = v*convergence['D']/(1-k)
    era_angle = gamma(8)*(era_offset+era_rate*domain+1)*360+u*360
    values = {
        'civilCalendarDays':civil,
        'civilToTTDays':civil_tt,
        'civilToTTDegrees':(ut_sensitivity/m+tt_sensitivity)*civil_tt,
        'civilToUTDegrees':(ut_sensitivity+tt_sensitivity*a)*civil,
        'forwardTTDegrees':tt_sensitivity*forward,
        'ttInverseDegrees':ut_sensitivity*inverse_days,
        'lightTimeDegrees':deg_per_rad*light_au/rho,
        'eraDegrees':era_angle*(1+site/rho),
        'joinDegrees':deg_per_rad*p/rho,
        'arrivalJumpInverseDegrees':ut_sensitivity*inverse_jump_days,
        'arrivalJumpForwardDegrees':tt_sensitivity*convergence['D'],
        'lightTimeJumpDegrees':deg_per_rad*light_jump_au/rho,
        'arrivalUncertaintyBaseDays':inverse_days+civil+civil_tt/m,
        'arrivalUncertaintyDays':inverse_days+inverse_jump_days+civil+civil_tt/m,
        'forwardTTDays':forward,
        'classificationGuardDays':guard['guardDays'],
        'classificationInverseGuardDays':guard['guardDays']/m,
        'deltaTJumpDays':convergence['D'],
        'ttImageSlope':a,
        'backdateMaxDays':convergence['T'],
        'utSensitivityDegreesPerDay':ut_sensitivity,
        'ttSensitivityDegreesPerDay':tt_sensitivity,
    }
    max_earth_perturbation = light_au+light_jump_au+v*a/(1-k)*values['arrivalUncertaintyDays']
    if max_earth_perturbation >= Q('.00001') or values['arrivalUncertaintyDays'] >= Q('.00001'):
        raise ValueError('The denominator or classification margin is insufficient')
    if 2*values['arrivalUncertaintyDays']+convergence['T'] >= 1:
        raise ValueError('Time hull can span multiple eight-day polynomial seams')
    paths = sorted(set(BINDINGS + [
        'Scripts/solar-numerics/derive_altitude.py', 'Scripts/solar-numerics/intervals.py',
        'Scripts/solar-numerics/certify_light_time.py', 'Scripts/solar-numerics/derived-earth.json',
        'Scripts/solar-numerics/derived-light-convergence.json',
        'Sources/AstronomyKit/Time.swift', 'Sources/AstronomyKit/Observer.swift',
        'Sources/AstronomyKit/Position.swift', 'Sources/AstronomyKit/SolarAltitudeObservation.swift',
        *[ENGINE+path for path in [
            'Positions/EngineGeocentric.swift', 'Positions/EngineEquatorial.swift',
            'Orientation/EngineObserver.swift', 'Orientation/EngineFrameRotations.swift',
            'Orientation/EnginePrecession.swift', 'Orientation/EngineEquationOfEquinoxes.swift',
            'Orientation/Generated/EquinoxComplementaryTerms.swift', 'Orientation/EngineHorizon.swift',
            'Orientation/EngineRefraction.swift', 'Orientation/EngineRotations.swift']],
    ]))
    return {'kind':'native-partial-altitude-derivation', 'schemaVersion':1, 'sourceSHA256':source_hashes(ROOT,paths),
            'dependency':'Earth and finite convergence artifacts must also pass their full check commands',
            'excludedAltitudeErrors':['polynomial evaluation and fit','frame and sidereal arithmetic','horizon transform and libm','DeltaT polynomial evaluation and decimal-year arithmetic'],
            'terms':{key:record(value) for key,value in values.items()},
            'classificationGuard':{key:str(value) for key,value in guard.items()},
            'nativeRadiusGuard':{key:str(value) for key,value in radius_guard.items()},
            'intermediate': {'deltaTMagnitudeSeconds':str(magnitude), 'topocentricRadiusMarginAU':str(rho),
                             'maxEarthPerturbationAU':str(max_earth_perturbation),
                             'ratesDegreesPerDay':{key:str(value) for key,value in rates.items()}}}


def render(result):
    fixed = {'polynomialStart':-36524.5,'polynomialStop':36889.5,'polynomialSegmentDays':8.0,
             'observerHeightMeters':10000.0,'inverseToleranceFloorDays':1e-12,
             'inverseTolerancePerDay':4.440892098500626e-16,'classificationUTLimit':37000.0}
    lines = ['// Generated by Scripts/solar-numerics/derive_altitude.py; do not edit.',
             '// Partial arithmetic bounds are rounded outward. Classification guards are not altitude terms.',
             'enum SolarAltitudeBounds {']
    for key,value in fixed.items():
        lines.append(f'    static let {key} = {value!r}')
    for key,value in result['terms'].items():
        lines.append(f"    static let {key} = {value['binary64']!r}")
    years = [1900,1920,1941,1961,1986,2005,2050]
    lines.append('    static let modelStepUTs: [Double] = ['+', '.join(repr(float(year_start(year))) for year in years)+']')
    lines += ['    struct Gap {', '        let lower: Double', '        let upper: Double',
              '        let lowerEnclosure: Double', '        let upperEnclosure: Double', '    }',
              '    static let positiveGaps: [Gap] = [']
    delta = DeltaT()
    for year in years:
        left = I(year_start(year))+delta.at_year(I(year),year-1)/86400
        right = I(year_start(year))+delta.at_year(I(year),year)/86400
        if right.lo > left.hi:
            if upward(left.lo) != upward(left.hi) or upward(right.lo) != upward(right.hi):
                raise ValueError('A model-gap endpoint needs a tighter exact enclosure')
            lines += ['        Gap(', f'            lower: {upward(left.hi)!r}, upper: {upward(right.hi)!r}, lowerEnclosure: {downward(left.lo)!r},', f'            upperEnclosure: {upward(right.hi)!r}),']
    lines += ['    ]','}','']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args = parser.parse_args()
    result = derive()
    artifact = ROOT/'Scripts/solar-numerics/derived-altitude.json'
    swift = ROOT/'Sources/AstronomyKit/SolarAltitudeBounds.swift'
    serialized = json.dumps(result,indent=2,sort_keys=True)+'\n'
    rendered = render(result)
    if args.check:
        if artifact.read_text() != serialized or swift.read_text() != rendered:
            raise SystemExit('Native altitude derivation or generated Swift constants are stale')
        print('Native partial altitude derivation and generated constants verified')
    else:
        artifact.write_text(serialized)
        swift.write_text(rendered)
        print(artifact)


if __name__ == '__main__':
    main()
