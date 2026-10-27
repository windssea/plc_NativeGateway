FUNCTION_BLOCK NG_AuditAssociation
VAR_INPUT
    Slot : UINT;
    MessageId : NG_Id;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    index : UINT;
    configSlot : UINT;
    j : UINT;
    offset : UINT;
END_VAR
IF NOT Buffer.AuditEnabled THEN RETURN; END_IF;
IF (Slot<1) OR (Slot>16) THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
IF Buffer.AssociationWriteSeq>=ULINT#9007199254740991 THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
IF Buffer.AssociationWriteSeq-Buffer.AssociationReadSeq>=32 THEN
    index:=TO_UINT(Buffer.AssociationReadSeq MOD 32)+1;
    configSlot:=Buffer.Associations[index].ConfigSlot;
    IF (configSlot<1) OR (configSlot>4) THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
    IF Buffer.Configs[configSlot].References=0 THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
    Buffer.Configs[configSlot].References:=Buffer.Configs[configSlot].References-1;
    Buffer.AssociationReadSeq:=Buffer.AssociationReadSeq+1;
    Buffer.AssociationDropped:=NG_SafeAdd(Buffer.AssociationDropped,ULINT#1); Buffer.EvidenceComplete:=FALSE;
END_IF;
Buffer.AssociationWriteSeq:=Buffer.AssociationWriteSeq+1; index:=TO_UINT((Buffer.AssociationWriteSeq-1) MOD 32)+1;
configSlot:=Buffer.BatchOwners[Slot].ConfigSlot;
IF (configSlot<1) OR (configSlot>4) THEN Buffer.CaptureStopped:=TRUE; Buffer.EvidenceComplete:=FALSE; RETURN; END_IF;
Buffer.Associations[index].Ordinal:=Buffer.AssociationWriteSeq;
Buffer.Associations[index].MessageId:=MessageId; Buffer.Associations[index].Digest:=Buffer.BatchOwners[Slot].Digest;
Buffer.Associations[index].ConfigSlot:=configSlot; Buffer.Associations[index].ConfigGeneration:=Buffer.Configs[configSlot].Generation;
Buffer.Associations[index].BatchGeneration:=Buffer.BatchGenerations[Slot]; Buffer.Associations[index].Category:=Buffer.BatchOwners[Slot].Category;
Buffer.Associations[index].Count:=Buffer.BatchOwners[Slot].Count; offset:=(Slot-1)*64;
FOR j:=1 TO Buffer.BatchOwners[Slot].Count DO Buffer.Associations[index].SampleSeqs[j]:=Buffer.Records[Buffer.BatchRefs[offset+j]].SampleSeq; END_FOR;
Buffer.Configs[configSlot].References:=Buffer.Configs[configSlot].References+1;
END_FUNCTION_BLOCK
