"""Evidence fences: mixed generations and ring loss must never certify a batch."""
import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from phase1_batch_trace_export import Exporter, EvidenceError, TYPES


class Journal:
    def __init__(self): self.rows=[]
    def append(self, rows): self.rows.extend(rows)


class BatchTraceExportTest(unittest.TestCase):
    def reader(self, end=1, after=1, boot='boot'):
        def read(names):
            result={}
            for n in names:
                if n=='BootId': result[n]=boot
                elif n=='P06TraceWriteSeq': result[n]=end
                elif n.startswith('P06BOrdinal'): result[n]=after if len(names)==2 else 1
                elif n.startswith('P06BId'): result[n]='message'
                else: result[n]=0
            return result
        return read

    def test_stable_row_exported_once(self):
        j=Journal(); e=Exporter(self.reader(),j,'boot'); e.poll();e.poll()
        self.assertEqual(len(j.rows),1); self.assertEqual(e.cursor,1)
        self.assertEqual(j.rows[0]['event']['Id'],'message')

    def test_overwrite_never_exports_partial_cohort(self):
        j=Journal();e=Exporter(self.reader(end=17),j,'boot')
        with self.assertRaises(EvidenceError):e.poll()
        self.assertEqual(j.rows,[])

    def test_seqlock_change_rejects_mixed_row(self):
        j=Journal();e=Exporter(self.reader(after=2),j,'boot')
        with self.assertRaises(EvidenceError):e.poll()
        self.assertEqual(e.cursor,0);self.assertEqual(j.rows,[])

    def test_unexpected_boot_does_not_continue_cursor(self):
        j=Journal();e=Exporter(self.reader(boot='other'),j,'boot')
        with self.assertRaises(EvidenceError):e.poll()
        self.assertEqual(j.rows,[])


if __name__=='__main__':unittest.main()
