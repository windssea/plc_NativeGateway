"""Independent, low-frequency read-only HMI endpoint availability recorder."""
import http.client,json,socket,time
from pathlib import Path
out=Path(__file__).resolve().parent/'soak'
while True:
 row={'receivedAt':time.time(),'host':'192.168.0.8'}
 for port in [80,443]:
  try:
   with socket.create_connection(('192.168.0.8',port),timeout=2):pass
   row['tcp'+str(port)]=True
  except OSError as e:row['tcp'+str(port)]=False;row['error'+str(port)]=type(e).__name__
 try:
  conn=http.client.HTTPConnection('192.168.0.8',80,timeout=2);conn.request('HEAD','/ehmi/hmiapp.html');r=conn.getresponse();row['http80Status']=r.status;row['redirectLocation']=r.getheader('Location');conn.close()
 except OSError as e:row['http80Error']=type(e).__name__
 with (out/'web-availability.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(row)+'\n')
 temp=out/'web-availability.tmp';temp.write_text(json.dumps(row));temp.replace(out/'web-availability.json')
 time.sleep(15)
