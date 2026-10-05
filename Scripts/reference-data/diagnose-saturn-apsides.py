#!/usr/bin/env python3
"""Failure-selected Saturn apsis model and center controls; no qualification."""
import argparse
import importlib.util
import json
import math
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "Documentation/Migration"
PLAN = DOCS / "saturn-apsis-diagnostic-plan.json"
BASELINE = DOCS / "planetary-apsis-assessment.json"
REPORT = DOCS / "saturn-apsis-diagnosis.json"
RAW = ROOT / "Scripts/reference-data/sources/saturn-apsis-diagnosis"
BUILD = ROOT / ".context/saturn-apsis-diagnosis"
SPEC = importlib.util.spec_from_file_location("apsides", Path(__file__).with_name("qualify-planetary-apsides.py"))
A = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(A)
Q = A.Q


def validate_plan(plan):
    baseline = json.loads(BASELINE.read_bytes())["bodies"]["Saturn"]
    cases = [{"publicIndex": p["publicIndex"], "rawRootIndex": p["rawRootIndex"],
              "publicJulianDateTT": baseline["publicEvents"][p["publicIndex"]]["julianDateTT"],
              "referenceJulianDateTT": baseline["rawRoots"][p["rawRootIndex"]]["julianDateTT"],
              "kind": baseline["publicEvents"][p["publicIndex"]]["kind"]} for p in baseline["comparison"]["pairs"]]
    expected = {"acceptanceTargetID": "699", "diagnosticTargetID": "6", "originID": "10", "timeScale": "TT", "frame": "ICRF", "correction": "NONE", "units": "AU-D", "timingTargetSeconds": 60, "timingComparison": "strictlyLessThan", "referenceAllowanceSeconds": 1, "cases": cases, "baselineAssessmentSHA256": A.digest(BASELINE.read_bytes())}
    if any(plan.get(key) != value for key, value in expected.items()):
        raise ValueError("diagnostic plan changed approved target, source or failure population")


def load_plan():
    plan = json.loads(PLAN.read_bytes())
    validate_plan(plan)
    return plan


def dates(plan, stage):
    if stage == "centers":
        grid = plan["centerControlGrid"]
        count = round(2 * grid["halfSpanDays"] / grid["stepDays"])
        return sorted(round(c["publicJulianDateTT"] - grid["halfSpanDays"] + i * grid["stepDays"], 8) for c in plan["cases"] for i in range(count + 1))
    if stage == "precision":
        return sorted(round(c["referenceJulianDateTT"] + offset, 8) for c in plan["cases"] for offset in plan["precisionControlGrid"]["offsetDays"])
    raise ValueError("unknown diagnostic stage")


def recipe(target, stage, plan):
    if target not in ("699", "6") or (stage == "precision" and target != "699"):
        raise ValueError("unsupported target/stage")
    return Q.parameters(target, "10", "NONE", dates(plan, stage))


def validate_archive(data, receipt, target, stage, plan):
    if receipt.get("parameters") != recipe(target, stage, plan) or receipt.get("responseSHA256") != A.digest(data) or receipt.get("planSHA256") != A.digest(PLAN.read_bytes()):
        raise ValueError("detached diagnostic source, request or plan")
    return Q.parse_response(data, receipt["parameters"])


def archive_pair(target, stage, plan, acquire=False):
    name = f"saturn-{target}-{stage}"
    response, query = RAW / (name + ".json"), RAW / (name + ".query.json")
    if acquire and not response.exists() and not query.exists():
        data = Q.download(recipe(target, stage, plan))
        RAW.mkdir(parents=True, exist_ok=True)
        response.write_bytes(data)
        query.write_bytes(A.encoded({"parameters": recipe(target, stage, plan), "responseSHA256": A.digest(data), "planSHA256": A.digest(PLAN.read_bytes())}))
    data, receipt = response.read_bytes(), json.loads(query.read_bytes())
    validate_archive(data, receipt, target, stage, plan)
    return data, receipt


def resolve(rows, kind):
    result = A.stage_root(rows)
    if result.get("status") != "resolved" or result.get("kind") != kind:
        raise ValueError("diagnostic root has absent, extra or wrong-kind crossing")
    return result


def build_probe():
    BUILD.mkdir(parents=True, exist_ok=True)
    binary = BUILD / "saturn-apsis-probe"
    sources = sorted(p for p in (ROOT / "Sources/CLibAstronomy").rglob("*.c") if p.name != "astronomy.c")
    subprocess.run(["clang", "-O2", "-I", str(ROOT / "Sources/CLibAstronomy/include"), str(Path(__file__).with_name("saturn-apsis-probe.c")), *map(str, sources), "-lm", "-lpthread", "-o", str(binary)], check=True)
    return binary


def acquire():
    plan = load_plan()
    for target, stage in [("699", "centers"), ("6", "centers"), ("699", "precision")]:
        archive_pair(target, stage, plan, acquire=True)


def scientific_report(report):
    return {key: value for key, value in report.items() if key not in {"candidateRevision", "candidateDirty"}}


def replay_baseline():
    archived = json.loads(BASELINE.read_bytes())
    replay = A.assess(A.BINARY)
    # The original receipt deliberately binds the executable, including rebuild differences.
    scientific = lambda report: {key: value for key, value in report.items() if key not in {"candidateRevision", "candidateDirty", "executableProvenance"}}
    if scientific(archived) != scientific(replay):
        raise ValueError("original scientific evidence no longer reproduces")
    old_executable = archived["executableProvenance"]
    new_executable = replay["executableProvenance"]
    differences = [key for key in sorted(set(old_executable) | set(new_executable)) if old_executable.get(key) != new_executable.get(key)]
    if differences not in ([], ["sha256"]):
        raise ValueError("baseline replay has additional executable/environment drift")
    return {"allScientificFieldsMatch": True, "totals": replay["totals"], "originalStrictCheckMatches": not differences, "executableDifferences": differences,
            "archivedExecutable": old_executable, "replayedExecutable": new_executable}


def center_roots(rows, case, plan):
    grid = plan["centerControlGrid"]
    samples = [row for row in rows if abs(row["julianDateTT"] - case["publicJulianDateTT"]) <= grid["halfSpanDays"] + 1e-7]
    results = []
    for i, j in Q.brackets(samples):
        offset = max(0, min(i - 2, len(samples) - 5))
        result = A.stage_root(samples[offset:offset + 5])
        result["withinOriginalNumericalAllowance"] = result.get("status") == "resolved" and result["quadraticDifferenceSeconds"] <= plan["referenceAllowanceSeconds"]
        results.append(result)
    return {"sampleCount": len(samples), "directedCrossingCount": len(results), "roots": results}


def validate_probe(result, case, plan):
    if result.get("publicKind") != case["kind"] or abs(result.get("publicJulianDateTT", math.inf) - case["publicJulianDateTT"]) * 86400 > 2:
        raise ValueError("public replay changed event identity or exceeds numerical diagnostic tolerance")
    roots = result.get("roots", [])
    expected = [(evaluator, step) for evaluator in ("production", "full-series") for step in [0, *plan["finiteDifferenceStepsDays"]]]
    if [(root.get("evaluator"), root.get("stepDays")) for root in roots] != expected:
        raise ValueError("model root controls changed")
    for root in roots:
        if root.get("kind") != case["kind"] or root.get("method") != ("analytic" if root["stepDays"] == 0 else "finite-difference"):
            raise ValueError("model root identity/method changed")
        fields = ["julianDateTT", "offsetFromArchivedPublicSeconds", "bracketWidthSeconds", "rateAtArchivedPublicAUPerDay", "rateAtArchivedReferenceAUPerDay"]
        if not all(math.isfinite(root.get(key, math.nan)) for key in fields) or not 0 <= root["bracketWidthSeconds"] <= plan["modelRootToleranceSeconds"]:
            raise ValueError("model root is nonfinite or imprecise")
        if abs((root["julianDateTT"] - case["publicJulianDateTT"]) * 86400 - root["offsetFromArchivedPublicSeconds"]) > plan["modelRootToleranceSeconds"]:
            raise ValueError("model root epoch/offset units disagree")


def assess():
    plan = load_plan()
    binary = build_probe()
    requests = "".join(f"{case['publicJulianDateTT']:.17g} {case['referenceJulianDateTT']:.17g} {plan['modelRootBracketHalfSpanDays']} {plan['modelRootToleranceSeconds']}\n" for case in plan["cases"])
    output = subprocess.check_output([str(binary)], input=requests, text=True)
    probe = [json.loads(line) for line in output.splitlines()]
    if len(probe) != len(plan["cases"]):
        raise ValueError("model probe response count mismatch")
    sources, metadata = {}, {}
    for target, stage in [("699", "centers"), ("6", "centers"), ("699", "precision")]:
        data, receipt = archive_pair(target, stage, plan)
        sources[target, stage], meta = validate_archive(data, receipt, target, stage, plan)
        metadata[f"{target}-{stage}"] = {"metadata": meta, "responseSHA256": receipt["responseSHA256"], "parameters": receipt["parameters"]}
    cases = []
    for case, model in zip(plan["cases"], probe):
        validate_probe(model, case, plan)
        precision_samples = [row for row in sources["699", "precision"] if abs(row["julianDateTT"] - case["referenceJulianDateTT"]) < 0.011]
        precision = resolve(precision_samples, case["kind"])
        if precision["quadraticDifferenceSeconds"] > plan["referenceAllowanceSeconds"]:
            raise ValueError("fresh body-center precision exceeds original allowance")
        centers = {target: center_roots(sources[target, "centers"], case, plan) for target in ("699", "6")}
        barycenter = centers["6"]
        if barycenter["directedCrossingCount"] != 1:
            raise ValueError("system-barycenter control is not a unique local root")
        barycenter_root = barycenter["roots"][0]
        if not barycenter_root["withinOriginalNumericalAllowance"] or barycenter_root["kind"] != case["kind"]:
            raise ValueError("system-barycenter root kind or precision changed")
        public_jd = case["publicJulianDateTT"]
        body_jd = precision["julianDateTT"]
        barycenter_jd = barycenter_root["julianDateTT"]
        body_error = (public_jd - body_jd) * 86400
        barycenter_error = (public_jd - barycenter_jd) * 86400
        center_shift = (barycenter_jd - body_jd) * 86400
        roots = model["roots"]
        analytic_production, analytic_full = roots[0], roots[4]
        cases.append({**case, "archivedSignedTimingErrorSeconds": (public_jd - case["referenceJulianDateTT"]) * 86400,
                      "freshBodyCenterRoot": precision, "centerControls": centers, "modelControls": model,
                      "freshRootMinusArchivedSeconds": (body_jd - case["referenceJulianDateTT"]) * 86400,
                      "productionMinusFullAnalyticRootSeconds": analytic_production["offsetFromArchivedPublicSeconds"] - analytic_full["offsetFromArchivedPublicSeconds"],
                      "publicMinusFreshBodyCenterSeconds": body_error,
                      "publicMinusSystemBarycenterSeconds": barycenter_error,
                      "systemBarycenterMinusBodyCenterSeconds": center_shift,
                      "centerShiftDominatesResidual": abs(center_shift) > abs(barycenter_error),
                      "withinStrictBodyCenterTimingTarget": abs(body_error) < plan["timingTargetSeconds"],
                      "diagnosticBarycenterWithinStrictTimingTarget": abs(barycenter_error) < plan["timingTargetSeconds"],
                      "originalPairIdentityLimitedByExtraCrossings": centers["699"]["directedCrossingCount"] != 1})
    inputs = A.input_hashes()
    extra = [PLAN, BASELINE, Path(__file__), Path(__file__).with_name("saturn-apsis-probe.c"), Path(__file__).with_name("test_saturn_apsis.py"), *RAW.glob("*.json")]
    inputs.update({str(path.relative_to(ROOT)): A.digest(path.read_bytes()) for path in extra})
    return {"schemaVersion": 1, "classification": "failure-selected-saturn-model-and-center-attribution-not-qualification", "qualified": False,
            "candidateRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "candidateDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
            "planSHA256": A.digest(PLAN.read_bytes()), "inputSHA256": dict(sorted(inputs.items())), "sources": metadata,
            "probeExecutable": {"sha256": A.digest(binary.read_bytes()), "clangVersion": subprocess.check_output(["clang", "--version"], text=True).strip(), "platform": platform.platform()},
            "baselineReplay": replay_baseline(), "cases": cases,
            "summary": {"cases": len(cases), "strictBodyCenterTimingFailures": sum(not c["withinStrictBodyCenterTimingTarget"] for c in cases),
                        "diagnosticBarycenterTimingFailures": sum(not c["diagnosticBarycenterWithinStrictTimingTarget"] for c in cases),
                        "centerDominatedCases": sum(c["centerShiftDominatesResidual"] for c in cases),
                        "originalPairsWithExtraLocalCrossings": sum(c["originalPairIdentityLimitedByExtraCrossings"] for c in cases)},
            "limitations": plan["limitations"] + ["The 1929 body-center grid exposes two additional raw crossings; its original orbit-scale pairing is limited.", "A finite grid does not prove continuous event completeness.", "Center differences dominate these six measurements; barycenter model residuals still exceed the strict target in every case.", "Finite-difference zero plateaus limit the interpretation of their final brackets.", "No production repair or new model/API policy is selected."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["acquire", "report", "check"])
    args = parser.parse_args()
    if args.action == "acquire":
        acquire()
        return
    report = assess()
    if args.action == "report":
        if REPORT.exists():
            raise ValueError("diagnosis report already frozen")
        REPORT.write_bytes(A.encoded(report))
    elif scientific_report(report) != scientific_report(json.loads(REPORT.read_bytes())):
        raise ValueError("Saturn diagnosis report drift")
    print(json.dumps(report["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
