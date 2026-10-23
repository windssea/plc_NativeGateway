"""Read actual PLC point samples independently of the Hub ingestion queue."""
import json,time,math,sys
import probe_hmi_rsc as sdk
from hub_api import OUT,save
phase=sys.argv[1] if len(sys.argv)>1 else 'final'
prefix='Arp.Plc.Eclr/MainInstance.'
with sdk.Device('192.168.0.8') as device:
    service=sdk.IDataAccessService(device)
    def read(names):
        result=[]
        for start in range(0,len(names),100):
            rows=service.Read([prefix+n for n in names[start:start+100]])
            for item in rows:
                assert int(item.Error)==0,str(item)
                result.append(item.Value.GetValue())
        return result
    version,devices,points,boot=read(['Active.Version','Active.DeviceCount','Active.PointCount','BootId'])
    assert devices==50 and points==250,(version,devices,points)
    fields=[]
    for d in range(1,51):fields += [f'Active.Devices[{d}].'+f for f in ['unitId','PointStart','PointCount']]
    defs=read(fields); pointdefs=[];fields=[]
    for at in range(0,len(defs),3):
        unit,start,count=defs[at:at+3]
        for i in range(start,start+count):
            pointdefs.append((unit,i));fields += [f'Active.Points[{i}].name',f'Samples[{i}].Value',f'Samples[{i}].Quality',f'Samples[{i}].Timestamp']
    values=read(fields);unix=read(['UnixMs'])[0];result=[];bad=[]
    for n,(u,idx) in enumerate(pointdefs):
        name,value,quality,timestamp=values[n*4:n*4+4]
        expected=dict(voltage=230+u/10,current=(123+u)*.1,frequency=(5000+u)*.01,power=1234+u,energy=100000+u)[name]
        row=dict(unitId=u,index=idx,name=name,value=value,quality=quality,timestamp=timestamp,ageMs=unix-timestamp)
        result.append(row)
        if quality!='GOOD' or not math.isclose(value,expected,abs_tol=.0001) or unix-timestamp>20000:bad.append(row)
    summary=dict(at=time.time(),configVersion=version,bootId=boot,devices=devices,points=points,bad=bad,
                 maxSampleAgeMs=max(r['ageMs'] for r in result),values=result)
    save('plc-acquisition-'+phase+'.json',summary)
    print(json.dumps({k:v for k,v in summary.items() if k!='values'}),flush=True)
    assert not bad,summary
