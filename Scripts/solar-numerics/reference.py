"""Independent high-precision definitions; values are measurements, never interval bounds."""
import re
import mpmath as mp

from numerics import ROOT, ENGINE, earth_model, unpack

mp.mp.dps = 80


def exact(value):
    numerator, denominator = value.as_integer_ratio()
    return mp.mpf(numerator) / denominator


def year_start(year):
    y = year - 1
    return mp.mpf(365 * y + y // 4 - y // 100 + y // 400) - mp.mpf("730119.5")


def decimal_year(ut):
    year = 2000 + int(mp.floor(ut / mp.mpf("365.2425")))
    while year_start(year) > ut:
        year -= 1
    while year_start(year + 1) <= ut:
        year += 1
    return year + (ut - year_start(year)) / (year_start(year + 1) - year_start(year))


def delta_t(ut, model="espenakMeeus"):
    """NASA/TP-2006-214141 polynomials, 1800 <= year < 2201; native Gregorian interpolation."""
    if model == "jplHorizons":
        ut = min(ut, 17 * mp.mpf("365.24217"))
    elif model != "espenakMeeus":
        raise ValueError("Unknown Delta T model")
    y = decimal_year(ut)
    if not 1800 <= y < 2201:
        raise ValueError("Reference Delta T domain is 1800 through 2200")
    pieces = [
        (1860, 1800, ["13.72", "-0.332447", "0.0068612", "0.0041116", "-0.00037436", "0.0000121272", "-0.0000001699", "0.000000000875"]),
        (1900, 1860, ["7.62", "0.5737", "-0.251754", "0.01680668", "-0.0004473624", mp.mpf(1)/233174]),
        (1920, 1900, ["-2.79", "1.494119", "-0.0598939", "0.0061966", "-0.000197"]),
        (1941, 1920, ["21.20", "0.84493", "-0.076100", "0.0020936"]),
        (1961, 1950, ["29.07", "0.407", -mp.mpf(1)/233, mp.mpf(1)/2547]),
        (1986, 1975, ["45.45", "1.067", -mp.mpf(1)/260, -mp.mpf(1)/718]),
        (2005, 2000, ["63.86", "0.3345", "-0.060374", "0.0017275", "0.000651814", "0.00002373599"]),
        (2050, 2000, ["62.92", "0.32217", "0.005589"]),
    ]
    for stop, origin, coefficients in pieces:
        if y < stop:
            return mp.fsum(mp.mpf(coefficient) * (y - origin)**k for k, coefficient in enumerate(coefficients))
    result = -20 + 32 * ((y - 1820) / 100)**2
    return result - mp.mpf("0.5628") * (2150 - y) if y < 2150 else result


def era(ut):
    """IAU 2000 ERA: one linear angle, reduced only after extended evaluation."""
    return mp.fmod(mp.mpf("0.7790572732640") + mp.mpf("1.00273781191135448") * ut, 1) * 360


def nutation(tt, root=ROOT):
    """IAU 2000B, 77 published terms and fixed planetary offsets, in degrees."""
    t = tt / 36525
    arguments = [("485868.249036", "1717915923.2178"), ("1287104.79305", "129596581.0481"),
                 ("335779.526232", "1739527262.8478"), ("1072260.70369", "1602961601.2090"),
                 ("450160.398036", "-6962890.5431")]
    angles = [(mp.mpf(a) + mp.mpf(b) * t) * mp.pi / 648000 for a, b in arguments]
    text = (root / (ENGINE + "Orientation/Generated/IAU2000BTerms.swift")).read_text()
    terms = [[int(value.strip().replace("_", "")) for value in row.split(",")]
             for row in re.findall(r"Term\(([^)]+)\)", text)]
    if len(terms) != 77 or any(len(row) != 11 for row in terms):
        raise ValueError("IAU 2000B table shape changed")
    longitude, obliquity = [], []
    for row in terms:
        angle = mp.fsum(n * a for n, a in zip(row[:5], angles))
        ps, pst, pc, ec, ect, es = row[5:]
        longitude.append((ps + pst * t) * mp.sin(angle) + pc * mp.cos(angle))
        obliquity.append((ec + ect * t) * mp.cos(angle) + es * mp.sin(angle))
    return [(mp.fsum(longitude) * mp.mpf("1e-7") - mp.mpf("0.000135")) / 3600,
            (mp.fsum(obliquity) * mp.mpf("1e-7") + mp.mpf("0.000388")) / 3600]


def polynomial(coefficients, x):
    """Definition sum(a_k T_k), using cos(k acos(x)), independent of Clenshaw."""
    angle = mp.acos(x)
    return mp.fsum(a * mp.cos(k * angle) for k, a in enumerate(coefficients))


class Earth:
    def __init__(self, root=ROOT):
        self.degree, width, start, stop, values = earth_model(root)
        self.width = mp.mpf(width.numerator) / width.denominator
        self.start = mp.mpf(start.numerator) / start.denominator
        self.stop = mp.mpf(stop.numerator) / stop.denominator
        self.coefficients = values
        text = (root / (ENGINE + "Planets/Generated/VSOP87BTerms.swift")).read_text().split("static let earth = Model(", 1)[1].split("static let mars = Model(", 1)[0]
        counts_text = text.split("termCounts:", 1)[1].split("terms:", 1)[0]
        self.counts = [[int(n.replace("_", "")) for n in re.findall(r"[\d_]+", row)]
                       for row in re.findall(r"\[([^\[\]]+)\]", counts_text)]
        self.terms = unpack(text)
        if len(self.counts) != 3 or 3 * sum(map(sum, self.counts)) != len(self.terms):
            raise ValueError("VSOP87B Earth table shape changed")

    def series(self, tt):
        """Bretagnon-Francou VSOP87B definition, with shipped binary64 coefficients exact."""
        t = tt / 365250
        coordinates, index = [], 0
        for counts in self.counts:
            powers = []
            for alpha, count in enumerate(counts):
                terms = []
                for _ in range(count):
                    a, b, c = map(exact, self.terms[index:index + 3])
                    index += 3
                    terms.append(a * mp.cos(b + c * t))
                powers.append(mp.fsum(terms) * t**alpha)
            coordinates.append(mp.fsum(powers))
        lon, lat, radius = coordinates
        return [radius * mp.cos(lat) * mp.cos(lon), radius * mp.cos(lat) * mp.sin(lon), radius * mp.sin(lat)]

    def position(self, tt):
        if not self.start <= tt < self.stop:
            return self.series(tt)
        segment = int(mp.floor((tt - self.start) / self.width))
        x = 2 * (tt - (self.start + segment * self.width)) / self.width - 1
        n = self.degree + 1
        return [polynomial([exact(v) for v in self.coefficients[(segment * 3 + axis) * n:(segment * 3 + axis + 1) * n]], x)
                for axis in range(3)]
