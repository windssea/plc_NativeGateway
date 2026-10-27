"""Package validation-only fault controls and per-cycle ESM statistics.

No device operation. The production source has no fault switches. Time fields
are whole task durations including preemption, never called incremental time.
"""
from pathlib import Path
import argparse
import re
from build_phase1_capture_test import ROOT,build

FIELDS='''    P06HoldSend : BOOL;
    P06Disconnect : BOOL;
    P06DropAck : BOOL;
    P06ResetStats : BOOL;
    P06PreviousReady : BOOL;
    P06PreviousMode : USINT;
    P06Mode : USINT;
    P06Samples : ULINT;
    P06OverPeriod : ULINT;
    P06OverOneMs : ULINT;
    P06MinUs : LINT;
    P06MaxUs : LINT;
    P06LastUs : LINT;
    P06SumUs : ULINT;
    P06SectionMark : ARRAY[1..9] OF ULINT;
    P06SectionLast : ARRAY[1..8] OF ULINT;
    P06SectionMax : ARRAY[1..8] OF ULINT;
    P06SectionSum : ARRAY[1..8] OF ULINT;
    P06SectionRx : ARRAY[1..8] OF INT;
    P06SectionTx : ARRAY[1..8] OF INT;
    P06SectionIndex : INT;
    P06WorstSections : ARRAY[1..8] OF ULINT;
    P06WorstAtMs : ULINT;
    P06WorstRx : INT;
    P06WorstTx : INT;
    P06WorstSourceUs : ULINT;
    P06WorkMark : ULINT;
    P06WorkParts : ARRAY[1..6] OF ULINT;
    P06WorstWorkParts : ARRAY[1..6] OF ULINT;
    P06ObservedWorkMax : ULINT;
    P06WorstWorkSource : ULINT;
    P06WorstWorkAtMs : ULINT;
    P06WorstWorkCaptured : ULINT;
    P06SourceParts : ARRAY[1..4] OF ULINT;
    P06WorstWorkSourceParts : ARRAY[1..4] OF ULINT;
    P06BudgetTimes : ARRAY[1..6] OF ULINT;
    P06WorstBudgetTimes : ARRAY[1..6] OF ULINT;
'''
FIELD_NAMES=re.findall(r'^    (P06\w+)\s*:',FIELDS,re.M)
MONITOR='''(* Previous scan timing, collected in every IEC scan. A change of test mode
   skips the boundary sample. Reset is a diagnostic action, no business reset. *)
P06Mode:=0; IF P06HoldSend THEN P06Mode:=1; END_IF; IF P06DropAck THEN P06Mode:=2; END_IF;
IF P06Disconnect THEN P06Mode:=3; END_IF;
IF P06ResetStats THEN
    P06Samples:=0; P06OverPeriod:=0; P06OverOneMs:=0; P06MaxUs:=0;
    P06MinUs:=LINT#9223372036854775807; P06SumUs:=0; P06PreviousReady:=FALSE;
    FOR P06SectionIndex:=1 TO 8 DO P06SectionMax[P06SectionIndex]:=0; P06SectionSum[P06SectionIndex]:=0; END_FOR;
    P06ResetStats:=FALSE;
END_IF;
IF StartupReady AND P06PreviousReady AND (P06Mode=P06PreviousMode) THEN
    P06LastUs:=ESM_DATA.ESM_INFOS[1].TASK_INFOS[1].LAST_EXEC_DURATION;
    IF P06Samples=0 THEN P06MinUs:=P06LastUs; END_IF;
    P06Samples:=P06Samples+1; P06MinUs:=MIN(P06MinUs,P06LastUs);
    IF P06LastUs>P06MaxUs THEN
        P06MaxUs:=P06LastUs; P06WorstAtMs:=NowMs; P06WorstRx:=RxStage; P06WorstTx:=TxKind; P06WorstSourceUs:=CaptureBuffer.SourceWorkUs;
        FOR P06SectionIndex:=1 TO 8 DO P06WorstSections[P06SectionIndex]:=P06SectionLast[P06SectionIndex]; END_FOR;
    END_IF;
    P06SumUs:=P06SumUs+TO_ULINT(P06LastUs);
    IF P06LastUs>ESM_DATA.ESM_INFOS[1].TASK_INFOS[1].INTERVAL THEN P06OverPeriod:=P06OverPeriod+1; END_IF;
    IF P06LastUs>1000 THEN P06OverOneMs:=P06OverOneMs+1; END_IF;
END_IF;
P06PreviousReady:=StartupReady; P06PreviousMode:=P06Mode;
'''

def package(output, work_budget_us=825):
    source=(ROOT/'src/Main.st').read_text(encoding='utf-8-sig')
    if work_budget_us != 825:
        assert source.count('ULINT#825') == 2
        source=source.replace('ULINT#825',f'ULINT#{work_budget_us}')
        source=source.replace('remaining 825 us',f'remaining {work_budget_us} us (DIAGNOSTIC WIDE BUDGET, NOT ACCEPTANCE)')
    source=source.replace('VAR_EXTERNAL\n','VAR_EXTERNAL\n    ESM_DATA : ESM_DAT;\n',1)
    source=source.replace('\nVAR\n','\nVAR\n'+FIELDS,1)
    source=source.replace('Clock(IN :=',MONITOR+'P06SectionMark[1]:=GET_MICROSECONDS(TRUE);\nClock(IN :=',1)
    boundaries=['TelemetryAllowed :=','(* P01 resource fence:', 'AuditDrain(BootId:=',
        'DataGate:=','IF TxActive THEN','Mqtt(Enable := Initialized AND StartupReady,', 'HMI.ActiveMessageId:=']
    for index,marker in enumerate(boundaries,2):
        assert marker in source,marker
        source=source.replace(marker,f'P06SectionMark[{index}]:=GET_MICROSECONDS(TRUE);\n'+marker,1)
    source=source.replace('END_PROGRAM','''P06SectionMark[9]:=GET_MICROSECONDS(TRUE);
FOR P06SectionIndex:=1 TO 8 DO
    P06SectionLast[P06SectionIndex]:=P06SectionMark[P06SectionIndex+1]-P06SectionMark[P06SectionIndex];
    P06SectionSum[P06SectionIndex]:=P06SectionSum[P06SectionIndex]+P06SectionLast[P06SectionIndex];
    IF P06SectionLast[P06SectionIndex]>P06SectionMax[P06SectionIndex] THEN
        P06SectionMax[P06SectionIndex]:=P06SectionLast[P06SectionIndex];
        P06SectionRx[P06SectionIndex]:=RxStage; P06SectionTx[P06SectionIndex]:=TxKind;
    END_IF;
END_FOR;
END_PROGRAM''')
    source=source.replace('DataGate:=Mqtt.Connected','DataGate:=NOT P06HoldSend AND Mqtt.Connected',1)
    source=source.replace('Mqtt(Enable := Initialized AND StartupReady,',
        'Mqtt(Enable := Initialized AND StartupReady AND NOT P06Disconnect,',1)
    marker='CaptureBuffer.SourceWorkUs:=GET_MICROSECONDS(TRUE)-CaptureBuffer.PipelineMarkUs;'
    assert source.count(marker)==1
    source=source.replace(marker,marker+'\nP06SourceParts[1]:=CaptureBuffer.SourceWorkUs;',1)
    marker='CaptureBuffer.SourceWorkUs:=CaptureBuffer.SourceWorkUs+GET_MICROSECONDS(TRUE)-CaptureBuffer.PipelineMarkUs;'
    assert source.count(marker)==2
    source=source.replace(marker,marker+'\nP06SourceParts[2]:=CaptureBuffer.SourceWorkUs-P06SourceParts[1];',1)
    marker='(* Same-scan final physical results win over stale transitions. *)'
    assert marker in source
    source=source.replace(marker,'P06SourceParts[3]:=CaptureBuffer.SourceWorkUs-P06SourceParts[1]-P06SourceParts[2];\n'+marker,1)
    marker='IF Mqtt.SessionCount <> SessionSeen THEN'
    assert marker in source
    source=source.replace(marker,'P06SourceParts[4]:=CaptureBuffer.SourceWorkUs-P06SourceParts[1]-P06SourceParts[2]-P06SourceParts[3];\n'+marker,1)
    for index,name in enumerate(['BufferMaintenance','ReportPolicy','BatchBuilder','Delivery','CheckCounters','Diagnostics'],1):
        pattern=re.compile(r'^'+name+r'\(.*?;\n',re.M|re.S)
        if name in ('BatchBuilder','Delivery'):
            b=2 if name=='BatchBuilder' else 4
            source,count=pattern.subn(lambda m:'P06WorkMark:=GET_MICROSECONDS(TRUE);\n'+f'P06BudgetTimes[{b}]:=P06WorkMark;\n'+m[0]+f'P06BudgetTimes[{b+1}]:=GET_MICROSECONDS(TRUE);\nP06WorkParts[{index}]:=P06BudgetTimes[{b+1}]-P06WorkMark;\n',source)
        else:
            source,count=pattern.subn(lambda m:'P06WorkMark:=GET_MICROSECONDS(TRUE);\n'+m[0]+f'P06WorkParts[{index}]:=GET_MICROSECONDS(TRUE)-P06WorkMark;\n',source)
        assert count==(2 if name in ('BatchBuilder','Delivery') else 1),(name,count)
    source=source.replace('BufferMaintenance(GateOpen:=','P06BudgetTimes[1]:=CaptureBuffer.WorkDeadlineUs;\nBufferMaintenance(GateOpen:=',1)
    marker='CaptureBuffer.WorkLastUs:=CaptureBuffer.SourceWorkUs+GET_MICROSECONDS(TRUE)-CaptureBuffer.PipelineMarkUs;'
    assert source.count(marker)==1
    source=source.replace(marker,'P06BudgetTimes[6]:=GET_MICROSECONDS(TRUE);\n'+marker.replace('GET_MICROSECONDS(TRUE)','P06BudgetTimes[6]'),1)
    marker='CaptureBuffer.WorkMaxUs:=MAX(CaptureBuffer.WorkMaxUs,CaptureBuffer.WorkLastUs);'
    assert marker in source
    source=source.replace(marker,marker+'''
IF CaptureBuffer.WorkLastUs>P06ObservedWorkMax THEN
    P06ObservedWorkMax:=CaptureBuffer.WorkLastUs;
    P06WorstWorkSource:=CaptureBuffer.SourceWorkUs;
    P06WorstWorkAtMs:=NowMs; P06WorstWorkCaptured:=CaptureBuffer.CapturedEventsTotal;
    FOR P06SectionIndex:=1 TO 4 DO P06WorstWorkSourceParts[P06SectionIndex]:=P06SourceParts[P06SectionIndex]; END_FOR;
    FOR P06SectionIndex:=1 TO 6 DO P06WorstWorkParts[P06SectionIndex]:=P06WorkParts[P06SectionIndex]; END_FOR;
    FOR P06SectionIndex:=1 TO 6 DO P06WorstBudgetTimes[P06SectionIndex]:=P06BudgetTimes[P06SectionIndex]; END_FOR;
END_IF;''',1)
    source=source.replace('SubmitAck:=SubmitDataAck,','SubmitAck:=SubmitDataAck AND NOT P06DropAck,',1)
    source=source.replace('CaptureBuffer.LayoutBytes:=',
        'CaptureExtraBytes:=CaptureExtraBytes+'+'+'.join('SIZEOF('+n+')' for n in FIELD_NAMES)+';\nCaptureBuffer.LayoutBytes:=',1)
    output.parent.mkdir(parents=True,exist_ok=True)
    fixture=output.parent/(output.stem+'.st')
    fixture.write_text(source,encoding='utf-8')
    keep={p.stem for p in (ROOT/'src').glob('*.st')}
    build(output,fixture,keep)

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output',type=Path)
    ap.add_argument('--work-budget-us',type=int,default=825,choices=(825,1800),
                    help='1800 is a separate diagnostic profile, never the <=1ms acceptance image')
    args=ap.parse_args();package(args.output.resolve(),args.work_budget_us)
