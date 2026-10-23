"""Resumable UTC/NTP maintenance acceptance on the isolated 2152 mock fixture.

pause/offset-zero/handback mutate controller configuration through the HMI's
native transaction path. pause temporarily edits one poll period so Hub telemetry
is isolated while the OS clock moves from local wall time to actual UTC.
Requires explicit maintenance authorization; never use on a production controller.
"""
from pathlib import Path
import argparse
import json
import socket
import time
import maintenance_mode_verify as v

OUT=Path(__file__).resolve().parent/'time-locking-20261023'
OUT.mkdir(exist_ok=True)
STATE=OUT/'time-state.json'

def save(name,value):
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase',choices=['pause','offset-zero','handback','read','reboot'])
    phase=parser.parse_args().phase
    state=json.loads(STATE.read_text(encoding='utf-8')) if STATE.exists() else {}
    if phase=='reboot':
        from PyPlcnextRsc.Arp.Device.Interface.Services import IDeviceControlService
        start=time.time()
        with v.sdk.Device(v.PLC) as d:
            g=v.sdk.IDataAccessService(d);before=v.core(g)
            assert not before['HMI.Managed'] and before['HMI.LocalChanges']
            assert v.read(g,['MainInstance.Bootstrap.UtcOffsetMinutes'])[0]==0
            assert abs(v.read(g,['MainInstance.UnixMs'])[0]/1000-time.time())<5
            state['beforeReboot']=before;save('time-state.json',state)
            try: IDeviceControlService(d).RestartDevice()
            except Exception as error: save('restart-response.json',dict(exception=type(error).__name__))
        down=False
        while time.time()-start<240:
            try:
                with socket.create_connection((v.PLC,41100),timeout=.8):pass
                reachable=True
            except OSError:reachable=False
            down|=not reachable
            with (OUT/'reboot-reachability.jsonl').open('a',encoding='utf-8') as f:
                f.write(json.dumps(dict(at=time.time(),rsc=reachable))+'\n')
            if down and reachable:
                try:
                    with v.sdk.Device(v.PLC) as d:
                        g=v.sdk.IDataAccessService(d)
                        if v.read(g,['HMI.GatewayId'])[0]!=v.GW:
                            time.sleep(2);continue
                        after=v.core(g)
                        if (after['MainInstance.BootId']==before['MainInstance.BootId']
                                or after['MainInstance.Store.Busy'] or after['HMI.Connection']!='CONNECTED'):
                            time.sleep(2);continue
                        assert not after['HMI.Managed'] and after['HMI.LocalChanges']
                        assert v.read(g,['MainInstance.Bootstrap.UtcOffsetMinutes'])[0]==0
                        delta=v.read(g,['MainInstance.UnixMs'])[0]/1000-time.time()
                        assert abs(delta)<5,delta
                        assert v.configuration(g,'Durable.HubConfig')==state['config']
                        state['reboot']=dict(at=time.time(),passed=True,observedRscOutage=down,
                            elapsedSeconds=round(time.time()-start,2),epochOffsetSeconds=round(delta,3),core=after)
                        save('reboot.json',state['reboot']);save('time-state.json',state)
                        print('PASS: reboot; UTC, offset zero and maintenance persisted',flush=True);return
                except (OSError,RuntimeError,v.CommonRemotingException):pass
            time.sleep(2)
        raise AssertionError('Controller reboot/time recovery timeout')
    with v.sdk.Device(v.PLC) as d:
        g=v.sdk.IDataAccessService(d)
        before=v.core(g)
        if phase=='pause':
            assert before['HMI.Managed'] and not before['HMI.LocalChanges']
            config=v.configuration(g)
            assert config['DeviceCount']==50 and config['PointCount']==250
            assert config==v.configuration(g,'Durable.HubConfig')
            state=dict(before=before,config=config,originalUtcOffset=v.read(g,['MainInstance.Bootstrap.UtcOffsetMinutes'])[0])
            save('time-state.json',state)
            v.nav(g,42);v.nav(g,68)
            v.wait(g,lambda r:not r['HMI.Managed'])
            v.nav(g,4)
            v.write(g,'HMI.PollIntervalMs',str(config['points'][0]['pollIntervalMs']+1000))
            v.write(g,'GW_SavePoint',True);time.sleep(.4);v.nav(g,36)
            v.wait(g,lambda r:r['HMI.LocalChanges'])
            assert not v.read(g,['MainInstance.TelemetryAllowed'])[0]
            # Drain pre-maintenance valid data before moving the wall clock.
            v.wait(g,lambda r:r['MainInstance.QueueCount']==0,seconds=180)
            state['paused']=v.core(g)
        elif phase=='offset-zero':
            assert not before['HMI.Managed'] and before['HMI.LocalChanges']
            assert not v.read(g,['MainInstance.TelemetryAllowed'])[0]
            v.write(g,'HMI.UtcOffsetMinutes','0');v.write(g,'GW_SaveBroker',True)
            v.wait(g,lambda r:r['HMI.Connection']=='CONNECTED' and r['MainInstance.Durable.Generation']>before['MainInstance.Durable.Generation'])
            assert v.read(g,['MainInstance.Bootstrap.UtcOffsetMinutes'])[0]==0
            state['offsetZero']=v.core(g)
        elif phase=='handback':
            assert not before['HMI.Managed'] and before['HMI.LocalChanges']
            stamp=v.read(g,['MainInstance.UnixMs'])[0]/1000
            assert abs(stamp-time.time())<5,'Controller UTC/NTP has not recovered'
            assert v.read(g,['MainInstance.Bootstrap.UtcOffsetMinutes'])[0]==0
            v.nav(g,41);v.nav(g,68)
            v.wait(g,lambda r:r['HMI.Managed'] and not r['HMI.LocalChanges'])
            assert v.configuration(g)==state['config']==v.configuration(g,'Durable.HubConfig')
            state['handback']=v.core(g)
        else:
            stamp=v.read(g,['MainInstance.UnixMs'])[0]/1000
            state['read']=dict(core=before,controllerEpoch=stamp,hostEpoch=time.time(),utcOffset=v.read(g,['MainInstance.Bootstrap.UtcOffsetMinutes'])[0])
        save('time-state.json',state)
        save(phase+'.json',dict(at=time.time(),passed=True,core=v.core(g)))
        print('PASS:',phase,flush=True)

if __name__=='__main__':main()
