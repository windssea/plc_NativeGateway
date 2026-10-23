"""Owned lab fault tests. Real Hub ACKs only; all fault actions have finally rollback."""
from pathlib import Path
import sys,json,time,io,contextlib,threading,socket,subprocess,copy,math,urllib.request,collections
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tests/hmi-recovery-20261023';OUT.mkdir(exist_ok=True)
if '--final' in sys.argv:OUT=OUT/'final';OUT.mkdir(exist_ok=True)
if '--verified' in sys.argv:OUT=ROOT/'tests/hmi-recovery-20261023/verified';OUT.mkdir(exist_ok=True)
with contextlib.redirect_stdout(io.StringIO()):import probe_hmi_rsc as sdk
from PyPlcnextRsc.Arp.Device.Interface.Services import IDeviceControlService
import paho.mqtt.client as mqtt
PREFIX='Arp.Plc.Eclr/MainInstance.'
CORE=['BootId','Durable.BootCounter','Active.Version','Active.DeviceCount','Active.PointCount','Active.MessageId','Mqtt.Connected','Mqtt.SessionCount','QueueCount','Dropped','UnixMs','Mqtt.ErrorText']
HFIELDS=['ReceivedConfigs','PublishedBatches','ConfirmedBatches','InvalidAcks','DeadBatches','UiStatus','UiConnection','English']
def save(name,value):
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
def append(name,value):
    with (OUT/name).open('a',encoding='utf-8') as f:f.write(json.dumps(value,ensure_ascii=False)+'\n')
def read(service,names):
    values=[]
    for start in range(0,len(names),100):
        for r in service.Read(names[start:start+100]):
            if int(r.Error):raise RuntimeError(str(r.Error))
            values.append(r.Value.GetValue())
    return values
def snapshot(full=False):
    with sdk.Device('192.168.0.8') as d:
        g=sdk.IDataAccessService(d);v=read(g,[PREFIX+n for n in CORE]+['Arp.Plc.Eclr/HMI.'+n for n in HFIELDS]);r=dict(zip(CORE+HFIELDS,v));r['at']=time.time()
        if r['Active.DeviceCount']!=50 or r['Active.PointCount']!=250:raise RuntimeError('Expected existing 50 x 5 fixture')
        if full:
            defs=read(g,[PREFIX+f'Active.Devices[{i}].{k}' for i in range(1,51) for k in ['unitId','PointStart','PointCount','deviceId']]);rows=[]
            for u,start,n,deviceid in zip(defs[::4],defs[1::4],defs[2::4],defs[3::4]):
                rows += [(u,i,deviceid) for i in range(start,start+n)]
            vals=read(g,[PREFIX+f'{field}[{i}].{k}' for _,i,_ in rows for field,k in [('Active.Points','name'),('Active.Points','pointId'),('Samples','Value'),('Samples','Quality'),('Samples','Timestamp')]])
            samples=[]
            for j,(u,i,deviceid) in enumerate(rows):
                name,pointid,value,quality,ts=vals[j*5:j*5+5];expected=dict(voltage=230+u/10,current=(123+u)*.1,frequency=(5000+u)*.01,power=1234+u,energy=100000+u)[name]
                samples.append(dict(unit=u,index=i,deviceId=deviceid,pointId=pointid,name=name,value=value,expected=expected,quality=quality,timestamp=ts,ageMs=r['UnixMs']-ts,correct=math.isclose(value,expected,abs_tol=.0001)))
            r['samples']=samples;r['good']=sum(s['quality']=='GOOD' and s['correct'] and s['ageMs']<=20000 for s in samples);r['maxAgeMs']=max(s['ageMs'] for s in samples)
        return r
class Wire:
    def __init__(self,label):
        self.label=label;self.events=[];self.lock=threading.Lock()
        self.c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-recovery-'+label)
        self.c.on_connect=lambda c,u,f,r,p:c.subscribe('iot/v1/gateway/NG-HUB-2152-01/#',1)
        def receive(c,u,m):
            r=dict(at=time.time(),topic=m.topic,payload=m.payload.decode('utf-8','replace'),retained=m.retain)
            with self.lock:self.events.append(r)
            append(label+'-wire.jsonl',r)
        self.c.on_message=receive;self.c.reconnect_delay_set(1,3);self.c.connect_async('127.0.0.1',1883);self.c.loop_start()
    def stop(self):self.c.disconnect();self.c.loop_stop()
    def result(self,since):
        with self.lock:events=list(self.events)
        batches={};acks={};heartbeats=[];schema=[];wrong=[]
        sys.path.insert(0,str(ROOT.parent/'PLCnext-iot/src'))
        from plcnext_iot.contracts import validate_message,topic_rules
        kinds={v['suffix']:k for k,v in topic_rules().items()}
        expected={ (s['deviceId'],s['pointId']):s['expected'] for s in BASE['samples'] }
        for e in events:
            if e['at']<since or not e['payload']:continue
            p=json.loads(e['payload']);suffix=e['topic'].split('/',4)[-1]
            kind=kinds.get(suffix) if suffix in ['data','data/ack','heartbeat'] else None
            if kind:
                issues=validate_message(kind,e['payload'].encode('utf-8'),expected_gateway_id='NG-HUB-2152-01')
                if issues:schema.append(dict(at=e['at'],suffix=suffix,issues=[str(i) for i in issues]))
            if suffix=='data':
                batches.setdefault(p['messageId'],e)
                for v in p['values']:
                    if v['quality']=='GOOD' and v['value'] is not None:
                        key=(v['deviceId'],v['pointId'])
                        if key not in expected or not math.isclose(v['value'],expected[key],abs_tol=.0001):wrong.append(v)
            elif suffix=='data/ack' and p['status']=='STORED':acks[p['messageId']]=e['at']
            elif suffix=='heartbeat':heartbeats.append(e)
        stored=[e for mid,e in batches.items() if mid in acks]
        coverage={(v['deviceId'],v['pointId']) for e in stored for v in json.loads(e['payload'])['values'] if v['quality']=='GOOD' and v['timestamp']>=since*1000}
        return dict(uniqueBatches=len(batches),storedBatches=len(stored),goodStoredPointCoverage=len(coverage),firstDataAt=min((e['at'] for e in batches.values()),default=None),firstStoredAt=min((acks[mid] for mid in batches if mid in acks),default=None),heartbeatCount=len(heartbeats),schemaErrors=schema,incorrectValues=wrong)
def mock(method,body=None):
    req=urllib.request.Request('http://127.0.0.1:18080/api/v1/config',data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'},method=method)
    with urllib.request.urlopen(req,timeout=20) as r:return json.load(r)
def port_open(port):
    try:
        with socket.create_connection(('192.168.0.8',port),timeout=.8):return True
    except OSError:return False
def suspend_owned_mock():
    import ctypes
    from ctypes import wintypes
    # The target must own this test's Modbus listener; never suspend arbitrary PIDs.
    command="(Get-NetTCPConnection -LocalPort 11502 -State Listen | Select-Object -ExpandProperty OwningProcess -Unique)"
    pid=int(subprocess.check_output(['powershell','-NoProfile','-Command',command],text=True).strip())
    commandline=subprocess.check_output(['powershell','-NoProfile','-Command',f'(Get-CimInstance Win32_Process -Filter "ProcessId={pid}").CommandLine'],text=True)
    assert 'iot_sim.main serve' in commandline and 'nativegateway-soak.db' in commandline
    kernel=ctypes.WinDLL('kernel32',use_last_error=True);nt=ctypes.WinDLL('ntdll')
    kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];kernel.OpenProcess.restype=wintypes.HANDLE
    nt.NtSuspendProcess.argtypes=[wintypes.HANDLE];nt.NtResumeProcess.argtypes=[wintypes.HANDLE];kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    handle=kernel.OpenProcess(0x0800|0x1000,False,pid)
    if not handle:raise ctypes.WinError(ctypes.get_last_error())
    if nt.NtSuspendProcess(handle)!=0:kernel.CloseHandle(handle);raise RuntimeError('Could not suspend owned mock')
    save('mock-pause.json',dict(at=time.time(),pid=pid,verified='iot_sim.main serve, nativegateway-soak.db, owns port 11502'))
    def resume():
        result=nt.NtResumeProcess(handle);kernel.CloseHandle(handle)
        if result!=0:raise RuntimeError('Could not resume owned mock')
    return resume
def monitor(label,start,limit,wire,oldboot=None):
    connected=None;allgood=None;firstreachable=None;rows=[];deadline=time.time()+limit
    while time.time()<deadline:
        try:
            r=snapshot(full=True);firstreachable=firstreachable or r['at']
            if oldboot and r['BootId']==oldboot:r['waitingForNewBoot']=True
            else:
                if r['Mqtt.Connected']:connected=connected or r['at']
                if r['good']==250:allgood=allgood or r['at']
            compact={k:v for k,v in r.items() if k!='samples'};append(label+'-samples.jsonl',compact);rows.append(compact)
            proof=wire.result(start)
            if connected and allgood and proof['goodStoredPointCoverage']==250 and proof['storedBatches']>=4:
                save(label+'-final-plc.json',r)
                return dict(startAt=start,firstReachableAt=firstreachable,connectedAt=connected,all250GoodAt=allgood,elapsedSeconds=time.time()-start,final={k:v for k,v in r.items() if k!='samples'},wire=proof)
        except Exception as e:append(label+'-samples.jsonl',dict(at=time.time(),error=type(e).__name__+': '+str(e)[:180]))
        time.sleep(2)
    raise AssertionError(label+' recovery criteria not met within '+str(limit)+' seconds')
phase=sys.argv[1] if len(sys.argv)>1 else 'baseline'
ready_until=time.time()+90
while True:
    try:
        BASE=snapshot(full=True)
        if BASE['good']==250 and BASE['Mqtt.Connected']:break
    except Exception as e:append(phase+'-startup-wait.jsonl',dict(at=time.time(),waiting=type(e).__name__))
    if time.time()>=ready_until:raise AssertionError('Precondition: 250 GOOD and broker connected')
    time.sleep(3)
save(phase+'-baseline.json',BASE)
if phase=='baseline':print(json.dumps({k:v for k,v in BASE.items() if k!='samples'}));sys.exit()
wire=Wire(phase);time.sleep(3)
try:
    if phase=='blackout':
        original=mock('GET');save('mock-config-before.json',original);assert len(original['devices'])==50
        broker=subprocess.run(['docker','inspect','--format','{{.State.Running}}','mosquitto'],capture_output=True,text=True,check=True).stdout.strip();assert broker=='true'
        paused='--pause-mock' in sys.argv
        start=time.time();save('blackout-control.json',dict(startAt=start,durationSeconds=60,scope='Local Docker broker 1883 stopped; own mock process suspended without clearing registers. PLC management LAN remains connected.' if paused else 'Local Docker broker 1883 stopped and own mock Modbus listener 11502 disabled; PLC management LAN remains connected.'))
        disabled=copy.deepcopy(original);disabled['modbus']['enabled']=False
        resume=None
        try:
            if paused:resume=suspend_owned_mock()
            else:mock('PUT',disabled)
            subprocess.run(['docker','stop','--time','2','mosquitto'],check=True,capture_output=True)
            deadline=time.time()+60
            while time.time()<deadline:
                r=snapshot(full=True);save('blackout-during.json',r);append('blackout-during-samples.jsonl',{k:v for k,v in r.items() if k!='samples'});time.sleep(3)
        finally:
            try:
                if resume:resume()
                elif not paused:
                    current=mock('GET');current['modbus']['enabled']=original['modbus']['enabled'];mock('PUT',current)
            finally:subprocess.run(['docker','start','mosquitto'],check=True,capture_output=True)
        restored=time.time();save('blackout-restored.json',dict(at=restored,outageStartAt=start,outageSeconds=restored-start))
        result=monitor(phase,restored,180,wire)
        result['outageStartAt']=start;result['outageSeconds']=restored-start
        assert result['final']['BootId']==BASE['BootId'];assert result['final']['Mqtt.SessionCount']>BASE['Mqtt.SessionCount']
    elif phase=='reboot':
        probe_stop=threading.Event()
        def probe():
            while not probe_stop.is_set():
                append('reboot-reachability.jsonl',dict(at=time.time(),https443=port_open(443),rsc41100=port_open(41100)))
                probe_stop.wait(1)
        probe_thread=threading.Thread(target=probe,daemon=True);probe_thread.start()
        start=time.time();save('reboot-control.json',dict(startAt=start,operation='IDeviceControlService.RestartDevice',oldBoot=BASE['BootId'],kind='Controller OS reboot, not IEC warm restart'))
        try:
            with sdk.Device('192.168.0.8') as d:IDeviceControlService(d).RestartDevice()
        except Exception as e:append('reboot-samples.jsonl',dict(at=time.time(),restartCall=type(e).__name__,note='A reboot may close the service connection'))
        try:result=monitor(phase,start,300,wire,BASE['BootId'])
        finally:probe_stop.set();probe_thread.join(timeout=3)
        assert result['final']['BootId']!=BASE['BootId']
        assert result['final']['Durable.BootCounter']==BASE['Durable.BootCounter']+1
        assert result['final']['ReceivedConfigs']==0,'Recovery must not require a new config publication'
    else:raise ValueError(phase)
    save(phase+'-candidate-result.json',result)
    final=result['final'];assert final['Active.Version']==BASE['Active.Version']==7 and final['Active.MessageId']==BASE['Active.MessageId']
    assert final['Dropped']==BASE['Dropped']==0 and final['InvalidAcks']==0 and str(final['DeadBatches'])=='0'
    assert not result['wire']['incorrectValues'] and not result['wire']['schemaErrors']
    result['passed']=True;save(phase+'-result.json',result);print(json.dumps(result,ensure_ascii=True),flush=True)
finally:wire.stop()
