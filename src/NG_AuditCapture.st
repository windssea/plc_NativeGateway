FUNCTION_BLOCK NG_AuditCapture
VAR_IN_OUT
    Buffer : NG_Buffer;
    Event : NG_CaptureEvent;
END_VAR
VAR
    index : UINT;
    oldIndex : UINT;
    configSlot : UINT;
END_VAR

IF NOT Buffer.AuditEnabled THEN RETURN; END_IF;
IF (Event.SampleSeq=0) OR (Event.ConfigSlot<1) OR (Event.ConfigSlot>4) THEN
    Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN;
END_IF;
IF Buffer.AuditWriteSeq-Buffer.AuditReadSeq>=512 THEN
    oldIndex:=TO_UINT(Buffer.AuditReadSeq MOD 512)+1;
    configSlot:=Buffer.AuditEvents[oldIndex].Event.ConfigSlot;
    IF (configSlot<1) OR (configSlot>4) THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
    IF Buffer.Configs[configSlot].References=0 THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
    Buffer.Configs[configSlot].References:=Buffer.Configs[configSlot].References-1;
    Buffer.AuditReadSeq:=Buffer.AuditReadSeq+1;
    Buffer.AuditDropped:=NG_SafeAdd(Buffer.AuditDropped,ULINT#1); Buffer.EvidenceComplete:=FALSE;
END_IF;
index:=TO_UINT((Event.SampleSeq-1) MOD 512)+1;
Buffer.AuditEvents[index].Event:=Event; Buffer.AuditEvents[index].Decision:=0; Buffer.AuditEvents[index].Reason:=0;
Buffer.Configs[Event.ConfigSlot].References:=Buffer.Configs[Event.ConfigSlot].References+1;
Buffer.AuditWriteSeq:=Event.SampleSeq;
END_FUNCTION_BLOCK
