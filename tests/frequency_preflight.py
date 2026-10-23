import json,time,collections
from pathlib import Path
import paho.mqtt.client as mqtt
ROOT=Path(__file__).resolve().parent; OUT=ROOT/'soak'; P='iot/v1/gateway/PLC-ENG-01/'
rows=[];acks=[]
def connect(c,u,f,r,p):c.subscribe(P+'#',1)
def receive(c,u,m):
 try:v=json.loads(m.payload)
 except ValueError:return
 if m.topic==P+'data' and any(p['deviceId']=='hmi-proof' for p in v['values']):rows.append((time.time(),v))
 if m.topic==P+'config/patch/ack':acks.append(v)
c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-period-proof');c.on_connect=connect;c.on_message=receive;c.connect('127.0.0.1',1883);c.loop_start()
start=time.time();time.sleep(12)
baseline=[t for t,p in rows if p['configVersion']==7]
active=json.loads((OUT/'latest-config-get.json').read_text())['payload']
device=json.loads((ROOT/'config-50x5.json').read_text())['config']['devices'][-1]
device['deviceId']='hmi-proof';device['name']='HMI Proof Device';point=device['points'][0];point.update(pointId='point-1',name='Point 1',pollIntervalMs=1000,reportIntervalMs=1000,unit='');device['points']=[point]
patch={'schemaVersion':1,'gatewayId':'PLC-ENG-01','timestamp':int(time.time()*1000),'messageId':'hmi-period-proof-8','configVersion':8,'baseConfigVersion':7,'baseMessageId':active['activeMessageId'],'operations':[{'op':'replace','deviceId':'hmi-proof','device':device}]}
(ROOT/'frequency-patch-8.json').write_text(json.dumps(patch,indent=2))
c.publish(P+'config/patch',json.dumps(patch,separators=(',',':')),1).wait_for_publish()
end=time.monotonic()+45
while not acks and time.monotonic()<end:time.sleep(.2)
assert acks and acks[-1]['status']=='APPLIED',acks
time.sleep(15);fast=[t for t,p in rows if p['configVersion']==8]
result={'baselineWindowSeconds':12,'baseline5sBatches':len(baseline),'patchedWindowSeconds':15,'patched1sBatches':len(fast),'ack':acks[-1],'passed':len(baseline)>=2 and len(fast)>=9}
(ROOT/'frequency-results-v2.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));c.disconnect();c.loop_stop()
