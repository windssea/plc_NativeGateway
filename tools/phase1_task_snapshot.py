"""Read-only ESM task duration and typed RSC structure probe."""
import contextlib,io,json,argparse,time
from pathlib import Path
from phase1_plc_probe import Device,IDataAccessService

def snapshot():
    result={}
    with Device('192.168.0.8') as device:
        service=IDataAccessService(device)
        for core in [1,2]:
            for task in [1,2]:
                prefix=f'Arp.Plc.Eclr/ESM_DATA.ESM_INFOS[{core}].TASK_INFOS[{task}].'
                for field in ['INTERVAL','LAST_EXEC_DURATION','MIN_EXEC_DURATION','MAX_EXEC_DURATION','EXEC_TIME_THRESHOLD','EXEC_TIME_THRESHOLD_CNT']:
                    row=service.ReadSingle(prefix+field)
                    result[prefix+field]=row.Value.GetValue() if int(row.Error)==0 else {'error':int(row.Error)}
        row=service.ReadSingle('Arp.Plc.Eclr/MainInstance.Samples[1]')
        result['sampleStructure']=row.Value.GetValue() if int(row.Error)==0 else {'error':int(row.Error)}
        row=service.ReadSingle('Arp.Plc.Eclr/MainInstance.BootId')
        result['bootId']=row.Value.GetValue() if int(row.Error)==0 else {'error':int(row.Error)}
    result['atUtc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    result['evidenceScope']='CURRENT_RUNTIME_LIFETIME_TASK_INFO_NOT_CANDIDATE_INCREMENTAL_TIMING'
    return result

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument('output',type=Path); args=ap.parse_args()
    with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()): result=snapshot()
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8'); print(json.dumps(result,ensure_ascii=False))
