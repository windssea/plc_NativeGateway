"""Test-side broker observer; no collection or gateway logic runs here."""
import json
import time
from pathlib import Path
import paho.mqtt.client as mqtt

ROOT = Path(__file__).resolve().parent
PREFIX = 'iot/v1/gateway/PLC-ENG-01/'
TRACE = ROOT / 'mqtt-trace.jsonl'

def connected(client, userdata, flags, reason, properties):
    print('broker connected', reason, flush=True)
    client.subscribe(PREFIX+'#', qos=1)

def received(client, userdata, message):
    raw=message.payload.decode('utf-8', errors='replace')
    record={'receivedAt':time.time(), 'topic':message.topic, 'retained':message.retain, 'payload':raw}
    with TRACE.open('a',encoding='utf-8') as stream:
        stream.write(json.dumps(record,ensure_ascii=False)+'\n')
        stream.flush()
    print(message.topic, raw[:1600], flush=True)
    if message.topic==PREFIX+'data':
        try:
            payload=json.loads(raw)
            ack={'schemaVersion':1,'gatewayId':'PLC-ENG-01','timestamp':int(time.time()*1000),'messageId':payload['messageId'],'status':'STORED','errors':[]}
            client.publish(PREFIX+'data/ack',json.dumps(ack,separators=(',',':')),qos=1)
        except (ValueError, KeyError):
            print('Invalid data payload; no acknowledgement sent',flush=True)

client=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='nativegateway-test-observer')
client.on_connect=connected
client.on_message=received
client.connect('127.0.0.1',1883)
client.loop_forever()
