"""Host exporter fault boundaries; these do not execute/validate IEC code."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from phase1_audit_export import Exporter,Journal,EvidenceError,EVENT_FIELDS,DIAGNOSTIC_FIELDS,GAP_FIELDS,RscTransport


class MemoryJournal:
    def __init__(self, fail=False):
        self.rows=[]
        self.fail=fail
    def append(self, rows):
        if self.fail: raise OSError('disk full')
        self.rows.extend(rows)


class Transport:
    def __init__(self, journal):
        self.journal=journal
        self.writes=[]
        self.hook=None
        self.read_calls=0
        self.values={'BootId':'boot-a', 'CaptureBuffer.AuditEnabled':True,
            'CaptureBuffer.AuditReadSeq':0,'CaptureBuffer.AuditWriteSeq':1,
            'CaptureBuffer.AssociationReadSeq':0,'CaptureBuffer.AssociationWriteSeq':0,
            'CaptureBuffer.AuditDropped':0,'CaptureBuffer.AssociationDropped':0,
            'CaptureBuffer.EvidenceComplete':True,'CaptureBuffer.Diagnostics.Revision':0}
        base='CaptureBuffer.AuditEvents[1].'
        self.values.update({base+'Event.'+n:0 for n in EVENT_FIELDS})
        self.values.update({base+'Event.SampleSeq':1,base+'Event.ConfigSlot':1,
            base+'Event.ConfigGeneration':7,base+'Event.PointIndex':1,
            base+'Decision':2,base+'Reason':0})
        base='CaptureBuffer.Configs[1].'
        for n,v in {'Generation':7,'GatewayId':'gateway','CaptureBootId':'boot-a',
            'Config.Version':13,'Config.DeviceCount':1,'Config.PointCount':1,
            'Config.Points[1].pointId':'point','Config.Points[1].dataType':'float64',
            'Config.Points[1].reportMode':'cyclic','Config.Points[1].reportIntervalMs':5000,
            'Config.Points[1].deadband':0,'Config.Devices[1].deviceId':'device',
            'Config.Devices[1].PointStart':1,'Config.Devices[1].PointCount':1}.items():
            self.values[base+n]=v
    def read(self, names):
        self.read_calls+=1
        if self.hook:self.hook(names)
        return {n:self.values[n] for n in names}
    def write(self, name, value):
        assert self.journal.rows, 'ACK before durable append'
        self.writes.append((name,value))


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.journal=MemoryJournal()
        self.io=Transport(self.journal)
        self.exporter=Exporter(self.io,self.journal)
    def reject(self):
        with self.assertRaises(EvidenceError):self.exporter.poll()
        self.assertEqual(self.io.writes,[])
    def test_durable_event_then_boot_fenced_ack(self):
        self.assertEqual(self.exporter.poll(),(1,0))
        self.assertEqual(self.journal.rows[0]['config']['deviceId'],'device')
        self.assertEqual(self.journal.rows[1]['configKey'],[1,7,1])
        self.assertEqual(self.io.writes,[('CaptureBuffer.AuditAckBootId',''),
            ('CaptureBuffer.AuditAckSeq',0),('CaptureBuffer.AuditAckBootId','boot-a'),
            ('CaptureBuffer.AuditAckSeq',1)])
    def test_disk_failure_no_ack(self):
        self.journal.fail=True
        with self.assertRaises(OSError):self.exporter.poll()
        self.assertEqual(self.io.writes,[])
    def test_pending_decision_not_exported_or_acked(self):
        self.io.values['CaptureBuffer.AuditEvents[1].Decision']=0
        self.assertEqual(self.exporter.poll(),(0,0))
        self.assertEqual(self.io.writes,[])
    def test_disabled_audit(self):
        self.io.values['CaptureBuffer.AuditEnabled']=False
        self.reject()
    def test_native_capture_overflow(self):
        self.io.values['CaptureBuffer.AuditDropped']=1
        self.reject()
    def test_native_association_overflow(self):
        self.io.values['CaptureBuffer.AssociationDropped']=1
        self.reject()
    def test_incomplete_flag(self):
        self.io.values['CaptureBuffer.EvidenceComplete']=False
        self.reject()
    def test_already_released_prefix_rejected(self):
        self.io.values['CaptureBuffer.AuditReadSeq']=1
        self.reject()
    def test_overwritten_capture(self):
        self.io.values['CaptureBuffer.AuditEvents[1].Event.SampleSeq']=513
        self.reject()
    def test_config_generation_rejected(self):
        self.io.values['CaptureBuffer.Configs[1].Generation']=8
        self.reject()
    def test_invalid_slot_rejected(self):
        self.io.values['CaptureBuffer.AuditEvents[1].Event.ConfigSlot']=0
        self.reject()
    def test_boot_change_in_split_read(self):
        def hook(names):
            if 'CaptureBuffer.Configs[1].Generation' in names:
                self.io.values['BootId']='boot-b'
        self.io.hook=hook
        self.reject()
    def test_overwrite_during_dictionary_read(self):
        def hook(names):
            if 'CaptureBuffer.Configs[1].Generation' in names:
                self.io.values['CaptureBuffer.AuditEvents[1].Event.SampleSeq']=513
        self.io.hook=hook
        self.reject()
    def test_configuration_owner_missing(self):
        self.io.values['CaptureBuffer.Configs[1].Config.Devices[1].PointStart']=2
        self.reject()
    def test_association_is_independent_of_live_business_slots(self):
        self.io.values['CaptureBuffer.AssociationWriteSeq']=1
        base='CaptureBuffer.Associations[1].'
        self.io.values.update({base+n:v for n,v in {'Ordinal':1,'MessageId':'msg',
            'Digest':'a'*64,'Count':1,'ConfigSlot':1,'ConfigGeneration':7,
            'BatchGeneration':9,'Category':2,'SampleSeqs[1]':1}.items()})
        self.assertEqual(self.exporter.poll(),(1,1))
        self.assertEqual(self.journal.rows[2]['association']['sampleSeqs'],[1])
        self.assertEqual(self.io.writes[-1],('CaptureBuffer.AssociationAckSeq',1))
    def diagnostic(self):
        base='CaptureBuffer.Diagnostics.'
        names=DIAGNOSTIC_FIELDS+[f'Totals[{i}]' for i in range(1,17)]+['LastGap.'+n for n in GAP_FIELDS]
        self.io.values.update({base+n:0 for n in names})
        self.io.values[base+'Revision']=2
        self.io.values[base+'BootId']='boot-a'
        self.io.values[base+'LastGap.Reason']=9
        self.io.values[base+'LastGap.Outcome']=4
    def test_unknown_age_and_restart_loss_export_null(self):
        self.diagnostic()
        self.exporter.poll()
        snapshot=self.journal.rows[-1]['snapshot']
        self.assertIsNone(snapshot['OldestPendingAgeMs'])
        self.assertIsNone(snapshot['LastGap.eventCount'])
        self.assertIsNone(snapshot['LastGap.SampleSeq'])
        self.assertEqual(snapshot['LastGap.Reason'],9)
    def test_torn_diagnostic_revision_is_not_exported(self):
        self.diagnostic()
        def hook(names):
            if 'CaptureBuffer.Diagnostics.Totals[1]' in names:
                self.io.values['CaptureBuffer.Diagnostics.Revision']=4
        self.io.hook=hook
        self.exporter.poll()
        self.assertFalse(any(r['kind']=='localDiagnostics' for r in self.journal.rows))
    def test_unchanged_diagnostic_is_not_written_again(self):
        self.diagnostic()
        self.exporter.poll()
        self.exporter.poll()
        self.assertEqual(sum(r['kind']=='localDiagnostics' for r in self.journal.rows),1)
    def test_sixty_four_events_use_bounded_bulk_reads(self):
        template=dict(self.io.values)
        for seq in range(2,65):
            old='CaptureBuffer.AuditEvents[1].'
            new=f'CaptureBuffer.AuditEvents[{seq}].'
            self.io.values.update({new+k[len(old):]:v for k,v in template.items() if k.startswith(old)})
            self.io.values[new+'Event.SampleSeq']=seq
        self.io.values['CaptureBuffer.AuditWriteSeq']=64
        self.assertEqual(self.exporter.poll(),(64,0))
        self.assertLessEqual(self.io.read_calls,12)
        self.assertEqual(sum(r['kind']=='dictionary' for r in self.journal.rows),1)
        self.assertEqual(sum(r['kind']=='capture' for r in self.journal.rows),64)
    def test_record_cap_preserves_file_without_partial_append(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'audit.jsonl'
            j=Journal(path,max_records=1)
            j.append([{}])
            with self.assertRaises(EvidenceError):j.append([{},{}])
            j.close()
            self.assertEqual(path.read_bytes(),b'{}\n')
    def test_real_sdk_uint64_cursor_encoding_without_device_connection(self):
        class Service:
            def WriteSingle(self,item):
                self.item=item
                return 0
        service=Service()
        RscTransport(service).write('CaptureBuffer.AuditAckSeq',9007199254740991)
        from PyPlcnextRsc.common.tag_type import RscType
        self.assertEqual(service.item.Value.GetValue(),9007199254740991)
        self.assertEqual(service.item.Value._type,RscType.Uint64)
    def test_file_is_exclusive(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'audit.jsonl'
            j=Journal(path)
            j.append([{'sampleSeq':1}]);j.close()
            with self.assertRaises(FileExistsError):Journal(path)
            self.assertEqual(json.loads(path.read_text()),{'sampleSeq':1})
    def test_file_byte_cap_preserves_prior_records(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'audit.jsonl'
            j=Journal(path,max_bytes=4)
            j.append([{}])
            with self.assertRaises(EvidenceError):j.append([{}])
            j.close()
            self.assertEqual(path.read_bytes(),b'{}\n')


if __name__=='__main__':unittest.main()
