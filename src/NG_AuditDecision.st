FUNCTION_BLOCK NG_AuditDecision
VAR_INPUT
    SampleSeq : ULINT;
    Decision : USINT;
    Reason : USINT;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    index : UINT;
END_VAR

IF NOT Buffer.AuditEnabled OR (SampleSeq=0) THEN RETURN; END_IF;
index:=TO_UINT((SampleSeq-1) MOD 512)+1;
IF (SampleSeq>Buffer.AuditReadSeq) AND (Buffer.AuditEvents[index].Event.SampleSeq=SampleSeq) THEN
    Buffer.AuditEvents[index].Decision:=Decision; Buffer.AuditEvents[index].Reason:=Reason;
ELSE Buffer.EvidenceComplete:=FALSE;
END_IF;
END_FUNCTION_BLOCK
