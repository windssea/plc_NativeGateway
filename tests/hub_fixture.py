"""Prepare dedicated Hub test assets using existing authenticated APIs only."""
from pathlib import Path
from copy import deepcopy
import json,sys,time
from hub_api import HubApi,OUT,save

api=HubApi().login()
state_file=OUT/'fixture.json'
state=json.loads(state_file.read_text(encoding='utf-8')) if state_file.exists() else {
    'gatewayId':'NG-HUB-2152-01','prefix':'ng-2152-20261023','children':{},'createdAt':time.time()}
def checkpoint():save('fixture.json',state)
if 'brokerId' not in state:
    brokers=api.api('GET','/api/system/mqtt-broker/listAll')
    owned=[b for b in brokers if b.get('name')==state['prefix']+' broker']
    if not owned:
        # Existing Local MQTT is the user-authorized Docker 1883 broker. Reuse
        # its binding without changing this shared broker row or its credentials.
        owned=[b for b in brokers if str(b.get('id'))=='1' and b.get('host') in ('localhost','127.0.0.1') and b.get('port')==1883]
    if owned:state['brokerId']=str(owned[0]['id'])
    else:
        api.api('POST','/api/system/mqtt-broker',dict(name=state['prefix']+' broker',host='127.0.0.1',port=1883,
             username='',password='',tlsEnabled=False,clientIdPrefix='hub-ng-2152',keepAlive=30,cleanSession=True,
             reconnectMaxAttempts=0,reconnectIntervalMs=3000,status=1))
        owned=[b for b in api.api('GET','/api/system/mqtt-broker/listAll') if b.get('name')==state['prefix']+' broker']
        assert len(owned)==1;state['brokerId']=str(owned[0]['id'])
    checkpoint()
if 'parentId' not in state:
    rows=api.api('GET','/api/device/listAll')
    own=[r for r in rows if r.get('deviceCode')==state['prefix']+'-gateway']
    if own:state['parentId']=str(own[0]['id'])
    else:state['parentId']=str(api.api('POST','/api/device',dict(deviceName='NativeGateway 2152 Hub 实测',
       deviceCode=state['prefix']+'-gateway',typeCode='IOT_GATEWAY',parentId='0',managementStatus='ENABLED',variables=[])))
    checkpoint()
parent=state['parentId']
binding=api.api('GET',f'/api/device/{parent}/iot-gateway')
if not binding or binding.get('gatewayId')!=state['gatewayId']:
    binding=api.api('PUT',f'/api/device/{parent}/iot-gateway',dict(brokerId=state['brokerId'],gatewayId=state['gatewayId'],
               enabled=True,expectedRevision=0,report=dict(batchIntervalMs=1000,maxBatchPoints=32)))
    save('initial-binding.json',binding)
points=json.loads((OUT.parent/'config-soak-104.json').read_text(encoding='utf-8-sig'))['config']['devices'][0]['points']
target_count=int(sys.argv[1]) if len(sys.argv)>1 else 2
for unit in range(1,target_count+1):
    key=str(unit)
    if key in state['children']:continue
    revision=api.api('GET',f'/api/device/{parent}/iot-gateway')['draftRevision']
    variables=[]
    for p in points:
        wire=deepcopy(p)
        var=dict(varName=p['pointId'],dataType=p['dataType'],unit=p.get('unit'),collected=True,
                 scaleFactor=p['scale'],offsetVal=p['offset'])
        var['iot']={k:p[k] for k in ['pointId','dataType','pollIntervalMs','reportMode','reportIntervalMs','deadband','staleAfterMs','modbus']}
        variables.append(var)
    code=state.get('replacementCodes',{}).get(key,state['prefix']+f'-meter-{unit:03}')
    body=dict(deviceName=f'Native mock meter {unit:03}',deviceCode=code,
              typeCode='METER',parentId=parent,managementStatus='ENABLED',expectedRevision=revision,
              dataCollection=dict(enabled=True,mode='REMOTE'),connection=dict(protocol='iot'),
              iot=dict(southboundProtocol='modbus_tcp',connection=dict(host='192.168.0.5',port=11502,unitId=unit,
                       connectTimeoutMs=5000,requestTimeoutMs=1500,retryCount=0)),variables=variables)
    # Recover an ambiguous create using the unique code, before issuing a new request.
    rows=api.api('GET','/api/device/listAll')
    own=[r for r in rows if r.get('deviceCode')==body['deviceCode']]
    child=str(own[0]['id']) if own else str(api.api('POST','/api/device',body))
    state['children'][key]=child;checkpoint()
    save(f'child-{unit:03}.json',api.api('GET','/api/device/'+child))
    print(json.dumps({'createdUnit':unit,'childId':child}),flush=True)
save('binding-after-drafts.json',api.api('GET',f'/api/device/{parent}/iot-gateway'))
print(json.dumps({'gatewayId':state['gatewayId'],'parentId':parent,'brokerId':state['brokerId'],'children':len(state['children'])}))
