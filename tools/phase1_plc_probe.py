"""Explicit, bounded RSC evidence for the P01/P02 maintenance test.

before/after/test only read. quiesce/candidate disable the collector in RAM,
without saving configuration, and wait for its business outbox to drain. On
success they leave it paused for the subsequent Engineer project restoration.
Never invokes a PLC restart/download or writes the development database.
"""
import argparse
import contextlib
import enum
import hashlib
import io
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
# Apply only the SDK's Python 3.12 enum compatibility adapter (no probe side effects).
original_setitem = enum._EnumDict.__setitem__
def enum_setitem(self, key, value):
    if key == '_create_pseudo_member_':
        dict.__setitem__(self, key, value)
    else:
        original_setitem(self, key, value)
enum._EnumDict.__setitem__ = enum_setitem
if not hasattr(enum, '_decompose'):
    def decompose(cls, value):
        members = [m for m in cls if m.value and m.value & value == m.value]
        remaining = value
        for member in members:
            remaining &= ~member.value
        return members, remaining
    enum._decompose = decompose
sys.path.insert(0, str(ROOT.parent / 'JPlcnextRsc'))
from PyPlcnextRsc import Device
from PyPlcnextRsc.Arp.Plc.Gds.Services import IDataAccessService, WriteItem
from PyPlcnextRsc.common.serviceDefinition.all_needed import RscVariant


def probe(action, output):
    prefix = 'Arp.Plc.Eclr/MainInstance.'
    with Device('192.168.0.8') as device:
        service = IDataAccessService(device)
        def read(names):
            rows = list(service.Read([prefix+n for n in names]))
            if any(int(row.Error) != 0 for row in rows):
                raise RuntimeError('Requested PLC variables not available in this project')
            return {name: row.Value.GetValue() for name, row in zip(names, rows)}
        if action == 'test':
            result = read(['Stage', 'Passed', 'FailedChecks', 'Done', 'RecordBytes', 'BufferBytes', 'BudgetBytes'] + [f'Checks[{i}]' for i in range(1,23)])
        else:
            gateway = service.ReadSingle('Arp.Plc.Eclr/HMI.GatewayId')
            if int(gateway.Error) or gateway.Value.GetValue() != 'NG-HUB-2152-01':
                raise RuntimeError('Unexpected PLC gateway identity')
            result = read(['Active.Version','Active.DeviceCount','Active.PointCount','Active.enabled','BootId','QueueCount','NowMs','UnixMs'])
            result['gatewayId'] = gateway.Value.GetValue()
            config_names=['Active.'+field for field in ['Version','MessageId','enabled','batchIntervalMs','maxBatchPoints','DeviceCount','PointCount']]
            for index in range(1,result['Active.DeviceCount']+1):
                config_names += [f'Active.Devices[{index}].'+field for field in ['deviceId','enabled','host','port','unitId','connectTimeoutMs','requestTimeoutMs','retryCount','PointStart','PointCount']]
            for index in range(1,result['Active.PointCount']+1):
                config_names += [f'Active.Points[{index}].'+field for field in ['pointId','enabled','dataType','pollIntervalMs','scale','offset','reportMode','reportIntervalMs','deadband','staleAfterMs','area','address','byteOrder']]
            config_values={}
            for start in range(0,len(config_names),100):
                config_values.update(read(config_names[start:start+100]))
            result['samplingConfigSha256']=hashlib.sha256(json.dumps(config_values,sort_keys=True,separators=(',',':')).encode()).hexdigest()
            for name in ['Connection','PublishedBatches','ConfirmedBatches','InvalidAcks','ActiveVersion']:
                item=service.ReadSingle('Arp.Plc.Eclr/HMI.'+name)
                if int(item.Error):
                    raise RuntimeError('HMI evidence unavailable')
                result['HMI.'+name]=item.Value.GetValue()
            if action == 'candidate':
                counters=['CaptureBuffer.'+name for name in ['LayoutValid','LayoutBytes','RecordBytes','IngressCount','CapturedEventsTotal','CaptureOverflowEventsTotal','UndecidedLostEventsTotal','MissedPollCyclesTotal','CancelledReadsTotal','ActiveSlot','SamplingGeneration','DetailTruncated','CaptureStopped','CounterOverflow']]
                result.update(read(counters))
                if not result['CaptureBuffer.LayoutValid'] or result['CaptureBuffer.CaptureStopped'] or result['CaptureBuffer.IngressCount']!=512 or result['CaptureBuffer.CaptureOverflowEventsTotal']==0:
                    raise RuntimeError('Candidate not yet ready for full-ingress observation')
            if action in ['quiesce','candidate']:
                error = service.WriteSingle(WriteItem(prefix+'Active.enabled', RscVariant.of(False)))
                if int(error):
                    raise RuntimeError('Collector RAM quiesce refused')
                deadline = time.monotonic()+45
                while True:
                    current = read(['Active.enabled','QueueCount'])
                    if not current['Active.enabled'] and current['QueueCount'] == 0:
                        break
                    if time.monotonic() >= deadline:
                        service.WriteSingle(WriteItem(prefix+'Active.enabled', RscVariant.of(bool(result['Active.enabled']))))
                        raise RuntimeError('Outbox did not drain; restored original collector enable')
                    time.sleep(.25)
                result['quiesced'] = current
            if action == 'candidate':
                result.update(read(counters))
                points=result['Active.PointCount']
                source_fields=[f'Samples[{i}].Quality' for i in range(1,points+1)]
                source_values={}
                for start in range(0,len(source_fields),100):
                    source_values.update(read(source_fields[start:start+100]))
                result['sourceGoodPoints']=sum(value=='GOOD' for value in source_values.values())
                records=[]
                fields=['SampleSeq','Kind','Quality','Value','CapturedUtcMs','Flags','CompletedMonoMs','NominalDueMonoMs','ConfigSlot','ConfigGeneration','SamplingGeneration','PointIndex']
                for index in [1,250,251,500,512]:
                    record=read([f'CaptureBuffer.Ingress[{index}].'+name for name in fields])
                    records.append({name.rsplit('.',1)[1]:value for name,value in record.items()})
                result['frozenIngressRecords']=records
                captured=result['CaptureBuffer.CapturedEventsTotal']
                overflow=result['CaptureBuffer.CaptureOverflowEventsTotal']
                if captured != 512+overflow or overflow != result['CaptureBuffer.UndecidedLostEventsTotal']:
                    raise RuntimeError('Stable capture conservation failed')
                if result['sourceGoodPoints']!=250 or records[0]['SampleSeq']!=1 or records[0]['Kind']!=2 or records[0]['Quality']!=1:
                    raise RuntimeError('Native source/immutable ingress check failed')
    result['atUtc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    result['target'] = '192.168.0.8'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    return result


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['before','quiesce','test','candidate','after'])
    parser.add_argument('output', type=Path)
    args=parser.parse_args()
    # The old SDK prints raw packet hex; keep it out of user-facing evidence.
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        data=probe(args.action,args.output)
    print(json.dumps(data, ensure_ascii=False))
