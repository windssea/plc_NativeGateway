import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from summarize_phase1_performance import summarize


class RecoverySummaryTest(unittest.TestCase):
    def test_empty_fifo_before_reconnect_is_not_history_clear_and_catchup_is_not_capacity(self):
        def row(now,connected,watermark,history,owned,stored):
            r={'BootId':'boot','NowMs':now,'Active.enabled':True,'P06HoldSend':False,
               'P06Disconnect':False,'runStage':'observe','HMI.Connection':connected,
               'CaptureBuffer.Watermark':watermark,'CaptureBuffer.CapturedEventsTotal':1000,
               'CaptureBuffer.OwnedCount':owned,'CaptureBuffer.StoredConfirmedEventsTotal':stored,
               'CaptureBuffer.QueueHead[1]':history,'CaptureBuffer.WorkMaxUs':1000,
               'P06MaxUs':4000,'P06OverPeriod':0,'CaptureBuffer.MissedPollCyclesTotal':0}
            for i in range(1,17):r[f'CaptureBuffer.BatchOwners[{i}].State']=0;r[f'CaptureBuffer.BatchOwners[{i}].Category']=0
            return r
        release=row(1000,'CONNECTING',0,0,1000,0)
        rows=[row(2000,'CONNECTING',0,0,1000,0),row(3000,'CONNECTED',1000,1,1000,0),
              row(4000,'CONNECTED',1000,1,900,100),row(5000,'CONNECTED',1000,0,100,200),
              row(6000,'CONNECTED',1000,0,100,250)]
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'run').write_text(json.dumps(dict(complete=True,snapshots=rows)))
            (p/'fault').write_text('\n'.join(json.dumps(r) for r in [dict(kind='fault',elapsedSeconds=0),
                 dict(kind='connectionClosed'),dict(kind='released',elapsedSeconds=60,snapshot=release)]))
            result=summarize(p/'run',p/'fault')
        self.assertEqual(result['historyClearBracket']['upperSeconds'],4)
        self.assertEqual(result['saturatedRecoveryWindowSeconds'],1)
        self.assertEqual(result['saturatedRecoveryConfirmedLocalReleaseEventsPerSecond'],100)
        self.assertEqual(result['activeRecoveryConfirmedLocalReleaseEventsPerSecond'],50)
        self.assertFalse(result['fullP06Acceptance'])


if __name__=='__main__':unittest.main()
