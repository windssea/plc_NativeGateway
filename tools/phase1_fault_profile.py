"""Bounded P06 fault window, exact candidate boot only; release flag in finally.

hold stops candidate DATA materialization/submission while collection continues.
drop-ack discards real business ACK application in the validation overlay only.
disconnect disables only this candidate's MQTT client, closing its real
connection while collection continues. Broker/Hub and physical LAN stay up.
No mode creates ACKs, writes DB or changes persistent configuration.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import time
from phase1_performance_probe import Device,IDataAccessService,WriteItem,RscVariant,snapshot


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('mode',choices=['hold','drop-ack','disconnect'])
    ap.add_argument('output',type=Path)
    ap.add_argument('--expect-boot',required=True)
    ap.add_argument('--seconds',type=int,default=300,choices=range(1,301))
    ap.add_argument('--stop-file',type=Path)
    ap.add_argument('--wait-ready',type=int,default=0,choices=range(301))
    args=ap.parse_args()
    if args.wait_ready:
        deadline=time.monotonic()+args.wait_ready
        with open(os.devnull,'w') as quiet:
            while True:
                try:
                    with contextlib.redirect_stdout(quiet),contextlib.redirect_stderr(quiet):
                        with Device('192.168.0.8') as device:
                            ready=snapshot(IDataAccessService(device),device)
                    if ready['BootId']!=args.expect_boot:raise RuntimeError('Waiting read-only for exact candidate boot')
                    if args.mode=='disconnect' and ready['HMI.Connection']!='CONNECTED':
                        raise RuntimeError('Waiting read-only for established MQTT connection')
                    break
                except Exception:
                    if time.monotonic()>=deadline:raise
                    time.sleep(.5)
    started=time.monotonic()
    field={'hold':'P06HoldSend','drop-ack':'P06DropAck','disconnect':'P06Disconnect'}[args.mode]
    with args.output.open('x',encoding='utf-8') as output:
        def record(kind,value):
            output.write(json.dumps(dict(kind=kind,elapsedSeconds=time.monotonic()-started,snapshot=value),ensure_ascii=False)+'\n')
            output.flush(); os.fsync(output.fileno())
        with open(os.devnull,'w') as quiet,contextlib.redirect_stdout(quiet),contextlib.redirect_stderr(quiet):
            with Device('192.168.0.8') as device:
                svc=IDataAccessService(device)
                before=snapshot(svc,device)
                if before['BootId']!=args.expect_boot or before['P06HoldSend'] or before['P06DropAck'] or before.get('P06Disconnect',False):
                    raise RuntimeError('Unexpected boot or existing fault; no write')
                if args.mode=='disconnect' and ('P06Disconnect' not in before or before['HMI.Connection']!='CONNECTED' or 'Mqtt.ReadyClient' not in before or 'Mqtt.Client.xBusy' not in before):
                    raise RuntimeError('Disconnect mode requires the candidate field and an established MQTT connection')
                record('before',before)
                def set_flag(value):
                    row=svc.ReadSingle('Arp.Plc.Eclr/MainInstance.BootId')
                    if int(row.Error) or row.Value.GetValue()!=args.expect_boot:
                        raise RuntimeError('Boot changed; no write to another runtime')
                    error=svc.WriteSingle(WriteItem('Arp.Plc.Eclr/MainInstance.'+field,RscVariant.of(value)))
                    if int(error):raise RuntimeError('Fault flag write refused')
                try:
                    set_flag(True)
                    if args.mode=='disconnect':
                        close_deadline=time.monotonic()+10
                        while True:
                            current=snapshot(svc,device)
                            if current['BootId']!=args.expect_boot:raise RuntimeError('Boot changed')
                            if current['HMI.Connection']!='CONNECTED' and not current['Mqtt.ReadyClient'] and not current['Mqtt.Client.xBusy']:
                                record('connectionClosed',current)
                                break
                            if time.monotonic()>close_deadline:raise RuntimeError('MQTT client did not close')
                            time.sleep(.1)
                    fault_started=time.monotonic()
                    deadline=fault_started+args.seconds
                    next_sample=0
                    while time.monotonic()<deadline:
                        if args.stop_file and args.stop_file.exists():break
                        if time.monotonic()>=next_sample:
                            current=snapshot(svc,device)
                            if current['BootId']!=args.expect_boot:raise RuntimeError('Boot changed')
                            record('fault',current)
                            next_sample=time.monotonic()+5
                        time.sleep(.1)
                    record('beforeRelease',snapshot(svc,device))
                finally:
                    set_flag(False)
                    time.sleep(.08)
                    record('released',snapshot(svc,device))
    print(json.dumps(dict(output=str(args.output),mode=args.mode,seconds=args.seconds,released=True)))


if __name__=='__main__':main()
