"""Real Hub publish/ingest acceptance after the NTP and row-lock fixes.

publish changes and restores isolated fixture gateway/point periods via Hub APIs.
latest/monitor are read-only. The MQTT monitor never generates business ACKs.
"""
from pathlib import Path
from copy import deepcopy
from datetime import datetime
import argparse,collections,json,math,sys,threading,time,urllib.parse,uuid
import paho.mqtt.client as mqtt
from hub_api import HubApi

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests/time-locking-20261023'
OUT.mkdir(exist_ok=True)
fixture=json.loads((ROOT/'tests/hub-runtime/fixture.json').read_text(encoding='utf-8'))
assert fixture['gatewayId']=='NG-HUB-2152-01' and fixture['prefix']=='ng-2152-20261023'
GW=fixture['gatewayId'];PARENT=fixture['parentId'];BASE='/api/device/'+PARENT
sys.path.insert(0,str(ROOT.parent/'PLCnext-iot/src'))
from plcnext_iot.contracts import topic_rules,validate_message

def save(name,value):
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def expected():
    config=json.loads((OUT/'time-state.json').read_text(encoding='utf-8'))['config']
    result={}
    for d in config['devices']:
        u=d['unitId'];numbers=dict(voltage=230+u/10,current=(123+u)*.1,
            frequency=(5000+u)*.01,power=1234+u,energy=100000+u)
        for i in range(d['PointStart']-1,d['PointStart']-1+d['PointCount']):
            p=config['points'][i];result[d['deviceId'],p['pointId']]=numbers[p['name']]
    assert len(result)==250
    return result

def release(api,ids,gateway_only,label):
    q=urllib.parse.urlencode([('deviceIds',i) for i in ids]+[('gatewayOnly',str(gateway_only).lower())])
    preview=api.api('GET',BASE+'/iot-config/device-releases/preview?'+q)
    assert not preview.get('issues'),preview
    command=dict(expectedRevision=preview['draftRevision'],requestId='ntp-lock-'+uuid.uuid4().hex,
                 deviceIds=ids,gatewayOnly=gateway_only)
    save(label+'-request.json',command)
    start=time.monotonic()
    value=api.api('POST',BASE+'/iot-config/device-releases',command)
    save(label+'-release.json',value)
    while time.monotonic()-start<120:
        value=api.api('GET',BASE+'/iot-config/releases/'+str(value['id']))
        if value['status'] in ('APPLIED','REJECTED','FAILED','TIMEOUT'):break
        time.sleep(.5)
    save(label+'-result.json',value)
    assert value['status']=='APPLIED',value
    result=dict(label=label,version=value['configVersion'],messageId=value['messageId'],
                status=value['status'],elapsedSeconds=round(time.monotonic()-start,3))
    print(json.dumps(result),flush=True)
    return result

def publish(api):
    policy=api.api('GET',BASE+'/iot-gateway')
    assert policy['devicePatchSupported'] and not policy['configDrift']
    original=dict(brokerId=policy['brokerId'],gatewayId=GW,enabled=policy['enabled'],report=policy['report'])
    child=fixture['children']['1'];detail=api.api('GET','/api/device/'+child)
    assert detail['deviceCode'].startswith(fixture['prefix'])
    save('original-policy.json',original);save('original-child-001.json',detail)
    results=[]
    for label,interval in [('batch-change',original['report']['batchIntervalMs']+100),
                           ('batch-restore',original['report']['batchIntervalMs'])]:
        revision=api.api('GET',BASE+'/iot-gateway')['draftRevision']
        request=deepcopy(original);request['expectedRevision']=revision;request['report']['batchIntervalMs']=interval
        api.api('PUT',BASE+'/iot-gateway',request)
        results.append(release(api,[],True,label))
        time.sleep(2)
    keys=['id','deviceName','deviceCode','typeCode','modelId','parentId','managementStatus','dataCollection','connection','iot','variables']
    for label,extra in [('point-change',1000),('point-restore',0)]:
        request={k:deepcopy(detail[k]) for k in keys}
        request['expectedRevision']=api.api('GET',BASE+'/iot-gateway')['draftRevision']
        for field in ['pollIntervalMs','reportIntervalMs']:
            request['variables'][0]['iot'][field]=detail['variables'][0]['iot'][field]+extra
        api.api('PUT','/api/device',request)
        results.append(release(api,[child],False,label))
        time.sleep(2)
    policy=api.api('GET',BASE+'/iot-gateway')
    assert policy['report']==original['report'] and not policy['draftDirty'] and not policy['configDrift']
    result=dict(at=time.time(),passed=True,releases=results,finalVersion=results[-1]['version'])
    save('publishes.json',result)

def latest(api):
    version=api.api('GET',BASE+'/iot-gateway')['activeConfigVersion']
    out={};ages=[]
    for unit,child in fixture['children'].items():
        rows=api.api('GET','/api/device/data/'+child+'/latest')
        rows=[r for r in rows if r['configVersion']==version]
        assert len(rows)==5,(unit,len(rows))
        u=int(unit);numbers=dict(voltage=230+u/10,current=(123+u)*.1,frequency=(5000+u)*.01,power=1234+u,energy=100000+u)
        for r in rows:
            assert r['qualityCode']=='GOOD' and math.isclose(r['value'],numbers[r['variableName']],abs_tol=.0001),r
            assert r['sourceGatewayId']==GW
            age=time.time()-datetime.fromisoformat(r['sampledAt'].replace('Z','+00:00')).timestamp()
            assert -5<=age<=25,(unit,age)
            ages.append(age)
        out[unit]=rows
    save('latest-values.json',out)
    result=dict(at=time.time(),passed=True,devices=len(out),points=len(ages),version=version,
        minAgeSeconds=round(min(ages),3),maxAgeSeconds=round(max(ages),3),
        bootPrefixes=sorted({r['sourceMessageId'].rsplit('-',1)[0] for rows in out.values() for r in rows}))
    save('latest-summary.json',result);print(json.dumps(result),flush=True)

def monitor(api,seconds):
    exp=expected();kinds={v['suffix']:k for k,v in topic_rules().items()}
    lock=threading.RLock();counts=collections.Counter();errors=[];batches={};stored=set();points={};latencies=[];heartbeats=[]
    start=time.time();boot=None;session=None;subscribed=threading.Event()
    def incoming(c,u,m):
        nonlocal boot,session
        at=time.time();suffix=m.topic.split('/',4)[-1]
        if not m.payload or m.retain:return
        with lock:
            try:
                p=json.loads(m.payload)
                if suffix in kinds:
                    issues=validate_message(kinds[suffix],m.payload,expected_gateway_id=GW)
                    if issues:errors.append(dict(at=at,kind='schema',topic=m.topic,issues=[str(x) for x in issues]))
                counts[suffix]+=1
                if suffix=='heartbeat':
                    if boot is not None and (boot!=p['bootId'] or session!=p['sessionId']):errors.append(dict(at=at,kind='unexpected-session-change'))
                    boot=p['bootId'];session=p['sessionId'];heartbeats.append((at,p['timestamp']/1000))
                    if p['queue']['droppedBatches']!=0:errors.append(dict(at=at,kind='dropped-batches'))
                    if p['points']['good']!=250 or p['points']['bad']!=0:errors.append(dict(at=at,kind='bad-heartbeat-points',points=p['points']))
                    if abs(p['timestamp']/1000-at)>5:errors.append(dict(at=at,kind='clock-offset'))
                elif suffix=='data':
                    mid=p['messageId'];batches.setdefault(mid,dict(at=at,payload=p))
                    for v in p['values']:
                        key=v['deviceId'],v['pointId']
                        if key not in exp or v['quality']!='GOOD' or v['value'] is None or not math.isclose(v['value'],exp[key],abs_tol=.0001):errors.append(dict(at=at,kind='incorrect-value',value=v))
                        points[key]=at
                elif suffix=='data/ack':
                    if p['status']!='STORED':errors.append(dict(at=at,kind='non-stored-ack',status=p['status']))
                    elif p['messageId'] in batches and p['messageId'] not in stored:
                        stored.add(p['messageId']);latencies.append(at-batches[p['messageId']]['at'])
                with (OUT/'monitor-wire.jsonl').open('a',encoding='utf-8') as f:
                    f.write(json.dumps(dict(at=at,topic=m.topic,payload=p),ensure_ascii=False)+'\n')
            except Exception as e:errors.append(dict(at=at,kind=type(e).__name__,message=str(e)[:250]))
    client=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-time-locking-readonly')
    client.on_connect=lambda c,u,f,r,p:c.subscribe('iot/v1/gateway/'+GW+'/#',1)
    client.on_subscribe=lambda *args:subscribed.set()
    client.on_message=incoming;client.connect('127.0.0.1',1883);client.loop_start()
    assert subscribed.wait(10)
    snapshots=[];ntp=[]
    try:
        while time.time()-start<seconds:
            at=time.time();call=time.monotonic()
            try:
                diag=api.api('GET','/api/device/iot-diagnostics')
                state=api.api('GET','/api/device/state/batch?ids='+PARENT)[PARENT]['iot']
                hb_age=time.time()-datetime.fromisoformat(state['lastHeartbeatAt'].replace('Z','+00:00')).timestamp()
                assert state['agentStatus']=='ONLINE' and hb_age<45,state
                snap=dict(at=at,hubHeartbeatAgeSeconds=round(hb_age,3),apiSeconds=round(time.monotonic()-call,3),diagnostics=diag)
                snapshots.append(snap)
                with (OUT/'hub-samples.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(snap)+'\n')
            except Exception as e:
                with lock:errors.append(dict(at=at,kind='hub-projection',error=str(e)[:400]))
            with lock:
                if at-start>30:
                    stale=[list(k) for k in exp if at-points.get(k,0)>20]
                    if stale:errors.append(dict(at=at,kind='point-coverage-stale',count=len(stale)))
                    if not heartbeats or at-heartbeats[-1][0]>40:errors.append(dict(at=at,kind='heartbeat-stale'))
                status=dict(at=at,elapsedSeconds=round(at-start,1),counts=dict(counts),coverage=len(points),storedBatches=len(stored),errors=errors[-30:])
                save('monitor-status.json',status)
            time.sleep(min(10,max(0,start+seconds-time.time())))
    finally:client.disconnect();client.loop_stop()
    with lock:
        coverage={(v['deviceId'],v['pointId']) for mid in stored for v in batches[mid]['payload']['values']}
        latencies.sort()
        result=dict(at=time.time(),requestedSeconds=seconds,actualSeconds=round(time.time()-start,2),counts=dict(counts),
            storedBatches=len(stored),storedValues=sum(len(batches[mid]['payload']['values']) for mid in stored),
            storedGoodCoverage=len(coverage),heartbeatCount=len(heartbeats),
            heartbeatMaxGapSeconds=max((b[0]-a[0] for a,b in zip(heartbeats,heartbeats[1:])),default=0),
            clockMinOffsetSeconds=min((h[1]-h[0] for h in heartbeats),default=None),clockMaxOffsetSeconds=max((h[1]-h[0] for h in heartbeats),default=None),
            ackP95Seconds=latencies[min(len(latencies)-1,int(len(latencies)*.95))] if latencies else None,
            ackMaxSeconds=max(latencies,default=None),hubSamples=len(snapshots),
            hubMaxHeartbeatAgeSeconds=max((s['hubHeartbeatAgeSeconds'] for s in snapshots),default=None),
            hubMaxApiSeconds=max((s['apiSeconds'] for s in snapshots),default=None),
            bootId=boot,sessionId=session,errors=errors,passed=not errors and coverage==set(exp) and len(heartbeats)>=seconds//35)
        save('monitor-results.json',result)
    print(json.dumps(result),flush=True)
    assert result['passed'],result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('phase',choices=['publish','latest','monitor']);parser.add_argument('--seconds',type=int,default=1200)
    args=parser.parse_args();api=HubApi(read_timeout=30).login()
    {'publish':lambda:publish(api),'latest':lambda:latest(api),'monitor':lambda:monitor(api,args.seconds)}[args.phase]()
