"""Read-only bounded native timing-fixture export; never writes or simulates Hub."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import time
from phase1_plc_probe import Device,IDataAccessService

def probe(output,wait_seconds):
    names=('Done Stage Scan SamplesMeasured SetupUs SourceStartupUs LastUs MaxUs MinUs SumUs OverOneMs OverPeriod Sequence').split()
    names+=['Buffer.'+n for n in ('CapturedEventsTotal EligibleEventsTotal StoredConfirmedEventsTotal OwnedCount IngressCount CaptureStopped AuditDropped AssociationDropped').split()]
    names+=[f'{n}[{i}]' for n in ('ProfileMax','ProfileSum','ProfileLast') for i in range(1,9)]
    prefix='Arp.Plc.Eclr/MainInstance.'
    with Device('192.168.0.8') as device:
        service=IDataAccessService(device);deadline=time.monotonic()+wait_seconds
        while True:
            rows=list(service.Read([prefix+n for n in names]))
            if any(int(r.Error) for r in rows):raise RuntimeError('Timing fixture fields unavailable')
            result={n:r.Value.GetValue() for n,r in zip(names,rows)}
            if result['Done'] or time.monotonic()>=deadline:break
            time.sleep(1)
    result['evidenceLevel']='PURE_IEC_GET_MICROSECONDS_COMPONENT_TIMING_FIXTURE_ACK_ONLY'
    result['componentOrder']=['auditDrainAndSourceState','sourceResult','maintenance','policy','builder','delivery','diagnostics','wholePipeline']
    result['atUtc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    return result

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('output',type=Path)
    ap.add_argument('--wait-seconds',type=int,choices=range(0,61),default=30);args=ap.parse_args()
    with open(os.devnull,'w') as quiet,contextlib.redirect_stdout(quiet),contextlib.redirect_stderr(quiet):
        result=probe(args.output,args.wait_seconds)
    print(json.dumps(result))
