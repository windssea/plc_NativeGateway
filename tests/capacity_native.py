import copy,json,sys,threading,time
from pathlib import Path
import paho.mqtt.client as mqtt
sys.path.insert(0,r'D:\work\code\PLCnext-iot\src')
from plcnext_iot.contracts import validate_message
ROOT=Path(__file__).resolve().parent
P='iot/v1/gateway/PLC-ENG-01/'
rows=[];cv=threading.Condition();results=[]
def connected(c,u,f,r,p):c.subscribe(P+'#',1)
def received(c,u,m):
    try:payload=json.loads(m.payload)
    except ValueError:return
    with cv:rows.append((time.time(),m.topic,payload));cv.notify_all()
def wait(predicate,after,timeout=60):
    end=time.monotonic()+timeout
    with cv:
        while True:
            for row in rows:
                if row[0]>=after and predicate(row):return row
            remaining=end-time.monotonic()
            if remaining<=0:raise AssertionError('PLC timeout')
            cv.wait(min(remaining,1))
def publish(payload,retain=False):
    issues=validate_message('configSet',json.dumps(payload).encode(),expected_gateway_id='PLC-ENG-01')
    assert not issues,issues
    sent=time.time();c.publish(P+'config/set',json.dumps(payload,separators=(',',':')),1,retain).wait_for_publish()
    ack=wait(lambda r:r[1]==P+'config/ack' and r[2].get('messageId')==payload['messageId'],sent)[2]
    assert ack['status']=='APPLIED',ack
    results.append({'test':'set_'+str(payload['configVersion']),'passed':True,'ack':ack})
    print('Applied',payload['configVersion'],flush=True)
    return sent
c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-capacity');c.on_connect=connected;c.on_message=received
c.connect('127.0.0.1',1883);c.loop_start()
baseline=json.loads((ROOT/'config-set.json').read_text())
try:
    # HMI commit v4 must survive the program update before the retained v3 can
    # be rejected as stale. This also proves HMI changes reach MQTT data.
    hmi=wait(lambda r:r[1]==P+'data' and r[2].get('configVersion')==4 and any(v['pointId']=='current' and v['quality']=='GOOD' and abs(v['value']-14.3)<1e-6 for v in r[2]['values']),time.time())
    results.append({'test':'hmi_commit_and_restart_recovery','passed':True,'data':hmi[2]})
    config=copy.deepcopy(baseline);config.update(configVersion=5,messageId='native-test-capacity-5',timestamp=int(time.time()*1000))
    first=config['config']['devices'][0]
    for n in range(3,33):
        point=copy.deepcopy(first['points'][1]);point.update(pointId=f'current-{n:02}',name=f'Current {n:02}')
        first['points'].append(point)
    second=copy.deepcopy(baseline['config']['devices'][0]);second['deviceId']='native-meter-02';second['name']='Second logical meter'
    config['config']['devices'].append(second);config['config']['report']['maxBatchPoints']=32
    (ROOT/'config-capacity-5.json').write_text(json.dumps(config,indent=2))
    sent=publish(config)
    expected={(d['deviceId'],p['pointId']) for d in config['config']['devices'] for p in d['points']}
    good={};end=time.monotonic()+25
    while time.monotonic()<end:
        with cv:
            data=[r for r in rows if r[0]>=sent and r[1]==P+'data' and r[2].get('configVersion')==5]
        for _,_,payload in data:
            assert len(payload['values'])<=32
            issues=validate_message('data',json.dumps(payload).encode(),expected_gateway_id='PLC-ENG-01');assert not issues,issues
            for value in payload['values']:
                if value['quality']=='GOOD':good[(value['deviceId'],value['pointId'])]=value
        if set(good)==expected:break
        with cv:cv.wait(0.5)
    assert set(good)==expected,{'missing':sorted(expected-set(good))}
    results.append({'test':'two_devices_34_points_split_batches','passed':True,'goodPoints':len(good),'dataBatches':len(data),'maxBatchValues':max(len(r[2]['values']) for r in data),'samples':list(good.values())})
    print('All 34 points GOOD',flush=True)
finally:
    final=copy.deepcopy(baseline);final.update(configVersion=6,messageId='native-test-set-6',timestamp=int(time.time()*1000))
    (ROOT/'config-final.json').write_text(json.dumps(final,indent=2))
    try:
        sent=publish(final,True)
        def baseline_data(r):
            if r[1]!=P+'data' or r[2].get('configVersion')!=6:return False
            values={v['pointId']:v for v in r[2]['values']}
            return all(p in values and values[p]['quality']=='GOOD' and abs(values[p]['value']-expected)<1e-6 for p,expected in [('voltage',230.5),('current',12.3)])
        restored=wait(baseline_data,sent)
        results.append({'test':'final_baseline_restored','passed':True,'data':restored[2]})
    finally:
        (ROOT/'capacity-results.json').write_text(json.dumps(results,indent=2))
        c.disconnect();c.loop_stop()
