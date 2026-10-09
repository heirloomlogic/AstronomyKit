import copy
import importlib.util
import json
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('observer_capture', Path(__file__).with_name('capture-pluto-observers.py'))
g = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(g)


class PlutoObserverCaptureTests(unittest.TestCase):
    def response(self, target=9):
        return (g.DATA / 'observer-sources' / f'horizons-{target}.json').read_bytes()

    def test_exact_selection_and_semantics(self):
        for target in g.EPOCHS:
            rows = g.parse(target, self.response(target))
            self.assertEqual(g.EPOCHS[target], [r['tt'] for r in rows])
            self.assertTrue(all(r['target'] == target for r in rows))
        self.assertEqual("'TT'", g.query(9)['TIME_TYPE'])
        self.assertEqual("'JD'", g.query(9)['TLIST_TYPE'])
        self.assertEqual("'1,2,21,45'", g.query(9)['QUANTITIES'])

    def test_semantic_negative_controls(self):
        original = self.response()
        replacements = [
            ('Pluto Barycenter (9)', 'Pluto (999)'), ('{source: DE441}', '{source: DE440}'),
            ('Earth (399)', 'Sun (10)'), ('GEOCENTRIC', 'TOPOCENTRIC'),
            ('Date_________JDTT', 'Date_________JDUT'), ('RA_(ICRF-a-app)', 'RA_wrong_frame'),
            ('NO (AIRLESS)', 'YES'), ('1685021.000000000', '1685022.000000000'),
            ('60.423758737', 'NaN'), ('60.423758737', '361.0'),
        ]
        for old, new in replacements:
            with self.subTest(old=old):
                self.assertIn(old.encode(), original)
                with self.assertRaises(ValueError):
                    g.parse(9, original.replace(old.encode(), new.encode()))
        response = json.loads(original)
        response['result'] = response['result'].replace('$$SOE', '$$MISSING')
        with self.assertRaises(ValueError):
            g.parse(9, json.dumps(response).encode())

    def test_missing_or_extra_rows_rejected(self):
        response = json.loads(self.response())
        before, rest = response['result'].split('$$SOE\n')
        rows, after = rest.split('$$EOE')
        for changed in ['\n'.join(rows.splitlines()[1:])+'\n', rows+rows.splitlines()[0]+'\n']:
            response['result'] = before+'$$SOE\n'+changed+'$$EOE'+after
            with self.assertRaises(ValueError):
                g.parse(9, json.dumps(response).encode())

    def test_native_measurement_rejects_wrong_selection_or_failed_accuracy(self):
        evidence = json.loads((g.DATA / 'observer-evidence.json').read_bytes())
        g.validate_measurement(evidence['debug'])
        for key, value in [('tt', 42), ('target', 999), ('astrometricArcminutes', 1.01),
                           ('apparentICRFArcminutes', float('nan')), ('emissionTT', -766526),
                           ('horizonsLightTimeMinutes', 0)]:
            changed = copy.deepcopy(evidence['debug'])
            changed['rows'][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                g.validate_measurement(changed)
        changed = copy.deepcopy(evidence['debug'])
        changed['omittedEarthFailures'] = 0
        with self.assertRaises(ValueError):
            g.validate_measurement(changed)


if __name__ == '__main__':
    unittest.main()
