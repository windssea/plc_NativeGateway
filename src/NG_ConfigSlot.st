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
        Buffer.Configs[i].Reserved:=TRUE; Slot:=TO_UINT(i); RETURN;
    END_IF;
END_FOR;
END_FUNCTION_BLOCK
