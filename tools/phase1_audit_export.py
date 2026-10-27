"""Bounded P05 RSC evidence export. No MQTT publishing, DB or acquisition writes.

The only PLC writes acknowledge already fsynced audit copies, never business
DATA/STORED. Run only against the P05 candidate. A fresh file is mandatory;
process restarts use another file and cannot certify an earlier cohort.
"""
import argparse
import contextlib
import io
import json
import os
from pathlib import Path
import time

EVENT_FIELDS = ('SampleSeq Value CapturedUtcMs CompletedMonoMs NominalDueMonoMs '
                'ClockRevision SamplingGeneration ConfigGeneration ConfigSlot '
                'PointIndex Quality Kind Flags').split()
DIAGNOSTIC_FIELDS = ('Revision BootId GatewayId CapturedMonoMs ConfigVersion '
    'DecisionPending PendingEvents DeadEvents UncertainRetainedEvents PendingBatches '
    'DeadBatches UsedBytes AllocatedBytes MaxBytes OldestPendingAgeMs HasPendingAge '
    'AccountingComplete CounterOverflow DetailTruncated RestartLossUnknown '
    'AuditDropped AssociationDropped EvidenceComplete LastGapCountKnown HmiSummary').split()
GAP_FIELDS = ('SampleSeq ConfigVersion CompletedMonoMs CapturedUtcMs Flags Outcome '
              'GatewayId CaptureBootId DeviceId PointId Reason').split()


class EvidenceError(RuntimeError):
    pass


class Journal:
    def __init__(self, path, max_bytes=64*1024*1024, max_records=100000):
        self.file = Path(path).open('xb')
        self.size = 0
        self.limit = max_bytes
        self.records = 0
        self.max_records = max_records

    def append(self, rows):
        data = ''.join(json.dumps(r, ensure_ascii=False, allow_nan=False,
                                  separators=(',', ':'))+'\n' for r in rows).encode()
        if self.size+len(data) > self.limit or self.records+len(rows) > self.max_records:
            raise EvidenceError('Evidence byte cap reached; no further ACK')
        self.file.write(data)
        self.file.flush()
        os.fsync(self.file.fileno())
        self.size += len(data)
        self.records += len(rows)

    def close(self):
        self.file.close()


class Exporter:
    """Single reader; native ring overflow is a failed evidence window.

    Transport.read returns an ordered field dictionary. Every call is bounded;
    no custom IEC struct or >256-character string is requested through RSC.
    """
    def __init__(self, transport, journal):
        self.io = transport
        self.journal = journal
        self.boot = None
        self.capture = 0
        self.association = 0
        self.configs = {}
        self.config_headers = {}
        self.complete = True
        self.diagnostic_revision = 0

    def head(self):
        return self.io.read(['BootId']+['CaptureBuffer.'+n for n in
            ('AuditEnabled AuditReadSeq AuditWriteSeq AssociationReadSeq '
             'AssociationWriteSeq AuditDropped AssociationDropped EvidenceComplete').split()])

    def check(self, head):
        if head['BootId'] != self.boot:
            raise EvidenceError('Boot changed during export; no ACK')
        if not head['CaptureBuffer.AuditEnabled']:
            raise EvidenceError('P05 audit is disabled')
        if (head['CaptureBuffer.AuditDropped'] or head['CaptureBuffer.AssociationDropped']
                or not head['CaptureBuffer.EvidenceComplete']):
            raise EvidenceError('Native evidence ring incomplete; cohort cannot pass')
        if (head['CaptureBuffer.AuditReadSeq'] > self.capture or
                head['CaptureBuffer.AssociationReadSeq'] > self.association):
            raise EvidenceError('Unrecorded ring entries already released')

    def config(self, slot, generation, point):
        key = slot, generation, point
        self.prefetch_configs([key])
        return self.configs[key]

    def prefetch_configs(self, keys):
        groups = {}
        for slot,generation,point in keys:
            if not 1 <= slot <= 4 or not 1 <= point <= 320:
                raise EvidenceError('Invalid configuration reference')
            if (slot,generation,point) not in self.configs:
                groups.setdefault((slot,generation),set()).add(point)
        for (slot,generation),points in groups.items():
            base = f'CaptureBuffer.Configs[{slot}].'
            names = ['Generation','GatewayId','CaptureBootId','Config.Version',
                     'Config.DeviceCount','Config.PointCount']
            raw = self.io.read([base+n for n in names])
            header = {n:raw[base+n] for n in names}
            if header['Generation'] != generation or header['CaptureBootId'] != self.boot:
                raise EvidenceError('Configuration generation/boot changed')
            if not 1 <= header['Config.DeviceCount'] <= 50 or max(points) > header['Config.PointCount']:
                raise EvidenceError('Invalid point dictionary')
            cached = self.config_headers.get(slot)
            if cached and cached[0] == generation:
                devices = cached[1]
            else:
                devices = self.io.read([base+f'Config.Devices[{i}].'+n
                    for i in range(1,header['Config.DeviceCount']+1)
                    for n in ('deviceId','PointStart','PointCount')])
            point_fields = ('pointId','dataType','reportMode','reportIntervalMs','deadband')
            raw = self.io.read([base+f'Config.Points[{point}].'+n
                                for point in sorted(points) for n in point_fields])
            if self.io.read([base+'Generation'])[base+'Generation'] != generation:
                raise EvidenceError('Configuration changed while reading')
            self.configs = {k:v for k,v in self.configs.items() if k[0] != slot or k[1] == generation}
            self.config_headers[slot] = generation,devices
            for point in points:
                row = dict(header)
                row.update((f'Config.Points[{point}].'+n,raw[base+f'Config.Points[{point}].'+n]) for n in point_fields)
                owners = [i for i in range(1,header['Config.DeviceCount']+1)
                    if devices[base+f'Config.Devices[{i}].PointStart'] <= point <
                       devices[base+f'Config.Devices[{i}].PointStart']+
                       devices[base+f'Config.Devices[{i}].PointCount']]
                if len(owners) != 1:
                    raise EvidenceError('Ambiguous point ownership')
                row['deviceId'] = devices[base+f'Config.Devices[{owners[0]}].deviceId']
                self.configs[slot,generation,point] = row

    def diagnostics(self):
        base = 'CaptureBuffer.Diagnostics.'
        before = self.io.read([base+'Revision'])[base+'Revision']
        if not before or before % 2 or before == self.diagnostic_revision:
            return None
        names = DIAGNOSTIC_FIELDS+[f'Totals[{i}]' for i in range(1,17)]
        names += ['LastGap.'+n for n in GAP_FIELDS]
        raw = self.io.read([base+n for n in names])
        after = self.io.read(['BootId', base+'Revision'])
        if before != after[base+'Revision'] or after['BootId'] != self.boot:
            return None
        row = {n:raw[base+n] for n in names}
        if row['BootId'] != self.boot:
            return None
        if not row['HasPendingAge']:
            row['OldestPendingAgeMs'] = None
        row['LastGap.eventCount'] = 1 if row['LastGapCountKnown'] else None
        if not row['LastGapCountKnown']:
            for n in GAP_FIELDS:
                if n not in ('Reason', 'Outcome'):
                    row['LastGap.'+n] = None
        return dict(kind='localDiagnostics', bootId=self.boot, snapshot=row)

    def acknowledge(self, name, sequence):
        # Invalidate first: a restart between individual RSC writes cannot turn
        # an old ordinal into an ACK for a new boot.
        base = 'CaptureBuffer.'+name
        self.io.write(base+'AckBootId', '')
        self.io.write(base+'AckSeq', 0)
        self.io.write(base+'AckBootId', self.boot)
        self.io.write(base+'AckSeq', sequence)

    def poll(self):
        before = self.head()
        if self.boot is None:
            self.boot = before['BootId']
            if not self.boot:
                raise EvidenceError('Empty boot')
        self.check(before)
        captures = []
        dictionaries = []
        end = min(before['CaptureBuffer.AuditWriteSeq'], self.capture+64)
        event_names = ['Event.'+n for n in EVENT_FIELDS]+['Decision','Reason']
        raw = self.io.read([f'CaptureBuffer.AuditEvents[{(seq-1)%512+1}].'+n
            for seq in range(self.capture+1,end+1) for n in event_names])
        batch = []
        for seq in range(self.capture+1, end+1):
            base = f'CaptureBuffer.AuditEvents[{(seq-1)%512+1}].'
            row = {n:raw[base+n] for n in event_names}
            if row['Event.SampleSeq'] != seq:
                raise EvidenceError('Capture overwritten during read')
            if row['Decision'] == 0:
                break
            batch.append((seq,row))
        old_keys = set(self.configs)
        self.prefetch_configs([(row['Event.ConfigSlot'],row['Event.ConfigGeneration'],row['Event.PointIndex'])
                               for seq,row in batch])
        fences = self.io.read([f'CaptureBuffer.AuditEvents[{(seq-1)%512+1}].Event.SampleSeq' for seq,row in batch])
        emitted = set()
        for seq,row in batch:
            base = f'CaptureBuffer.AuditEvents[{(seq-1)%512+1}].'
            key = row['Event.ConfigSlot'],row['Event.ConfigGeneration'],row['Event.PointIndex']
            cfg = self.configs[key]
            if key not in old_keys and key not in emitted:
                dictionaries.append(dict(kind='dictionary',bootId=self.boot,
                    configKey=list(key),config=cfg))
                emitted.add(key)
            # A repeated seq check plus final ring bounds also fences eviction
            # across the split dictionary read.
            if fences[base+'Event.SampleSeq'] != seq:
                raise EvidenceError('Capture changed while reading dictionary')
            captures.append(dict(kind='capture',bootId=self.boot,event=row,configKey=list(key)))
        associations = []
        end = min(before['CaptureBuffer.AssociationWriteSeq'],self.association+16)
        for seq in range(self.association+1,end+1):
            base = f'CaptureBuffer.Associations[{(seq-1)%32+1}].'
            names = ['Ordinal','MessageId','Digest','Count','ConfigSlot','ConfigGeneration','BatchGeneration','Category']
            raw = self.io.read([base+n for n in names])
            row = {n:raw[base+n] for n in names}
            if row['Ordinal'] != seq or not 1 <= row['Count'] <= 64:
                raise EvidenceError('Association overwritten/invalid')
            raw = self.io.read([base+f'SampleSeqs[{i}]' for i in range(1,row['Count']+1)])
            row['sampleSeqs'] = list(raw.values())
            if self.io.read([base+'Ordinal'])[base+'Ordinal'] != seq:
                raise EvidenceError('Association changed during read')
            associations.append(dict(kind='association',bootId=self.boot,association=row))
        diag = self.diagnostics()
        self.check(self.head())
        rows = dictionaries+captures+associations+([diag] if diag else [])
        if rows:
            self.journal.append(rows)  # Fsync must succeed before any ACK.
        if diag:
            self.diagnostic_revision = diag['snapshot']['Revision']
        if captures:
            self.capture = captures[-1]['event']['Event.SampleSeq']
            self.acknowledge('Audit',self.capture)
        if associations:
            self.association = associations[-1]['association']['Ordinal']
            self.acknowledge('Association',self.association)
        return len(captures),len(associations)


class RscTransport:
    def __init__(self, service):
        self.service = service

    def read(self, names):
        result = {}
        for start in range(0,len(names),64):
            batch = names[start:start+64]
            rows = list(self.service.Read(['Arp.Plc.Eclr/MainInstance.'+n for n in batch]))
            if len(rows) != len(batch) or any(int(r.Error) for r in rows):
                raise EvidenceError('P05 RSC fields unavailable')
            result.update((n,r.Value.GetValue()) for n,r in zip(batch,rows))
        return result

    def write(self, name, value):
        from phase1_plc_probe import WriteItem,RscVariant
        from PyPlcnextRsc.common.tag_type import RscType
        variant = RscVariant(value,RscType.Uint64) if type(value) is int else RscVariant.of(value)
        err = self.service.WriteSingle(WriteItem('Arp.Plc.Eclr/MainInstance.'+name,variant))
        if int(err):
            raise EvidenceError('Audit cursor write refused')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output',type=Path)
    ap.add_argument('--seconds',type=int,default=60,choices=range(1,3601))
    ap.add_argument('--wait-ready',type=int,default=120,choices=range(0,301),
                    help='Read-only wait for P05 fields before Engineer download; no reconnect after candidate export begins')
    ap.add_argument('--stop-file',type=Path,help='Finish and fsync after a controller quiesce/drain; file creation does not alter the PLC')
    ap.add_argument('--after-boot',help='Wait read-only until a new boot replaces this exact prior candidate')
    args = ap.parse_args()
    from phase1_plc_probe import Device,IDataAccessService
    journal = Journal(args.output)
    exporter = None
    try:
        with open(os.devnull,'w') as quiet,contextlib.redirect_stdout(quiet),contextlib.redirect_stderr(quiet):
            ready_deadline = time.monotonic()+args.wait_ready
            candidate_seen = False
            while True:
                try:
                    with Device('192.168.0.8') as device:
                        exporter = Exporter(RscTransport(IDataAccessService(device)),journal)
                        head = exporter.head()
                        if not head['CaptureBuffer.AuditEnabled'] or not head['BootId'] or head['BootId']==args.after_boot:
                            raise EvidenceError('Waiting for candidate audit enable')
                        candidate_seen = True
                        deadline = time.monotonic()+args.seconds
                        while time.monotonic()<deadline:
                            exporter.poll()
                            if args.stop_file and args.stop_file.exists():
                                break
                            time.sleep(.1)
                    break
                except Exception:
                    if candidate_seen or time.monotonic()>=ready_deadline:
                        raise
                    time.sleep(.25)
        journal.append([dict(kind='end',bootId=exporter.boot,capture=exporter.capture,
                            association=exporter.association,exportCompleted=True)])
    except Exception as exc:
        # Failure/timeout never certifies a complete acceptance cohort.
        try:
            journal.append([dict(kind='failure',error=str(exc),exportCompleted=False)])
        except Exception:
            pass
        raise
    finally:
        journal.close()
    print(json.dumps(dict(output=str(args.output),lastCapture=exporter.capture,
                         lastAssociation=exporter.association,evidence='EXTERNAL_RSC_COPIES_ONLY')))


if __name__ == '__main__':
    main()
