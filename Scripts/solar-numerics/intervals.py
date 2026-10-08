"""Outward rational intervals for the finite light-time convergence certificate."""
import ast
from dataclasses import dataclass
from fractions import Fraction as Q
import re

from numerics import ROOT, ENGINE, earth_model, sqrt_interval

SCALE = 10**60


def down(value):
    return Q(value * SCALE // 1, SCALE)


def up(value):
    return -down(-value)


@dataclass(frozen=True)
class Interval:
    lo: Q
    hi: Q

    def __init__(self, lo, hi=None):
        object.__setattr__(self, 'lo', Q(lo))
        object.__setattr__(self, 'hi', Q(lo if hi is None else hi))
        if self.lo > self.hi:
            raise ValueError('Reversed interval')

    @staticmethod
    def hull(values):
        values = list(values)
        return Interval(min(v.lo for v in values), max(v.hi for v in values))

    def __add__(self, other):
        other = as_interval(other)
        return Interval(down(self.lo + other.lo), up(self.hi + other.hi))

    __radd__ = __add__

    def __neg__(self):
        return Interval(-self.hi, -self.lo)

    def __sub__(self, other):
        return self + -as_interval(other)

    def __rsub__(self, other):
        return as_interval(other) + -self

    def __mul__(self, other):
        other = as_interval(other)
        endpoints = [x*y for x in [self.lo, self.hi] for y in [other.lo, other.hi]]
        return Interval(down(min(endpoints)), up(max(endpoints)))

    __rmul__ = __mul__

    def __truediv__(self, other):
        other = as_interval(other)
        if other.lo <= 0 <= other.hi:
            raise ValueError('Division interval contains zero')
        return self * Interval(down(1/other.hi), up(1/other.lo))

    def __pow__(self, n):
        if not isinstance(n, int) or n < 0:
            raise ValueError('Expected a nonnegative integer power')
        if n == 0:
            return Interval(1)
        if n % 2 == 0:
            low = 0 if self.lo <= 0 <= self.hi else min(self.lo**n, self.hi**n)
            return Interval(down(low), up(max(self.lo**n, self.hi**n)))
        return Interval(down(self.lo**n), up(self.hi**n))

    def sqrt(self):
        return Interval(sqrt_interval(self.lo, 60)[0], sqrt_interval(self.hi, 60)[1])

    def abs_upper(self):
        return max(abs(self.lo), abs(self.hi))


def as_interval(value):
    return value if isinstance(value, Interval) else Interval(value)


def year_start(year):
    y = year - 1
    return Q(365*y + y//4 - y//100 + y//400) - Q('730119.5')


def year_at(value):
    year = 2000 + int(value // Q('365.2425'))
    while year_start(year) > value:
        year -= 1
    while year_start(year+1) <= value:
        year += 1
    return year


def expression(text, variables, derivatives=None):
    """Evaluate the checked Swift arithmetic subset, preserving decimal tokens."""
    text = re.sub(r'p\.u(\d+)', r'(u**\1)', text.strip().replace('_', ''))
    tree = ast.parse(text, mode='eval')
    def evaluate(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return Interval(Q(ast.get_source_segment(text, node))), Interval(0)
        if isinstance(node, ast.Name) and node.id in variables:
            return variables[node.id], as_interval((derivatives or {}).get(node.id, 0))
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            value, slope = evaluate(node.operand)
            return -value, -slope
        if isinstance(node, ast.BinOp):
            left, dl = evaluate(node.left)
            if isinstance(node.op, ast.Pow) and isinstance(node.right, ast.Constant):
                n = node.right.value
                return left ** n, n*(left**(n-1))*dl if n else Interval(0)
            right, dr = evaluate(node.right)
            if isinstance(node.op, ast.Add): return left+right, dl+dr
            if isinstance(node.op, ast.Sub): return left-right, dl-dr
            if isinstance(node.op, ast.Mult): return left*right, dl*right+left*dr
            if isinstance(node.op, ast.Div): return left/right, (dl*right-left*dr)/(right**2)
        raise ValueError(f'Unrecognized proof-relevant Swift expression: {ast.dump(node)}')
    result = evaluate(tree.body)
    return result[0] if derivatives is None else result[1]


class DeltaT:
    def __init__(self):
        text = (ROOT / (ENGINE+'Foundation/EngineDeltaT.swift')).read_text()
        self.pieces = []
        for stop, body in re.findall(r'if y < (-?\d+) \{(.*?)\n            \}', text, re.S):
            origin = re.search(r'let u = ([^\n]+)', body)
            result = re.search(r'return (.*)', body, re.S)
            if origin and result:
                self.pieces.append((int(stop), origin[1], ' '.join(result[1].split())))
        if [stop for stop, _, _ in self.pieces] != [-500, 500, 1600, 1700, 1800, 1860, 1900, 1920, 1941, 1961, 1986, 2005, 2050, 2150]:
            raise ValueError('DeltaT piece layout changed')

    def at_year(self, value, piece_year):
        for stop, origin, result in self.pieces:
            if piece_year < stop:
                u = expression(origin, {'y': value})
                return expression(result, {'y': value, 'u': u})
        raise ValueError('DeltaT proof domain ends before 2150')

    def derivative_at_year(self, value, piece_year):
        for stop, origin, result in self.pieces:
            if piece_year < stop:
                u = expression(origin, {'y': value})
                du = expression(origin, {'y': value}, {'y': 1})
                return expression(result, {'y': value, 'u': u}, {'y': 1, 'u': du})
        raise ValueError('DeltaT proof domain ends before 2150')

    def seconds(self, ut, model):
        if model == 'jplHorizons':
            hold = 17*Q('365.24217')
            ut = Interval(min(ut.lo, hold), min(ut.hi, hold))
        elif model != 'espenakMeeus':
            raise ValueError('Unknown DeltaT model')
        first, last = year_at(ut.lo), year_at(ut.hi)
        if first < 1898 or last > 2101:
            raise ValueError('Outside certified DeltaT domain')
        values = []
        for year in range(first, last+1):
            start, stop = year_start(year), year_start(year+1)
            part = Interval(max(ut.lo, start), min(ut.hi, stop))
            decimal = year + (part-start)/(stop-start)
            values.append(self.at_year(decimal, year))
        return Interval.hull(values)

    def forward(self, ut, model):
        return ut + self.seconds(ut, model)/86400


def equatorial_matrix():
    text = (ROOT/(ENGINE+'Planets/EnginePlanetPositions.swift')).read_text()
    block = text.split('static let toEquatorial =', 1)[1].split('\n    )', 1)[0]
    columns = [tuple(Q(value.strip().replace('_', '')) for value in row.split(','))
               for row in re.findall(r'\(([-+0-9_., ]+)\)', block)]
    if len(columns) != 3 or any(len(column) != 3 for column in columns):
        raise ValueError('Fixed EQJ matrix layout changed')
    return [[columns[j][i] for j in range(3)] for i in range(3)]


class Earth:
    def __init__(self):
        self.degree, self.width, self.start, self.stop, values = earth_model(ROOT)
        self.coefficients = [Q(value) for value in values]
        self.matrix = equatorial_matrix()

    def position(self, tt):
        if tt.lo < self.start or tt.hi >= self.stop:
            raise ValueError('Outside polynomial proof domain')
        first = int((tt.lo-self.start)//self.width)
        last = int((tt.hi-self.start)//self.width)
        positions = []
        for segment in range(first, last+1):
            start = self.start + segment*self.width
            part = Interval(max(tt.lo, start), min(tt.hi, start+self.width))
            x = 2*(part-start)/self.width-1
            n = self.degree+1
            axes = []
            for axis in range(3):
                coefficients = self.coefficients[(segment*3+axis)*n:(segment*3+axis+1)*n]
                previous, current, total = Interval(1), x, Interval(coefficients[0])
                for coefficient in coefficients[1:]:
                    total = total + coefficient*current
                    previous, current = current, 2*x*current-previous
                axes.append(total)
            positions.append([sum((coefficient*axis for coefficient, axis in zip(row, axes)), Interval(0)) for row in self.matrix])
        return [Interval.hull(position[axis] for position in positions) for axis in range(3)]

    def radius(self, tt):
        return sum((value**2 for value in self.position(tt)), Interval(0)).sqrt()
