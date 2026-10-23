import json,time,threading
from pathlib import Path
import paho.mqtt.client as mqtt
ROOT=Path(__file__).resolve().parent;P='iot/v1/gateway/PLC-ENG-01/'
cfg=json.loads((ROOT/'config-50x5.json').read_text());expected=json.loads((ROOT/'expected-50x5.json').read_text())
# Keep the HMI-created temporary device selected and available for delete testing.
device=cfg['config']['devices'][-1];device['deviceId']='hmi-proof';device['name']='HMI Proof Device';device['points'][0]['pointId']='point-1'
for p in device['points']:
 old='soak-meter-050/'+('voltage' if p['pointId']=='point-1' else p['pointId']);expected['hmi-proof/'+p['pointId']]=expected.pop(old)
cfg['messageId']='capacity-50x5-hmi-100';cfg['timestamp']=int(time.time()*1000)
(ROOT/'config-capacity-v2-100.json').write_text(json.dumps(cfg,separators=(',',':')))
good={};acks=[];batches=0;errors=[];hb={};last_at=time.time()
def connect(c,u,f,r,p):c.subscribe(P+'#',1)
def receive(c,u,m):
 global batches,hb,last_at
 try:v=json.loads(m.payload)
 except ValueError:return
 if m.topic==P+'config/ack' and v.get('messageId')==cfg['messageId']:acks.append(v)
 if m.topic==P+'heartbeat':hb=v
 if m.topic==P+'data' and v.get('configVersion')==100:
  batches+=1
  for p in v['values']:
   key=p['deviceId']+'/'+p['pointId']
   if p['quality']=='GOOD' and key in expected and abs(p['value']-expected[key]['value'])<=expected[key]['tolerance']:good[key]=p
   elif p['quality'] not in ['UNKNOWN']:errors.append(p)
c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-capacity-v2');c.on_connect=connect;c.on_message=receive;c.connect('127.0.0.1',1883);c.loop_start();time.sleep(.3)
sent=time.time();c.publish(P+'config/set',json.dumps(cfg,separators=(',',':')),1,True).wait_for_publish()
deadline=sent+100
while time.time()<deadline and len(good)<250:time.sleep(.5)
result={'passed':len(good)==250 and not errors and any(a['status']=='APPLIED' for a in acks),'devices':50,'expectedPoints':250,'goodPoints':len(good),'batches':batches,'elapsedSeconds':time.time()-sent,'ack':acks,'missing':sorted(set(expected)-set(good)),'errors':errors[:30],'heartbeat':hb,'samples':good}
(ROOT/'capacity-results-v2.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k not in ['samples','heartbeat']}));c.disconnect();c.loop_stop()
assert result['passed'], '50 x 5 capacity verification failed'
