"""Add a bounded, diagnostic-only batch lifecycle trace to a performance overlay.

Never connects to a controller. Instrumentation perturbs timing and is ineligible
for the frozen <=1ms acceptance. Production POUs and the 64-value limit are untouched.
Completed rows use a seqlock; late SDK completions are separate correlated events.
"""
import argparse
from pathlib import Path
import re
import zipfile


TYPES = dict(Id='NG_Id', Generation='UDINT', Count='UINT', Bytes='UDINT',
             BuildBeginUs='ULINT', JsonDoneUs='ULINT', BuildDoneUs='ULINT',
             FirstSubmitUs='ULINT', LastSubmitUs='ULINT', SdkDoneUs='ULINT',
             AckRxUs='ULINT', AckParsedUs='ULINT', SendHashDoneUs='ULINT',
             AckHashDoneUs='ULINT', ReleaseUs='ULINT', BuilderOtherUs='ULINT',
             BuilderHashUs='ULINT', SendHashUs='ULINT', AckHashUs='ULINT',
             DeliveryOtherUs='ULINT', Attempts='UDINT', Slot='UINT', Kind='USINT', Ordinal='ULINT')


def replace_once(text, old, new):
    assert text.count(old) == 1, old[:120]
    return text.replace(old, new, 1)


def instrument_fb(files, name, builder):
    prefix=f'PROJECT/Logical%20Elements/{name}.pou/'
    variables=files[prefix+'Variables.var'].decode('utf-8-sig')
    common='''    P06TraceSlot : UINT;
    P06TraceGeneration : UDINT;
    P06TraceOtherUs : ULINT;
    P06TraceHashUs : ULINT;
'''
    extra=('''    P06TraceActive : BOOL;
    P06TraceJsonDoneUs : ULINT;
''' if builder else '''    P06TraceHashOp : UINT;
    P06TraceHashDoneUs : ULINT;
    P06TraceStored : BOOL;
''')
    variables=replace_once(variables, 'VAR_OUTPUT\n', 'VAR_OUTPUT\n'+common+extra)
    variables=replace_once(variables, '\nVAR\n', '\nVAR\n    P06TraceStartUs : ULINT;\n    P06TraceHashStartUs : ULINT;\n')
    code=files[prefix+'Code.st'].decode('utf-8-sig')
    if builder:
        begin='P06TraceActive:=Stage<>0; P06TraceHashUs:=0; P06TraceStartUs:=GET_MICROSECONDS(TRUE);\n'
        code=replace_once(code, 'first:=FALSE; Stage:=10; Busy:=TRUE;', 'first:=FALSE; Stage:=10; Busy:=TRUE; P06TraceActive:=TRUE; P06TraceJsonDoneUs:=0;')
        marker="Packets[Slot].Length:=TO_UDINT(LEN(Packets[Slot].Payload)); Stage:=2;"
        code=replace_once(code,marker,marker+' P06TraceJsonDoneUs:=GET_MICROSECONDS(TRUE);')
    else:
        begin='P06TraceSlot:=0; P06TraceHashOp:=0; P06TraceHashUs:=0; P06TraceHashDoneUs:=0; P06TraceStored:=FALSE; P06TraceStartUs:=GET_MICROSECONDS(TRUE);\n'
        code=replace_once(code, '    Digest(Execute:=TRUE,', '    P06TraceSlot:=slot; P06TraceGeneration:=generation; P06TraceHashOp:=op;\n    Digest(Execute:=TRUE,')
        code=replace_once(code, '    IF Digest.Done THEN', '    IF Digest.Done THEN\n        P06TraceHashDoneUs:=GET_MICROSECONDS(TRUE);')
        marker='ELSE EndBatch(Slot:=slot,Outcome:=USINT#1,Reason:=USINT#0,NowMs:=NowMs,Buffer:=Buffer,Packets:=Packets); END_IF;'
        code=replace_once(code,marker,marker.replace(' END_IF;', ' P06TraceStored:=Buffer.BatchOwners[slot].State=0; END_IF;'))
    pattern=re.compile(r'^[ \t]*Digest\(Execute:=TRUE,.*?;\n',re.M)
    code,n=pattern.subn(lambda m:'P06TraceHashStartUs:=GET_MICROSECONDS(TRUE);\n'+m[0]+'P06TraceHashUs:=GET_MICROSECONDS(TRUE)-P06TraceHashStartUs;\n',code)
    assert n==1
    finish=('P06TraceSlot:=Slot; P06TraceGeneration:=generation; ' if builder else '')+'P06TraceOtherUs:=GET_MICROSECONDS(TRUE)-P06TraceStartUs-P06TraceHashUs;'
    # Account every normal early-return path, including an exhausted budget.
    code=code.replace('RETURN;', finish+' RETURN;')
    code=begin+code+'\n'+finish+'\n'
    files[prefix+'Variables.var']=variables.encode()
    files[prefix+'Code.st']=code.encode()


def publish(kind, source='P06TraceSlot'):
    lines=['P06TraceRow:=17+TO_INT(P06TraceWriteSeq MOD 16);', 'P06BOrdinal[P06TraceRow]:=0;']
    for field in TYPES:
        if field in ('Ordinal','Kind','Slot'): continue
        lines.append(f'P06B{field}[P06TraceRow]:=P06B{field}[{source}];')
    lines += [f'P06BKind[P06TraceRow]:={kind};',f'P06BSlot[P06TraceRow]:={source};',
              'P06BOrdinal[P06TraceRow]:=P06TraceWriteSeq+1;', 'P06TraceWriteSeq:=P06TraceWriteSeq+1;']
    return '\n'.join(lines)+'\n'


def build(base, output):
    with zipfile.ZipFile(base) as z: files={n:z.read(n) for n in z.namelist()}
    instrument_fb(files,'NG_BatchBuilder',True)
    instrument_fb(files,'NG_Delivery',False)
    wrapper='PROJECT/Logical%20Elements/NG_DeliveryParallel.pou/'
    variables=files[wrapper+'Variables.var'].decode('utf-8-sig')
    code=files[wrapper+'Code.st'].decode('utf-8-sig')
    public=''; copies=''
    for label,path in [('Send','SendPath'),('Ack','AckPath')]:
        for field,t in [('Slot','UINT'),('Generation','UDINT'),('OtherUs','ULINT'),('HashUs','ULINT'),('HashDoneUs','ULINT'),('Stored','BOOL')]:
            public+=f'    P06Trace{label}{field} : {t};\n'
            copies+=f'P06Trace{label}{field}:={path}.P06Trace{field};\n'
    files[wrapper+'Variables.var']=replace_once(variables,'VAR_OUTPUT\n','VAR_OUTPUT\n'+public).encode()
    files[wrapper+'Code.st']=(code+'\n'+copies).encode()
    prefix='PROJECT/Logical%20Elements/Main.pou/'
    variables=files[prefix+'Variables.var'].decode('utf-8-sig')
    fields=''.join(f'    P06B{k} : ARRAY[1..32] OF {t};\n' for k,t in TYPES.items())
    fields+='''    P06TraceWriteSeq : ULINT;
    P06TraceSlot : UINT;
    P06TraceRow : INT;
    P06TraceCallAt : ULINT;
    P06TraceRxAt : ULINT;
    P06TraceTxSlot : UINT;
    P06TraceTxGeneration : UDINT;
    P06TraceTxAttempt : UDINT;
'''
    variables=replace_once(variables,'\nVAR\n','\nVAR\n'+fields)
    code=files[prefix+'Code.st'].decode('utf-8-sig')
    resets='\n'.join(f'P06B{k}[P06TraceSlot]:='+ ("''" if t=='NG_Id' else '0')+';' for k,t in TYPES.items())
    builder_after='''
IF BatchBuilder.P06TraceActive AND (BatchBuilder.P06TraceSlot>0) THEN
    P06TraceSlot:=BatchBuilder.P06TraceSlot;
    IF P06BGeneration[P06TraceSlot]<>BatchBuilder.P06TraceGeneration THEN
'''+resets+'''
        P06BId[P06TraceSlot]:=Outbox[P06TraceSlot].MessageId;
        P06BGeneration[P06TraceSlot]:=BatchBuilder.P06TraceGeneration;
        P06BBuildBeginUs[P06TraceSlot]:=P06TraceCallAt;
    END_IF;
    P06BCount[P06TraceSlot]:=CaptureBuffer.BatchOwners[P06TraceSlot].Count;
    P06BBytes[P06TraceSlot]:=Outbox[P06TraceSlot].Length;
    P06BBuilderOtherUs[P06TraceSlot]:=P06BBuilderOtherUs[P06TraceSlot]+BatchBuilder.P06TraceOtherUs;
    P06BBuilderHashUs[P06TraceSlot]:=P06BBuilderHashUs[P06TraceSlot]+BatchBuilder.P06TraceHashUs;
    P06BJsonDoneUs[P06TraceSlot]:=BatchBuilder.P06TraceJsonDoneUs;
    IF (CaptureBuffer.BatchOwners[P06TraceSlot].State=2) AND (P06BBuildDoneUs[P06TraceSlot]=0) THEN
        P06BBuildDoneUs[P06TraceSlot]:=GET_MICROSECONDS(TRUE);
    END_IF;
END_IF;
'''
    pattern=re.compile(r'^BatchBuilder\(.*?;\n',re.M|re.S)
    code,n=pattern.subn(lambda m:'P06TraceCallAt:=GET_MICROSECONDS(TRUE);\n'+m[0]+builder_after,code);assert n==2
    delivery_after=''
    for path in ['SendPath','AckPath']:
        obj='Delivery.'+path
        field='SendHashUs' if path=='SendPath' else 'AckHashUs'
        done='SendHashDoneUs' if path=='SendPath' else 'AckHashDoneUs'
        delivery_after+=f'''
IF ({obj}.P06TraceSlot>0) THEN
    P06TraceSlot:={obj}.P06TraceSlot;
    IF P06BGeneration[P06TraceSlot]={obj}.P06TraceGeneration THEN
        P06B{field}[P06TraceSlot]:=P06B{field}[P06TraceSlot]+{obj}.P06TraceHashUs;
        P06BDeliveryOtherUs[P06TraceSlot]:=P06BDeliveryOtherUs[P06TraceSlot]+{obj}.P06TraceOtherUs;
        IF ({obj}.P06TraceHashDoneUs>0) AND (P06B{done}[P06TraceSlot]=0) THEN
            P06B{done}[P06TraceSlot]:={obj}.P06TraceHashDoneUs;
        END_IF;
'''
        if path=='AckPath':
            delivery_after+=f'''        IF {obj}.P06TraceStored THEN
            P06BReleaseUs[P06TraceSlot]:=GET_MICROSECONDS(TRUE);
'''+publish(1)+'''        END_IF;
'''
        delivery_after+='    END_IF;\nEND_IF;\n'
    pattern=re.compile(r'^Delivery\(.*?;\n',re.M|re.S)
    for label,path in [('Send','SendPath'),('Ack','AckPath')]:
        for field in ('Slot','Generation','OtherUs','HashUs','HashDoneUs','Stored'):
            delivery_after=delivery_after.replace(f'Delivery.{path}.P06Trace{field}',f'Delivery.P06Trace{label}{field}')
    code,n=pattern.subn(lambda m:m[0]+delivery_after,code);assert n==2
    marker='RxTopic := Mqtt.RxTopic; RxLength := Mqtt.RxLength; RxRetain := Mqtt.RxRetained;'
    code=replace_once(code,marker,marker+' P06TraceRxAt:=GET_MICROSECONDS(TRUE);')
    marker='SubmitDataAck:=TRUE; DataAckId:=AckReader.MessageId;'
    code=replace_once(code,marker,marker+'''
                    IF AckReader.Stored THEN
                        FOR P06TraceSlot:=1 TO 16 DO
                            IF (P06BId[P06TraceSlot]=AckReader.MessageId) AND (P06BAckRxUs[P06TraceSlot]=0) THEN
                                P06BAckRxUs[P06TraceSlot]:=P06TraceRxAt;
                                P06BAckParsedUs[P06TraceSlot]:=GET_MICROSECONDS(TRUE);
                            END_IF;
                        END_FOR;
                    END_IF;''')
    marker='IF Outbox[Head].Attempts<UDINT#4294967295 THEN Outbox[Head].Attempts:=Outbox[Head].Attempts+1; END_IF;'
    code=replace_once(code,marker,marker+'''
                P06TraceTxSlot:=TO_UINT(Head); P06TraceTxGeneration:=TxBatchGeneration;
                P06TraceTxAttempt:=Outbox[Head].Attempts;
                P06BAttempts[Head]:=Outbox[Head].Attempts;
                P06BLastSubmitUs[Head]:=GET_MICROSECONDS(TRUE);
                IF P06BFirstSubmitUs[Head]=0 THEN P06BFirstSubmitUs[Head]:=P06BLastSubmitUs[Head]; END_IF;''')
    marker='HMI.PublishedBatches := HMI.PublishedBatches+1;'
    auxiliary='''
                P06TraceRow:=17+TO_INT(P06TraceWriteSeq MOD 16);
                P06BOrdinal[P06TraceRow]:=0;
'''+ '\n'.join(f'P06B{k}[P06TraceRow]:='+ ("''" if t=='NG_Id' else '0')+';' for k,t in TYPES.items() if k!='Ordinal')+'''
                P06BId[P06TraceRow]:=TxBatchId;
                P06BGeneration[P06TraceRow]:=P06TraceTxGeneration;
                P06BSlot[P06TraceRow]:=P06TraceTxSlot;
                P06BAttempts[P06TraceRow]:=P06TraceTxAttempt;
                P06BSdkDoneUs[P06TraceRow]:=GET_MICROSECONDS(TRUE);
                P06BKind[P06TraceRow]:=2;
                P06BOrdinal[P06TraceRow]:=P06TraceWriteSeq+1;
                P06TraceWriteSeq:=P06TraceWriteSeq+1;
'''
    code=replace_once(code,marker,marker+auxiliary)
    names=re.findall(r'^    (P06\w+)\s*:',fields,re.M)
    code=replace_once(code,'CaptureBuffer.LayoutBytes:=','CaptureExtraBytes:=CaptureExtraBytes+'+'+'.join('SIZEOF('+n+')' for n in names)+';\nCaptureBuffer.LayoutBytes:=')
    files[prefix+'Variables.var']=variables.encode()
    files[prefix+'Code.st']=code.encode()
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
        for n,b in files.items():z.writestr(n,b)
    print(output)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('base',type=Path);p.add_argument('output',type=Path)
    a=p.parse_args();build(a.base,a.output)
