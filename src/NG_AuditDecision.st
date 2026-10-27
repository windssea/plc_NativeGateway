FUNCTION_BLOCK NG_AuditDecision
VAR_INPUT
    SampleSeq : ULINT;
    Decision : USINT;
    Reason : USINT;
    ReportSkipped : ULINT;
    ReportEpochCode : UINT := 65535; (* 65535 normal; 0..254 quality offset+127; 255 unsupported *)
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    index : UINT;
    delta : ULINT;
    flags : BYTE;
END_VAR
IF NOT Buffer.AuditEnabled OR (SampleSeq=0) THEN RETURN; END_IF;
index:=TO_UINT((SampleSeq-1) MOD 512)+1;
IF (SampleSeq>Buffer.AuditReadSeq) AND (Buffer.AuditEvents[index].Event.SampleSeq=SampleSeq) THEN
    IF Buffer.AuditEvents[index].Decision<>0 THEN
        Buffer.EvidenceComplete:=FALSE; Buffer.AuditFactsComplete:=FALSE; RETURN;
    END_IF;
    flags:=BYTE#1;
    IF Buffer.PlatformTime THEN flags:=flags OR BYTE#2; END_IF;
    IF Buffer.TimeValid THEN flags:=flags OR BYTE#4; END_IF;
    IF Buffer.DecisionSnapshotMonoMs>=Buffer.AuditEvents[index].Event.CompletedMonoMs THEN
        delta:=Buffer.DecisionSnapshotMonoMs-Buffer.AuditEvents[index].Event.CompletedMonoMs;
        IF delta<=ULINT#16777215 THEN
            Buffer.AuditEvents[index].DecisionDelayLo:=TO_UINT(delta MOD 65536);
            Buffer.AuditEvents[index].DecisionDelayHi:=TO_USINT(delta/65536);
            flags:=flags OR BYTE#8;
        END_IF;
    END_IF;
    IF Buffer.ClockRevision>=Buffer.AuditEvents[index].Event.ClockRevision THEN
        delta:=Buffer.ClockRevision-Buffer.AuditEvents[index].Event.ClockRevision;
        IF delta<=ULINT#255 THEN
            Buffer.AuditEvents[index].DecisionRevisionDelta:=TO_USINT(delta);
            flags:=flags OR BYTE#16;
        END_IF;
    END_IF;
    Buffer.AuditEvents[index].ReportSkipped:=USINT#255;
    IF ReportEpochCode<>UINT#65535 THEN
        flags:=flags OR BYTE#64;
        IF (Buffer.AuditEvents[index].Event.Kind=2) AND (ReportEpochCode<=UINT#254) THEN
            Buffer.AuditEvents[index].ReportSkipped:=TO_USINT(ReportEpochCode); flags:=flags OR BYTE#32;
        END_IF;
    ELSIF ReportSkipped<=ULINT#254 THEN
        Buffer.AuditEvents[index].ReportSkipped:=TO_USINT(ReportSkipped);
        flags:=flags OR BYTE#32;
    END_IF;
    Buffer.AuditEvents[index].Reason:=Reason;
    Buffer.AuditEvents[index].DecisionFlags:=flags;
    IF (flags AND BYTE#57)<>BYTE#57 THEN Buffer.AuditFactsComplete:=FALSE; END_IF;
    (* Publish terminal Decision last; readers must bracket by identity/Decision. *)
    Buffer.AuditEvents[index].Decision:=Decision;
ELSE Buffer.EvidenceComplete:=FALSE;
END_IF;
END_FUNCTION_BLOCK
