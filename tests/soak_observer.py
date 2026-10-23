"""Bounded test-side recorder + durable-wire STORED adapter. No PLC gateway logic."""
import collections, csv, ctypes, datetime, json, math, os, sys, time
from pathlib import Path
import paho.mqtt.client as mqtt
sys.path.insert(0, r'D:\work\code\PLCnext-iot\src')
from plcnext_iot.contracts import validate_message

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'soak'; OUT.mkdir(exist_ok=True)
PREFIX='iot/v1/gateway/PLC-ENG-01/'
expected_path=ROOT/'expected-soak-101.json'
if len(sys.argv)>1:expected_path=Path(sys.argv[1])
EXPECTED=json.loads((expected_path if expected_path.exists() else ROOT/'expected-50x5.json').read_text())
KINDS={'heartbeat':'heartbeat','data':'data','config/ack':'configAck','config/patch/ack':'configPatchAck','config/get':'configGet','status':'status'}
last={}; point_times={}; seen=collections.OrderedDict(); counters=collections.Counter(); errors=collections.deque(maxlen=40)
state={'pid':os.getpid(),'recorderStartedAt':time.time(),'mode':'preflight'}
trace_index=0; trace=None; last_write=0; last_minute=0; control_start=None
aggregate={}; disconnects=0; previous_boot=None; previous_session=None; final_written=False; resource_at=0

def atomic(path, data):
    tmp=path.with_suffix('.tmp'); tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8'); tmp.replace(path)

def wire(record):
    global trace,trace_index
    if trace is None or trace.tell()>=64*1024*1024:
        if trace: trace.close()
        while (OUT/f'wire-{trace_index:03}.jsonl').exists(): trace_index+=1
        trace=(OUT/f'wire-{trace_index:03}.jsonl').open('a',encoding='utf-8')
    trace.write(json.dumps(record,ensure_ascii=False,separators=(',',':'))+'\n'); trace.flush()

def connected(c,u,f,r,p):
    state['brokerConnected']=not r.is_failure; state['brokerConnectedAt']=time.time(); c.subscribe(PREFIX+'#',1)

def disconnected(c,u,f,r,p):
    global disconnects
    disconnects+=1; state['brokerConnected']=False; state['disconnects']=disconnects

def received(c,u,m):
    global previous_boot,previous_session
    now=time.time(); suffix=m.topic[len(PREFIX):]; raw=m.payload.decode('utf-8',errors='replace')
    wire({'receivedAt':now,'topic':m.topic,'retained':m.retain,'payload':raw})
    try: payload=json.loads(raw)
    except ValueError:
        if raw: counters['invalidJson']+=1; errors.append({'at':now,'topic':suffix,'error':'invalid JSON'})
        return
    kind=KINDS.get(suffix)
    issues=validate_message(kind,m.payload,expected_gateway_id='PLC-ENG-01') if kind else []
    if issues:
        counters['schemaErrors']+=1; errors.append({'at':now,'topic':suffix,'issues':[vars(i) for i in issues]}); return
    if suffix in KINDS or suffix=='diagnostics/resources':
        last[suffix]={'at':now,'payload':payload}; atomic(OUT/('latest-'+suffix.replace('/','-')+'.json'),last[suffix])
    if suffix=='data':
        # Contract-valid bytes have been flushed to a local wire log before ACK.
        os.fsync(trace.fileno())
        ack={'schemaVersion':1,'gatewayId':'PLC-ENG-01','timestamp':int(now*1000),'messageId':payload['messageId'],'status':'STORED','errors':[]}
        c.publish(PREFIX+'data/ack',json.dumps(ack,separators=(',',':')),1)
        if state['mode']=='completed':return
        cfg=state.get('configuration',{})
        if state['mode']=='running' and payload.get('configVersion')!=cfg.get('configVersion'):
            counters['unexpectedConfigBatches']+=1
        key=payload['messageId']
        if key in seen: counters['duplicateBatches']+=1; return
        seen[key]=True
        if len(seen)>4096: seen.popitem(last=False)
        counters['uniqueBatches']+=1; counters['values']+=len(payload['values'])
        for v in payload['values']:
            key=v['deviceId']+'/'+v['pointId']; counters['quality_'+v['quality']]+=1
            if key in EXPECTED:
                e=EXPECTED[key]; value=v.get('value')
                correct=v['quality']=='GOOD' and isinstance(value,(int,float)) and math.isfinite(value) and abs(value-e['value'])<=e['tolerance']
                if not correct: counters['incorrectValues']+=1; errors.append({'at':now,'point':key,'sample':v})
                previous=point_times.get(key)
                if previous: aggregate['maxPointGapSeconds']=max(aggregate.get('maxPointGapSeconds',0),now-previous)
                point_times[key]=now
    elif suffix=='heartbeat' and state['mode']!='completed':
        boot=payload.get('bootId'); session=payload.get('sessionId')
        if previous_boot and boot!=previous_boot:counters['bootChanges']+=1
        if previous_session and session!=previous_session:counters['sessionChanges']+=1
        previous_boot=boot;previous_session=session
        q=payload.get('queue',{})
        aggregate['maxQueueBatches']=max(aggregate.get('maxQueueBatches',0),q.get('batches',0))
        aggregate['maxDroppedBatches']=max(aggregate.get('maxDroppedBatches',0),q.get('droppedBatches',0))
    elif suffix=='diagnostics/resources':
        with (OUT/'resources.csv').open('a',newline='',encoding='utf-8') as f:
            w=csv.writer(f)
            if f.tell()==0:w.writerow(['receivedAt','bootId','uptimeMs','memoryValid','cpuValid','processValid','totalKiB','availableKiB','rssKiB','cpuPercent','processName','devices','points','error'])
            w.writerow([now]+[payload.get(k) for k in ['bootId','uptimeMs','memoryValid','cpuValid','processValid','totalKiB','availableKiB','rssKiB','cpuPercent','processName','devices','points','error']])
        for field in ['availableKiB','rssKiB','cpuPercent']:
            val=payload.get(field)
            if isinstance(val,(int,float)):
                aggregate[field+'Min']=min(aggregate.get(field+'Min',val),val); aggregate[field+'Max']=max(aggregate.get(field+'Max',val),val)

def update():
    global last_write,last_minute,control_start,counters,aggregate,point_times,final_written,resource_at
    now=time.time()
    if now-last_write<2:return
    last_write=now
    control=OUT/'control.json'
    if control.exists():
        cfg=json.loads(control.read_text())
        if cfg.get('startAt')!=control_start:
            control_start=cfg['startAt']; counters=collections.Counter(); aggregate={}; point_times={}; errors.clear()
            state.update(mode='running',startAt=control_start,endAt=control_start+cfg.get('durationSeconds',28800),configuration=cfg)
    if state['mode']=='running' and now>=state['endAt']:
        state['mode']='completed'; state['completedAt']=now
    hb=last.get('heartbeat',{}); resource=last.get('diagnostics/resources',{})
    controller=None
    try:controller=json.loads((OUT/'controller-resources.json').read_text())
    except (OSError,ValueError):pass
    if controller and controller['receivedAt']!=resource_at and state['mode']!='completed':
        resource_at=controller['receivedAt']
        for field in ['cpuPercent','memoryUsagePercent','actualMemoryPercent','iecProgramPercent','iecDataPercent','temperatureC']:
            val=controller.get(field)
            if isinstance(val,(int,float)):
                aggregate[field+'Min']=min(aggregate.get(field+'Min',val),val); aggregate[field+'Max']=max(aggregate.get(field+'Max',val),val)
    ages=[now-point_times[k] for k in EXPECTED if k in point_times]
    summary={**state,'updatedAt':now,'elapsedSeconds':now-control_start if control_start else None,'counters':dict(counters),'aggregate':aggregate,'expectedPoints':250,'coveredPoints':len(point_times),'pointsSeenLast20s':sum(now-t<20 for t in point_times.values()),'maxCurrentPointAgeSeconds':max(ages) if ages else None,'heartbeatAgeSeconds':now-hb['at'] if hb else None,'controllerResourcesAgeSeconds':now-controller['receivedAt'] if controller else None,'controllerResources':controller,'heartbeat':hb.get('payload'),'recentErrors':list(errors)}
    atomic(OUT/'summary.json',summary)
    if state['mode']=='completed' and not final_written:
        atomic(OUT/'final-summary.json',summary);final_written=True
    if now-last_minute>=60:
        last_minute=now
        with (OUT/'minute-summary.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(summary,ensure_ascii=False,separators=(',',':'))+'\n')

if os.name=='nt': ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
client=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-soak-recorder')
client.on_connect=connected;client.on_disconnect=disconnected;client.on_message=received
client.connect('127.0.0.1',1883)
try:
    while True:
        client.loop(timeout=1); update()
except KeyboardInterrupt: pass
finally:
    if trace:trace.close()
    if os.name=='nt':ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
