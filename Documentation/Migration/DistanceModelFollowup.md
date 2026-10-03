# Outer-planet and Pluto model follow-up

Investigated 2026-10-02 against the 131-epoch characterization in `Documentation/Migration/distance-characterization.json`, SHA-256 `dbf643669766fe2fb32b0e0632e6189cc2872ddfecdddd1d78a3f419fdd2e16c`. These diagnostics do not change the frozen measurement script, characterization results, or acceptance budgets. Passing the owner-selected empirical policy does not establish that the distance errors are suitable for a product requirement.

## Findings supported by direct experiments

The large Pluto residual already exists in the unmodified upstream C engine at the exact vendored revision `826e26ff3a6dc03ee46658b1138fef582d96c5d9`. Compiling that engine and evaluating the same 131 TT epochs against the archived heliocentric body-center references gives a maximum radial residual of **213,557.979 km**, at JDTT `2471355.0784273`. Local production gives **213,749.676 km** at that epoch. Across all 131 Pluto epochs, the largest pointwise local-minus-upstream vector difference is **593.818 km**, and the largest absolute radial difference is **403.207 km**. Consequently, the local full-series, polynomial, and arithmetic patches cannot explain most of the observed 214,000 km discrepancy.

The unchanged upstream Uranus and Neptune reduced models give much larger maximum radial residuals, **132,454.710 km** and **195,881.497 km**, respectively. The local complete series improve these to **8,881.262 km** and **9,306.030 km**. Thus upstream reduced-series agreement is not an appropriate independent distance-accuracy requirement.

An independent Python sum of the raw archived radius series, using each file's header counts, final amplitude/phase/frequency columns, and `math.fsum`, reproduces the Uranus/Neptune maxima to the printed precision. Across all 131 epochs, its largest absolute radius disagreement with local production is **0.000005847 km** for Uranus and **0.000003189 km** for Neptune. Together with the existing polynomial/full-series diagnostics, this makes a radial coefficient-generation or polynomial error an implausible explanation at these samples. It does not prove the archive is the correct intended scientific model at every date.

The extracted `PlutoStateTable` declaration and all its initializers are byte-identical between local and vendored upstream source; SHA-256 of that exact declaration is `c24c44a0f0ff04d2665601518804a0828744a79bf7f7e97ec71fb3773260b3a6`. `MajorBodyBary` is also byte-identical, but it calls the selected planetary model, so the local full-series change alters the perturbator trajectories. `GravFromState` explicitly converts the table's heliocentric seed states to barycentric states; it does not interpret the stored states as already barycentric.

## Independent center diagnostics

Six new responses and their request recipes are archived under `Scripts/reference-data/sources/distance/diagnostics/`. Each pair uses `TIME_TYPE='TT'`, Sun center `500@10`, ICRF equatorial vectors, `AU-D`, `VEC_CORR='NONE'`, and the body's characterization worst radial epoch. API signature is `NASA/JPL Horizons API`, version `1.0`; response headers record 2026-10-02 Pasadena acquisition times. The recipes retain every request parameter and exact response hash.

| Body | JDTT | Center trajectory source | Barycenter source | Norm of returned trajectory difference (km) | Barycenter minus center radius (km) | Local minus barycenter radius (km) |
| --- | ---: | --- | --- | ---: | ---: | ---: |
| Uranus | 2487838.33854224 | ura184_merged | DE441 | 4229.360 | +602.256 | +8279.006 |
| Neptune | 2460253.02362222 | nep098_merged | DE441 | 319.293 | -307.549 | -8998.481 |
| Pluto | 2471355.0784273 | plu060_merged | DE441 | 2131.343 | +119.106 | +213630.571 |

These are **returned trajectory differences**, not an isolated measurement of physical displacement between a planet and its satellites' barycenter. The center and barycenter source tags differ, and the Sun source is also `nep098_merged` or `plu060_merged` for those center requests. They can include different fitted trajectories as well as center offsets. At these three epochs, merely changing the target to the system barycenter does not remove the large radial discrepancy. The [Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html) explains separate planetary and satellite solutions; the [JPL satellite ephemeris catalog](https://ssd.jpl.nasa.gov/sats/ephem/sep.html) identifies the satellite solutions.

| File stem | Response SHA-256 | Query-file SHA-256 |
| --- | --- | --- |
| uranus-center | 43ec65bf1fbc96aedf306f2b3ae82411d4fefb9ae59e5b9ae4d1684edb5d7b5b | b3bafbd0ad6090ecc21e52df9bdbc66586456d7b3298750e6b4f952ebe3fa493 |
| uranus-barycenter | c48063a9a76e3c026b7c45a97a2ff8647e20aef2de07ec16967547cb9077315b | 327d5116f8feef122d3409bf0d50a424a448d1b2bb16bd2f9ed21177c20b7e62 |
| neptune-center | 41ed6e1d64674723527bd7c8322d91c0ee5098c20ffacd2af8e6bf468e0e8b7d | a5ae0292754df98102180eebec59ace21b7d5da85181b696b6bfb7e0c7ab02a4 |
| neptune-barycenter | efa3da6587fc7585ee0e2bd32b89573836aa73861212d331103be74474f8e2a5 | d3c333afe52a0e8f788835fe5d4678fe78fd227fe0200e52714489604bfe2d8f |
| pluto-center | 087d3486837eb5b6eb899caa6330d28f72e99c1fd95975a06ef168c031633cce | e05d7f4747a0099dee4941f09fa8f5c707c59f5d634d7626114fde191dff741f |
| pluto-barycenter | e9a7cd158398fcdc37db697c4c6ce401ff7295e5ee386987b65ee141809df822 | d6957cf096c23b22395e36434bd446f09f5404130477ab445bd471a8bfda1256 |

## What remains a hypothesis

VSOP87 is fitted to DE200, while these body-center references use newer planetary/satellite solutions. Differences in fitted orbital elements and observations are a plausible source of the remaining Uranus/Neptune residuals. [Bretagnon and Francou (1988)](https://articles.adsabs.harvard.edu/pdf/1988A%26A...202..309B) identifies the DE200 fit; [Park et al. (2021)](https://ssd.jpl.nasa.gov/doc/Park.2021.AJ.DE440.pdf) describes newer observations and models. Neither source quantifies the exact residual seen here. A direct DE200 comparison and a consistently sourced center-offset decomposition are required before assigning a cause.

Pluto's custom integration uses 29,200-day seed intervals, 146-day integration steps, forward/backward propagation and blending, and gravity from the Sun plus four outer planets. The [upstream integration constants](https://raw.githubusercontent.com/cosinekitty/astronomy/826e26ff3a6dc03ee46658b1138fef582d96c5d9/generate/gravsim/pluto_gravsim.h) and [upstream C implementation](https://raw.githubusercontent.com/cosinekitty/astronomy/826e26ff3a6dc03ee46658b1138fef582d96c5d9/source/c/astronomy.c) establish these facts. Seed-state mismatch with the modern ephemeris, limited force model, integration truncation, and blending/interpolation error are distinct hypotheses. This investigation has not separated their contributions. The J2000 seed epoch already has a 10,938.308 km radial residual, which cannot be caused by integration away from that seed; nearby samples around another seed also remain large, but exact seed requests are needed to interpret them.

The [upstream author's description](https://github.com/cosinekitty/astronomy#why-i-created-this-thing) promises approximately one-arcminute accuracy and describes validation against NOVAS and TOP2013. That broad angular goal can accommodate large distance errors at Pluto. The [TOP2013-to-JPL checking script](https://raw.githubusercontent.com/cosinekitty/astronomy/826e26ff3a6dc03ee46658b1138fef582d96c5d9/generate/top2013/jplcheck.py) scales vector discrepancy by range and reports arcminutes; it does not establish a kilometre acceptance budget for this custom integrator. No claim is made here that any one of the hypotheses is the confirmed cause.

## Recommended follow-up issue

Create a separate model-fitness issue: **Diagnose outer-planet distance errors and Pluto seed/integration accuracy against modern ephemerides**. Preserve this change's frozen acceptance policy and evidence. First define the product's maximum useful radial/vector errors independently of the observed maxima. Then compare raw full VSOP87B against DE200 and DE441 with explicit centers, and compare Pluto at exact seed epochs and predetermined interior offsets against TOP2013 and modern barycentric/body-center references. Replay Pluto with smaller predetermined integration steps to identify convergence behavior without tuning against acceptance data. Report seed, force-model, integration, interpolation, and reference-solution contributions separately before choosing a repair or replacement model. Any revised model needs fresh characterization and a newly independent holdout.

## Upstream diagnostic reproduction

Run this command from the workspace root. It fetches the exact upstream source/header into a temporary directory, checks their hashes, compiles both the untouched upstream probe and the existing local probe, evaluates the same ordered characterization rows, and prints body-specific maxima and pointwise local changes. It writes no production files or acceptance fixtures. The source paths are upstream `source/c/astronomy.c` and `source/c/astronomy.h`, not the separately archived event-harness engine at another revision.

```sh
python3 - <<'PY'
import hashlib, json, math, pathlib, subprocess, tempfile, urllib.request
root = pathlib.Path.cwd()
revision = '826e26ff3a6dc03ee46658b1138fef582d96c5d9'
base = f'https://raw.githubusercontent.com/cosinekitty/astronomy/{revision}/source/c/'
expected = {
    'astronomy.c': '3ef243a3ee4c10fc05a5cb460d753e4e17eb2f57dad7892690e12599088717ac',
    'astronomy.h': '747cb1268a801126ed74cb97e1f33e37eb20b999dd277de47e491a493a57415f',
}
report = json.loads((root / 'Documentation/Migration/distance-characterization.json').read_bytes())
rows = [r for r in report['results'] if r['body'] in ('Uranus', 'Neptune', 'Pluto') and r['mode'] == 'heliocentric']
with tempfile.TemporaryDirectory(prefix='distance-upstream-diagnostic-') as tmp:
    directory = pathlib.Path(tmp)
    for name, checksum in expected.items():
        data = urllib.request.urlopen(base + name).read()
        assert hashlib.sha256(data).hexdigest() == checksum
        (directory / name).write_bytes(data)
    source = directory / 'probe.c'
    source.write_text('''#include <stdio.h>
#include "astronomy.c"
int main(void) {
    char name[32]; double tt;
    while (scanf("%31s %lf", name, &tt) == 2) {
        astro_time_t time = Astronomy_TerrestrialTime(tt);
        astro_vector_t p = Astronomy_HelioVector(Astronomy_BodyCode(name), time);
        printf("%.17g %.17g %.17g\\n", p.x, p.y, p.z);
    }
    return 0;
}
''')
    subprocess.run(['cc', '-O2', '-std=c11', str(source), '-lm', '-o', str(directory / 'upstream')], check=True)
    subprocess.run(['cc', '-O2', '-std=c11', '-pthread', '-I', str(root / 'Sources/CLibAstronomy/include'), str(root / 'Scripts/reference-data/distance-probe.c'), '-lm', '-o', str(directory / 'local')], check=True)
    upstream_input = ''.join(f"{r['body']} {r['julianDateTT'] - 2451545}\n" for r in rows).encode()
    local_input = ''.join(f"{r['body']} heliocentric {r['julianDateTT'] - 2451545}\n" for r in rows).encode()
    upstream_output = subprocess.check_output([str(directory / 'upstream')], input=upstream_input)
    local_output = subprocess.check_output([str(directory / 'local')], input=local_input)
    assert len(upstream_output.splitlines()) == len(local_output.splitlines()) == len(rows)
    print('ordered upstream output SHA256', hashlib.sha256(upstream_output).hexdigest())
    results = []
    for row, upstream_line, local_line in zip(rows, upstream_output.splitlines(), local_output.splitlines()):
        p = list(map(float, upstream_line.split()))
        local = json.loads(local_line)
        radius = math.sqrt(sum(value * value for value in p))
        results.append({
            'body': row['body'], 'jdTT': row['julianDateTT'],
            'upstreamRadiusErrorKm': (radius - row['referenceRangeAU']) * 149597870.7,
            'upstreamVectorResidualKm': math.dist(p, row['referencePositionAU']) * 149597870.7,
            'localMinusUpstreamVectorKm': math.dist(local['positionAU'], p) * 149597870.7,
            'localMinusUpstreamRadiusKm': (row['actualRangeAU'] - radius) * 149597870.7,
        })
    for body in ('Uranus', 'Neptune', 'Pluto'):
        values = [r for r in results if r['body'] == body]
        print(body, 'samples', len(values))
        print('worst radial residual', max(values, key=lambda r: abs(r['upstreamRadiusErrorKm'])))
        print('maximum local vector/radial changes', max(r['localMinusUpstreamVectorKm'] for r in values), max(abs(r['localMinusUpstreamRadiusKm']) for r in values))
PY
```

The ordered upstream output SHA-256 on this machine was `c5f609e85b320ad107416e138b8c263a89530317cb8c18d055b87eef1e2669bb`. Floating-point output hashes are compiler/platform evidence, not portable mathematical invariants; keep source and query hashes authoritative and compare numerical diagnostics with an explicit rounding allowance when reproducing elsewhere.
