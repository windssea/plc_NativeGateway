"""Build a no-I/O benchmark of the actual builder and send/ACK ownership paths.

No production SHA is skipped. Synthetic STORED is private to this no-network
harness; never sent to a broker. Setup is outside timed regions. Timing remains
diagnostic, not a proof of whole-gateway <=1ms or real committed throughput.
"""
import argparse
from pathlib import Path
import zipfile
from build_phase1_capture_test import build, ROOT
from build_phase1_pipeline_test import KEEP
from build_phase1_batch_trace import instrument_fb


SOURCE = '''PROGRAM Main
VAR
    Buffer : NG_Buffer;
    EmptyBuffer : NG_Buffer;
    Packets : ARRAY[1..16] OF NG_Packet;
    EmptyPacket : NG_Packet;
    Builder : NG_BatchBuilder;
    Sender : NG_Delivery;
    Acker : NG_Delivery;
    Sequence : ULINT;
    Tick : ULINT;
    Stage : UINT;
    Sample : INT := 1;
    Done : BOOL;
    Passed : BOOL := TRUE;
    i : INT;
    MarkUs : ULINT;
    BudgetUs : ULINT;
    Calls : ARRAY[1..16] OF UDINT;
    BuildOtherUs : ARRAY[1..16] OF ULINT;
    BuildHashUs : ARRAY[1..16] OF ULINT;
    SendHashUs : ARRAY[1..16] OF ULINT;
    AckHashUs : ARRAY[1..16] OF ULINT;
    SendOtherUs : ARRAY[1..16] OF ULINT;
    AckOtherUs : ARRAY[1..16] OF ULINT;
    MaxCallUs : ARRAY[1..16] OF ULINT;
    BuildScans : ARRAY[1..16] OF UDINT;
    SendScans : ARRAY[1..16] OF UDINT;
    AckScans : ARRAY[1..16] OF UDINT;
    Bytes : ARRAY[1..16] OF UDINT;
    Golden : STRING[64] := '83b83ecad3b481855e8a5d641af181152f10eedeb82368876c9f6b80ad9d91b4';
END_VAR
IF Done THEN RETURN; END_IF;
Tick:=Tick+20;
BudgetUs:=0; IF Sample MOD 2=0 THEN BudgetUs:=825; END_IF;
CASE Stage OF
0:
    Buffer:=EmptyBuffer;
    FOR i:=1 TO 16 DO Packets[i]:=EmptyPacket; END_FOR;
    Sender(GateOpen:=FALSE,NowMs:=Tick,SubmitAck:=FALSE,Buffer:=Buffer,Packets:=Packets);
    Acker(GateOpen:=FALSE,NowMs:=Tick,SubmitAck:=FALSE,Buffer:=Buffer,Packets:=Packets);
    Buffer.LayoutValid:=TRUE; Buffer.AccountingComplete:=TRUE; Buffer.ActiveSlot:=1;
    Buffer.Configs[1].Generation:=1; Buffer.Configs[1].References:=64;
    Buffer.Configs[1].GatewayId:='test-gw'; Buffer.Configs[1].CaptureBootId:='test-boot';
    Buffer.Configs[1].Config.Version:=1; Buffer.Configs[1].Config.maxBatchPoints:=64;
    Buffer.Configs[1].Config.DeviceCount:=2; Buffer.Configs[1].Config.PointCount:=64;
    Buffer.Configs[1].Config.Devices[1].deviceId:='dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
    Buffer.Configs[1].Config.Devices[2].deviceId:='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
    Buffer.Configs[1].Config.Devices[1].PointStart:=1; Buffer.Configs[1].Config.Devices[1].PointCount:=32;
    Buffer.Configs[1].Config.Devices[2].PointStart:=33; Buffer.Configs[1].Config.Devices[2].PointCount:=32;
    FOR i:=1 TO 64 DO
        Buffer.Configs[1].Config.Points[i].pointId:=CONCAT('pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp',TO_STRING(i,'{0:d}'));
        Buffer.Configs[1].Config.Points[i].dataType:='float64';
        Buffer.Configs[1].PointDevices[i]:=1; IF i>32 THEN Buffer.Configs[1].PointDevices[i]:=2; END_IF;
        Buffer.Records[i].ConfigSlot:=1; Buffer.Records[i].PointIndex:=TO_UINT(i);
        Buffer.Records[i].SampleSeq:=TO_ULINT(i); Buffer.Records[i].CompletedMonoMs:=10;
        Buffer.Records[i].CapturedUtcMs:=9007199254740991;
        Buffer.Records[i].Value:=LREAL#-1.2345678901234567E300; Buffer.Records[i].Quality:=2;
        Buffer.RecordGenerations[i]:=1; Buffer.RecordStates[i]:=1;
        Buffer.FreeSlots[i]:=TO_UINT(i+1);
    END_FOR;
    Buffer.FreeSlots[64]:=0; Buffer.QueueHead[2]:=1; Buffer.QueueTail[2]:=64;
    Buffer.HighSlot:=64; Buffer.OwnedCount:=64; Buffer.EligibleEventsTotal:=64;
    (* Golden vector was reserved at sequence5; identity bytes are hashed too. *)
    Buffer.PreferMaterialize:=2; Buffer.PreferSend:=2; Sequence:=4;
    Stage:=1;
1:
    Buffer.WorkDeadlineUs:=0; IF BudgetUs>0 THEN Buffer.WorkDeadlineUs:=GET_MICROSECONDS(TRUE)+BudgetUs; END_IF;
    MarkUs:=GET_MICROSECONDS(TRUE);
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#2000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    MaxCallUs[Sample]:=MAX(MaxCallUs[Sample],GET_MICROSECONDS(TRUE)-MarkUs);
    BuildOtherUs[Sample]:=BuildOtherUs[Sample]+Builder.P06TraceOtherUs;
    BuildHashUs[Sample]:=BuildHashUs[Sample]+Builder.P06TraceHashUs;
    BuildScans[Sample]:=BuildScans[Sample]+1;
    IF Buffer.BatchOwners[1].State=2 THEN
        Bytes[Sample]:=Packets[1].Length;
        Passed:=Passed AND (Packets[1].Length=15244) AND (Buffer.BatchOwners[1].Count=64) AND (Buffer.BatchOwners[1].Digest=Golden);
        Stage:=2;
    END_IF;
2:
    Buffer.WorkDeadlineUs:=0; IF BudgetUs>0 THEN Buffer.WorkDeadlineUs:=GET_MICROSECONDS(TRUE)+BudgetUs; END_IF;
    MarkUs:=GET_MICROSECONDS(TRUE);
    Sender(GateOpen:=TRUE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=FALSE,AckMessageId:='',AckStored:=FALSE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    MaxCallUs[Sample]:=MAX(MaxCallUs[Sample],GET_MICROSECONDS(TRUE)-MarkUs);
    SendOtherUs[Sample]:=SendOtherUs[Sample]+Sender.P06TraceOtherUs;
    SendHashUs[Sample]:=SendHashUs[Sample]+Sender.P06TraceHashUs;
    SendScans[Sample]:=SendScans[Sample]+1;
    IF Sender.SendSlot=1 THEN Packets[1].WasSent:=TRUE; Stage:=3; END_IF;
3,4:
    Buffer.WorkDeadlineUs:=0; IF BudgetUs>0 THEN Buffer.WorkDeadlineUs:=GET_MICROSECONDS(TRUE)+BudgetUs; END_IF;
    MarkUs:=GET_MICROSECONDS(TRUE);
    Acker(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=Stage=3,AckMessageId:=Packets[1].MessageId,AckStored:=TRUE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    MaxCallUs[Sample]:=MAX(MaxCallUs[Sample],GET_MICROSECONDS(TRUE)-MarkUs);
    AckOtherUs[Sample]:=AckOtherUs[Sample]+Acker.P06TraceOtherUs;
    AckHashUs[Sample]:=AckHashUs[Sample]+Acker.P06TraceHashUs;
    AckScans[Sample]:=AckScans[Sample]+1; Stage:=4;
    IF Buffer.BatchOwners[1].State=0 THEN
        Passed:=Passed AND (Buffer.StoredConfirmedEventsTotal=64) AND (Buffer.OwnedCount=0) AND NOT Buffer.CaptureStopped;
        Sample:=Sample+1; Stage:=0;
        IF Sample>16 THEN Done:=TRUE; END_IF;
    END_IF;
END_CASE;
IF NOT Done THEN
    Calls[Sample]:=Calls[Sample]+1;
    IF Calls[Sample]>3000 OR Buffer.CaptureStopped THEN Passed:=FALSE; Done:=TRUE; END_IF;
END_IF;
END_PROGRAM
'''


def package(output):
    fixture=output.with_suffix('.st');fixture.parent.mkdir(parents=True,exist_ok=True)
    fixture.write_text(SOURCE,encoding='utf-8')
    build(output,fixture,KEEP)
    with zipfile.ZipFile(output) as z: files={n:z.read(n) for n in z.namelist()}
    instrument_fb(files,'NG_BatchBuilder',True)
    instrument_fb(files,'NG_Delivery',False)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
        for n,data in files.items():z.writestr(n,data)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path)
    package(p.parse_args().output.resolve())
