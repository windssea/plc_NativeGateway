"""Validate HMI presentation and command guards without changing saved config."""
from pathlib import Path
import json,time,io,contextlib
with contextlib.redirect_stdout(io.StringIO()):import probe_hmi_rsc as sdk
from PyPlcnextRsc.common.serviceDefinition.all_needed import RscType
OUT=Path(__file__).resolve().parent/'hmi-recovery-20261023/final'
with sdk.Device('192.168.0.8') as d:
    g=sdk.IDataAccessService(d)
    def read(field):
        r=g.ReadSingle('Arp.Plc.Eclr/HMI.'+field);assert int(r.Error)==0;return r.Value.GetValue()
    def nav(n):
        assert int(g.WriteSingle(sdk.WriteItem('Arp.Plc.Eclr/GW_Nav',sdk.RscVariant(n,RscType.Int16))))==0
        time.sleep(.4)
    before={f:read(f) for f in ['GatewayId','ActiveVersion','TotalPoints','ManagementMode']};assert before['ActiveVersion']=='7'
    nav(31);zh={f:read(f) for f in ['UiConnection','DeviceRow1','PointRow1','UiConfigSource','UiPersistence']}
    assert '站号' in zh['DeviceRow1'] and '采集' in zh['PointRow1'] and '\n' in zh['PointRow1']
    assert '平台' in zh['UiConfigSource'] and '自动恢复' in zh['UiPersistence']
    nav(32);en={f:read(f) for f in zh};assert 'Unit' in en['DeviceRow1'] and 'Poll' in en['PointRow1'] and 'Managed by Hub' in en['UiConfigSource']
    nav(3);assert read('View')==1
    nav(4);assert read('View')==2
    nav(59);assert read('View')==8
    nav(2);assert read('View')==3
    nav(57);assert read('View')==7
    nav(2);assert read('View')==3
    blocked=[]
    for cmd in ['GW_SaveDevice','GW_SavePoint','GW_Apply']:
        assert int(g.WriteSingle(sdk.WriteItem('Arp.Plc.Eclr/'+cmd,sdk.RscVariant.of(True))))==0;time.sleep(.3)
        after={f:read(f) for f in before};assert after==before
        assert 'Hub' in read('Status');blocked.append(cmd)
    nav(31);nav(1)
    result=dict(at=time.time(),before=before,chinese=zh,english=en,hubGuardedCommands=blocked,passed=True,notes='Read-only pages and review navigation tested; no config republish or persistence changes.')
    (OUT/'ui-workflow.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS: bilingual rows, line breaks, ownership guidance, details/help/review navigation and Hub write guard.')
