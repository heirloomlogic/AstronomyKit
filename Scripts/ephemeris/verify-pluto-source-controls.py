#!/usr/bin/env python3
"""Source-only endpoint and deliberate body-center omission controls."""
import importlib.util
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('pluto_generator', HERE / 'generate-pluto.py')
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


def check():
    plan = P.load_plan()
    payloads, _ = P.products(plan)
    lower, upper = plan['publicTTDomain']
    dates = [lower, math.nextafter(lower, math.inf), math.nextafter(upper, -math.inf), upper,
             2456293.5 - 1e-8, 2456293.5, 2456293.5 + 1e-8]
    second = []
    for date in dates:
        a, b = P.tdb(date)
        if a != 2451545.0:
            raise ValueError('unexpected split epoch convention')
        second.append(b)
    second = P.np.array(second)
    native, reference = [], []
    for component in plan['components']:
        d = P.decode(payloads[component['filename']])
        native.append(P.evaluate((*d[:4], d[4] / P.AU), 2451545.0, second))
        with P.SPK.open(str(P.KERNELS[component['kernel']])) as kernel:
            reference.append(P.reference_state(kernel, component, 2451545.0, second))
    position = sum(s[0] for s in native) * P.AU
    velocity = sum(s[1] for s in native) * P.AU
    reference_position = sum(s[0] for s in reference)
    reference_velocity = sum(s[1] for s in reference)
    pd = float(P.np.max(P.np.abs(position - reference_position)))
    vd = float(P.np.max(P.np.abs(velocity - reference_velocity)))
    if pd > plan['parityLimits']['positionComponentKm'] or vd > plan['parityLimits']['velocityComponentKmPerDay']:
        raise ValueError('split-TDB endpoint parity failed')
    # Broad product tolerances alone could miss barycenter/body confusion.
    wrong_center = sum(s[0] for s in native[:2]) * P.AU
    omission_errors = P.np.linalg.norm(wrong_center - reference_position, axis=0)
    if not P.np.all(omission_errors > 1.0):
        raise ValueError('negative control failed to distinguish body center from barycenter')
    return {'planSHA256': P.digest(P.PLAN.read_bytes()), 'stateCount': len(dates),
            'maximumPositionComponentErrorKm': pd, 'maximumVelocityComponentErrorKmPerDay': vd,
            'minimumDeliberateBodyCenterOmissionErrorKm': float(min(omission_errors)),
            'julianDatesTT': dates}


if __name__ == '__main__':
    print(json.dumps(check(), sort_keys=True))
