import json,sys,time
from pathlib import Path
import paho.mqtt.client as mqtt
ROOT=Path(__file__).resolve().parent
path=Path(sys.argv[1]); payload=json.loads(path.read_text()); payload['timestamp']=int(time.time()*1000)
client=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-config-test')
client.connect('127.0.0.1',1883);client.loop_start()
suffix='config/patch' if 'operations' in payload else 'config/set'
client.publish('iot/v1/gateway/PLC-ENG-01/'+suffix,json.dumps(payload,separators=(',',':')),1,'--retain' in sys.argv).wait_for_publish()
client.disconnect();client.loop_stop();print(payload['messageId'],payload['configVersion'])
