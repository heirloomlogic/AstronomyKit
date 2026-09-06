"""Integrity and convention checks for the follow-up experiments."""
import gzip
import hashlib
import json
from pathlib import Path
import unittest

from future_utc import utc_policy
from measure import fixtures

RESULTS = Path(__file__).parent/'results/followup'


class FollowupTests(unittest.TestCase):
    def test_announced_utc_offset_not_predictive_delta_t(self):
        policy = utc_policy()
        self.assertEqual(policy['effectiveUTDays'], 6209.5)
        self.assertAlmostEqual(policy['ttMinusUTCSeconds'], 69.184, places=12)

    def test_jpl_response_integrity_and_event_identity(self):
        directory = RESULTS/'horizons'
        manifest = json.loads((directory/'manifest.json').read_text())
        for body, record in manifest.items():
            self.assertEqual(hashlib.sha256((directory/f'{body}-response.json').read_bytes()).hexdigest(),
                             record['responseSHA256'])
        audit = json.loads((directory/'station-audit.json').read_text())
        originals = {(case, i): e for case, oracle in fixtures() for i, e in enumerate(oracle['events'])
                     if e['kind'] == 'station'}
        self.assertEqual(len(audit['cases']), 12)
        self.assertEqual({(r['caseID'], r['eventIndex']) for r in audit['cases']}, set(originals))
        for row in audit['cases']:
            self.assertEqual(row['original'], originals[(row['caseID'], row['eventIndex'])])
        with gzip.open(RESULTS.parent/'matrix.json.gz', 'rt') as stream:
            matrix = json.load(stream)
        self.assertEqual(audit['nativeLibrarySHA256'], matrix['libraries']['full']['binarySHA256'])

    def test_future_utc_keeps_all_original_references_and_separate_gates(self):
        with gzip.open(RESULTS/'future-utc.json.gz', 'rt') as stream:
            report = json.load(stream)
        originals = {(case, i): e for case, oracle in fixtures() for i, e in enumerate(oracle['events'])}
        self.assertEqual(report['civilTTModeledUT1']['library'], report['fullModel'])
        for rows in (report['production']['full-future-utc-date']['results'],
                     report['civilTTModeledUT1']['data']['results']):
            self.assertEqual(len(rows), 36)
            self.assertEqual({(r['caseID'], r['eventIndex']) for r in rows}, set(originals))
            for row in rows:
                self.assertEqual(row['identity'], originals[(row['caseID'], row['eventIndex'])])
                self.assertTrue(row['passes60SecondReferenceGate'])
                self.assertLessEqual(row['bracketWidthSeconds'], 1)
                self.assertLessEqual(abs(row['localResidual']), 1e-6 if row['kind'] == 'station' else 1e-4)
