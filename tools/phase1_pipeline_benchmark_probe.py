"""Read-only capture of the no-I/O benchmark; no runtime writes."""
import argparse
import contextlib
import io
import json
from pathlib import Path
from phase1_plc_probe import Device, IDataAccessService

FIELDS=['BuildOtherUs','BuildHashUs','SendHashUs','AckHashUs','SendOtherUs',
        'AckOtherUs','MaxCallUs','BuildScans','SendScans','AckScans','Bytes','Calls']

def read(output,prefix=''):
    with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
        with Device('192.168.0.8') as device:
            service=IDataAccessService(device)
            names=['Stage','Sample','Done','Passed']+[f'{n}[{i}]' for n in FIELDS for i in range(1,17)]
            result={}
            for start in range(0,len(names),50):
                chunk=names[start:start+50]
                rows=list(service.Read(['Arp.Plc.Eclr/MainInstance.'+prefix+n for n in chunk]))
                assert len(rows)==len(chunk) and not any(int(r.Error) for r in rows),'Benchmark fields unavailable'
                result.update({n:r.Value.GetValue() for n,r in zip(chunk,rows)})
    result['scope']='NO_IO_SYNTHETIC_PRIVATE_ACK_DIAGNOSTIC_NOT_REAL_HUB_OR_P06'
    # Preserve negative evidence before assertions stop the probe.
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    if result['Done']:
        assert result['Passed'] and result['Sample']==17,'Native benchmark failed'
        result['profiles']={}
        for label,indices in [('fixed8blocks',range(1,17,2)),('deadline825us',range(2,17,2))]:
            samples=[{n:result[f'{n}[{i}]'] for n in FIELDS} for i in indices]
            assert all(s['Bytes']==15244 and min(s['BuildHashUs'],s['SendHashUs'],s['AckHashUs'])>0 for s in samples)
            result['profiles'][label]={'samples':samples,'mean':{n:sum(s[n] for s in samples)/len(samples) for n in FIELDS}}
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if '[' not in k and k!='profiles'}))
    if result.get('profiles'):print(json.dumps({k:v['mean'] for k,v in result['profiles'].items()}))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);p.add_argument('--prefix',default='',choices=('','Cost'));a=p.parse_args();read(a.output,a.prefix)
