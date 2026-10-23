import json,time
from pathlib import Path
import paho.mqtt.client as mqtt
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'soak';P='iot/v1/gateway/PLC-ENG-01/'
cfg=json.loads((ROOT/'config-capacity-v2-100.json').read_text());cfg.update(configVersion=101,messageId='backpressure-50x5-101',timestamp=int(time.time()*1000))
expected=json.loads((ROOT/'expected-50x5.json').read_text())
for p in cfg['config']['devices'][-1]['points']:
 old='soak-meter-050/'+('voltage' if p['pointId']=='point-1' else p['pointId']);expected['hmi-proof/'+p['pointId']]=expected.pop(old)
deadline=time.time()+90
while time.time()<deadline:
 hb=json.loads((OUT/'latest-heartbeat.json').read_text());h=hb['payload']
 if h['bootId']!='eng-1792718178000-12' and h['activeConfigVersion']==100 and h['points']['good']==250 and h['queue']['droppedBatches']==0:break
 time.sleep(1)
else:raise AssertionError('Final program did not recover 50x5 with zero drop counter')
rows=[];acks=[];good={};peak=0;drop=0
def connect(c,u,f,r,p):c.subscribe(P+'#',1)
def receive(c,u,m):
 global peak,drop
 try:v=json.loads(m.payload)
 except ValueError:return
 if m.topic==P+'config/ack' and v.get('messageId')==cfg['messageId']:acks.append(v)
 if m.topic==P+'heartbeat':
  peak=max(peak,v['queue']['batches']);drop=max(drop,v['queue']['droppedBatches'])
 if m.topic==P+'data' and v.get('configVersion')==101:
  rows.append(v)
  for p in v['values']:
   key=p['deviceId']+'/'+p['pointId'];e=expected.get(key)
   if e and p['quality']=='GOOD' and abs(p['value']-e['value'])<=e['tolerance']:good[key]=p
c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-backpressure-proof');c.on_connect=connect;c.on_message=receive;c.connect('127.0.0.1',1883);c.loop_start();time.sleep(.3)
(ROOT/'config-soak-101.json').write_text(json.dumps(cfg,separators=(',',':')))
sent=time.time();c.publish(P+'config/set',json.dumps(cfg,separators=(',',':')),1,True).wait_for_publish()
deadline=sent+90
while time.time()<deadline and (len(good)<250 or not acks):time.sleep(.5)
time.sleep(8)
result={'passed':len(good)==250 and drop==0 and any(a['status']=='APPLIED' for a in acks),'goodPoints':len(good),'maxQueueDuringConfig':peak,'droppedBatches':drop,'elapsedSeconds':time.time()-sent,'acks':acks,'batches':len(rows)}
(ROOT/'backpressure-results-v2.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));c.disconnect();c.loop_stop();assert result['passed'],result
