FUNCTION_BLOCK NG_Modbus
VAR_INPUT
    Enable : BOOL;
    Reset : BOOL;
    NowMs : ULINT;
    UnixMs : ULINT;
END_VAR
VAR_IN_OUT
    Device : NG_Device;
    Points : ARRAY[1..320] OF NG_Point;
    Samples : ARRAY[1..320] OF NG_Sample;
END_VAR
VAR_OUTPUT
    StateText : STRING[16];
    LastError : STRING[24];
    LastGoodTimestamp : ULINT;
    Completed : UDINT;
END_VAR
VAR
    Socket : TLS_SOCKET_2;
    Send : TLS_SEND_2;
    Receive : TLS_RECEIVE_2;
    State : INT;
    Active : BOOL;
    Scan : INT;
    Selected : INT;
    i : INT;
    j : INT;
    Retry : USINT;
    Deadline : ULINT;
    RetryAt : ULINT;
    Transaction : UINT;
    FunctionCode : BYTE;
    Width : UINT;
    Tx : ARRAY[0..11] OF BYTE;
    Chunk : ARRAY[0..259] OF BYTE;
    Rx : ARRAY[0..259] OF BYTE;
    RxCount : UDINT;
    FrameLength : UDINT;
    ByteCount : UINT;
    Point : NG_Point;
    Decode : ARRAY[0..3] OF BYTE;
    UIntValue : UDINT;
    IntValue : LINT;
    FloatValue : REAL;
    ToFloat : BUF_TO_REAL;
    Value : LREAL;
    OperationFailed : BOOL;
    FailQuality : STRING[24];
    host : STRING;
END_VAR
OperationFailed := FALSE;
host := Device.host;
IF Reset OR NOT Enable OR NOT Device.enabled THEN State := 90; END_IF;
Socket(ACTIVATE := (State <> 90) AND Enable AND Device.enabled AND (NowMs >= RetryAt), IS_SRV := FALSE, BIND_IP := '', BIND_PORT := UINT#0, DEST_IP := host, DEST_PORT := Device.port, START_TLS := FALSE);
Send(REQ := (State = 20) OR (State = 21), HANDLE := Socket.HANDLE, DATA_CNT := UDINT#12, SEND_SECURE := FALSE, DATA := Tx);
Receive(EN_R := (State = 30) AND Socket.ACTIVE, HANDLE := Socket.HANDLE, EXP_DATA_CNT := UDINT#0, RECEIVE_SECURE := FALSE, DATA := Chunk);
ToFloat(REQ := FALSE, BUF_FORMAT := TRUE, BUF_OFFS := 0, BUF_CNT := 4, BUFFER := Decode, DST := FloatValue);
CASE State OF
0:
    StateText := 'CONNECTING'; Deadline := NowMs + Device.connectTimeoutMs; State := 10;
10:
    IF Socket.ACTIVE THEN State := 15;
    ELSIF NowMs >= Deadline THEN
        StateText := 'OFFLINE'; LastError := 'BAD_CONNECTION'; RetryAt := NowMs + 2000; State := 90;
        FOR i := 1 TO Device.PointCount DO
            IF Points[Device.PointStart+i-1].enabled THEN Samples[Device.PointStart+i-1].Quality := 'BAD_CONNECTION'; Samples[Device.PointStart+i-1].Timestamp := UnixMs; Samples[Device.PointStart+i-1].Fresh := TRUE; END_IF;
        END_FOR;
    END_IF;
15:
    IF NOT Socket.ACTIVE THEN State := 0;
    ELSE
        Selected := 0;
        FOR i := 1 TO Device.PointCount DO
            Scan := Scan + 1; IF Scan > Device.PointCount THEN Scan := 1; END_IF;
            IF Points[Device.PointStart+Scan-1].enabled AND (NowMs >= Samples[Device.PointStart+Scan-1].NextPollMs) THEN Selected := Scan; EXIT; END_IF;
        END_FOR;
        IF Selected > 0 THEN
            Point := Points[Device.PointStart+Selected-1]; Retry := 0; State := 18;
        END_IF;
    END_IF;
18:
    Transaction := Transaction + 1;
    IF Point.area = 'coil' THEN FunctionCode := BYTE#1;
    ELSIF Point.area = 'discrete_input' THEN FunctionCode := BYTE#2;
    ELSIF Point.area = 'holding_register' THEN FunctionCode := BYTE#3;
    ELSE FunctionCode := BYTE#4;
    END_IF;
    Width := 1;
    IF (Point.dataType = 'float32') OR (Point.dataType = 'int32') OR (Point.dataType = 'uint32') THEN Width := 2; END_IF;
    Tx[0] := TO_BYTE(Transaction / 256); Tx[1] := TO_BYTE(Transaction MOD 256);
    Tx[2] := BYTE#0; Tx[3] := BYTE#0; Tx[4] := BYTE#0; Tx[5] := BYTE#6;
    Tx[6] := TO_BYTE(Device.unitId); Tx[7] := FunctionCode;
    Tx[8] := TO_BYTE(Point.address / 256); Tx[9] := TO_BYTE(Point.address MOD 256);
    Tx[10] := BYTE#0; Tx[11] := TO_BYTE(Width);
    RxCount := 0; FrameLength := 0; Deadline := NowMs + Device.requestTimeoutMs; State := 20;
20:
    IF Send.ERROR THEN OperationFailed := TRUE; FailQuality := 'BAD_CONNECTION';
    ELSIF Send.DONE THEN State := 30;
    ELSE State := 21;
    END_IF;
21:
    IF Send.ERROR THEN OperationFailed := TRUE; FailQuality := 'BAD_CONNECTION';
    ELSIF Send.DONE THEN State := 30;
    ELSIF NowMs >= Deadline THEN OperationFailed := TRUE; FailQuality := 'BAD_TIMEOUT';
    END_IF;
30:
    IF Receive.ERROR OR NOT Socket.ACTIVE THEN OperationFailed := TRUE; FailQuality := 'BAD_CONNECTION';
    ELSIF Receive.NDR THEN
        IF RxCount + Receive.DATA_CNT > 260 THEN OperationFailed := TRUE; FailQuality := 'BAD_PROTOCOL';
        ELSE
            FOR i := 0 TO TO_INT(Receive.DATA_CNT)-1 DO Rx[TO_INT(RxCount)+i] := Chunk[i]; END_FOR;
            RxCount := RxCount + Receive.DATA_CNT;
            IF RxCount >= 7 THEN
                FrameLength := UDINT#6 + TO_UDINT(Rx[4])*256 + TO_UDINT(Rx[5]);
                IF (FrameLength < 9) OR (FrameLength > 260) THEN OperationFailed := TRUE; FailQuality := 'BAD_PROTOCOL';
                ELSIF RxCount >= FrameLength THEN State := 40;
                END_IF;
            END_IF;
        END_IF;
    END_IF;
    IF (NowMs >= Deadline) AND (State = 30) THEN OperationFailed := TRUE; FailQuality := 'BAD_TIMEOUT'; END_IF;
40:
    IF (RxCount <> FrameLength) OR (Rx[0] <> Tx[0]) OR (Rx[1] <> Tx[1]) OR (Rx[2] <> 0) OR (Rx[3] <> 0) OR (Rx[6] <> Tx[6]) OR (Rx[7] <> FunctionCode) THEN
        OperationFailed := TRUE; FailQuality := 'BAD_PROTOCOL';
    ELSE
        IF Point.dataType = 'bool' THEN ByteCount := 1; ELSE ByteCount := Width*2; END_IF;
        IF (TO_UINT(Rx[8]) <> ByteCount) OR (FrameLength <> TO_UDINT(UINT#9+ByteCount)) THEN OperationFailed := TRUE; FailQuality := 'BAD_PROTOCOL';
        ELSE
            IF Point.dataType = 'bool' THEN
                IF (Rx[9] AND BYTE#1) <> 0 THEN Value := 1; ELSE Value := 0; END_IF;
            ELSE
                Decode[0] := Rx[9]; Decode[1] := Rx[10]; Decode[2] := Rx[11]; Decode[3] := Rx[12];
                IF (Point.byteOrder = 'BA') OR (Point.byteOrder = 'BADC') OR (Point.byteOrder = 'DCBA') THEN
                    Decode[0] := Rx[10]; Decode[1] := Rx[9]; Decode[2] := Rx[12]; Decode[3] := Rx[11];
                END_IF;
                IF (Point.byteOrder = 'CDAB') OR (Point.byteOrder = 'DCBA') THEN
                    IF Point.byteOrder = 'CDAB' THEN Decode[0] := Rx[11]; Decode[1] := Rx[12]; Decode[2] := Rx[9]; Decode[3] := Rx[10];
                    ELSE Decode[0] := Rx[12]; Decode[1] := Rx[11]; Decode[2] := Rx[10]; Decode[3] := Rx[9]; END_IF;
                END_IF;
                UIntValue := TO_UDINT(Decode[0])*256 + TO_UDINT(Decode[1]);
                IF Width = 2 THEN UIntValue := UIntValue*65536 + TO_UDINT(Decode[2])*256 + TO_UDINT(Decode[3]); END_IF;
                IF Point.dataType = 'float32' THEN
                    IF (TO_DWORD(UIntValue) AND DWORD#16#7F800000) = DWORD#16#7F800000 THEN OperationFailed := TRUE; FailQuality := 'BAD_DECODE';
                    ELSE
                        ToFloat(REQ := TRUE, BUF_FORMAT := TRUE, BUF_OFFS := 0, BUF_CNT := 4, BUFFER := Decode, DST := FloatValue);
                        Value := TO_LREAL(FloatValue);
                    END_IF;
                ELSE
                    IntValue := TO_LINT(UIntValue);
                    IF (Point.dataType = 'int16') AND (UIntValue >= 32768) THEN IntValue := IntValue - 65536; END_IF;
                    IF (Point.dataType = 'int32') AND (UIntValue >= UDINT#2147483648) THEN IntValue := IntValue - LINT#4294967296; END_IF;
                    Value := TO_LREAL(IntValue);
                END_IF;
            END_IF;
            IF NOT OperationFailed THEN
                Samples[Device.PointStart+Selected-1].Value := Value*Point.scale + Point.offset;
                Samples[Device.PointStart+Selected-1].Quality := 'GOOD'; Samples[Device.PointStart+Selected-1].Timestamp := UnixMs;
                Samples[Device.PointStart+Selected-1].LastGoodMs := NowMs; Samples[Device.PointStart+Selected-1].Fresh := TRUE;
                Samples[Device.PointStart+Selected-1].NextPollMs := NowMs + Point.pollIntervalMs;
                LastGoodTimestamp := UnixMs; StateText := 'ONLINE'; LastError := ''; Completed := Completed + 1; State := 15;
            END_IF;
        END_IF;
    END_IF;
90:
    IF NOT Socket.ACTIVE AND NOT Socket.BUSY THEN
        IF Enable AND Device.enabled AND NOT Reset AND (NowMs >= RetryAt) THEN State := 0;
        ELSIF Enable AND Device.enabled THEN StateText := 'OFFLINE';
        ELSE StateText := 'DISABLED'; END_IF;
    END_IF;
END_CASE;
IF OperationFailed THEN
    IF (Retry < Device.retryCount) AND (FailQuality = 'BAD_PROTOCOL') THEN Retry := TO_USINT(Retry + 1); State := 18;
    ELSE
        Samples[Device.PointStart+Selected-1].Quality := FailQuality; Samples[Device.PointStart+Selected-1].Timestamp := UnixMs; Samples[Device.PointStart+Selected-1].Fresh := TRUE;
        Samples[Device.PointStart+Selected-1].NextPollMs := NowMs + Point.pollIntervalMs;
        LastError := FailQuality; StateText := 'DEGRADED';
        IF (FailQuality = 'BAD_TIMEOUT') OR (FailQuality = 'BAD_CONNECTION') THEN
            StateText := 'OFFLINE'; RetryAt := NowMs + 1000; State := 90;
        ELSE State := 15; END_IF;
    END_IF;
END_IF;
FOR i := 1 TO Device.PointCount DO
    IF Points[Device.PointStart+i-1].enabled AND (Samples[Device.PointStart+i-1].Quality = 'GOOD') AND (NowMs > Samples[Device.PointStart+i-1].LastGoodMs + Points[Device.PointStart+i-1].staleAfterMs) THEN
        Samples[Device.PointStart+i-1].Quality := 'STALE'; Samples[Device.PointStart+i-1].Timestamp := UnixMs; Samples[Device.PointStart+i-1].Fresh := TRUE;
    END_IF;
END_FOR;
END_FUNCTION_BLOCK

