FUNCTION_BLOCK NG_AuditDrain
VAR_INPUT
    BootId : NG_Id;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    index : UINT;
    configSlot : UINT;
    n : INT;
END_VAR
IF (Buffer.AuditAckBootId=BootId) AND (Buffer.AuditAckSeq<=Buffer.AuditWriteSeq) THEN
    FOR n:=1 TO 8 DO
        IF Buffer.AuditReadSeq>=Buffer.AuditAckSeq THEN EXIT; END_IF;
        index:=TO_UINT(Buffer.AuditReadSeq MOD 512)+1;
        IF Buffer.AuditEvents[index].Event.SampleSeq<>Buffer.AuditReadSeq+1 THEN Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        IF Buffer.AuditEvents[index].Decision=0 THEN EXIT; END_IF;
        configSlot:=Buffer.AuditEvents[index].Event.ConfigSlot;
        IF (configSlot<1) OR (configSlot>4) THEN Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        IF Buffer.Configs[configSlot].References=0 THEN Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        Buffer.Configs[configSlot].References:=Buffer.Configs[configSlot].References-1;
        Buffer.AuditReadSeq:=Buffer.AuditReadSeq+1;
    END_FOR;
END_IF;
IF (Buffer.AssociationAckBootId=BootId) AND (Buffer.AssociationAckSeq<=Buffer.AssociationWriteSeq) THEN
    FOR n:=1 TO 4 DO
        IF Buffer.AssociationReadSeq>=Buffer.AssociationAckSeq THEN EXIT; END_IF;
        index:=TO_UINT(Buffer.AssociationReadSeq MOD 32)+1;
        IF Buffer.Associations[index].Ordinal<>Buffer.AssociationReadSeq+1 THEN Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        configSlot:=Buffer.Associations[index].ConfigSlot;
        IF (configSlot<1) OR (configSlot>4) THEN Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        IF Buffer.Configs[configSlot].References=0 THEN Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        Buffer.Configs[configSlot].References:=Buffer.Configs[configSlot].References-1;
        Buffer.AssociationReadSeq:=Buffer.AssociationReadSeq+1;
    END_FOR;
END_IF;
END_FUNCTION_BLOCK
