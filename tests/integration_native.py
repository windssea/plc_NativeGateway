"""Exercise the real IEC gateway over Docker MQTT, using mock Modbus only."""
import copy
import json
from pathlib import Path
import sys
import threading
import time
import paho.mqtt.client as mqtt

sys.path.insert(0, r'D:\work\code\PLCnext-iot\src')
from plcnext_iot.contracts import validate_message, topic_rules

ROOT=Path(__file__).resolve().parent
PREFIX='iot/v1/gateway/PLC-ENG-01/'
messages=[]
condition=threading.Condition()
results=[]
def connected(client, userdata, flags, reason, properties):
    client.subscribe(PREFIX+'#',qos=1)
def received(client, userdata, msg):
    try: payload=json.loads(msg.payload)
    except ValueError:return
    with condition:
        messages.append((time.time(),msg.topic,payload,msg.payload))
        condition.notify_all()
def wait_for(predicate, after, timeout=60):
    end=time.monotonic()+timeout
    with condition:
        while True:
            for item in messages:
                if item[0]>=after and predicate(item):return item
            remaining=end-time.monotonic()
            if remaining<=0:raise AssertionError('Timed out waiting for real PLC response')
            condition.wait(min(remaining,1))
def check_data(version, current):
    def predicate(item):
        if item[1]!=PREFIX+'data' or item[2].get('configVersion')!=version:return False
        values={v['pointId']:v for v in item[2]['values']}
        return all(p in values and values[p]['quality']=='GOOD' and abs(values[p]['value']-v)<1e-6 for p,v in [('voltage',230.5),('current',current)])
    return predicate
def send(name,suffix,payload,status,active,error=None,retained=False):
    raw=json.dumps(payload,separators=(',',':')).encode()
    sent=time.time()
    client.publish(PREFIX+suffix,raw,qos=1,retain=retained).wait_for_publish()
    ack=wait_for(lambda i:i[1]==PREFIX+suffix.replace('/set','')+'/ack' and i[2].get('messageId')==payload['messageId'],sent)[2]
    assert ack['status']==status,ack
    assert ack['activeConfigVersion']==active,ack
    if error:assert any(e['code']==error for e in ack['errors']),ack
    results.append({'test':name,'passed':True,'ack':ack})
    print(name,json.dumps(ack),flush=True)
    return sent

client=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-integration')
client.on_connect=connected;client.on_message=received
client.connect('127.0.0.1',1883);client.loop_start()
try:
    baseline=json.loads((ROOT/'config-set.json').read_text())
    first=wait_for(check_data(1,12.3),time.time())
    results.append({'test':'native_modbus_initial','passed':True,'data':first[2]})
    device=copy.deepcopy(baseline['config']['devices'][0]);device['points'][1]['offset']=1
    patch={'schemaVersion':1,'gatewayId':'PLC-ENG-01','timestamp':int(time.time()*1000),'messageId':'native-test-patch-2','configVersion':2,'baseConfigVersion':1,'baseMessageId':'native-test-set-1','operations':[{'op':'replace','deviceId':device['deviceId'],'device':device}]}
    (ROOT/'config-patch-2.json').write_text(json.dumps(patch,indent=2))
    sent=send('patch_applied','config/patch',patch,'APPLIED',2)
    changed=wait_for(check_data(2,13.3),sent)
    results.append({'test':'patch_changes_real_collection','passed':True,'data':changed[2]})
    send('duplicate_patch_idempotent','config/patch',patch,'APPLIED',2)
    badbase=copy.deepcopy(patch);badbase.update(messageId='native-test-bad-base',configVersion=3)
    send('wrong_base_rejected','config/patch',badbase,'REJECTED',2,'BASE_CONFIG_MISMATCH')
    invalid=copy.deepcopy(baseline);invalid.update(messageId='native-test-invalid-address',configVersion=3,timestamp=int(time.time()*1000))
    invalid['config']['devices'][0]['points'][0]['modbus']['address']=65535
    sent=send('invalid_address_rejected','config/set',invalid,'REJECTED',2)
    assert results[-1]['ack']['errors'],results[-1]
    wait_for(check_data(2,13.3),sent)
    restored=copy.deepcopy(baseline);restored.update(messageId='native-test-set-3',configVersion=3,timestamp=int(time.time()*1000))
    (ROOT/'config-set-3.json').write_text(json.dumps(restored,indent=2))
    sent=send('full_set_restore','config/set',restored,'APPLIED',3,retained=True)
    final=wait_for(check_data(3,12.3),sent)
    results.append({'test':'restored_collection','passed':True,'data':final[2]})
    by_suffix={v['suffix']:k for k,v in topic_rules().items()}
    issues=[]
    for at,topic,payload,raw in messages:
        suffix=topic.removeprefix(PREFIX)
        if suffix in by_suffix and topic_rules()[by_suffix[suffix]]['direction']=='from_agent':
            found=validate_message(by_suffix[suffix],raw,expected_gateway_id='PLC-ENG-01')
            if found:issues.append({'topic':topic,'messageId':payload.get('messageId'),'issues':[vars(i) for i in found]})
    results.append({'test':'reference_contract_validation','passed':not issues,'messageCount':len(messages),'issues':issues})
finally:
    (ROOT/'integration-results.json').write_text(json.dumps(results,indent=2,ensure_ascii=False))
    client.disconnect();client.loop_stop()
print(json.dumps(results[-1],indent=2),flush=True)
