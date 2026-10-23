FUNCTION_BLOCK NG_Store
VAR_INPUT
    Save : BOOL;
END_VAR
VAR_IN_OUT
    Candidate : NG_Durable;
END_VAR
VAR_OUTPUT
    Ready : BOOL;
    NeedsMigration : BOOL;
    Busy : BOOL;
    Done : BOOL;
    Error : BOOL;
    ErrorText : NG_Text;
    Active : NG_Durable;
END_VAR
VAR
    LegacyRecord : NG1_File;
    V2Record : NG2_File;
    V2 : BOOL;
    Legacy : BOOL;
    StateLength : UDINT;
    d : INT;
    p : INT;
    idx : INT;
    Stage : INT;
    Slot : INT := 1;
    ActiveSlot : INT;
    Prev : BOOL;
    Name : STRING;
    OpenFile : FILE_OPEN;
    ReadFile : FILE_READ;
    WriteFile : FILE_WRITE;
    CloseFile : FILE_CLOSE;
    Handle : UINT;
    Record : NG_File;
    Verify : NG_File;
    Bytes : NG_Bytes;
    CopyBytes : BUF_TO_BYTE;
    Hash : NG_SHA256;
    Valid : BOOL;
    Saving : BOOL;
    OperationFailed : BOOL;
END_VAR
Done := FALSE;
IF Legacy THEN
    IF Slot = 1 THEN Name := '/opt/plcnext/NativeGateway-A.bin'; ELSE Name := '/opt/plcnext/NativeGateway-B.bin'; END_IF;
    StateLength := SIZEOF(LegacyRecord.State);
ELSIF V2 THEN
    IF Slot = 1 THEN Name := '/opt/plcnext/NativeGateway-v2-A.bin'; ELSE Name := '/opt/plcnext/NativeGateway-v2-B.bin'; END_IF;
    StateLength := SIZEOF(V2Record.State);
ELSE
    IF Slot = 1 THEN Name := '/opt/plcnext/NativeGateway-v3-A.bin'; ELSE Name := '/opt/plcnext/NativeGateway-v3-B.bin'; END_IF;
    StateLength := SIZEOF(Record.State);
END_IF;
OpenFile(Execute := (Stage = 10) OR (Stage = 60) OR (Stage = 90), Name := Name);
IF Legacy THEN
    ReadFile(Execute := Stage = 20, Handle := Handle, MaxLength := SIZEOF(LegacyRecord), Buffer := LegacyRecord);
ELSIF V2 THEN
    ReadFile(Execute := Stage = 20, Handle := Handle, MaxLength := SIZEOF(V2Record), Buffer := V2Record);
ELSE
    ReadFile(Execute := (Stage = 20) OR (Stage = 100), Handle := Handle, MaxLength := SIZEOF(Record), Buffer := Record);
END_IF;
WriteFile(Execute := Stage = 70, Handle := Handle, Length := SIZEOF(Record), Buffer := Record);
CloseFile(Execute := (Stage = 30) OR (Stage = 80) OR (Stage = 110) OR (Stage = 900), Handle := Handle);
IF Legacy THEN
    CopyBytes(REQ := Stage = 35, BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := StateLength, BUFFER := LegacyRecord.State, DST := Bytes);
ELSIF V2 THEN
    CopyBytes(REQ := Stage = 35, BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := StateLength, BUFFER := V2Record.State, DST := Bytes);
ELSE
    CopyBytes(REQ := (Stage = 35) OR (Stage = 50) OR (Stage = 115), BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := StateLength, BUFFER := Record.State, DST := Bytes);
END_IF;
Hash(Execute := (Stage = 40) OR (Stage = 55) OR (Stage = 120), Length := StateLength, Buffer := Bytes);
CASE Stage OF
0: Ready := FALSE; Busy := TRUE; Slot := 1; Stage := 10;
10:
    IF OpenFile.Error THEN Stage := 45;
    ELSIF OpenFile.Done THEN Handle := OpenFile.Handle; Stage := 20;
    END_IF;
20:
    IF ReadFile.Error OR ReadFile.Done THEN
        IF Legacy THEN Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(LegacyRecord)) AND (LegacyRecord.Magic = DWORD#16#4E475731) AND (LegacyRecord.FormatVersion = 1);
        ELSIF V2 THEN Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(V2Record)) AND (V2Record.Magic = DWORD#16#4E475732) AND (V2Record.FormatVersion = 2);
        ELSE Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(Record)) AND (Record.Magic = DWORD#16#4E475733) AND (Record.FormatVersion = 3); END_IF;
        Stage := 30;
    END_IF;
30:
    IF CloseFile.Done OR CloseFile.Error THEN
        IF Valid AND NOT CloseFile.Error THEN Stage := 35; ELSE Stage := 45; END_IF;
    END_IF;
35: IF CopyBytes.DONE THEN Stage := 40; ELSIF CopyBytes.ERROR THEN Stage := 45; END_IF;
40:
    IF Hash.Done THEN
        IF Legacy THEN
            IF (Hash.Digest = LegacyRecord.Digest) AND (LegacyRecord.State.Generation > Active.Generation) THEN
                Active.Managed := FALSE; Active.BootCounter := 0;
                Active.Generation := LegacyRecord.State.Generation; Active.Bootstrap := LegacyRecord.State.Bootstrap;
                Active.ReplayIndex := LegacyRecord.State.ReplayIndex; Active.Requests := LegacyRecord.State.Requests;
                Active.Config.Version := LegacyRecord.State.Config.Version; Active.Config.MessageId := LegacyRecord.State.Config.MessageId;
                Active.Config.enabled := LegacyRecord.State.Config.enabled; Active.Config.batchIntervalMs := LegacyRecord.State.Config.batchIntervalMs;
                Active.Config.maxBatchPoints := LegacyRecord.State.Config.maxBatchPoints; Active.Config.DeviceCount := LegacyRecord.State.Config.DeviceCount;
                idx := 1;
                FOR d := 1 TO Active.Config.DeviceCount DO
                    Active.Config.Devices[d].deviceId := LegacyRecord.State.Config.Devices[d].deviceId;
                    Active.Config.Devices[d].name := LegacyRecord.State.Config.Devices[d].name;
                    Active.Config.Devices[d].enabled := LegacyRecord.State.Config.Devices[d].enabled;
                    Active.Config.Devices[d].host := LegacyRecord.State.Config.Devices[d].host;
                    Active.Config.Devices[d].port := LegacyRecord.State.Config.Devices[d].port;
                    Active.Config.Devices[d].unitId := LegacyRecord.State.Config.Devices[d].unitId;
                    Active.Config.Devices[d].connectTimeoutMs := LegacyRecord.State.Config.Devices[d].connectTimeoutMs;
                    Active.Config.Devices[d].requestTimeoutMs := LegacyRecord.State.Config.Devices[d].requestTimeoutMs;
                    Active.Config.Devices[d].retryCount := LegacyRecord.State.Config.Devices[d].retryCount;
                    Active.Config.Devices[d].PointCount := LegacyRecord.State.Config.Devices[d].PointCount;
                    Active.Config.Devices[d].PointStart := idx;
                    FOR p := 1 TO Active.Config.Devices[d].PointCount DO Active.Config.Points[idx] := LegacyRecord.State.Config.Devices[d].Points[p]; idx := idx+1; END_FOR;
                END_FOR;
                Active.Config.PointCount := idx-1; NeedsMigration := TRUE;
            END_IF;
        ELSIF V2 THEN
            IF (Hash.Digest = V2Record.Digest) AND (V2Record.State.Generation > Active.Generation) THEN
                Active.Generation := V2Record.State.Generation; Active.Bootstrap := V2Record.State.Bootstrap;
                Active.Config := V2Record.State.Config; Active.Requests := V2Record.State.Requests; Active.ReplayIndex := V2Record.State.ReplayIndex;
                Active.Managed := FALSE; Active.BootCounter := 0; NeedsMigration := TRUE;
            END_IF;
        ELSIF (Hash.Digest = Record.Digest) AND (Record.State.Generation > Active.Generation) THEN Active := Record.State; ActiveSlot := Slot; END_IF;
        Stage := 45;
    END_IF;
45:
    IF Slot = 1 THEN Slot := 2; Stage := 10;
    ELSIF (Active.Generation = 0) AND NOT Legacy AND NOT V2 THEN V2 := TRUE; Slot := 1; Stage := 10;
    ELSIF (Active.Generation = 0) AND V2 THEN V2 := FALSE; Legacy := TRUE; Slot := 1; Stage := 10;
    ELSE Ready := TRUE; Busy := FALSE; Stage := 200; END_IF;
50: IF CopyBytes.DONE THEN Stage := 55; ELSIF CopyBytes.ERROR THEN Error := TRUE; ErrorText := 'STORAGE_ERROR'; Busy := FALSE; Stage := 200; END_IF;
55:
    IF Hash.Done THEN Record.Digest := Hash.Digest; Stage := 60; END_IF;
60:
    IF OpenFile.Error THEN Error := TRUE; ErrorText := 'STORAGE_ERROR'; Busy := FALSE; Stage := 200;
    ELSIF OpenFile.Done THEN Handle := OpenFile.Handle; Stage := 70; END_IF;
70:
    IF WriteFile.Error OR WriteFile.Done THEN
        OperationFailed := WriteFile.Error OR (WriteFile.LengthWritten <> SIZEOF(Record)); Stage := 80;
    END_IF;
80:
    IF CloseFile.Done OR CloseFile.Error THEN
        IF OperationFailed OR CloseFile.Error THEN Error := TRUE; ErrorText := 'STORAGE_ERROR'; Busy := FALSE; Stage := 200;
        ELSE Verify := Record; Stage := 85; END_IF;
    END_IF;
85: Stage := 90;
90:
    IF OpenFile.Error THEN Error := TRUE; ErrorText := 'STORAGE_ERROR'; Busy := FALSE; Stage := 200;
    ELSIF OpenFile.Done THEN Handle := OpenFile.Handle; Stage := 100; END_IF;
100:
    IF ReadFile.Error OR ReadFile.Done THEN
        Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(Record)) AND (Record.Magic = Verify.Magic) AND (Record.FormatVersion = 3) AND (Record.State.Generation = Verify.State.Generation);
        Stage := 110;
    END_IF;
110:
    IF CloseFile.Done OR CloseFile.Error THEN
        IF Valid AND NOT CloseFile.Error THEN Stage := 115;
        ELSE Error := TRUE; ErrorText := 'STORAGE_ERROR'; Busy := FALSE; Stage := 200; END_IF;
    END_IF;
115: IF CopyBytes.DONE THEN Stage := 120; ELSIF CopyBytes.ERROR THEN Error := TRUE; ErrorText := 'STORAGE_ERROR'; Busy := FALSE; Stage := 200; END_IF;
120:
    IF Hash.Done THEN
        IF (Hash.Digest = Verify.Digest) AND (Record.Digest = Verify.Digest) THEN
            Active := Record.State; ActiveSlot := Slot; Done := TRUE; NeedsMigration := FALSE;
        ELSE Error := TRUE; ErrorText := 'STORAGE_ERROR'; END_IF;
        Busy := FALSE; Stage := 200;
    END_IF;
200:
    IF Save AND NOT Prev THEN
        Error := FALSE; ErrorText := ''; Busy := TRUE;
        Legacy := FALSE; V2 := FALSE;
        Record.Magic := DWORD#16#4E475733; Record.FormatVersion := 3;
        Record.State := Candidate; Record.State.Generation := Active.Generation+1;
        IF ActiveSlot = 1 THEN Slot := 2; ELSE Slot := 1; END_IF;
        Stage := 50;
    END_IF;
END_CASE;
Prev := Save;
END_FUNCTION_BLOCK

