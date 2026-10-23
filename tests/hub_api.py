"""Hub dev API helper. Credentials and access tokens stay in memory."""
from pathlib import Path
import json,re,urllib.request,urllib.error
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests/hub-runtime'
class HubApi:
    def __init__(self,read_timeout=45):self.token=None;self.read_timeout=read_timeout
    def request(self,method,path,body=None):
        headers={'Content-Type':'application/json'}
        if self.token:headers['Authorization']='Bearer '+self.token
        raw=None if body is None else json.dumps(body,ensure_ascii=False).encode('utf-8')
        req=urllib.request.Request('http://127.0.0.1:8080'+path,raw,headers,method=method)
        try:
            slow=(method=='POST' and '/device-releases' in path) or (method=='PUT' and path.endswith('/iot-gateway'))
            with urllib.request.urlopen(req,timeout=max(180,self.read_timeout) if slow else self.read_timeout) as r:value=json.load(r)
        except urllib.error.HTTPError as e:
            try:value=json.loads(e.read())
            except ValueError:raise RuntimeError('HTTP '+str(e.code)) from None
        if value.get('code')!=200:raise RuntimeError('Hub API '+method+' '+path+': '+str(value.get('message') or value.get('msg') or value.get('code'))[:300])
        return value.get('data')
    def login(self):
        skill=(ROOT.parent/'PLCnext-Hub-Backend/.agents/skills/hub-dev-test/SKILL.md').read_text(encoding='utf-8')
        password=re.search(r'- Password: `([^`]+)`',skill).group(1)
        value=self.request('POST','/api/auth/login',dict(username='admin',password=password,rememberMe=False))
        self.token=value['accessToken'];return self
    def api(self,method,path,body=None):
        if not self.token:self.login()
        return self.request(method,path,body)
def save(name,value):
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':
    api=HubApi().login()
    brokers=api.api('GET','/api/system/mqtt-broker/listAll')
    print(json.dumps({'login':True,'brokers':[dict(id=b.get('id'),name=b.get('name'),host=b.get('host'),port=b.get('port')) for b in brokers]},ensure_ascii=False))
