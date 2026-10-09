import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT/'Scripts'/file)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


references = load('observer_reference_test', 'capture-observer-events.py')
record = load('observer_record_test', 'record-observer-event-evidence.py')


class ObserverSourcesTests(unittest.TestCase):
    def source(self):
        return references.read_source(references.DATA/'sources/horizons/sun.json')

    def test_replay_frozen_fixture(self):
        self.assertEqual(references.fixture(), json.loads(references.FIXTURE.read_bytes()))

    def test_nonfinite_epoch_and_values(self):
        for old, new in [('2415020.500000000', 'nan'), ('-18.304851246', 'nan'), ('6.440174497', 'inf')]:
            with self.subTest(old=old):
                document, query = self.source()
                self.assertIn(old, document['result'])
                document['result'] = document['result'].replace(old, new, 1)
                with self.assertRaises(ValueError):
                    references.parse_horizons(document, query, *references.CASES[0])

    def test_changed_time_frame_refraction_site_and_target(self):
        mutations = [('TIME_TYPE', "'UT'"), ('COMMAND', "'399'"), ('APPARENT', "'REFRACTED'"), ('SITE_COORD', "'0,0,0'")]
        for key, value in mutations:
            with self.subTest(key=key):
                document, query = self.source()
                query[key] = value
                with self.assertRaises(ValueError):
                    references.parse_horizons(document, query, *references.CASES[0])
        for old, new in [('Date_________JDTT', 'Date_________JDUT'), ('R.A.__(a-app)', 'R.A.___(ICRF)'), ('Sun (10)', 'Earth (399)')]:
            document, query = self.source()
            document['result'] = document['result'].replace(old, new, 1)
            with self.assertRaises(ValueError):
                references.parse_horizons(document, query, *references.CASES[0])

    def test_missing_and_extra_rows(self):
        for extra in [False, True]:
            document, query = self.source()
            head, rest = document['result'].split('$$SOE\n')
            rows, tail = rest.split('$$EOE')
            lines = rows.splitlines()
            document['result'] = head+'$$SOE\n'+'\n'.join(lines+lines[:1] if extra else lines[:-1])+'\n$$EOE'+tail
            with self.assertRaises(ValueError):
                references.parse_horizons(document, query, *references.CASES[0])

    def test_fuzz_corpus_bindings(self):
        for name, digest in [('fixed-riseset-infinite-limit', '6d88cbde5da0ca9da353a20326d522e27c88dde3714498e5d4bc6929753a4e02'),
                             ('fixed-riseset-stall', 'ca78b6218e4c663f595a10afa5cb38a76a73ba5d15e81f3923c133d3454305c8')]:
            self.assertEqual(hashlib.sha256((ROOT/'Fuzzing/corpus'/name).read_bytes()).hexdigest(), digest)


class ObserverRecordingTests(unittest.TestCase):
    def setUp(self):
        self.captures = json.loads(record.CAPTURES.read_bytes())
        self.evidence = json.loads(record.OUTPUT.read_bytes())

    def test_complete_recording(self):
        self.assertEqual(record.evidence(self.captures, record.sources()), self.evidence)

    def test_each_published_measurement_section_is_validated(self):
        for section, field in [('usno', 'residualSeconds'), ('points', 'altitudeErrorArcminutes'),
                               ('semidiameters', 'opticalResidualDegrees'), ('polar', 'sourceOpticalResidualDegrees')]:
            with self.subTest(section=section):
                changed = copy.deepcopy(self.captures['debug'])
                changed[section][0][field] += 1
                with self.assertRaises(ValueError):
                    record.validate_measurements(changed)

    def test_no_omitted_duplicate_shifted_or_nonfinite_observations(self):
        for mutation in ['omit', 'duplicate', 'time', 'direction', 'nan']:
            with self.subTest(mutation=mutation):
                changed = copy.deepcopy(self.captures['debug'])
                if mutation == 'omit': changed['usno'].pop()
                if mutation == 'duplicate': changed['usno'][1] = changed['usno'][0]
                if mutation == 'time': changed['usno'][0]['referenceUT'] += 1/86400
                if mutation == 'direction': changed['usno'][0]['direction'] = 'invalid'
                if mutation == 'nan': changed['points'][0]['hourAngleHours'] = float('nan')
                with self.assertRaises(ValueError): record.validate_measurements(changed)

    def test_all_recorded_metadata_and_resources_are_compared(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'mutated.json'
            for key in self.evidence:
                with self.subTest(key=key):
                    changed = copy.deepcopy(self.evidence)
                    changed[key] = None
                    path.write_text(json.dumps(changed))
                    with mock.patch.object(record, 'OUTPUT', path), mock.patch('sys.argv', ['record-observer-event-evidence.py', '--check']):
                        with self.assertRaisesRegex(SystemExit, 'recorded observer evidence differs'):
                            record.main()
        changed = copy.deepcopy(self.captures)
        changed['resources']['seconds']['sunRise'] = -1
        with self.assertRaises(ValueError): record.evidence(changed, {})


if __name__ == '__main__':
    unittest.main()
