import copy
import json
import tempfile
from pathlib import Path
from unittest.mock import patch
import unittest
import measure_altitude as measure


class AltitudeMeasurementProvenanceTests(unittest.TestCase):
    def test_recheck_rejects_paired_request_and_result_deletion(self):
        # Exercise the actual CLI before expensive reference evaluation. Matching
        # deletions must fail even if the stored summaries and hashes survive.
        saved = {'requests': measure.grid(), 'rows': [{'request': row} for row in measure.grid()]}
        del saved['requests'][0]
        del saved['rows'][0]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'omitted.json'
            path.write_text(json.dumps(saved))
            with patch('sys.argv', ['measure_altitude.py', '--recheck', '--output', str(path)]):
                with self.assertRaisesRegex(ValueError, 'canonical request grid'):
                    measure.main()

    def test_complete_request_grid_is_required(self):
        rows = measure.grid()
        self.assertEqual(len({r['id'] for r in rows}), len(rows))
        for change in ['delete', 'reorder', 'duplicate', 'observer']:
            changed = copy.deepcopy(rows)
            if change == 'delete':
                del changed[0]
            elif change == 'reorder':
                changed[0], changed[1] = changed[1], changed[0]
            elif change == 'duplicate':
                changed[0] = changed[1]
            else:
                changed[0]['observer'][0] = 33.0
            with self.assertRaisesRegex(ValueError, 'canonical request grid'):
                measure.validate_requests(changed)

    def test_wrong_result_association_is_rejected_before_evaluation(self):
        request = measure.grid()[0]
        record = {'request': {**request, 'model': 'other'}}
        with self.assertRaisesRegex(ValueError, 'wrong request'):
            measure.comparisons([record], [request])

    def test_missing_output_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Missing or duplicate'):
            measure.comparisons([], measure.grid()[:1])


if __name__ == '__main__':
    unittest.main()
