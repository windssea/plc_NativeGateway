"""Clear only this isolated gateway's test config, to prove local reboot recovery."""
import paho.mqtt.client as mqtt
c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='nativegateway-persistence-proof');c.connect('127.0.0.1',1883);c.loop_start()
c.publish('iot/v1/gateway/PLC-ENG-01/config/set',b'',1,True).wait_for_publish()
c.disconnect();c.loop_stop();print('Cleared isolated retained config/set; backup is config-soak-101.json')
