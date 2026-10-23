"""Read-only verification that all 50 device projections use the new boot."""
from pathlib import Path
import sys,json,time,math
from datetime import datetime
from hub_api import HubApi
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tests/hmi-recovery-20261023/verified'
fixture=json.loads((ROOT/'tests/hub-runtime/fixture.json').read_text(encoding='utf-8'));reboot=json.loads((OUT/'reboot-result.json').read_text(encoding='utf-8'));boot=reboot['final']['BootId']
api=HubApi().login();start=time.time();result={};raw_result={};wrong=[];ages=[];historical=0
for unit,child in fixture['children'].items():
    u=int(unit);raw=api.api('GET','/api/device/data/'+child+'/latest');raw_result[unit]=raw
    rows=[r for r in raw if r['configVersion']==7];historical+=len(raw)-len(rows);result[unit]=rows
    expected=dict(voltage=230+u/10,current=(123+u)*.1,frequency=(5000+u)*.01,power=1234+u,energy=100000+u)
    if len(rows)!=5:wrong.append(dict(unit=u,reason='point count',count=len(rows)))
    for r in rows:
        good=r['qualityCode']=='GOOD' and r['value'] is not None and math.isclose(r['value'],expected[r['variableName']],abs_tol=.0001)
        current=r['configVersion']==7 and r['sourceMessageId'].startswith('d-'+boot+'-') and r['sourceGatewayId']=='NG-HUB-2152-01'
        if not(good and current):wrong.append(dict(unit=u,row=r))
        ages.append(time.time()-datetime.fromisoformat(r['sampledAt'].replace('Z','+00:00')).timestamp())
(OUT/'hub-latest-after-reboot.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'hub-latest-after-reboot-raw.json').write_text(json.dumps(raw_result,ensure_ascii=False,indent=2),encoding='utf-8')
summary=dict(at=time.time(),durationSeconds=time.time()-start,bootId=boot,devices=len(result),points=sum(map(len,result.values())),historicalRowsExcluded=historical,incorrect=wrong,minAgeSeconds=min(ages),maxAgeSeconds=max(ages),passed=not wrong)
(OUT/'hub-latest-verification.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(summary,ensure_ascii=True));assert not wrong
