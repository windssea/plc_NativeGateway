"""P03/P04 full gateway snapshot; --pause-and-drain leaves RAM acquisition paused
for Engineer restoration. On drain failure it restores acquisition enable.
Never downloads, reboots, changes persistent config or creates a database.
"""
import argparse,contextlib,io,json,time,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from phase1_plc_probe import Device,IDataAccessService,WriteItem,RscVariant

def snapshot(output,pause):
    prefix='Arp.Plc.Eclr/MainInstance.'
    fields=['Active.Version','Active.DeviceCount','Active.PointCount','Active.enabled','BootId','QueueCount','NowMs','UnixMs']
    totals=['CapturedEventsTotal','EligibleEventsTotal','PolicyFilteredEventsTotal','CaptureOverflowEventsTotal',
            'UndecidedLostEventsTotal','KnownUnsentEventsTotal','TimeInvalidEventsTotal','IsolatedEventsTotal',
            'UncertainDeliveryEventsTotal','StoredConfirmedEventsTotal','LateStoredEventsTotal',
            'MissedPollCyclesTotal','MissedReportSlotsTotal','EnqueueRejectedAttemptsTotal','GapRecordsTotal',
            'OwnedCount','IngressCount','LayoutValid','LayoutBytes','CaptureStopped','CounterOverflow',
            'AccountingComplete','HighSlot','FreeHead']
    fields+=['CaptureBuffer.'+n for n in totals]
    with Device('192.168.0.8') as dev:
        svc=IDataAccessService(dev)
        def read(names):
            rows=list(svc.Read([prefix+n for n in names]))
            if any(int(r.Error) for r in rows): raise RuntimeError('Candidate data unavailable')
            return {n:r.Value.GetValue() for n,r in zip(names,rows)}
        result=read(fields)
        if not result['BootId'] or result['Active.Version']!=13 or not result['CaptureBuffer.LayoutValid']:
            raise RuntimeError('Candidate startup/config not ready')
        result['beforePause']=dict(result)
        if pause:
            err=svc.WriteSingle(WriteItem(prefix+'Active.enabled',RscVariant.of(False)))
            if int(err): raise RuntimeError('Pause refused')
            deadline=time.monotonic()+45
            while time.monotonic()<deadline:
                result.update(read(fields))
                if result['CaptureBuffer.OwnedCount']==0 and result['CaptureBuffer.IngressCount']==0:
                    break
                time.sleep(.25)
            else:
                svc.WriteSingle(WriteItem(prefix+'Active.enabled',RscVariant.of(True)))
                raise RuntimeError('Drain timed out; restored acquisition enable')
        for n in ['Connection','ConfirmedBatches','PublishedBatches','InvalidAcks']:
            row=svc.ReadSingle('Arp.Plc.Eclr/HMI.'+n)
            result['HMI.'+n]=row.Value.GetValue()
        result['atUtc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
        result['pausedForRestore']=pause
    output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    return result

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output',type=Path)
    ap.add_argument('--pause-and-drain',action='store_true')
    args=ap.parse_args()
    with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
        result=snapshot(args.output,args.pause_and_drain)
    print(json.dumps(result,ensure_ascii=False))
