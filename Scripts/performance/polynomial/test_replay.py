"""Checks of the request-replay record layout and the Python-side deduplication."""
import gzip
import math
from pathlib import Path
import struct
import tempfile
import unittest
from replay import FILES, RECORD, SIZE, load_requests


def write(directory, records):
    path=Path(directory)/'requests.bin.gz'
    payload=b''.join(struct.pack(RECORD,*r) for r in records)
    path.write_bytes(gzip.compress(payload,mtime=0))
    return path


class RecordLayoutTests(unittest.TestCase):
    def test_layout_matches_the_capture_harness(self):
        self.assertEqual(RECORD,'<IiiId')
        self.assertEqual(SIZE,24)
        self.assertEqual(struct.calcsize(RECORD),SIZE)
        packed=struct.pack(RECORD,7,1,3,1,-36524.5)
        self.assertEqual(packed[:4],(7).to_bytes(4,'little'))
        self.assertEqual(packed[4:8],(1).to_bytes(4,'little'))
        self.assertEqual(packed[8:12],(3).to_bytes(4,'little'))
        self.assertEqual(packed[12:16],(1).to_bytes(4,'little'))
        self.assertEqual(packed[16:],struct.pack('<d',-36524.5))

    def test_populations_are_the_four_frozen_workloads(self):
        self.assertEqual(FILES,['scoring','nyc-day','nyc-week','reykjavik-day'])


class LoadRequestsTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)

    def unpack(self, blob):
        return [tuple(r) for r in struct.iter_unpack(RECORD,blob)]

    def test_deduplicates_kind_body_and_exact_tt(self):
        records=[(1,0,3,1,10.5),(2,0,3,0,10.5),(1,1,3,1,10.5),(1,0,4,1,10.5),(1,0,3,1,10.25)]
        count,blob,unique=load_requests(write(self.temporary.name,records))
        self.assertEqual(count,5)
        self.assertEqual(unique,4)
        self.assertEqual(len(blob),4*SIZE)
        # The first occurrence is retained, in capture order.
        self.assertEqual(self.unpack(blob),[records[0],records[2],records[3],records[4]])

    def test_distinguishes_signed_zero_and_keeps_not_a_number(self):
        records=[(0,0,0,1,0.0),(0,0,0,1,-0.0),(0,0,0,1,math.nan),(0,0,0,1,math.nan)]
        count,blob,unique=load_requests(write(self.temporary.name,records))
        self.assertEqual((count,unique),(4,3))
        values=[r[4] for r in self.unpack(blob)]
        self.assertEqual(math.copysign(1,values[0]),1)
        self.assertEqual(math.copysign(1,values[1]),-1)
        self.assertTrue(math.isnan(values[2]))

    def test_empty_population(self):
        count,blob,unique=load_requests(write(self.temporary.name,[]))
        self.assertEqual((count,blob,unique),(0,b'',0))

    def test_partial_record_is_rejected(self):
        path=Path(self.temporary.name)/'partial.bin.gz'
        path.write_bytes(gzip.compress(struct.pack(RECORD,1,0,0,1,1.0)[:-1],mtime=0))
        with self.assertRaises(ValueError): load_requests(path)


if __name__=='__main__': unittest.main()
