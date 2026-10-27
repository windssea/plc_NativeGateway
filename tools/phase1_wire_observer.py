"""Read-only bounded MQTT wire evidence. Never publishes or fabricates ACKs."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import paho.mqtt.client as mqtt

def observe(output, seconds, stop_file=None):
    rows=[]
    client=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='p03-wire-observer',protocol=mqtt.MQTTv311)
    def connected(c, userdata, flags, reason_code, properties):
        if reason_code==0:
            c.subscribe([('iot/v1/gateway/NG-HUB-2152-01/data',1),('iot/v1/gateway/NG-HUB-2152-01/data/ack',1)])
    def message(c, userdata, msg):
        if len(rows)>=4000:
            return
        raw=bytes(msg.payload)
        rows.append(dict(observedUtcMs=int(time.time()*1000),topic=msg.topic,retained=bool(msg.retain),
                         sha256=hashlib.sha256(raw).hexdigest(),payload=raw.decode('utf-8')))
    client.on_connect=connected
    client.on_message=message
    client.connect('192.168.0.5',1883,30)
    started=time.monotonic(); deadline=started+seconds
    while time.monotonic()<deadline:
        client.loop(timeout=.25)
        if stop_file and stop_file.exists(): break
    client.disconnect()
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(dict(evidenceLevel='PASSIVE_REAL_MQTT_WIRE',requestedSeconds=seconds,durationSeconds=time.monotonic()-started,
        rowLimit=4000,truncated=len(rows)>=4000,rows=rows),ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(dict(output=str(output),rows=len(rows))))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--seconds',type=int,default=90,choices=range(1,3601))
    parser.add_argument('--stop-file',type=Path)
    args=parser.parse_args()
    observe(args.output,args.seconds,args.stop_file)
