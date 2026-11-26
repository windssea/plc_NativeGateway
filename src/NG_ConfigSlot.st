FUNCTION_BLOCK NG_ConfigSlot
VAR_INPUT
    GatewayId : NG_Id;
    CaptureBootId : NG_Id;
END_VAR
VAR_OUTPUT
    Slot : UINT;
END_VAR
VAR_IN_OUT
    Config : NG_Config;
    Buffer : NG_Buffer;
END_VAR
VAR
    Compare : NG_SameConfig;
    i : INT;
    j : INT;
    oldIndex : UINT;
    configSlot : UINT;
    hasFree : BOOL;
END_VAR
Slot := 0;
IF Buffer.ActiveSlot>0 THEN
    Compare(A:=Buffer.Configs[Buffer.ActiveSlot].Config,B:=Config);
    IF (Buffer.Configs[Buffer.ActiveSlot].GatewayId=GatewayId) AND
       (Buffer.Configs[Buffer.ActiveSlot].CaptureBootId=CaptureBootId) AND
       Compare.Equal THEN
        Slot:=Buffer.ActiveSlot; RETURN;
    END_IF;
END_IF;
IF Buffer.NextConfigGeneration=UDINT#4294967295 THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
FOR i:=1 TO 4 DO
    IF (i<>TO_INT(Buffer.ActiveSlot)) AND (Buffer.Configs[i].References=0) AND NOT Buffer.Configs[i].Reserved THEN
        Buffer.NextConfigGeneration:=Buffer.NextConfigGeneration+1;
        Buffer.Configs[i].Config:=Config; Buffer.Configs[i].GatewayId:=GatewayId;
        Buffer.Configs[i].CaptureBootId:=CaptureBootId;
        Buffer.Configs[i].Generation:=Buffer.NextConfigGeneration;
        FOR j:=1 TO 320 DO Buffer.Configs[i].PointDevices[j]:=0; END_FOR;
        Buffer.Configs[i].Reserved:=TRUE; Slot:=TO_UINT(i); RETURN;
    END_IF;
END_FOR;
(* When no external audit collector is attached, evict oldest audit/association
   ring entries on dictionary exhaustion so inactive config slots can be freed
   without dropping live Ingress/Records/Outbox telemetry. *)
IF (Buffer.AuditAckBootId<>CaptureBootId) AND (Buffer.AssociationAckBootId<>CaptureBootId) THEN
    hasFree:=FALSE;
    WHILE (NOT hasFree) AND (Buffer.AuditReadSeq<Buffer.AuditWriteSeq) DO
        oldIndex:=TO_UINT(Buffer.AuditReadSeq MOD 512)+1;
        configSlot:=Buffer.AuditEvents[oldIndex].Event.ConfigSlot;
        IF (configSlot<1) OR (configSlot>4) THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        IF Buffer.Configs[configSlot].References=0 THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        Buffer.Configs[configSlot].References:=Buffer.Configs[configSlot].References-1;
        Buffer.AuditReadSeq:=Buffer.AuditReadSeq+1;
        Buffer.AuditDropped:=NG_SafeAdd(Buffer.AuditDropped,ULINT#1);
        Buffer.EvidenceComplete:=FALSE;
        IF (configSlot<>Buffer.ActiveSlot) AND (Buffer.Configs[configSlot].References=0) AND NOT Buffer.Configs[configSlot].Reserved THEN
            hasFree:=TRUE;
        END_IF;
    END_WHILE;
    WHILE (NOT hasFree) AND (Buffer.AssociationReadSeq<Buffer.AssociationWriteSeq) DO
        oldIndex:=TO_UINT(Buffer.AssociationReadSeq MOD 32)+1;
        configSlot:=Buffer.Associations[oldIndex].ConfigSlot;
        IF (configSlot<1) OR (configSlot>4) THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        IF Buffer.Configs[configSlot].References=0 THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
        Buffer.Configs[configSlot].References:=Buffer.Configs[configSlot].References-1;
        Buffer.AssociationReadSeq:=Buffer.AssociationReadSeq+1;
        Buffer.AssociationDropped:=NG_SafeAdd(Buffer.AssociationDropped,ULINT#1);
        Buffer.EvidenceComplete:=FALSE;
        IF (configSlot<>Buffer.ActiveSlot) AND (Buffer.Configs[configSlot].References=0) AND NOT Buffer.Configs[configSlot].Reserved THEN
            hasFree:=TRUE;
        END_IF;
    END_WHILE;
    FOR i:=1 TO 4 DO
        IF (i<>TO_INT(Buffer.ActiveSlot)) AND (Buffer.Configs[i].References=0) AND NOT Buffer.Configs[i].Reserved THEN
            Buffer.NextConfigGeneration:=Buffer.NextConfigGeneration+1;
            Buffer.Configs[i].Config:=Config; Buffer.Configs[i].GatewayId:=GatewayId;
            Buffer.Configs[i].CaptureBootId:=CaptureBootId;
            Buffer.Configs[i].Generation:=Buffer.NextConfigGeneration;
            FOR j:=1 TO 320 DO Buffer.Configs[i].PointDevices[j]:=0; END_FOR;
            Buffer.Configs[i].Reserved:=TRUE; Slot:=TO_UINT(i); RETURN;
        END_IF;
    END_FOR;
END_IF;
END_FUNCTION_BLOCK
