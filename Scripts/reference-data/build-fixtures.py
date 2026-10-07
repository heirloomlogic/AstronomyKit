#!/usr/bin/env python3
"""Build the independent astronomical reference fixture archive."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "Scripts/reference-data/sources"
OUTPUT_DIR = ROOT / "Tests/AstronomyKitTests/Fixtures/IndependentReferences"
UPSTREAM_REVISION = "865d3da7d8112bbc7911238052c6af4aaf877181"
UPSTREAM_BASE = f"https://raw.githubusercontent.com/cosinekitty/astronomy/{UPSTREAM_REVISION}"

UPSTREAM_SOURCES = {
    "parse-moon-phases.js": ("generate/moonphase/parse_moon_phases.js", "19d0658653ad7a289b8f8c51fced6ad76e056f7c54133a3ae660d3333d16e263"),
    "normalize-eclipses.py": ("generate/eclipse/norm.py", "27aad287e710b6e55c13cb2ccbc6da588bcec718ba9b6fddacb47bd8896c3f6f"),
    "readme-lunar-eclipse.txt": ("generate/eclipse/readme_lunar_eclipse.txt", "9fed27ab68cf32b1d3b28f6910dc0f3645947ce75f350da33b3e419b776df170"),
    "seasons.txt": ("generate/seasons/seasons.txt", "92a0b2a5f8c67510b49f342f6f7a763cb6eee1ef32413344e71ce169a3582383"),
    "moonphases.txt": ("generate/moonphase/moonphases.txt", "959ec955d89b4d9d2366a737ecffad0ace1deafdb7d54947c94a0585b316c064"),
    "moon_nodes.txt": ("generate/moon_nodes/moon_nodes.txt", "c6140f77c8642be53687a4f7be00497c2bae6cc78ac6d9d6c61be73c06a4a1d5"),
    "moon_apsides.txt": ("generate/apsides/moon.txt", "d01d330774ce3f7ae6c912eef86adc982f833cbdf0345f6fa16cc1af7e187e8b"),
    "earth_apsides.txt": ("generate/apsides/earth.txt", "38405b56a8dce7b9a19405e29242bdf4c08e978ae48b5f14123a65b57a874cf1"),
    "riseset.txt": ("generate/riseset/riseset.txt", "92f5c1edf647c3f46d8964cfab06315fbe09cb580bc512d1418d41039424ff48"),
    "local_solar_eclipse.txt": ("generate/eclipse/local_solar_eclipse.txt", "1273c79b53122d6e5efc264b3c64e571e9a47d777103eaffbcdf5fb44c7743f0"),
    "mercury.html": ("generate/eclipse/mercury.html", "e29ff3e1ada11eaee343032f0c5b927ccf9a9b2cacad8e006a2bd6b4fc71ba40"),
    "venus.html": ("generate/eclipse/venus.html", "c06f2f10efc8554328bb51ed1725d13f1ec53a5a82a0c25089dcf1104994ca7f"),
    "solar_1701.html": ("generate/eclipse/se1701.html", "3c5c9d8e7acfdf48c023e4f7feb14272273121c0620b948cb106f90b6ed04a06"),
    "solar_2001.html": ("generate/eclipse/se2001.html", "820b7a9e4a04881ff212ee59603f03fb3ebdcb72e340414494b1fb84271efc9d"),
    "lunar_1701.html": ("generate/eclipse/le1701.html", "15ed1e6e6b1153f6c85e724258aa91e23655fecb08ac7623fd6e2b4b1d8199f7"),
    "lunar_1901.html": ("generate/eclipse/le1901.html", "587cf5bf48e1b9f17b0e2b6d72d42fc81828f62e9a9252d7f661a747b95154ca"),
    "lunar_2001.html": ("generate/eclipse/le2001.html", "cf12604099d2ed7766180139a4e79633ae361dd9030e2bd618f8b3eadaefde72"),
    "astronomy-engine-license.txt": ("LICENSE", "a76df666a7db8a06f599d08e07c3ff74c4b250b50b49c43353af2bd5bb34604e"),
}

HORIZONS_OBSERVER_QUERIES = {
    "moon-observer": ("301", [2415020.5, 2451544.5, 2488069.5]),
    "mars-observer": ("499", [2415020.5, 2451544.5, 2488069.5]),
    "pluto-observer": ("999", [2415020.5, 2451544.5, 2488069.5]),
    "mercury-station": ("199", [2460897.5, 2460898.5, 2460899.5]),
}

HORIZONS_VECTOR_QUERIES = {
    "chiron-vector": ("2060;", "500@10", [2415020.5, 2451544.5, 2488069.5]),
    "io-vector": ("501", "500@599", [2415020.5, 2451544.5, 2488069.5]),
    "europa-vector": ("502", "500@599", [2415020.5, 2451544.5, 2488069.5]),
    "ganymede-vector": ("503", "500@599", [2415020.5, 2451544.5, 2488069.5]),
    "callisto-vector": ("504", "500@599", [2415020.5, 2451544.5, 2488069.5]),
    # The Moon outside the DE440 Moon's span and across the 32-day blends at 1900 and 2131, out to the accepted-range ends.
    "moon-vector": ("301", "500@399", [990546.0, 990910.5, 1173170.5, 1355795.5, 1538420.5, 1721045.5, 1903670.5, 2086295.5, 2268920.5, 2341970.5, 2378495.5, 2396758.5, 2414980.5, 2414996.5, 2415004.5, 2415012.5, 2415019.5, 2415021.5, 2499390.5, 2499392.5, 2499407.5, 2499422.5, 2499430.5, 2524595.5, 2634170.5, 2816795.5, 3182045.5, 3547295.5, 3912180.5, 3912544.0]),
}

JUPITER_MOON_RELATIVE_TOLERANCE = 9e-4
JUPITER_MOON_TOLERANCE_JD_TDB_RANGE = (2_426_545.0, 2_476_545.0)
RISE_SET_ROW_COUNT = 5_909
# Limits from Astronomy Engine's C test harness, generate/ctest.c at UPSTREAM_REVISION (865d3da7): MoonPhase 90 s, LunarEclipseTest 2 min, RiseSet 1.18 min.
LUNAR_PHASE_TOLERANCE_SECONDS = 90.0
LUNAR_ECLIPSE_TOLERANCE_SECONDS = 120.0
RISE_SET_TOLERANCE_SECONDS = 70.8


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "AstronomyKit independent reference fixture generator"})
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.read()
        except OSError as error:
            last_error = error
            if attempt < 2:
                time.sleep(1 << attempt)
    raise RuntimeError(f"download failed after three attempts: {url}: {last_error}")


def quoted(value: str) -> str:
    return f"'{value}'"


def horizons_url(parameters: dict[str, str]) -> str:
    return "https://ssd.jpl.nasa.gov/api/horizons.api?" + urllib.parse.urlencode({"format": "json", **parameters})


def observer_query(command: str, julian_dates: list[float]) -> dict[str, str]:
    return {
        "COMMAND": quoted(command),
        "OBJ_DATA": quoted("NO"),
        "MAKE_EPHEM": quoted("YES"),
        "EPHEM_TYPE": quoted("OBSERVER"),
        "CENTER": quoted("500@399"),
        "TLIST": quoted(",".join(str(value) for value in julian_dates)),
        "QUANTITIES": quoted("1,3,20,31"),
        "REF_SYSTEM": quoted("ICRF"),
        "CAL_FORMAT": quoted("CAL"),
        "TIME_DIGITS": quoted("SECONDS"),
        "ANG_FORMAT": quoted("DEG"),
        "APPARENT": quoted("AIRLESS"),
        "RANGE_UNITS": quoted("AU"),
        "CSV_FORMAT": quoted("YES"),
    }


def vector_query(command: str, center: str, julian_dates: list[float]) -> dict[str, str]:
    return {
        "COMMAND": quoted(command),
        "OBJ_DATA": quoted("NO"),
        "MAKE_EPHEM": quoted("YES"),
        "EPHEM_TYPE": quoted("VECTORS"),
        "CENTER": quoted(center),
        "TLIST": quoted(",".join(str(value) for value in julian_dates)),
        "REF_SYSTEM": quoted("ICRF"),
        "REF_PLANE": quoted("FRAME"),
        "OUT_UNITS": quoted("AU-D"),
        "VEC_TABLE": quoted("2"),
        "VEC_CORR": quoted("NONE"),
        "CSV_FORMAT": quoted("YES"),
    }


def horizons_acquisitions() -> list[tuple[str, dict[str, str]]]:
    acquisitions = [
        (name, observer_query(command, dates))
        for name, (command, dates) in HORIZONS_OBSERVER_QUERIES.items()
    ]
    acquisitions.extend(
        (name, vector_query(command, center, dates))
        for name, (command, center, dates) in HORIZONS_VECTOR_QUERIES.items()
    )
    return acquisitions


def validate_horizons_response(name: str, data: bytes) -> None:
    try:
        envelope = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"invalid Horizons response {name}: {error}") from error
    result = envelope.get("result")
    if not isinstance(result, str) or "$$SOE\n" not in result or "$$EOE" not in result:
        raise RuntimeError(f"Horizons response {name} has no complete result table")


def refresh_sources() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    writes: dict[Path, bytes] = {}
    for local_name, (remote_path, expected_hash) in UPSTREAM_SOURCES.items():
        destination = SOURCE_DIR / local_name
        if destination.exists() and sha256(destination.read_bytes()) == expected_hash:
            continue
        data = download(f"{UPSTREAM_BASE}/{remote_path}")
        actual_hash = sha256(data)
        if actual_hash != expected_hash:
            raise RuntimeError(f"source hash changed for {remote_path}: expected {expected_hash}, got {actual_hash}")
        writes[destination] = data
    horizons_dir = SOURCE_DIR / "horizons"
    horizons_dir.mkdir(parents=True, exist_ok=True)
    for name, parameters in horizons_acquisitions():
        response = download(horizons_url(parameters))
        validate_horizons_response(name, response)
        writes[horizons_dir / f"{name}.json"] = response
        recipe = {**parameters, "_responseSHA256": sha256(response)}
        writes[horizons_dir / f"{name}.query.json"] = encoded(recipe)
    for path, data in writes.items():
        path.write_bytes(data)


def verify_recorded_queries(directory: Path | None = None) -> None:
    """Check each recorded Horizons response in sources/jpl-validation against its recipe's SHA-256.

    Tests read these tables directly; no fixture is built from them.
    """
    directory = directory or SOURCE_DIR / "jpl-validation"
    for response_path in sorted(directory.glob("*.json")):
        if response_path.name.endswith(".query.json"):
            continue
        recipe_path = response_path.with_name(response_path.stem + ".query.json")
        if not recipe_path.exists():
            raise RuntimeError(f"recorded Horizons response without a recipe: {response_path}")
        expected = json.loads(recipe_path.read_text()).get("_responseSHA256")
        if sha256(response_path.read_bytes()) != expected:
            raise RuntimeError(f"recorded Horizons response hash mismatch: {response_path}")


def verify_sources() -> list[dict[str, str]]:
    records = []
    for local_name, (remote_path, expected_hash) in UPSTREAM_SOURCES.items():
        path = SOURCE_DIR / local_name
        if not path.exists():
            raise RuntimeError(f"missing source snapshot: {path}; run with --refresh")
        actual_hash = sha256(path.read_bytes())
        if actual_hash != expected_hash:
            raise RuntimeError(f"source snapshot hash mismatch for {path}: expected {expected_hash}, got {actual_hash}")
        records.append({"path": str(path.relative_to(ROOT)), "sha256": actual_hash, "url": f"{UPSTREAM_BASE}/{remote_path}"})
    for name, parameters in horizons_acquisitions():
        response_path = SOURCE_DIR / "horizons" / f"{name}.json"
        recipe_path = SOURCE_DIR / "horizons" / f"{name}.query.json"
        if not response_path.exists() or not recipe_path.exists():
            raise RuntimeError(f"missing Horizons response/recipe pair: {name}; run with --refresh")
        response = response_path.read_bytes()
        validate_horizons_response(name, response)
        expected_recipe = {**parameters, "_responseSHA256": sha256(response)}
        if json.loads(recipe_path.read_text()) != expected_recipe:
            raise RuntimeError(f"Horizons recipe or response hash mismatch for {name}")
    for path in sorted((SOURCE_DIR / "horizons").glob("*.json")):
        records.append({"path": str(path.relative_to(ROOT)), "sha256": sha256(path.read_bytes()), "url": "generated from the adjacent query recipe"})
    return records


def source_text(name: str) -> str:
    return (SOURCE_DIR / name).read_text()


def selected_lines(name: str, predicate) -> list[str]:
    return [line for line in source_text(name).splitlines() if predicate(line)]


def parse_rise_set() -> list[dict[str, object]]:
    pattern = re.compile(
        r"^(Sun|Moon)\s+([+-]?\d+(?:\.\d+)?)\s+([+-]?\d+(?:\.\d+)?)\s+"
        r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z)\s+([rs])$"
    )
    rows: list[dict[str, object]] = []
    seen_groups: set[tuple[str, float, float, int]] = set()
    current_group: tuple[str, float, float, int] | None = None
    previous_time: datetime.datetime | None = None
    previous_direction: str | None = None
    for line_number, line in enumerate(source_text("riseset.txt").splitlines(), 1):
        match = pattern.fullmatch(line)
        if match is None:
            raise RuntimeError(f"invalid rise/set record at line {line_number}: {line!r}")
        body, longitude_text, latitude_text, timestamp, direction = match.groups()
        try:
            event_time = datetime.datetime.strptime(timestamp, "%Y-%m-%dT%H:%MZ")
        except ValueError as error:
            raise RuntimeError(f"invalid rise/set timestamp at line {line_number}: {timestamp}") from error
        longitude = float(longitude_text)
        latitude = float(latitude_text)
        if not -180 <= longitude <= 180 or not -90 <= latitude <= 90:
            raise RuntimeError(f"invalid rise/set coordinates at line {line_number}")
        group = (body, longitude, latitude, event_time.year)
        if group != current_group:
            if group in seen_groups:
                raise RuntimeError(f"noncontiguous rise/set group at line {line_number}")
            seen_groups.add(group)
            current_group = group
            previous_time = None
            previous_direction = None
        if previous_time is not None and event_time <= previous_time:
            raise RuntimeError(f"rise/set group is not chronological at line {line_number}")
        if previous_direction == direction:
            raise RuntimeError(f"rise/set directions do not alternate at line {line_number}")
        rows.append(
            {
                "sourceLine": line_number,
                "body": body.lower(),
                "longitudeDegrees": longitude,
                "latitudeDegrees": latitude,
                "utc": timestamp,
                "direction": "rise" if direction == "r" else "set",
                "timeToleranceSeconds": RISE_SET_TOLERANCE_SECONDS,
            }
        )
        previous_time = event_time
        previous_direction = direction
    if len(rows) != RISE_SET_ROW_COUNT:
        raise RuntimeError(
            f"rise/set table has {len(rows)} records; expected {RISE_SET_ROW_COUNT}"
        )
    return rows


def parse_upstream_events() -> dict[str, list[dict[str, object]]]:
    seasons = []
    for line in selected_lines("seasons.txt", lambda item: item[:4] in {"1800", "2000", "2100"} and ("Equinox" in item or "Solstice" in item)):
        timestamp, kind = line.split()
        month = int(timestamp[5:7])
        event = {3: "marchEquinox", 6: "juneSolstice", 9: "septemberEquinox", 12: "decemberSolstice"}[month]
        seasons.append({"event": event, "utc": timestamp, "toleranceSeconds": 142.2})

    phases = []
    phase_names = {0: "new", 1: "firstQuarter", 2: "full", 3: "lastQuarter"}
    by_year_and_quarter: dict[tuple[int, int], dict[str, object]] = {}
    for line in source_text("moonphases.txt").splitlines():
        quarter_text, timestamp = line.split()
        year, quarter = int(timestamp[:4]), int(quarter_text)
        if year in {1800, 2000, 2100}:
            by_year_and_quarter.setdefault((year, quarter), {"phase": phase_names[quarter], "sourceTime": timestamp, "toleranceSeconds": LUNAR_PHASE_TOLERANCE_SECONDS})
    phases.extend(by_year_and_quarter[key] for key in sorted(by_year_and_quarter))

    nodes = []
    node_pattern = re.compile(r"^([AD]) (\S+)\s+([\d.]+)\s+([\-\d.]+)$")
    node_seen: set[tuple[int, str]] = set()
    for line in source_text("moon_nodes.txt").splitlines():
        match = node_pattern.match(line)
        if not match:
            continue
        year, kind = int(match.group(2)[:4]), match.group(1)
        key = (year, kind)
        if year in {2001, 2050, 2100} and key not in node_seen:
            node_seen.add(key)
            nodes.append({"kind": "ascending" if kind == "A" else "descending", "utc": match.group(2), "rightAscensionHours": float(match.group(3)), "declinationDegrees": float(match.group(4)), "timeToleranceSeconds": 220.86, "positionToleranceArcminutes": 1.54})

    def parse_apsides(name: str, years: set[int], moon: bool) -> list[dict[str, object]]:
        result = []
        seen: set[tuple[int, int]] = set()
        for line in source_text(name).splitlines():
            kind_text, timestamp, distance_text = line.split()
            year, kind = int(timestamp[:4]), int(kind_text)
            key = (year, kind)
            if year in years and key not in seen:
                seen.add(key)
                item: dict[str, object] = {"kind": "pericenter" if kind == 0 else "apocenter", "utc": timestamp, "timeToleranceSeconds": 2100.0 if moon else 7234.8}
                item["distanceKM" if moon else "distanceAU"] = float(distance_text)
                item["distanceToleranceKM" if moon else "distanceToleranceAU"] = 25.0 if moon else 1.2e-5
                result.append(item)
        return result

    return {
        "seasons": seasons,
        "lunarPhases": phases,
        "lunarNodes": nodes,
        "lunarApsides": parse_apsides("moon_apsides.txt", {2001, 2050, 2100}, True),
        "earthApsides": parse_apsides("earth_apsides.txt", {2001, 2050, 2100}, False),
        "riseSet": parse_rise_set(),
    }


def parse_eclipses() -> dict[str, list[dict[str, object]]]:
    month = {name: index + 1 for index, name in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())}
    lunar_pattern = re.compile(r"^\s{2}(\d{4})\s+(\w{3})\s+(\d{2})\s+(\d{2}):(\d{2})\s+\S+\s+\d+\s+\S+\s+\S+\s+\S+\s+(\d+m|-)\s+(\d+m|-)")
    lunar = []
    for name in ("lunar_1701.html", "lunar_1901.html", "lunar_2001.html"):
        for line in source_text(name).splitlines():
            match = lunar_pattern.match(line)
            if not match or int(match.group(1)) not in {1800, 2000, 2099}:
                continue
            partial = 0 if match.group(6) == "-" else int(match.group(6)[:-1])
            total = 0 if match.group(7) == "-" else int(match.group(7)[:-1])
            if not lunar or int(match.group(1)) != int(lunar[-1]["universalTime"][:4]):
                lunar.append({"universalTime": f"{match.group(1)}-{month[match.group(2)]:02d}-{int(match.group(3)):02d}T{int(match.group(4)):02d}:{int(match.group(5)):02d}Z", "partialSemiDurationMinutes": partial, "totalSemiDurationMinutes": total, "toleranceSeconds": LUNAR_ECLIPSE_TOLERANCE_SECONDS, "durationToleranceMinutes": LUNAR_ECLIPSE_TOLERANCE_SECONDS / 60})

    solar_pattern = re.compile(r'^<a\s+href="[^"]+">\d+</a>\s+(\d{4})\s+(\w{3})\s+(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\s+-?\d+\s+\S+\s+<a\s+href="[^"]+">\d+</a>\s+([PATH])\S?\s+\S+\s+\S+\s+(\d+\.\d[NS])\s+(\d+\.\d[EW])')
    solar = []
    kind_names = {"P": "partial", "A": "annular", "T": "total", "H": "total"}
    for name in ("solar_1701.html", "solar_2001.html"):
        for line in source_text(name).splitlines():
            match = solar_pattern.match(line)
            if not match or int(match.group(1)) not in {1800, 2024, 2099}:
                continue
            year = int(match.group(1))
            if any(item["terrestrialTime"].startswith(str(year)) for item in solar):
                continue
            latitude = float(match.group(8)[:-1]) * (1 if match.group(8)[-1] == "N" else -1)
            longitude = float(match.group(9)[:-1]) * (1 if match.group(9)[-1] == "E" else -1)
            solar.append({"terrestrialTime": f"{year:04d}-{month[match.group(2)]:02d}-{int(match.group(3)):02d}T{int(match.group(4)):02d}:{int(match.group(5)):02d}:{int(match.group(6)):02d}Z", "kind": kind_names[match.group(7)], "latitudeDegrees": latitude, "longitudeDegrees": longitude, "timeToleranceSeconds": 453.6, "locationToleranceDegrees": 0.247})

    transit_pattern = re.compile(r"^\s*(\d+)\s+(\w{3})\s+(\d+)\s+(\d+):(\d+)\s+\S+\s+(\d+):(\d+)\s+\S+\s+(\d+):(\d+)\s+([\d.]+)")
    transits = []
    wanted = {("mercury", 2003), ("mercury", 2019), ("mercury", 2049), ("venus", 2012), ("venus", 2117), ("venus", 2125)}
    for body in ("mercury", "venus"):
        for line in source_text(f"{body}.html").splitlines():
            match = transit_pattern.match(line)
            if not match:
                continue
            year = int(match.group(1))
            if (body, year) not in wanted:
                continue
            day, month_value = int(match.group(3)), month[match.group(2)]
            start_hour, start_minute = int(match.group(4)), int(match.group(5))
            peak_hour, peak_minute = int(match.group(6)), int(match.group(7))
            finish_hour, finish_minute = int(match.group(8)), int(match.group(9))
            start_day = day - 1 if (start_hour, start_minute) > (peak_hour, peak_minute) else day
            finish_day = day + 1 if (finish_hour, finish_minute) < (peak_hour, peak_minute) else day
            transits.append({"body": body, "startUTC": f"{year:04d}-{month_value:02d}-{start_day:02d}T{start_hour:02d}:{start_minute:02d}Z", "peakUTC": f"{year:04d}-{month_value:02d}-{day:02d}T{peak_hour:02d}:{peak_minute:02d}Z", "finishUTC": f"{year:04d}-{month_value:02d}-{finish_day:02d}T{finish_hour:02d}:{finish_minute:02d}Z", "separationArcminutes": float(match.group(10)) / 60.0, "timeToleranceSeconds": 642.6 if body == "mercury" else 546.54, "separationToleranceArcminutes": 0.2121 if body == "mercury" else 0.6772})

    local_solar = []
    wanted_observers = {(29.0181, -80.9481), (41.0341, -83.6523), (-48.2051, -70.6549)}
    local_pattern = re.compile(r"^\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+([PAT])\s+(\S+)\s+(-?\d+(?:\.\d+)?)\s+(\S+)\s+(-?\d+(?:\.\d+)?)\s+(\S+)\s+(-?\d+(?:\.\d+)?)\s+(\S+)\s+(-?\d+(?:\.\d+)?)\s+(\S+)\s+(-?\d+(?:\.\d+)?)$")
    local_kind_names = {"P": "partial", "A": "annular", "T": "total"}
    for line in source_text("local_solar_eclipse.txt").splitlines():
        match = local_pattern.match(line)
        if not match:
            continue
        latitude = float(match.group(1))
        longitude = float(match.group(2))
        if (latitude, longitude) not in wanted_observers:
            continue
        item: dict[str, object] = {
            "latitudeDegrees": latitude,
            "longitudeDegrees": longitude,
            "kind": local_kind_names[match.group(3)],
            "partialBeginUTC": match.group(4),
            "partialBeginAltitudeDegrees": float(match.group(5)),
            "peakUTC": match.group(8),
            "peakAltitudeDegrees": float(match.group(9)),
            "partialEndUTC": match.group(12),
            "partialEndAltitudeDegrees": float(match.group(13)),
            "timeToleranceSeconds": 60.0,
            "altitudeToleranceDegrees": 0.5,
        }
        if match.group(6) != "-":
            item["totalBeginUTC"] = match.group(6)
            item["totalBeginAltitudeDegrees"] = float(match.group(7))
            item["totalEndUTC"] = match.group(10)
            item["totalEndAltitudeDegrees"] = float(match.group(11))
        local_solar.append(item)

    return {"lunarEclipses": lunar, "globalSolarEclipses": solar, "localSolarEclipses": local_solar, "transits": transits}


def horizons_result(name: str) -> str:
    envelope = json.loads((SOURCE_DIR / "horizons" / f"{name}.json").read_text())
    if "result" not in envelope:
        raise RuntimeError(f"Horizons response {name} has no result")
    return envelope["result"]


def data_lines(result: str) -> list[str]:
    return result.split("$$SOE\n", 1)[1].split("$$EOE", 1)[0].strip().splitlines()


def jupiter_moon_relative_tolerance(julian_date_tdb: float) -> float | None:
    start, end = JUPITER_MOON_TOLERANCE_JD_TDB_RANGE
    if start <= julian_date_tdb <= end:
        return JUPITER_MOON_RELATIVE_TOLERANCE
    return None


def parse_horizons() -> dict[str, list[dict[str, object]]]:
    observations = []
    body_names = {"moon-observer": "moon", "mars-observer": "mars", "pluto-observer": "pluto", "mercury-station": "mercury"}
    for name, body in body_names.items():
        for line in data_lines(horizons_result(name)):
            columns = [column.strip() for column in line.split(",")]
            observations.append({"series": name, "body": body, "utc": columns[0].replace("A.D. ", ""), "rightAscensionDegrees": float(columns[3]), "declinationDegrees": float(columns[4]), "rightAscensionRateArcsecondsPerHour": float(columns[5]), "declinationRateArcsecondsPerHour": float(columns[6]), "apparentRangeAU": float(columns[7]), "rangeRateKmPerSecond": float(columns[8]), "eclipticLongitudeDegrees": float(columns[9]), "eclipticLatitudeDegrees": float(columns[10]), "angularToleranceArcminutes": 1.5 if body in {"pluto"} else 1.0})

    vectors = []
    vector_names = {"chiron-vector": ("chiron", "sun"), "io-vector": ("io", "jupiter"), "europa-vector": ("europa", "jupiter"), "ganymede-vector": ("ganymede", "jupiter"), "callisto-vector": ("callisto", "jupiter"), "moon-vector": ("moon", "earth")}
    for name, (body, origin) in vector_names.items():
        for line in data_lines(horizons_result(name)):
            columns = [column.strip() for column in line.split(",")]
            julian_date_tdb = float(columns[0])
            vectors.append({"body": body, "origin": origin, "julianDateTDB": julian_date_tdb, "tdb": columns[1].replace("A.D. ", ""), "positionAU": [float(columns[2]), float(columns[3]), float(columns[4])], "velocityAUPerDay": [float(columns[5]), float(columns[6]), float(columns[7])], "relativeTolerance": jupiter_moon_relative_tolerance(julian_date_tdb) if origin == "jupiter" else None, "sanityToleranceAU": 0.01 if body == "chiron" else None})
    return {"observations": observations, "vectors": vectors}


def build_archive() -> dict[str, object]:
    archive: dict[str, object] = {
        "schemaVersion": 3,
        "provenance": source_catalog(),
    }
    archive.update(parse_upstream_events())
    archive.update(parse_eclipses())
    archive.update(parse_horizons())
    return archive


def source_catalog() -> dict[str, dict[str, str]]:
    upstream = f"https://github.com/cosinekitty/astronomy/tree/{UPSTREAM_REVISION}/generate"
    mit_license = "Upstream transformation files retain the Astronomy Engine MIT license archived with these fixtures"
    government_license = "U.S. government factual output is public domain; transformed files also retain the archived Astronomy Engine MIT license"
    nasa_license = "NASA factual data may be reproduced with acknowledgment and without implied endorsement; transformed files also retain the archived Astronomy Engine MIT license"
    return {
        "jplObserver": {"serviceVersion": "recorded in every archived response", "frame": "ICRF/J2000 equatorial and IAU76/80 true ecliptic and equinox of date", "origin": "Earth center 500@399", "units": "degrees, arcseconds/hour, AU, and km/s", "timeScale": "UT/UTC calendar output", "aberration": "apparent AIRLESS observer solution with down-leg light time and response-listed corrections", "refraction": "none (AIRLESS)", "domain": "1900, 2000, and 2100 samples, plus a three-day 2025 Mercury station bracket", "license": "NASA/JPL factual output; acknowledge NASA and do not imply endorsement", "url": "https://ssd.jpl.nasa.gov/horizons/manual.html", "recipe": "Adjacent *.query.json files contain every Horizons API parameter and the response SHA-256"},
        "jplVectors": {"serviceVersion": "recorded in every archived response", "frame": "geometric ICRF/J2000 vectors", "origin": "Sun center 500@10 for Chiron; Jupiter center 500@599 for Galilean moons; Earth center 500@399 for the Moon", "units": "AU and AU/day", "timeScale": "TDB", "aberration": "none (VEC_CORR=NONE)", "refraction": "not applicable to geometric vectors", "domain": "JPL vectors sampled at 1900, 2000, and 2100; Astronomy Engine's 9e-4 Galilean-moon threshold covers only JD 2426545.0 through 2476545.0; the Moon at 30 dates from 2002 BCE to 6000 CE, eleven of them within 40 days of 1900-01-01 or 2131-01-01", "license": "NASA/JPL factual output; acknowledge NASA and do not imply endorsement", "url": "https://ssd.jpl.nasa.gov/horizons/manual.html", "recipe": "Adjacent *.query.json files contain every Horizons API parameter and the response SHA-256"},
        "usnoSeasonsAndPhases": {"version": UPSTREAM_REVISION, "frame": "geocentric seasonal and lunar-phase event definitions from USNO APIs", "origin": "Earth center", "units": "calendar timestamps", "timeScale": "source timestamps are serialized with Z; the pinned C harness passes them to Astronomy_MakeTime as UT coordinates and compares lunar-quarter TT values derived with its default Espenak-Meeus Delta T model", "aberration": "not separately configurable or documented in the archived API output", "refraction": "not applicable to geocentric event times", "domain": "pinned table contains one year every ten years from 1800 through 2100; sampled at 1800, 2000, and 2100", "license": government_license, "url": "https://aa.usno.navy.mil/data/api", "recipe": f"Pinned parser, C validation harness, engine source, and table under {upstream}/moonphase, {upstream}/ctest.c, and the matching source/c tree"},
        "espenakMoonNodes": {"version": UPSTREAM_REVISION, "frame": "geocentric equator and equinox of date as consumed by the pinned harness", "origin": "Earth center", "units": "UTC calendar timestamps, right ascension hours, and declination degrees", "timeScale": "UTC as serialized by the pinned transformation", "aberration": "not documented by the source table", "refraction": "not applicable to geocentric node events", "domain": "published table 2001 through 2100; sampled at 2001, 2050, and 2100", "license": f"Fred Espenak table with attribution; {mit_license}", "url": "http://astropixels.com/ephemeris/moon/moonnodes2001.html", "recipe": f"Pinned README, parser, and table under {upstream}/moon_nodes"},
        "astronomyEngineApsides": {"version": UPSTREAM_REVISION, "frame": "scalar Earth-Moon and Sun-Earth distances; no orientation frame", "origin": "Earth center for lunar distance and Sun center for Earth distance", "units": "UTC-like calendar timestamps, km, and AU", "timeScale": "calendar strings are interpreted as UT/UTC by the pinned harness; original acquisition metadata is absent", "aberration": "not documented in the pinned tables", "refraction": "not applicable to scalar apsis distances", "domain": "pinned lunar and Earth tables beginning in 2001; sampled at 2001, 2050, and 2100", "license": mit_license, "url": f"{upstream}/apsides", "recipe": "Pinned moon.txt and earth.txt are parsed directly; evidence is classified as third-party parity because upstream does not retain the original acquisition recipe"},
        "usnoRiseSet": {"version": UPSTREAM_REVISION, "frame": "topocentric apparent horizon", "origin": "named terrestrial longitude and latitude", "units": "calendar timestamps treated as UT coordinates and geographic degrees", "timeScale": "the pinned C harness passes every timestamp to Astronomy_MakeTime as a UT coordinate, derives TT with the default Espenak-Meeus model, and compares event TT", "aberration": "included in the USNO apparent-position service", "refraction": "USNO standard apparent-horizon refraction", "domain": "all 5,909 pinned rows in 17 body/location/year groups from 1750 through 2050; the USNO service documents years 1700 through 2100", "license": government_license, "url": "https://aa.usno.navy.mil/data/RS_OneYear", "recipe": f"Pinned acquisition instructions, full table, C validation harness, and engine source under {upstream}/riseset, {upstream}/ctest.c, and the matching source/c tree"},
        "nasaLunarEclipses": {"version": UPSTREAM_REVISION, "frame": "geocentric Earth-shadow geometry", "origin": "Earth center", "units": "UT calendar timestamps and minutes", "timeScale": "UT; the pinned C harness compares eclipse.peak.ut with the parsed catalog coordinate under its default Espenak-Meeus Delta T model", "aberration": "not separately configurable in the published catalog", "refraction": "not applicable to geocentric eclipse geometry", "domain": "NASA catalog centuries represented by archived pages; sampled at 1800, 2000, and 2099", "license": nasa_license, "url": "https://eclipse.gsfc.nasa.gov/lunar.html", "recipe": f"Pinned catalog pages, source key, normalizer, C validation harness, and engine source under {upstream}/eclipse, {upstream}/ctest.c, and the matching source/c tree"},
        "nasaGlobalSolarEclipses": {"version": UPSTREAM_REVISION, "frame": "geocentric shadow-axis geometry with terrestrial greatest-eclipse location", "origin": "Earth center and catalog surface coordinates", "units": "TD calendar timestamps and geographic degrees", "timeScale": "Terrestrial Dynamical Time (TD)", "aberration": "not separately configurable in the published catalog", "refraction": "not applicable to global shadow geometry", "domain": "NASA catalog centuries represented by archived pages; sampled at 1800, 2024, and 2099", "license": nasa_license, "url": "https://eclipse.gsfc.nasa.gov/solar.html", "recipe": f"Pinned catalog pages and source key under {upstream}/eclipse"},
        "nasaPlanetaryTransits": {"version": UPSTREAM_REVISION, "frame": "geocentric Sun-planet contact geometry", "origin": "Earth center", "units": "UT calendar timestamps and arcseconds converted to arcminutes", "timeScale": "UT", "aberration": "not separately configurable in the published catalog", "refraction": "not applicable to geocentric transit contacts", "domain": "Mercury 1601 through 2300 and Venus 2000 BCE through 4000 CE; sampled from 2003 through 2125", "license": nasa_license, "url": "https://eclipse.gsfc.nasa.gov/transit/catalog/", "recipe": f"Pinned Mercury and Venus catalog pages under {upstream}/eclipse"},
        "eclipseWiseLocalSolar": {"version": UPSTREAM_REVISION, "frame": "topocentric apparent solar altitude at local contacts", "origin": "named terrestrial longitude and latitude", "units": "UTC calendar timestamps and degrees", "timeScale": "UTC as serialized by the pinned table", "aberration": "included in the published local circumstances", "refraction": "source altitude convention retained; below-horizon altitudes are not asserted", "domain": "published cases retained by the pinned table; three 2024 geometries sampled", "license": f"EclipseWise/Fred Espenak table with attribution; {mit_license}", "url": "https://www.eclipsewise.com/solar/SEcirc/SEcirc.html", "recipe": f"Pinned local_solar_eclipse.txt under {upstream}/eclipse"},
    }


def encoded(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def write_or_check(path: Path, data: bytes, check: bool) -> None:
    if check:
        if not path.exists() or path.read_bytes() != data:
            raise RuntimeError(f"generated output is stale: {path}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--refresh", action="store_true", help="download pinned source snapshots and fresh JPL responses")
    parser.add_argument("--check", action="store_true", help="verify sources and generated files without writing")
    args = parser.parse_args()
    if args.refresh:
        refresh_sources()
    sources = verify_sources()
    verify_recorded_queries()
    archive_data = encoded(build_archive())
    write_or_check(OUTPUT_DIR / "reference-fixtures.json", archive_data, args.check)
    print(f"verified {len(sources)} source artifacts and archive {sha256(archive_data)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, KeyError, IndexError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
