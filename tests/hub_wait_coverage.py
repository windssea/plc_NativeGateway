"""Wait for every point to appear in a real Hub-STORED MQTT batch."""
import json,time,sys,collections
from hub_api import HubApi,OUT,save
phase=sys.argv[1] if len(sys.argv)>1 else 'capacity-50'
state=json.loads((OUT/'fixture.json').read_text())
release_file='release-gateway-64-result.json' if phase.startswith('final-64') else 'release-capacity-50-result.json'
release=json.loads((OUT/release_file).read_text());assert release['status']=='APPLIED'
version=release['configVersion'];expected={'d-'+v for v in state['children'].values()}
assert len(expected)==50
cutoff=0;boot=None
if phase!='capacity-50':
    cutoff=json.loads((OUT/'backend-process.json').read_text())['startedAt']
    boot=json.loads((OUT/'latest-NG-HUB-2152-01-heartbeat.json').read_text())['payload']['bootId']
    if phase.startswith('final-64'):assert json.loads((OUT/'latest-NG-HUB-2152-01-heartbeat.json').read_text())['payload']['agentVersion']=='native-0.3.1'
    assert boot!=json.loads((OUT/'before-final-download.json').read_text())['heartbeat']['payload']['bootId']
data={};acks=set();latest={};start=time.time();deadline=start+240;last=0
with (OUT/'wire.jsonl').open(encoding='utf8') as stream:
    while time.time()<deadline:
        for line in stream:
            record=json.loads(line)
            if not record['topic'].startswith('iot/v1/gateway/NG-HUB-2152-01/'):continue
            if not record['payload']:continue
            p=json.loads(record['payload'])
            if record['topic'].endswith('/data') and p['configVersion']==version and p['timestamp']>=cutoff*1000 and (boot is None or p['bootId']==boot):
                data[p['messageId']]=(record['receivedAt'],p)
            elif record['topic'].endswith('/data/ack') and p['status']=='STORED' and record['receivedAt']>=cutoff:acks.add(p['messageId'])
        for mid in data.keys() & acks:
            at,p=data[mid]
            for v in p['values']:
                key=(v['deviceId'],v['pointId'])
                if key not in latest or v['timestamp']>latest[key]['timestamp']:latest[key]=v
        counts=collections.Counter(v['deviceId'] for v in latest.values() if v['quality']=='GOOD')
        good=sum(counts.values())
        if time.time()>last+10:
            print('Real Hub STORED coverage',version,len(counts),good,flush=True);last=time.time()
        if set(counts)==expected and all(n==5 for n in counts.values()):
            result=dict(at=time.time(),version=version,devices=len(counts),goodPoints=good,waitSeconds=time.time()-start,cutoff=cutoff,bootId=boot,
                        storedBatches=len(data.keys() & acks),counts=dict(counts),values=list(latest.values()))
            save('stored-coverage-'+phase+'.json',result);print('PASS: 50 devices / 250 GOOD points covered by real STORED.',flush=True);break
        time.sleep(1)
    else:raise AssertionError('Missing real Hub STORED coverage')
