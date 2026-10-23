"""Seed an isolated mock DB through its API and emit the reference MQTT config."""
import json,time,urllib.request,sys
from pathlib import Path
sys.path.insert(0,r'D:\work\code\PLCnext-iot\src')
from plcnext_iot.contracts import validate_message
ROOT=Path(__file__).resolve().parent
def request(path,payload=None):
    data=None if payload is None else json.dumps(payload).encode()
    req=urllib.request.Request('http://127.0.0.1:18080'+path,data=data,method='GET' if data is None else 'PUT',headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=30) as response:return json.load(response)
current=request('/api/v1/config')
config=current.get('config',current)
config['devices']=[]
gateway=[];expected={}
for unit in range(1,51):
    specs=[('voltage','float32','input_register',0,230+unit/10,1,'V'),('current','uint16','holding_register',10,123+unit,0.1,'A'),('frequency','uint16','holding_register',11,5000+unit,0.01,'Hz'),('power','float32','input_register',2,1234+unit,1,'W'),('energy','uint32','holding_register',20,100000+unit,1,'kWh')]
    signals=[];points=[];device_id=f'soak-meter-{unit:03}'
    for point_id,kind,area,address,raw,scale,unit_name in specs:
        signals.append({'id':point_id,'name':point_id,'unit':unit_name,'value_type':kind,'generator':{'type':'random_range','min':raw,'max':raw,'precision':3},'binding':{'type':'modbus','table':area,'address':address,'wire_type':kind,'byte_order':'big','word_order':'big'}})
        points.append({'pointId':point_id,'name':point_id,'enabled':True,'dataType':kind,'pollIntervalMs':5000,'scale':scale,'offset':0,'unit':unit_name,'reportMode':'cyclic','reportIntervalMs':5000,'deadband':0,'staleAfterMs':20000,'modbus':{'area':area,'address':address,'byteOrder':'AB' if kind=='uint16' else 'ABCD'}})
        expected[device_id+'/'+point_id]={'value':raw*scale,'tolerance':0.001,'unitId':unit}
    config['devices'].append({'id':f'mock-meter-{unit:03}','name':f'Soak Meter {unit:03}','protocol':'modbus','protocol_config':{'unit_id':unit},'enabled':True,'desired_state':'running','default_interval_ms':1000,'signals':signals})
    gateway.append({'deviceId':device_id,'name':f'Soak Meter {unit:03}','enabled':True,'protocol':'modbus_tcp','connection':{'host':'192.168.0.5','port':11502,'unitId':unit,'connectTimeoutMs':5000,'requestTimeoutMs':1500,'retryCount':0},'points':points})
result=request('/api/v1/config',config)
payload={'schemaVersion':1,'gatewayId':'PLC-ENG-01','timestamp':int(time.time()*1000),'messageId':'capacity-50x5-100','configVersion':100,'config':{'enabled':True,'report':{'batchIntervalMs':1000,'maxBatchPoints':32},'devices':gateway}}
raw=json.dumps(payload,separators=(',',':')).encode()
issues=validate_message('configSet',raw,expected_gateway_id='PLC-ENG-01');assert not issues,issues
assert len(raw)<=131071
(ROOT/'config-50x5.json').write_bytes(raw)
(ROOT/'expected-50x5.json').write_text(json.dumps(expected,indent=2))
(ROOT/'mock-50x5-config.json').write_text(json.dumps(config,indent=2))
print(json.dumps({'mockApply':result,'devices':len(gateway),'points':len(expected),'payloadBytes':len(raw)},ensure_ascii=False)[:1600])
