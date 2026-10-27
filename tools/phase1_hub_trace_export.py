"""Authenticated, read-only dev diagnostics export; credentials stay in memory."""
import argparse
import json
from pathlib import Path
import sys
import time
from phase1_audit_export import Journal, EvidenceError

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tests'))
from hub_api import HubApi


def run(args):
    api=HubApi().login(); journal=Journal(args.output,max_bytes=128*1024*1024)
    instance=None; cursor=0; started=time.monotonic()
    try:
        while time.monotonic()-started < args.seconds:
            row=api.api('GET','/api/device/iot-diagnostics')
            if not row.get('batchTraceEnabled'): raise EvidenceError('Hub batch trace disabled')
            last=int(row['batchTraceLastOrdinal'])
            if instance is None: instance=row['instanceId']; cursor=last
            if row['instanceId']!=instance: raise EvidenceError('Hub instance changed during observation')
            if last-cursor>int(row['batchTraceCapacity']):
                raise EvidenceError('Hub trace rows overwritten between exports')
            journal.append([dict(kind='hubDiagnostics',snapshot=row)])
            cursor=last
            if args.stop_file.exists(): break
            time.sleep(2)
        journal.append([dict(kind='end',instanceId=instance,exportCompleted=True)])
    except Exception as exc:
        journal.append([dict(kind='failure',error=str(exc),exportCompleted=False)]);raise
    finally: journal.close()
    print(json.dumps(dict(output=str(args.output),instanceId=instance,lastOrdinal=cursor)))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path)
    p.add_argument('--seconds',type=int,default=1200,choices=range(1,3601));p.add_argument('--stop-file',type=Path,required=True)
    run(p.parse_args())
