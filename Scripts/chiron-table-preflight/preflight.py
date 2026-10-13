#!/usr/bin/env python3
"""Capture and replay a source-qualified Chebyshev table for 2060 Chiron."""

import argparse
import datetime as dt
import gzip
import hashlib
import json
import math
import os
import re
import struct
import tempfile
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCES = ROOT / "sources"
RECEIPTS = ROOT / "source-receipts.json"
COEFFICIENTS = ROOT / "coefficients.bin"
REPORT = ROOT / "report.json"
API_URL = "https://ssd.jpl.nasa.gov/api/horizons_file.api"
BASE_REVISION = "3c31e2d56eb4e887554ea185f5f75bdb78b3a674"
START_JD_TDB = 2_415_019.5
END_JD_TDB = 2_506_333.5
RECORD_DAYS = 38.0
RECORD_COUNT = 2_403
DEGREE_COUNT = 16
FIT_RECORDS_PER_BATCH = 240
HOLDOUT_RECORDS_PER_BATCH = 120
FIT_POINTS_PER_RECORD = 38
HOLDOUT_DAY_OFFSETS = (0.0, 5.0, 12.0, 19.0, 26.0, 33.0, 38.0)
HOLDOUT_X = tuple(2 * offset / RECORD_DAYS - 1 for offset in HOLDOUT_DAY_OFFSETS)
AU_KM = 149_597_870.7
POSITION_LIMIT_KM = 1.0
VELOCITY_LIMIT_KM_PER_DAY = 1.0
REPORT_DECIMAL_PLACES = 9
QUERY_KEYS = {
    "COMMAND": "'2060;'",
    "OBJ_DATA": "'YES'",
    "MAKE_EPHEM": "'YES'",
    "TABLE_TYPE": "'VECTORS'",
    "CENTER": "'500@10'",
    "TIME_TYPE": "'TDB'",
    "REF_SYSTEM": "'ICRF'",
    "REF_PLANE": "'FRAME'",
    "VEC_TABLE": "'2'",
    "VEC_CORR": "'NONE'",
    "OUT_UNITS": "'KM-S'",
    "CSV_FORMAT": "'YES'",
    "VEC_LABELS": "'YES'",
    "CAL_FORMAT": "'JD'",
}


class PreflightError(ValueError):
    pass


def digest_bytes(value):
    return hashlib.sha256(value).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def canonical(value):
    if isinstance(value, float):
        result = round(value, REPORT_DECIMAL_PLACES)
        return 0.0 if result == 0 else result
    if isinstance(value, dict):
        return {key: canonical(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [canonical(item) for item in value]
    return value


def require_object(value, fields, label):
    if not isinstance(value, dict) or set(value) != fields:
        raise PreflightError("{} fields differ".format(label))


def contained_path(relative):
    if not isinstance(relative, str) or Path(relative).is_absolute() or ".." in Path(relative).parts or Path(relative).as_posix() != relative:
        raise PreflightError("source path is not canonical: {!r}".format(relative))
    candidate = ROOT / relative
    path = candidate.resolve()
    if os.path.commonpath((str(ROOT), str(path))) != str(ROOT) or candidate.is_symlink() or not path.is_file():
        raise PreflightError("source path is not a contained regular file: {}".format(relative))
    return path


def fit_epochs():
    return [START_JD_TDB + 0.5 + day for day in range(RECORD_COUNT * FIT_POINTS_PER_RECORD)]


def holdout_epochs():
    return sorted({START_JD_TDB + record * RECORD_DAYS + offset for record in range(RECORD_COUNT) for offset in HOLDOUT_DAY_OFFSETS})


def query_text(start, stop, step):
    lines = ["!$$SOF"] + ["{}={}".format(key, value) for key, value in QUERY_KEYS.items()]
    lines.extend(("START_TIME='JD {:.15f}'".format(start), "STOP_TIME='JD {:.15f}'".format(stop), "STEP_SIZE='{}'".format(step)))
    lines.append("!$$EOF")
    return ("\n".join(lines) + "\n").encode()


def multipart(query):
    boundary = "----AstronomyKitChironSourceCapture"
    body = []
    for name, value, filename in (("format", b"json", None), ("input", query, "query.txt")):
        body.append(("--{}\r\n".format(boundary)).encode())
        disposition = 'Content-Disposition: form-data; name="{}"'.format(name)
        if filename:
            disposition += '; filename="{}"'.format(filename)
        body.append((disposition + "\r\n").encode())
        if filename:
            body.append(b"Content-Type: text/plain\r\n")
        body.append(b"\r\n" + value + b"\r\n")
    body.append(("--{}--\r\n".format(boundary)).encode())
    return b"".join(body), "multipart/form-data; boundary={}".format(boundary)


def download(query):
    body, content_type = multipart(query)
    request = urllib.request.Request(API_URL, data=body, headers={"Content-Type": content_type, "User-Agent": "AstronomyKit Chiron source preflight"})
    with urllib.request.urlopen(request, timeout=120) as response:
        result = response.read()
        retrieved = response.headers.get("Date")
    if not retrieved:
        retrieved = dt.datetime.now(dt.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")
    return result, retrieved


def parse_query(data):
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError as error:
        raise PreflightError("query is not ASCII") from error
    lines = text.splitlines()
    if not lines or lines[0] != "!$$SOF" or lines[-1] != "!$$EOF":
        raise PreflightError("query envelope differs")
    values = {}
    for line in lines[1:-1]:
        if "=" not in line:
            raise PreflightError("query setting differs")
        key, value = line.split("=", 1)
        if key in values:
            raise PreflightError("query setting is duplicated")
        values[key] = value
    expected = set(QUERY_KEYS) | {"START_TIME", "STOP_TIME", "STEP_SIZE"}
    if set(values) != expected or any(values[key] != value for key, value in QUERY_KEYS.items()):
        raise PreflightError("query contract differs")
    try:
        start = float(re.fullmatch(r"'JD ([0-9.]+)'", values["START_TIME"]).group(1))
        stop = float(re.fullmatch(r"'JD ([0-9.]+)'", values["STOP_TIME"]).group(1))
        step_match = re.fullmatch(r"'(1 d|12 h|912 h)'", values["STEP_SIZE"])
        if step_match is None:
            raise ValueError
        step = {"1 d": 1.0, "12 h": 0.5, "912 h": 38.0}[step_match.group(1)]
    except (ValueError, AttributeError) as error:
        raise PreflightError("query time range is malformed") from error
    count = round((stop - start) / step)
    epochs = [start + index * step for index in range(count + 1)]
    if count < 0 or abs(epochs[-1] - stop) > 5e-10 or len(epochs) > 10_000 or any(not math.isfinite(value) for value in epochs):
        raise PreflightError("query epochs differ")
    return epochs


def parse_response(data, epochs):
    try:
        payload = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PreflightError("response JSON is malformed") from error
    require_object(payload, {"signature", "result"}, "response")
    signature = payload["signature"]
    require_object(signature, {"source", "version"}, "response signature")
    if signature != {"source": "NASA/JPL Horizons API", "version": "1.0"}:
        raise PreflightError("response API identity differs")
    result = payload["result"]
    if not isinstance(result, str):
        raise PreflightError("response result differs")
    required = (
        "Target body name: 2060 Chiron (1977 UB)           {source: JPL#171}",
        "Center body name: Sun (10)                        {source: DE441}",
        "Output type     : GEOMETRIC cartesian states",
        "Reference frame : ICRF",
        'Barycentric Dynamical Time ("TDB" or T_eph) output was requested.',
        "Output units    : KM-S",
    )
    if any(text not in result for text in required) or result.count("$$SOE") != 1 or result.count("$$EOE") != 1:
        raise PreflightError("response source identity differs")
    body = result.split("$$SOE", 1)[1].split("$$EOE", 1)[0]
    rows = []
    for line in body.splitlines():
        fields = [field.strip() for field in line.split(",")]
        if len(fields) < 8:
            continue
        try:
            values = tuple(float(value) for value in (fields[0], *fields[2:8]))
        except ValueError:
            continue
        if any(not math.isfinite(value) for value in values):
            raise PreflightError("response contains a nonfinite vector")
        rows.append(values)
    if len(rows) != len(epochs):
        raise PreflightError("response vector inventory differs")
    for expected, row in zip(epochs, rows):
        if abs(expected - row[0]) > 5e-10:
            raise PreflightError("response epoch differs")
    return rows


def source_recipes():
    recipes = []
    for index, first_record in enumerate(range(0, RECORD_COUNT, FIT_RECORDS_PER_BATCH)):
        record_count = min(FIT_RECORDS_PER_BATCH, RECORD_COUNT - first_record)
        start = START_JD_TDB + first_record * RECORD_DAYS + 0.5
        stop = start + record_count * RECORD_DAYS - 1
        recipes.append(("fit", index, start, stop, "1 d"))
    for index, first_record in enumerate(range(0, RECORD_COUNT, HOLDOUT_RECORDS_PER_BATCH)):
        record_count = min(HOLDOUT_RECORDS_PER_BATCH, RECORD_COUNT - first_record)
        start = START_JD_TDB + first_record * RECORD_DAYS - 0.5
        stop = START_JD_TDB + (first_record + record_count) * RECORD_DAYS + 0.5
        recipes.append(("holdout", index, start, stop, "12 h"))
    negative_start = START_JD_TDB + 12
    recipes.append(("negative", 0, negative_start, negative_start + (RECORD_COUNT - 1) * RECORD_DAYS, "912 h"))
    return recipes


def same_epochs(left, right):
    return len(left) == len(right) and all(abs(a - b) <= 5e-10 for a, b in zip(left, right))


def source_receipt(kind, index, query_path, response_path, query, response, raw_response, retrieved, vector_count):
    return {
        "kind": kind,
        "index": index,
        "query": {"path": query_path, "sha256": digest_bytes(query), "bytes": len(query)},
        "response": {"path": response_path, "sha256": digest_bytes(response), "bytes": len(response), "uncompressedSHA256": digest_bytes(raw_response), "uncompressedBytes": len(raw_response)},
        "retrievedAtHTTPDate": retrieved,
        "vectorCount": vector_count,
    }


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix="." + path.name + ".")
    try:
        with os.fdopen(handle, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def require_source_inventory(expected_paths):
    try:
        entries = tuple(SOURCES.iterdir())
    except OSError as error:
        raise PreflightError("source directory inventory is unavailable") from error
    actual_paths = set()
    for path in entries:
        if path.is_symlink() or not path.is_file():
            raise PreflightError("source directory contains a non-regular entry")
        actual_paths.add(path.relative_to(ROOT).as_posix())
    if actual_paths != set(expected_paths):
        raise PreflightError("source directory inventory differs")


def capture_sources():
    SOURCES.mkdir(parents=True, exist_ok=True)
    receipts = []
    expected_paths = set()
    for kind, index, start, stop, step in source_recipes():
        query = query_text(start, stop, step)
        epochs = parse_query(query)
        query_relative = "sources/{}-{:03d}.query.txt".format(kind, index)
        response_relative = "sources/{}-{:03d}.response.json.gz".format(kind, index)
        raw_response, retrieved = download(query)
        parse_response(raw_response, epochs)
        response = gzip.compress(raw_response, compresslevel=9, mtime=0)
        write_atomic(ROOT / query_relative, query)
        write_atomic(ROOT / response_relative, response)
        expected_paths.update((query_relative, response_relative))
        receipts.append(source_receipt(kind, index, query_relative, response_relative, query, response, raw_response, retrieved, len(epochs)))
    require_source_inventory(expected_paths)
    receipt = {"schemaVersion": 1, "baseRevision": BASE_REVISION, "api": {"url": API_URL, "method": "multipart POST", "format": "json", "signatureVersion": "1.0"}, "sources": receipts}
    write_atomic(RECEIPTS, encoded(receipt))


def read_sources(receipt_data=None):
    receipt = json.loads(RECEIPTS.read_bytes()) if receipt_data is None else receipt_data
    require_object(receipt, {"schemaVersion", "baseRevision", "api", "sources"}, "receipt")
    if receipt["schemaVersion"] != 1 or receipt["baseRevision"] != BASE_REVISION:
        raise PreflightError("receipt version or base differs")
    require_object(receipt["api"], {"url", "method", "format", "signatureVersion"}, "API receipt")
    if receipt["api"] != {"url": API_URL, "method": "multipart POST", "format": "json", "signatureVersion": "1.0"}:
        raise PreflightError("API receipt differs")
    entries = receipt["sources"]
    if not isinstance(entries, list):
        raise PreflightError("source receipt inventory differs")
    recipes = source_recipes()
    if len(entries) != len(recipes):
        raise PreflightError("source receipt count differs")
    observed_paths = set()
    vectors = {"fit": [], "holdout": [], "negative": []}
    archive = {"queryBytes": 0, "compressedResponseBytes": 0, "uncompressedResponseBytes": 0, "vectors": {"fit": 0, "holdout": 0, "negative": 0}}
    for entry, (kind, index, start, stop, step) in zip(entries, recipes):
        require_object(entry, {"kind", "index", "query", "response", "retrievedAtHTTPDate", "vectorCount"}, "source receipt")
        if entry["kind"] != kind or type(entry["index"]) is not int or entry["index"] != index or type(entry["vectorCount"]) is not int:
            raise PreflightError("source receipt identity differs")
        if not isinstance(entry["retrievedAtHTTPDate"], str) or not entry["retrievedAtHTTPDate"].endswith(" GMT"):
            raise PreflightError("source receipt HTTP date differs")
        require_object(entry["query"], {"path", "sha256", "bytes"}, "query receipt")
        require_object(entry["response"], {"path", "sha256", "bytes", "uncompressedSHA256", "uncompressedBytes"}, "response receipt")
        query_path = contained_path(entry["query"]["path"])
        response_path = contained_path(entry["response"]["path"])
        for field, path in ((entry["query"], query_path), (entry["response"], response_path)):
            if not isinstance(field["sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", field["sha256"]) or type(field["bytes"]) is not int or field["bytes"] != path.stat().st_size or field["sha256"] != digest_bytes(path.read_bytes()):
                raise PreflightError("source file receipt differs")
        compressed = response_path.read_bytes()
        try:
            raw_response = gzip.decompress(compressed)
        except (gzip.BadGzipFile, EOFError) as error:
            raise PreflightError("response compression differs") from error
        response_receipt = entry["response"]
        if not isinstance(response_receipt["uncompressedSHA256"], str) or not re.fullmatch(r"[0-9a-f]{64}", response_receipt["uncompressedSHA256"]) or type(response_receipt["uncompressedBytes"]) is not int or response_receipt["uncompressedBytes"] != len(raw_response) or response_receipt["uncompressedSHA256"] != digest_bytes(raw_response):
            raise PreflightError("uncompressed response receipt differs")
        query = query_path.read_bytes()
        epochs = parse_query(query)
        expected_epochs = parse_query(query_text(start, stop, step))
        if not same_epochs(epochs, expected_epochs) or entry["vectorCount"] != len(epochs):
            raise PreflightError("source query epoch inventory differs")
        vectors[kind].extend(parse_response(raw_response, epochs))
        archive["queryBytes"] += entry["query"]["bytes"]
        archive["compressedResponseBytes"] += entry["response"]["bytes"]
        archive["uncompressedResponseBytes"] += entry["response"]["uncompressedBytes"]
        archive["vectors"][kind] += entry["vectorCount"]
        observed_paths.update((entry["query"]["path"], entry["response"]["path"]))
    require_source_inventory(observed_paths)
    fit = vectors["fit"]
    expected_heldout = {round(value, 9) for value in holdout_epochs()}
    expected_fit = {round(value, 9) for value in fit_epochs()}
    heldout_map = {}
    repeated_fit_map = {}
    overlap_position_maximum = overlap_velocity_maximum = 0.0
    for row in vectors["holdout"]:
        key = round(row[0], 9)
        destination = heldout_map if key in expected_heldout else repeated_fit_map if key in expected_fit else None
        if destination is not None:
            if key in destination:
                existing = destination[key]
                overlap_position_maximum = max(overlap_position_maximum, magnitude(a - b for a, b in zip(row[1:4], existing[1:4])))
                overlap_velocity_maximum = max(overlap_velocity_maximum, magnitude(86_400 * (a - b) for a, b in zip(row[4:7], existing[4:7])))
            else:
                destination[key] = row
    heldout = [heldout_map[key] for key in sorted(heldout_map)]
    if len(fit) != RECORD_COUNT * FIT_POINTS_PER_RECORD or set(heldout_map) != expected_heldout or set(repeated_fit_map) != expected_fit:
        raise PreflightError("vector inventory differs")
    fit_times = {row[0] for row in fit}
    heldout_times = {row[0] for row in heldout}
    if fit_times & heldout_times:
        raise PreflightError("fit and holdout epochs overlap")
    fit_map = {round(row[0], 9): row for row in fit}
    position_maximum = velocity_maximum = 0.0
    for key, row in repeated_fit_map.items():
        original = fit_map[key]
        position_maximum = max(position_maximum, magnitude(a - b for a, b in zip(row[1:4], original[1:4])))
        velocity_maximum = max(velocity_maximum, magnitude(86_400 * (a - b) for a, b in zip(row[4:7], original[4:7])))
    if max(position_maximum, overlap_position_maximum) > POSITION_LIMIT_KM or max(velocity_maximum, overlap_velocity_maximum) > VELOCITY_LIMIT_KM_PER_DAY:
        raise PreflightError("aligned same-epoch source queries disagree")
    negative_position = negative_velocity = 0.0
    for row in vectors["negative"]:
        aligned = heldout_map.get(round(row[0], 9))
        if aligned is None:
            raise PreflightError("negative query control epoch differs")
        negative_position = max(negative_position, magnitude(a - b for a, b in zip(row[1:4], aligned[1:4])))
        negative_velocity = max(negative_velocity, magnitude(86_400 * (a - b) for a, b in zip(row[4:7], aligned[4:7])))
    if len(vectors["negative"]) != RECORD_COUNT or negative_position <= POSITION_LIMIT_KM:
        raise PreflightError("negative query-path control no longer discriminates")
    return fit, heldout, {"alignedQueries": {"fitEpochsRepeated": len(repeated_fit_map), "overlappingRangeEpochs": 3 * (len([recipe for recipe in source_recipes() if recipe[0] == "holdout"]) - 1), "maximumPositionKm": max(position_maximum, overlap_position_maximum), "maximumVelocityKmPerTDBDay": max(velocity_maximum, overlap_velocity_maximum)}, "rejectedOffsetQueryControl": {"epochs": len(vectors["negative"]), "offsetDays": 12, "stepDays": 38, "maximumPositionDifferenceKm": negative_position, "maximumVelocityDifferenceKmPerTDBDay": negative_velocity, "reason": "Horizons' numerically integrated small-body output depends on the discrete query path; this offset 38-day recipe exceeds the 1 km source-reproduction screen and is retained only as a negative control."}}, archive


def fit_coefficients(rows):
    by_epoch = {round(row[0], 9): row for row in rows}
    if len(by_epoch) != len(rows):
        raise PreflightError("fit source contains duplicate epochs")
    x_values = [-1 + 2 * (index + 0.5) / FIT_POINTS_PER_RECORD for index in range(FIT_POINTS_PER_RECORD)]
    design = [chebyshev_terms(x, DEGREE_COUNT) for x in x_values]
    factor = qr_factor(design)
    values = []
    for record in range(RECORD_COUNT):
        nodes = []
        for point in range(FIT_POINTS_PER_RECORD):
            epoch = START_JD_TDB + record * RECORD_DAYS + point + 0.5
            match = by_epoch.get(round(epoch, 9))
            if match is None:
                raise PreflightError("fit source omits a node")
            if abs(match[0] - epoch) > 5e-10:
                raise PreflightError("fit source omits a node")
            nodes.append(match)
        for axis in range(3):
            scaled = [row[axis + 1] / AU_KM for row in nodes]
            for coefficient in qr_solve(factor, scaled):
                coefficient *= AU_KM
                if not math.isfinite(coefficient):
                    raise PreflightError("fit produced a nonfinite coefficient")
                values.append(coefficient)
    return values


def chebyshev_terms(x, count):
    values = [1.0]
    if count > 1:
        values.append(x)
    while len(values) < count:
        values.append(2 * x * values[-1] - values[-2])
    return values


def qr_factor(matrix):
    work = [list(row) for row in matrix]
    transforms = []
    columns = len(work[0])
    for column in range(columns):
        vector = [work[row][column] for row in range(column, len(work))]
        norm = math.sqrt(math.fsum(value * value for value in vector))
        if norm < 1e-14:
            raise PreflightError("fit design is singular")
        vector[0] += math.copysign(norm, vector[0])
        denominator = math.fsum(value * value for value in vector)
        beta = 2 / denominator
        for target in range(column, columns):
            projection = beta * math.fsum(vector[index] * work[column + index][target] for index in range(len(vector)))
            for index, value in enumerate(vector):
                work[column + index][target] -= projection * value
        transforms.append((column, vector, beta))
    upper = [[work[row][column] if column >= row else 0.0 for column in range(columns)] for row in range(columns)]
    return upper, transforms


def qr_solve(factor, right):
    upper, transforms = factor
    transformed = list(right)
    for column, vector, beta in transforms:
        projection = beta * math.fsum(vector[index] * transformed[column + index] for index in range(len(vector)))
        for index, value in enumerate(vector):
            transformed[column + index] -= projection * value
    result = [0.0] * len(upper)
    for row in range(len(upper) - 1, -1, -1):
        result[row] = (transformed[row] - math.fsum(upper[row][column] * result[column] for column in range(row + 1, len(upper)))) / upper[row][row]
    return result


def evaluate(coefficients, record, x):
    position = []
    velocity = []
    for axis in range(3):
        base = (record * 3 + axis) * DEGREE_COUNT
        series = coefficients[base:base + DEGREE_COUNT]
        b1 = b2 = d1 = d2 = 0.0
        for degree in range(DEGREE_COUNT - 1, 0, -1):
            b = 2 * x * b1 - b2 + series[degree]
            derivative = 2 * b1 + 2 * x * d1 - d2
            b2, b1 = b1, b
            d2, d1 = d1, derivative
        position.append(series[0] + x * b1 - b2)
        velocity.append((b1 + x * d1 - d2) * 2 / RECORD_DAYS)
    return position, velocity


def magnitude(values):
    return math.sqrt(math.fsum(value * value for value in values))


def assessment(coefficients, fit, heldout, source_consistency, archive):
    by_epoch = {round(row[0], 9): row for row in heldout}
    if len(by_epoch) != len(heldout):
        raise PreflightError("heldout source contains duplicate epochs")
    position_worst = (-1.0, None)
    velocity_worst = (-1.0, None)
    seam_position_worst = (-1.0, None)
    seam_velocity_worst = (-1.0, None)
    comparisons = 0
    training_position_maximum = training_velocity_maximum = 0.0
    fit_map = {round(row[0], 9): row for row in fit}
    for record in range(RECORD_COUNT):
        for point in range(FIT_POINTS_PER_RECORD):
            epoch = START_JD_TDB + record * RECORD_DAYS + point + 0.5
            x = -1 + 2 * (point + 0.5) / FIT_POINTS_PER_RECORD
            row = fit_map[round(epoch, 9)]
            position, velocity = evaluate(coefficients, record, x)
            training_position_maximum = max(training_position_maximum, magnitude(a - b for a, b in zip(position, row[1:4])))
            training_velocity_maximum = max(training_velocity_maximum, magnitude(a - 86_400 * b for a, b in zip(velocity, row[4:7])))
    for record in range(RECORD_COUNT):
        middle = START_JD_TDB + (record + 0.5) * RECORD_DAYS
        for x in HOLDOUT_X:
            epoch = middle + 0.5 * RECORD_DAYS * x
            row = by_epoch.get(round(epoch, 9))
            if row is None:
                raise PreflightError("heldout source omits an epoch")
            if abs(row[0] - epoch) > 5e-10:
                raise PreflightError("heldout source omits an epoch")
            position, velocity = evaluate(coefficients, record, x)
            position_error = magnitude(a - b for a, b in zip(position, row[1:4]))
            velocity_error = magnitude(a - 86_400 * b for a, b in zip(velocity, row[4:7]))
            detail = {"record": record, "x": x, "julianDateTDB": epoch}
            if position_error > position_worst[0]:
                position_worst = (position_error, detail)
            if velocity_error > velocity_worst[0]:
                velocity_worst = (velocity_error, detail)
            comparisons += 1
        if record:
            epoch = START_JD_TDB + record * RECORD_DAYS
            left_position, left_velocity = evaluate(coefficients, record - 1, 1.0)
            right_position, right_velocity = evaluate(coefficients, record, -1.0)
            position_jump = magnitude(a - b for a, b in zip(left_position, right_position))
            velocity_jump = magnitude(a - b for a, b in zip(left_velocity, right_velocity))
            detail = {"leftRecord": record - 1, "rightRecord": record, "julianDateTDB": epoch}
            if position_jump > seam_position_worst[0]:
                seam_position_worst = (position_jump, detail)
            if velocity_jump > seam_velocity_worst[0]:
                seam_velocity_worst = (velocity_jump, detail)
    if max(position_worst[0], training_position_maximum) > POSITION_LIMIT_KM or max(velocity_worst[0], training_velocity_maximum) > VELOCITY_LIMIT_KM_PER_DAY:
        raise PreflightError("candidate exceeds the source-reproduction screen")
    coefficient_bytes = struct.pack("<{}d".format(len(coefficients)), *coefficients)
    return coefficient_bytes, canonical({
        "schemaVersion": 1,
        "baseRevision": BASE_REVISION,
        "source": {"target": "2060 Chiron (1977 UB)", "targetSolution": "JPL#171", "center": "Sun (10)", "centerSource": "DE441", "state": "geometric ICRF", "clock": "JD TDB", "units": "km and km/s", "archive": archive},
        "coverage": {"startJulianDateTDB": START_JD_TDB, "endJulianDateTDB": END_JD_TDB, "recordDays": RECORD_DAYS, "recordCount": RECORD_COUNT, "everyRecordHeldout": True, "globalEndpointsHeldout": True, "allSeamsHeldout": True},
        "table": {"degreeCount": DEGREE_COUNT, "coefficientCount": len(coefficients), "payloadBytes": len(coefficient_bytes), "payloadSHA256": digest_bytes(coefficient_bytes), "layout": "record, x/y/z axis, ascending Chebyshev degree; uniform record index floor((jdTDB-start)/38), with the inclusive final endpoint handled explicitly by a future runtime integration"},
        "screen": {"positionLimitKm": POSITION_LIMIT_KM, "velocityLimitKmPerTDBDay": VELOCITY_LIMIT_KM_PER_DAY, "trainingFit": {"epochs": len(fit), "maximumPositionKm": training_position_maximum, "maximumVelocityKmPerTDBDay": training_velocity_maximum}, "heldoutXPerRecord": list(HOLDOUT_X), "recordComparisons": comparisons, "sameEpochCrossQueryConsistency": source_consistency, "position": {"maximumKm": position_worst[0], **position_worst[1]}, "analyticVelocity": {"maximumKmPerTDBDay": velocity_worst[0], **velocity_worst[1]}, "seams": {"count": RECORD_COUNT - 1, "maximumPositionJumpKm": seam_position_worst[0], **seam_position_worst[1], "maximumVelocityJumpKmPerTDBDay": seam_velocity_worst[0], **seam_velocity_worst[1]}},
        "limitations": ["The limits are reversible first-link source-reproduction screens, not a public AstronomyKit accuracy policy.", "The passing residuals apply to the exact aligned daily and half-day query recipe. The retained offset 38-day negative query differs by more than 1 km, so this report does not claim the same result for every legitimate Horizons sampling recipe.", "The archived heldouts cover every record, every seam, and both endpoints, but finite samples do not establish a continuous-domain error bound.", "Agreement with JPL Horizons solution 171 does not establish the physical accuracy or future orbit uncertainty of that solution.", "Lookup latency, package/build cost, and public route behavior remain Link 2 work after PR #283 clears review and ownership.", "This foundation does not change the runtime, its supported interval, or its TT-to-TDB and frame conversions."],
    })


def replay():
    fit, heldout, source_consistency, archive = read_sources()
    coefficients = fit_coefficients(fit)
    coefficient_bytes, report = assessment(coefficients, fit, heldout, source_consistency, archive)
    return coefficient_bytes, encoded(report)


def publish():
    coefficient_bytes, report = replay()
    write_atomic(COEFFICIENTS, coefficient_bytes)
    write_atomic(REPORT, report)


def check():
    coefficient_bytes, report = replay()
    if COEFFICIENTS.read_bytes() != coefficient_bytes:
        raise PreflightError("committed coefficient payload differs")
    if REPORT.read_bytes() != report:
        raise PreflightError("committed report differs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--capture", action="store_true", help="replace the pinned Horizons sources and derived artifacts")
    modes.add_argument("--check", action="store_true", help="replay the pinned sources without network access")
    arguments = parser.parse_args()
    if arguments.capture:
        capture_sources()
        publish()
    else:
        check()


if __name__ == "__main__":
    main()
