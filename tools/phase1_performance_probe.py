"""P06 validation-only RAM controls and read-only performance snapshots.

Mutations require an exact expected boot and the P06 fields. No persistent
configuration, real STORED, MQTT, DB, OS restart or service change is made.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import time
from phase1_plc_probe import Device,IDataAccessService,WriteItem,RscVariant

PERF_FIELDS=('P06HoldSend P06DropAck P06Samples P06OverPeriod P06OverOneMs '
             'P06MinUs P06MaxUs P06LastUs P06SumUs').split()
TOTALS=('CapturedEventsTotal EligibleEventsTotal PolicyFilteredEventsTotal '
        'TimeInvalidEventsTotal CaptureOverflowEventsTotal UndecidedLostEventsTotal '
        'KnownUnsentEventsTotal IsolatedEventsTotal UncertainDeliveryEventsTotal '
        'StoredConfirmedEventsTotal LateStoredEventsTotal EnqueueRejectedAttemptsTotal '
        'MissedPollCyclesTotal MissedReportSlotsTotal SourceTimestampRepeatTotal '
        'GapRecordsTotal OwnedCount IngressCount LayoutValid LayoutBytes CaptureStopped '
        'CounterOverflow AuditDropped AssociationDropped AuditReadSeq AuditWriteSeq '
        'AssociationReadSeq AssociationWriteSeq EvidenceComplete SourceWorkUs WorkLastUs WorkMaxUs').split()
CONTROLS={'hold':('P06HoldSend',True),'release':('P06HoldSend',False),
    'drop-ack':('P06DropAck',True),'accept-ack':('P06DropAck',False),
    'pause':('Active.enabled',False),'resume':('Active.enabled',True),
    'reset':('P06ResetStats',True)}


def snapshot(service,device=None):
    prefix='Arp.Plc.Eclr/MainInstance.'
    names=['BootId','Active.Version','Active.PointCount','Active.enabled','NowMs','UnixMs','QueueCount']
    names+=PERF_FIELDS+['CaptureBuffer.'+n for n in TOTALS]
    names+=['CaptureBuffer.Watermark','CaptureBuffer.QueueHead[1]']
    names += [f'CaptureBuffer.BatchOwners[{i}].'+n for i in range(1,17) for n in ('State','Category','OrderSeq')]
    rows=list(service.Read([prefix+n for n in names]))
    if len(rows)!=len(names) or any(int(r.Error) for r in rows):
        raise RuntimeError('P06 candidate fields unavailable')
    result={n:r.Value.GetValue() for n,r in zip(names,rows)}
    disconnect=service.ReadSingle(prefix+'P06Disconnect')
    if not int(disconnect.Error):result['P06Disconnect']=disconnect.Value.GetValue()
    for field in ('Mqtt.ReadyClient','Mqtt.Client.xBusy'):
        row=service.ReadSingle(prefix+field)
        if not int(row.Error):result[field]=row.Value.GetValue()
    if not result['BootId'] or result['Active.Version']!=13 or result['Active.PointCount']!=250:
        raise RuntimeError('Unexpected candidate identity/configuration')
    row=service.ReadSingle('Arp.Plc.Eclr/HMI.GatewayId')
    if int(row.Error) or row.Value.GetValue()!='NG-HUB-2152-01':
        raise RuntimeError('Unexpected gateway')
    for n in ['Connection','ConfirmedBatches','PublishedBatches','InvalidAcks']:
        row=service.ReadSingle('Arp.Plc.Eclr/HMI.'+n)
        result['HMI.'+n]=row.Value.GetValue() if not int(row.Error) else None
    result['atUtc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    result['atMonotonic']=time.monotonic()
    if device is not None:
        from PyPlcnextRsc.Arp.Device.Interface.Services import IDeviceStatusService
        identifiers=['Status.Cpu.0.Load.Percent','Status.Memory.Usage.Percent',
            'Status.Memory.Usage.Percent.Actual','Status.ProgramMemoryIEC.Usage.Percent',
            'Status.DataMemoryIEC.Usage.Percent']
        values=IDeviceStatusService(device).GetItems(identifiers)
        result['deviceResources']={n:v.GetValue() for n,v in zip(identifiers,values)}
    section_names=[f'{n}[{i}]' for n in ('P06SectionMax','P06SectionSum','P06SectionLast','P06SectionRx','P06SectionTx') for i in range(1,9)]
    sections=list(service.Read([prefix+n for n in section_names]))
    if not any(int(r.Error) for r in sections):
        result.update((n,r.Value.GetValue()) for n,r in zip(section_names,sections))
        result['sectionOrder']=['clockStoreStartup','receiveAckAndEditor','layoutAndConfig',
            'auditAndModbus','pipeline','statusHeartbeatTransmit','mqttSdk','hmi']
    optional=['P06WorstAtMs','P06WorstRx','P06WorstTx','P06WorstSourceUs']+[f'P06WorstSections[{i}]' for i in range(1,9)]
    values=list(service.Read([prefix+n for n in optional]))
    if not any(int(r.Error) for r in values):result.update((n,r.Value.GetValue()) for n,r in zip(optional,values))
    optional=['P06ObservedWorkMax','P06WorstWorkSource','P06WorstWorkAtMs','P06WorstWorkCaptured']
    optional += [f'{name}[{i}]' for name in ('P06WorkParts','P06WorstWorkParts') for i in range(1,7)]
    values=list(service.Read([prefix+n for n in optional]))
    if not any(int(r.Error) for r in values):
        result.update((n,r.Value.GetValue()) for n,r in zip(optional,values))
        result['workPartOrder']=['maintenance','policy','builder','delivery','counters','diagnostics']
    optional=[f'{name}[{i}]' for name in ('P06SourceParts','P06WorstWorkSourceParts') for i in range(1,5)]
    values=list(service.Read([prefix+n for n in optional]))
    if not any(int(r.Error) for r in values):
        result.update((n,r.Value.GetValue()) for n,r in zip(optional,values))
        result['sourcePartOrder']=['auditReferenceDrain','sourceActivation','physicalFinalResults','staleDetection']
    optional=[f'P06WorstBudgetTimes[{i}]' for i in range(1,7)]
    values=list(service.Read([prefix+n for n in optional]))
    if not any(int(r.Error) for r in values):
        result.update((n,r.Value.GetValue()) for n,r in zip(optional,values))
        result['worstBudgetOrder']=['deadline','beforeBuilder','afterBuilder','beforeDelivery','afterDelivery','workEnd']
    return result


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action',choices=['snapshot']+list(CONTROLS))
    ap.add_argument('output',type=Path)
    ap.add_argument('--expect-boot')
    args=ap.parse_args()
    with open(os.devnull,'w') as quiet,contextlib.redirect_stdout(quiet),contextlib.redirect_stderr(quiet):
        with Device('192.168.0.8') as device:
            service=IDataAccessService(device)
            result=snapshot(service,device)
            if args.action!='snapshot':
                if result['BootId']!=args.expect_boot:
                    raise RuntimeError('Exact boot required for mutation')
                name,value=CONTROLS[args.action]
                error=service.WriteSingle(WriteItem('Arp.Plc.Eclr/MainInstance.'+name,RscVariant.of(value)))
                if int(error):raise RuntimeError('P06 control write refused')
                time.sleep(.08)
                result=dict(before=result,after=snapshot(service,device),action=args.action)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    compact=result.get('after',result)
    print(json.dumps({n:compact[n] for n in ['BootId','Active.enabled','NowMs','P06HoldSend','P06DropAck',
        'P06Samples','P06MaxUs','P06OverPeriod','CaptureBuffer.CapturedEventsTotal',
        'CaptureBuffer.StoredConfirmedEventsTotal','CaptureBuffer.OwnedCount',
        'CaptureBuffer.AuditDropped','CaptureBuffer.AssociationDropped','CaptureBuffer.Watermark',
        'CaptureBuffer.QueueHead[1]']},ensure_ascii=False))


if __name__=='__main__':main()
