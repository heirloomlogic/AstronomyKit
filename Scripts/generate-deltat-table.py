#!/usr/bin/env python3
"""Generate the observed Delta T table offline from checksummed IERS and HMNAO records.

Sources (URLs and SHA-256 in Scripts/deltat-data/manifest.json):

- IERS EOP 20 C04, daily UT1-UTC at 0h UTC from 1962, with formal errors.
- IERS Rapid Service/Prediction Centre finals2000A.all (Bulletin A): rapid
  UT1-UTC after the last C04 row, then about a year of predictions, each row
  with its stated error.
- USNO TAI-UTC (Scripts/time-data/tai-utc.dat, shared with the civil table).
- Morrison, Stephenson, Hohenkerk and Zawilski (2021), Addendum 2020 to
  Stephenson, Morrison and Hohenkerk (2016): Table S15 v2020 spline
  coefficients for Delta T from -720 to 2019, and the HM Nautical Almanac
  Office page that tabulates the error estimates and states the long-term
  length-of-day model used to extrapolate beyond the spline.
- IERS EOP 20 C04 sampled at 12h UTC (validation only): measures the error of
  linear interpolation between the daily 0h rows.

Delta T = TT - UT1 = (TAI-UTC) + 32.184 s - (UT1-UTC), exact in units of
1e-7 s at every 0h UTC row.
"""
import argparse
from decimal import Decimal
import hashlib
import html
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'Scripts/deltat-data'
TIME_DATA = ROOT / 'Scripts/time-data'
OUTPUT = ROOT / 'Sources/CLibAstronomy/generated/deltat_iers.h'
VERSION_SOURCE = ROOT / 'Sources/AstronomyKit/AstronomyKit.swift'

MJD_J2000 = Decimal('51544.5')
E7 = Decimal('10000000')

# Long-term length-of-day model, HMNAO (2021): lod = +1.72 t - 3.5 sin(2 pi (t + 0.75) / 14) ms,
# t in Julian centuries from 1825.0. The generator verifies the page states this formula.
LOD_RATE = 1.72
LOD_AMPLITUDE = 3.5
LOD_PERIOD = 14.0
LOD_PHASE = 0.75
LOD_EPOCH = 1825.0
LOD_FORMULA = 'lod = +1.72 t − 3.5 sin(2π( t +0.75)/14)'
JOIN_KNOT = 1962.0


def verify_manifest(directory):
    manifest = json.loads((directory/'manifest.json').read_text())
    for name, record in manifest['files'].items():
        if hashlib.sha256((directory/name).read_bytes()).hexdigest() != record['sha256']:
            raise ValueError(f'Checksum mismatch: {directory.name}/{name}')
    return manifest


def mjd_from_date(year, month, day):
    # Fliegel and Van Flandern (1968), Gregorian calendar to Julian Day Number.
    a = (14 - month) // 12
    y = year + 4800 - a
    m = month + 12 * a - 3
    jdn = day + (153 * m + 2) // 5 + 365 * y + y // 4 - y // 100 + y // 400 - 32045
    return jdn - 2400001


def parse_tai_utc():
    segments = []
    for line in (TIME_DATA/'tai-utc.dat').read_text().splitlines():
        match = re.search(
            r'=JD\s+([\d.]+)\s+TAI-UTC=\s+([\d.]+)\s+S\s+\+\s+\(MJD -\s*([\d.]+)\)\s+X\s+([\d.]+)', line
        )
        if not match:
            raise ValueError(f'Invalid USNO time segment: {line}')
        jd, offset, reference, rate = map(Decimal, match.groups())
        segments.append((jd - Decimal('2400000.5'), offset, reference, rate))
    if len(segments) != 41:
        raise ValueError('Expected all 41 pinned USNO segments')
    return segments


def tai_minus_utc(segments, mjd):
    current = [segment for segment in segments if mjd >= segment[0]]
    if not current:
        raise ValueError(f'MJD {mjd} precedes the TAI-UTC table')
    start, offset, reference, rate = current[-1]
    return offset + (mjd - reference) * rate


def exact_e7(value):
    scaled = value * E7
    if scaled != scaled.to_integral_value():
        raise ValueError(f'{value} is not exact in units of 1e-7 s')
    return int(scaled)


def parse_c04(name, hour):
    rows = []
    for line in (DATA/name).read_text().splitlines():
        if line.startswith('#'):
            continue
        fields = line.split()
        if len(fields) != 21:
            raise ValueError(f'Invalid C04 row: {line}')
        year, month, day, hh = map(int, fields[:4])
        mjd = Decimal(fields[4])
        if hh != hour or mjd != Decimal(mjd_from_date(year, month, day)) + Decimal(hour) / 24:
            raise ValueError(f'C04 date and MJD disagree: {line}')
        if rows and mjd != rows[-1][0] + 1:
            raise ValueError(f'C04 rows are not consecutive at MJD {mjd}')
        rows.append((mjd, Decimal(fields[7]), Decimal(fields[15])))
    return rows


def parse_finals(after_mjd):
    rows = []
    blank_seen = False
    for line in (DATA/'finals2000A.all').read_text().splitlines():
        line = line.ljust(80)
        mjd = Decimal(line[7:15].strip())
        flag = line[57]
        if flag == ' ':
            blank_seen = True
            continue
        if blank_seen:
            raise ValueError(f'finals2000A UT1-UTC resumes after a blank at MJD {mjd}')
        if flag not in 'IP':
            raise ValueError(f'Unknown finals2000A UT1-UTC flag {flag!r} at MJD {mjd}')
        if mjd <= after_mjd:
            continue
        if rows and mjd != rows[-1][0] + 1:
            raise ValueError(f'finals2000A rows are not consecutive at MJD {mjd}')
        if rows and rows[-1][3] == 'P' and flag == 'I':
            raise ValueError('finals2000A observed rows follow predictions')
        rows.append((mjd, Decimal(line[58:68]), Decimal(line[68:78]), flag))
    if not rows or rows[0][0] != after_mjd + 1 or rows[0][3] != 'I' or rows[-1][3] != 'P':
        raise ValueError('finals2000A does not continue the C04 series with rapid values then predictions')
    return rows


def parse_spline():
    rows = []
    for line in (DATA/'Table-S15.2020.txt').read_text().splitlines():
        fields = line.split()
        if len(fields) == 7 and fields[0].isdigit():
            if int(fields[0]) != len(rows) + 1:
                raise ValueError(f'Table S15 rows out of order: {line}')
            rows.append([float(value) for value in fields[1:]])
    if len(rows) != 58 or rows[0][0] != -720.0 or rows[-1][1] != 2019.0:
        raise ValueError('Expected 58 Table S15 v2020 rows from -720 to 2019')
    for previous, current in zip(rows, rows[1:]):
        if previous[1] != current[0]:
            raise ValueError('Table S15 knots are not contiguous')
    return rows


def spline_value(row, year):
    k0, k1, a0, a1, a2, a3 = row
    t = (year - k0) / (k1 - k0)
    return a0 + t * (a1 + t * (a2 + t * a3))


def spline_slope(row, year):
    """Delta T rate in seconds per year."""
    k0, k1, a0, a1, a2, a3 = row
    t = (year - k0) / (k1 - k0)
    return (a1 + t * (2 * a2 + t * 3 * a3)) / (k1 - k0)


def page_text():
    text = (DATA/'hmnao-lvm.html').read_text()
    text = re.sub(r'<!--.*?-->', ' ', text, flags=re.S)
    return text


def parse_epsilon_tables():
    """Error estimates from the HMNAO Delta T tables, as (year, seconds) knots."""
    page = page_text()
    plain = html.unescape(re.sub(r'<[^>]+>', ' ', page))
    plain = re.sub(r'\s+', ' ', plain)
    if plain.count(LOD_FORMULA) != 2:
        raise ValueError('HMNAO page no longer states the long-term lod model')
    tables = {
        'a2': (-2000.0, -800.0, 3600.0),
        'b2': (-720.0, 1600.0, 1.0),
        'c2': (1600.0, 1800.0, 1.0),
        'd2': (1800.0, 1950.0, 1.0),
        'e2': (1950.0, 2019.0, 1.0),
        'f2': (2020.0, 2500.0, 1.0),
    }
    knots = {}
    for tab, (first, last, scale) in tables.items():
        start = page.index(f'<div id="tabs-{tab}">')
        body = page.index('class="DTTable"', start)
        end = re.compile(r'</table>', re.I).search(page, body).start()
        header = html.unescape(re.sub(r'<[^>]+>', ' ', page[start:body]))
        uniform = re.search(r'ε = ±([\d.]+)', header)
        cells = [re.sub(r'\s', '', html.unescape(re.sub(r'<[^>]+>', '', cell))).replace('−', '-')
                 for cell in re.findall(r'<TD[^>]*>(.*?)</TD>', page[body:end], flags=re.S | re.I)]
        stride = 2 if uniform else 3
        if len(cells) % stride:
            raise ValueError(f'Unexpected HMNAO table shape in {tab}')
        for index in range(0, len(cells), stride):
            year = float(cells[index])
            epsilon = float(uniform.group(1)) if uniform else float(cells[index + 2].lstrip('±'))
            if not first <= year <= last:
                continue
            epsilon *= scale
            if year in knots and knots[year] != epsilon:
                raise ValueError(f'HMNAO error estimates disagree at {year}')
            knots[year] = epsilon
    ordered = sorted(knots.items())
    # Interior knots equal to both neighbours add nothing to linear interpolation.
    return [knot for index, knot in enumerate(ordered)
            if index in (0, len(ordered) - 1) or not ordered[index - 1][1] == knot[1] == ordered[index + 1][1]]


def lod_integral(year):
    """Delta T in seconds, up to a constant, from integrating the long-term lod model."""
    t = (year - LOD_EPOCH) / 100.0
    phase = 2.0 * math.pi * (t + LOD_PHASE) / LOD_PERIOD
    return 36.525 * (0.5 * LOD_RATE * t * t + LOD_AMPLITUDE * LOD_PERIOD / (2.0 * math.pi) * math.cos(phase))


def decimal_year(ut):
    # Julian epoch: J2000.0 is 2000-01-01 12h, so J1962.0 is 1962-01-01 0h.
    return 2000.0 + ut / 365.25


def c_double(value):
    text = repr(float(value))
    return text if any(c in text for c in '.en') else text + '.0'


def generate():
    verify_manifest(TIME_DATA)
    manifest = verify_manifest(DATA)
    segments = parse_tai_utc()

    c04 = parse_c04('eopc04.1962-now', 0)
    finals = parse_finals(c04[-1][0])
    rows = [(mjd, dut, sigma, 'C') for mjd, dut, sigma in c04] + finals
    first_predicted = next(index for index, row in enumerate(rows) if row[3] == 'P')

    table = []
    for mjd, dut, sigma, _ in rows:
        if abs(dut) >= 1 or sigma <= 0:
            raise ValueError(f'Implausible UT1-UTC row at MJD {mjd}')
        delta_t = tai_minus_utc(segments, mjd) + Decimal('32.184') - dut
        table.append((exact_e7(delta_t), exact_e7(dut), exact_e7(sigma)))

    def abscissa(index):
        return float(rows[index][0] - MJD_J2000) + table[index][1] / 1.0e7 / 86400.0

    # Measure linear interpolation against the independent 12h C04 samples.
    daily = {mjd: dut for mjd, dut, _ in c04}
    interpolation = []
    for mjd, dut, _ in parse_c04('eopc04.12h.1984-now', 12):
        before, after = daily.get(mjd - Decimal('0.5')), daily.get(mjd + Decimal('0.5'))
        if before is None or after is None:
            continue
        # A positive leap second at the end of the day raises the next 0h row by 1 s.
        after -= tai_minus_utc(segments, mjd + Decimal('0.5')) - tai_minus_utc(segments, mjd - Decimal('0.5'))
        interpolation.append(abs(float((before + after) / 2 - dut)))
    interpolation_max = max(interpolation)
    interpolation_rms = math.sqrt(sum(e * e for e in interpolation) / len(interpolation))

    # The spline below the first C04 row, made C0 and C1 at every knot.
    # Table S15 converts a cubic spline to per-segment polynomials rounded to
    # 1 ms, so one-sided values and slopes at a knot disagree by up to that
    # rounding. Each knot takes the mean of its one-sided value and slope, and
    # each segment becomes the cubic Hermite interpolant of its end values and
    # slopes. The last segment ends at the first C04 row with the C04 value
    # and the rate of the first C04 interval, which also absorbs the
    # spline's departure from C04 there (Skyfield adjusts only the linear
    # term, which leaves the rate discontinuous).
    spline = parse_spline()
    first_ut = abscissa(0)
    join_year = decimal_year(first_ut)
    if abs(join_year - JOIN_KNOT) > 1e-6:
        raise ValueError('The first C04 row no longer falls on the 1962.0 spline knot')
    published = [row for row in spline if row[1] <= JOIN_KNOT]
    knot_years = [row[0] for row in published] + [join_year]
    values = [spline_value(published[0], published[0][0])]
    slopes = [spline_slope(published[0], published[0][0])]
    for before, after in zip(published, published[1:]):
        knot = after[0]
        values.append((spline_value(before, knot) + spline_value(after, knot)) / 2)
        slopes.append((spline_slope(before, knot) + spline_slope(after, knot)) / 2)
    join_value = table[0][0] / 1.0e7
    join_rate = (table[1][0] - table[0][0]) / 1.0e7 / (abscissa(1) - abscissa(0)) * 365.25
    spline_step = join_value - spline_value(published[-1], join_year)
    values.append(join_value)
    slopes.append(join_rate)
    historical = []
    for index in range(len(published)):
        k0, k1 = knot_years[index], knot_years[index + 1]
        width = k1 - k0
        p0, p1 = values[index], values[index + 1]
        m0, m1 = slopes[index] * width, slopes[index + 1] * width
        historical.append([k0, k1, p0, m0, 3 * (p1 - p0) - 2 * m0 - m1, 2 * (p0 - p1) + m0 + m1])
    # The reconstruction must stay within the published rounding, except in
    # the last segment, which carries the join to C04.
    reconstruction = []
    for rebuilt, original in zip(historical, published):
        reconstruction.append(max(
            abs(spline_value(rebuilt, rebuilt[0] + f * (rebuilt[1] - rebuilt[0]))
                - spline_value(original, original[0] + f * (original[1] - original[0])))
            for f in (i / 200 for i in range(201))
        ))
    if max(reconstruction[:-1]) > 0.0015:
        raise ValueError(f'Spline reconstruction departs from Table S15 by {max(reconstruction[:-1])} s')
    for rebuilt, after in zip(historical, historical[1:]):
        if abs(spline_value(rebuilt, rebuilt[1]) - after[2]) > 1e-9:
            raise ValueError(f'Spline is discontinuous at {rebuilt[1]}')
    if abs(spline_value(historical[-1], join_year) - join_value) > 1e-9:
        raise ValueError('Spline does not meet the first C04 row')
    published_value_jump = max(abs(spline_value(a, a[1]) - spline_value(b, b[0])) for a, b in zip(published, published[1:]))
    published_slope_jump = max(abs(spline_slope(a, a[1]) - spline_slope(b, b[0])) for a, b in zip(published, published[1:])) / 365.25
    join_rate_step = (join_rate - spline_slope(published[-1], join_year)) / 365.25

    # The spline's misfit to IERS where both exist bounds how much its
    # stated error estimates can be trusted after 1962.
    misfit = 0.0
    for index, (mjd, dut, _) in enumerate(c04):
        year = decimal_year(abscissa(index))
        if year > 2019.0:
            break
        row = next(row for row in spline if row[0] <= year <= row[1])
        misfit = max(misfit, abs(spline_value(row, year) - table[index][0] / 1.0e7))

    knots = parse_epsilon_tables()

    observed_end = rows[first_predicted - 1][0]
    predicted_end = rows[-1][0]
    table_id = 'iers-c04-{}-pred-{}-smh2020'.format(
        mjd_date(c04[-1][0]).replace('-', ''), mjd_date(predicted_end).replace('-', '')
    )
    version = VERSION_SOURCE.read_text()
    if f'deltat-{table_id}' not in version:
        raise ValueError(f'AstronomyConfig.ephemerisVersion must name deltat-{table_id}')

    files = manifest['files']
    lines = [
        '/* Generated by Scripts/generate-deltat-table.py; do not edit. */',
        f'/* Retrieved {manifest["retrieved"]}. Source URLs and SHA-256: Scripts/deltat-data/manifest.json. */',
        '/*',
        f' * Observed: IERS EOP 20 C04 UT1-UTC, MJD {c04[0][0]} ({mjd_date(c04[0][0])}) to MJD {c04[-1][0]} ({mjd_date(c04[-1][0])}).',
        f' * Rapid:    IERS Bulletin A (finals2000A), to MJD {observed_end} ({mjd_date(observed_end)}).',
        f' * Predicted: IERS Bulletin A (finals2000A), to MJD {predicted_end} ({mjd_date(predicted_end)}).',
        ' * Rows are 0h UTC: {Delta T, UT1-UTC, stated error of UT1-UTC}, in units of 1e-7 s.',
        f' * Linear interpolation against the 12h C04 samples, 1984 to {mjd_date(c04[-1][0])}:',
        f' * maximum {interpolation_max * 1e3:.4f} ms, rms {interpolation_rms * 1e3:.4f} ms over {len(interpolation)} samples.',
        f' * Table S15 v2020 departs from C04 by at most {misfit:.4f} s over 1962-2019.',
        f' * Table S15 one-sided knot values differ by up to {published_value_jump * 1e3:.3f} ms and rates by',
        f' * {published_slope_jump:.3e} s/day; the Hermite reconstruction below is C0 and C1 at every knot',
        f' * and stays within {max(reconstruction[:-1]) * 1e3:.3f} ms of the published polynomials before 1959.',
        f' * At the first C04 row the published spline is {spline_step:+.6f} s and {join_rate_step:+.3e} s/day',
        f' * from C04; the 1959-1962 segment absorbs both and departs from Table S15 by up to {reconstruction[-1]:.4f} s.',
        ' */',
        '',
        f'#define DELTAT_IERS_TABLE_ID "{table_id}"',
        f'#define DELTAT_IERS_FIRST_MJD {int(c04[0][0])}',
        f'#define DELTAT_IERS_COUNT {len(table)}',
        f'#define DELTAT_IERS_FIRST_PREDICTED {first_predicted}',
        f'#define DELTAT_IERS_INTERPOLATION_MAX {c_double(interpolation_max)}',
        f'#define DELTAT_HISTORICAL_MISFIT {c_double(misfit)}',
        f'#define DELTAT_SPLINE_COUNT {len(historical)}',
        f'#define DELTAT_EPSILON_COUNT {len(knots)}',
        f'#define DELTAT_LOD_RATE {c_double(LOD_RATE)}',
        f'#define DELTAT_LOD_AMPLITUDE {c_double(LOD_AMPLITUDE)}',
        f'#define DELTAT_LOD_PERIOD {c_double(LOD_PERIOD)}',
        f'#define DELTAT_LOD_PHASE {c_double(LOD_PHASE)}',
        f'#define DELTAT_LOD_EPOCH {c_double(LOD_EPOCH)}',
        '',
        '/* Table S15 v2020 segments {K_i, K_{i+1}, a_0, a_1, a_2, a_3} below the first C04 row, rebuilt as',
        ' * cubic Hermite segments through the mean one-sided value and rate at each knot; the last segment',
        f' * ends at the first C04 row with its value and rate. Source: {files["Table-S15.2020.txt"]["url"]} */',
        'static const double deltat_spline[DELTAT_SPLINE_COUNT][6] =',
        '{',
    ]
    lines += ['    {' + ', '.join(c_double(value) for value in row) + '},' for row in historical]
    lines += [
        '};',
        '',
        '/* HMNAO error estimates {decimal year, seconds}. Source: ' + files['hmnao-lvm.html']['url'] + ' */',
        'static const double deltat_epsilon[DELTAT_EPSILON_COUNT][2] =',
        '{',
    ]
    lines += [f'    {{{c_double(year)}, {c_double(epsilon)}}},' for year, epsilon in knots]
    lines += [
        '};',
        '',
        'static const int32_t deltat_iers_rows[DELTAT_IERS_COUNT][3] =',
        '{',
    ]
    lines += [f'    {{{dt}, {dut}, {sigma}}},' for dt, dut, sigma in table]
    lines += ['};', '']
    report = {
        'table_id': table_id,
        'rows': len(table),
        'interpolation_max_ms': interpolation_max * 1e3,
        'interpolation_rms_ms': interpolation_rms * 1e3,
        'spline_misfit_s': misfit,
        'spline_step_s': spline_step,
        'spline_join_rate_step_s_per_day': join_rate_step,
        'published_knot_value_jump_ms': published_value_jump * 1e3,
        'published_knot_rate_jump_s_per_day': published_slope_jump,
        'reconstruction_max_ms_before_1959': max(reconstruction[:-1]) * 1e3,
        'reconstruction_last_segment_s': reconstruction[-1],
    }
    return '\n'.join(lines), report


def mjd_date(mjd):
    jd = int(mjd) + 2400001
    # Inverse of Fliegel and Van Flandern.
    l = jd + 68569
    n = 4 * l // 146097
    l = l - (146097 * n + 3) // 4
    i = 4000 * (l + 1) // 1461001
    l = l - 1461 * i // 4 + 31
    j = 80 * l // 2447
    day = l - 2447 * j // 80
    l = j // 11
    month = j + 2 - 12 * l
    year = 100 * (n - 49) + i + l
    return f'{year:04d}-{month:02d}-{day:02d}'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    expected, report = generate()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != expected:
            raise SystemExit('Generated Delta T table differs')
    else:
        OUTPUT.write_text(expected)
    print(('Verified' if args.check else 'Generated') + ' Delta T table ' + json.dumps(report))
