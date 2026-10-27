"""Package pure P03/P04 IEC assertions; no network or PLC operation."""
from pathlib import Path
import argparse
import zipfile
import re
from build_phase1_capture_test import build, ROOT

KEEP={'Main','NG_Capture','NG_GapLog','NG_SafeAdd','NG_ReportPolicy',
      'NG_BufferMaintenance','NG_BatchBuilder','NG_Delivery','NG_EndBatch',
      'NG_FreeRecord','NG_PruneTerminal','NG_StringSHA256',
      'NG_Quote','NG_QualityName','NG_SourceState','NG_SourceResult','NG_QualityCode',
      'NG_AuditCapture','NG_AuditDecision','NG_AuditAssociation'}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--parallel-delivery',action='store_true',help='P06 candidate: same assertions with independent ACK/send hash state')
    parser.add_argument('--slice-assertions',action='store_true',help='Test-only hold after value preparation to fence expiry/reuse and gate cancellation')
    parser.add_argument('--cost-benchmark',action='store_true',help='Run the fixed cost fixture after assertions, reusing buffers; diagnostic only')
    args=parser.parse_args()
    source=ROOT/'tests/phase1_pipeline_test.st'
    keep=set(KEEP)
    if args.parallel_delivery:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        source=args.output.parent/'phase1_pipeline_parallel_test.st'
        source.write_text((ROOT/'tests/phase1_pipeline_test.st').read_text(encoding='utf-8').replace(
            'Delivery : NG_Delivery;','Delivery : NG_DeliveryParallel;'),encoding='utf-8')
        keep.add('NG_DeliveryParallel')
    if args.slice_assertions:
        text=source.read_text(encoding='utf-8')
        extension=(ROOT/'tests/phase1_pipeline_slice_checks.st').read_text(encoding='utf-8')
        assert text.count('106:\n    Done:=TRUE;')==1
        text=text.replace('106:\n    Done:=TRUE;','106:\n    Stage:=110;\n'+extension)
        source=args.output.parent/'phase1_pipeline_slice_test.st'
        source.write_text(text,encoding='utf-8')
    build(args.output.resolve(),source,keep)
    if args.slice_assertions:
        # Only the no-I/O test copy exposes a deterministic pause. Production
        # interfaces and controller DATA/ACK traffic never contain this hook.
        with zipfile.ZipFile(args.output) as z:files={n:z.read(n) for n in z.namelist()}
        prefix='PROJECT/Logical%20Elements/NG_BatchBuilder.pou/'
        variables=files[prefix+'Variables.var'].decode().replace('VAR_INPUT\n','VAR_INPUT\n    SliceTestHold : BOOL;\n',1).replace('VAR_OUTPUT\n','VAR_OUTPUT\n    SliceTestPending : BOOL;\n',1)
        code=files[prefix+'Code.st'].decode();marker='        IF ItemPhase=1 THEN\n'
        assert code.count(marker)==1
        code='SliceTestPending:=FALSE;\n'+code.replace(marker,'        IF (ItemPhase=1) AND SliceTestHold THEN SliceTestPending:=TRUE; RETURN; END_IF;\n'+marker,1)
        files[prefix+'Variables.var']=variables.encode();files[prefix+'Code.st']=code.encode()
        with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED) as z:
            for n,data in files.items():z.writestr(n,data)
    if args.cost_benchmark:
        from build_phase1_pipeline_benchmark import SOURCE
        from build_phase1_batch_trace import instrument_fb
        with zipfile.ZipFile(args.output) as z:files={n:z.read(n) for n in z.namelist()}
        instrument_fb(files,'NG_BatchBuilder',True)
        instrument_fb(files,'NG_Delivery',False)
        declaration=re.search(r'VAR\n(.*?)END_VAR',SOURCE,re.S).group(1)
        code=SOURCE.split('END_VAR',1)[1].rsplit('END_PROGRAM',1)[0].strip()+'\n'
        shared={'Buffer','EmptyBuffer','Packets','EmptyPacket','Builder','Sequence','Tick','i'}
        names=re.findall(r'^    (\w+)\s*:',declaration,re.M)
        for name in names:
            if name in shared:
                declaration=re.sub(r'^    '+name+r'\s*:.*\n','',declaration,flags=re.M)
            else:
                declaration=re.sub(r'\b'+name+r'\b','Cost'+name,declaration)
                code=re.sub(r'\b'+name+r'\b','Cost'+name,code)
        prefix='PROJECT/Logical%20Elements/Main.pou/'
        variables=re.sub(r'^VAR\n',lambda m:'VAR\n'+declaration,files[prefix+'Variables.var'].decode(),count=1)
        assert 'CostDone : BOOL;' in variables
        original=files[prefix+'Code.st'].decode();marker='IF Done THEN RETURN; END_IF;'
        assert original.count(marker)==1
        original=original.replace(marker,'IF Done THEN\n'+code+'\nRETURN;\nEND_IF;',1)
        files[prefix+'Variables.var']=variables.encode();files[prefix+'Code.st']=original.encode()
        with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED) as z:
            for n,data in files.items():z.writestr(n,data)
