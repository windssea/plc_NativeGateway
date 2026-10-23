"""Read-only MQTT evidence recorder. Never sends a business data ACK."""
from pathlib import Path
import json,time,os,sys,collections
import paho.mqtt.client as mqtt
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'PLCnext-iot/src'))
from plcnext_iot.contracts import topic_rules,validate_message
out=Path(__file__).resolve().parent/'hub-runtime'
out.mkdir(exist_ok=True)
kinds={v['suffix']:k for k,v in topic_rules().items()}
counts=collections.Counter(); errors=collections.deque(maxlen=30); last={}
def connected(c,u,f,r,p):
    for gateway in ['PLC-ENG-01','NG-HUB-2152-01']:
        c.subscribe('iot/v1/gateway/'+gateway+'/#',1)
def received(c,u,m):
    at=time.time(); record=dict(receivedAt=at,topic=m.topic,retained=m.retain,payload=m.payload.decode('utf-8','replace'))
    with (out/'wire.jsonl').open('a',encoding='utf-8') as f: f.write(json.dumps(record,ensure_ascii=False)+'\n')
    suffix=m.topic.split('/',4)[-1]; gw=m.topic.split('/')[3]
    if not m.payload:return
    try:value=json.loads(m.payload)
    except ValueError:errors.append(dict(at=at,topic=m.topic,error='INVALID_JSON'));return
    issues=validate_message(kinds[suffix],m.payload,expected_gateway_id=gw) if suffix in kinds else []
    if issues:errors.append(dict(at=at,topic=m.topic,issues=[vars(x) for x in issues]))
    counts[gw+'/'+suffix]+=1;last[gw+'/'+suffix]=dict(at=at,payload=value)
    target=out/('latest-'+gw+'-'+suffix.replace('/','-')+'.json')
    tmp=target.with_suffix('.tmp');tmp.write_text(json.dumps(last[gw+'/'+suffix],ensure_ascii=False,indent=2),encoding='utf-8');tmp.replace(target)
client=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-hub-readonly-observer')
client.on_connect=connected;client.on_message=received;client.connect('127.0.0.1',1883)
reconnect_at=0
while True:
    client.loop(timeout=1)
    if not client.is_connected() and time.time()>=reconnect_at:
        reconnect_at=time.time()+3
        try:client.reconnect()
        except OSError:pass
    value=dict(updatedAt=time.time(),pid=os.getpid(),mode='read-only-no-business-ack',counts=dict(counts),errors=list(errors))
    tmp=out/'observer.tmp';tmp.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8');tmp.replace(out/'observer.json')
