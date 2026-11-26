FUNCTION_BLOCK NG_Modbus
VAR_INPUT
    Enable : BOOL;
    Reset : BOOL;
    NowMs : ULINT;
    UnixMs : ULINT;
    MaxMergeGap : UINT := UINT#16;
    MaxGapSpan : UINT := UINT#40;
    InterFrameGapMs : UDINT := UDINT#0;
    MaxTimeoutRetries : USINT := USINT#2;
END_VAR
VAR_IN_OUT
    Device : NG_Device;
    Points : ARRAY[1..320] OF NG_Point;
    Samples : ARRAY[1..320] OF NG_Sample;
    Buffer : NG_Buffer;
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
    k : INT;
    Retry : USINT;
    Deadline : ULINT;
    RetryAt : ULINT;
    BackoffLevel : USINT;
    BackoffMs : ULINT;
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
    PointDecodeFailed : BOOL;
    FailQuality : STRING[24];
    host : STRING;
    Accepted : BOOL;
    SourceResult : NG_SourceResult;
    PollSlot : NG_PollSlot;
    Index : UINT;
    SourceMarkUs : ULINT;
    NominalDueMs : ULINT;
    RequestSlot : UINT;
    RequestConfigGeneration : UDINT;
    RequestSamplingGeneration : ULINT;
    BlockIndices : ARRAY[1..64] OF UINT;
    BlockNominalDue : ARRAY[1..64] OF ULINT;
    SavedNextDue : ARRAY[1..64] OF ULINT;
    BlockCount : INT;
    BlockStartAddr : UINT;
    BlockEndAddr : UINT;
    BlockWidth : UINT;
    BlockHasHoles : BOOL;
    HoleMergeDisabled : BOOL;
    EffectiveMaxGap : UINT;
    EffectiveGapSpan : UINT;
    EffectiveContigSpan : UINT;
    SpanLimit : UINT;
    CandIndex : UINT;
    CandWidth : UINT;
    CandEnd : UINT;
    CandGap : UINT;
    CandSpan : UINT;
    BestIndex : UINT;
    BestGap : UINT;
    BestNewStart : UINT;
    BestNewEnd : UINT;
    AlreadyInBlock : BOOL;
    MergedPass : BOOL;
    RequestSentMs : ULINT;
    LastRttMs : ULINT;
    NextTxAllowedMs : ULINT;
    TimeoutInReceive : BOOL;
    StaleDrains : USINT;
    TimeoutRetryCap : USINT;
    CanRetry : BOOL;
    RemainBytes : INT;
    RawOff : INT;
    AnyGoodInBlock : BOOL;
    AnyErrorInBlock : BOOL;
    BlockLastErr : STRING[24];
END_VAR
OperationFailed := FALSE;
host := Device.host;
IF Reset OR NOT Enable OR NOT Device.enabled THEN
    IF (State>=16) AND (State<=40) THEN
        Buffer.CancelledReadsTotal:=NG_SafeAdd(Buffer.CancelledReadsTotal,ULINT#1);
        Buffer.CancellationReason:=2;
    END_IF;
    State:=90; Selected:=0; BlockCount:=0; BlockHasHoles:=FALSE; BackoffLevel:=USINT#0;
    NextTxAllowedMs:=ULINT#0; LastRttMs:=ULINT#0; TimeoutInReceive:=FALSE; StaleDrains:=USINT#0;
    IF Reset THEN HoleMergeDisabled:=FALSE; END_IF;
END_IF;
(* Limit only new socket activation work; nominal sampling grids remain fixed.
   Already-active sockets and final physical results are never budget-blocked. *)
IF (State=0) AND Enable AND Device.enabled AND (NowMs>=RetryAt) THEN
    IF Buffer.ConnectBudget=0 THEN StateText:='WAIT_CONNECT'; RETURN; END_IF;
    Buffer.ConnectBudget:=Buffer.ConnectBudget-USINT#1;
END_IF;
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
        StateText := 'OFFLINE'; LastError := 'BAD_CONNECTION';
        IF BackoffLevel < USINT#5 THEN BackoffLevel := BackoffLevel + USINT#1; END_IF;
        BackoffMs := ULINT#1000;
        FOR i := 1 TO TO_INT(BackoffLevel) DO
            IF BackoffMs < ULINT#15000 THEN BackoffMs := BackoffMs * ULINT#2; ELSE BackoffMs := ULINT#30000; END_IF;
        END_FOR;
        RetryAt := NowMs + BackoffMs + TO_ULINT(Device.unitId MOD USINT#8) * ULINT#125;
        State := 90;
        (* Charge the complete final-result loop once, including dispatch and
           index work; avoid four timer calls for each individual point. *)
        SourceMarkUs:=GET_MICROSECONDS(TRUE);
        FOR i := 1 TO Device.PointCount DO
            Index:=TO_UINT(Device.PointStart+i-1);
            IF Points[Index].enabled AND (NowMs>=Buffer.Cursors[Index].NextDueMonoMs) THEN
                PollSlot(NowMs:=NowMs, PeriodMs:=Points[Index].pollIntervalMs, Cursor:=Buffer.Cursors[Index], Buffer:=Buffer);
                NominalDueMs:=PollSlot.NominalDueMs;
                SourceResult(Index:=Index, Value:=LREAL#0.0, Quality:='BAD_CONNECTION', NowMs:=NowMs, UnixMs:=UnixMs, NominalDueMs:=NominalDueMs, ConfigSlot:=Buffer.ActiveSlot, ConfigGeneration:=Buffer.Configs[Buffer.ActiveSlot].Generation, SamplingGeneration:=Buffer.SamplingGeneration, Samples:=Samples, Buffer:=Buffer);
                Accepted:=SourceResult.Accepted;
            END_IF;
        END_FOR;
        Buffer.SourceWorkUs:=Buffer.SourceWorkUs+GET_MICROSECONDS(TRUE)-SourceMarkUs;
    END_IF;
15:
    IF NOT Socket.ACTIVE THEN State := 0;
    ELSIF (NowMs >= NextTxAllowedMs) AND (Buffer.PollStartBudget>0) THEN
        Selected := 0;
        FOR i := 1 TO Device.PointCount DO
            Scan := Scan + 1; IF Scan > Device.PointCount THEN Scan := 1; END_IF;
            IF Points[Device.PointStart+Scan-1].enabled AND (NowMs >= Samples[Device.PointStart+Scan-1].NextPollMs) THEN Selected := Scan; EXIT; END_IF;
        END_FOR;
        IF Selected > 0 THEN
            Buffer.PollStartBudget:=Buffer.PollStartBudget-USINT#1;
            Index:=TO_UINT(Device.PointStart+Selected-1);
            Point:=Points[Index]; Retry:=USINT#0; StaleDrains:=USINT#0;
            Width := UINT#1;
            IF (Point.dataType = 'float32') OR (Point.dataType = 'int32') OR (Point.dataType = 'uint32') THEN Width := UINT#2; END_IF;
            BlockCount := 1;
            BlockIndices[1] := Index;
            BlockStartAddr := Point.address;
            BlockEndAddr := Point.address + Width;
            BlockHasHoles := FALSE;
            (* Register merging for holding/input registers:
               per-device maxReadRegisters (default 120, capped at 120) and maxRegisterGap
               (default MaxMergeGap), with automatic fallback on Modbus Exception. *)
            EffectiveContigSpan := UINT#120;
            IF (Device.maxReadRegisters > UINT#0) AND (Device.maxReadRegisters < EffectiveContigSpan) THEN
                EffectiveContigSpan := Device.maxReadRegisters;
            END_IF;
            IF HoleMergeDisabled THEN EffectiveMaxGap := UINT#0;
            ELSIF Device.hasMaxRegisterGap THEN
                EffectiveMaxGap := Device.maxRegisterGap;
                IF EffectiveMaxGap > UINT#118 THEN EffectiveMaxGap := UINT#118; END_IF;
            ELSE
                EffectiveMaxGap := MaxMergeGap;
                IF EffectiveMaxGap > UINT#118 THEN EffectiveMaxGap := UINT#118; END_IF;
            END_IF;
            EffectiveGapSpan := MaxGapSpan;
            IF EffectiveGapSpan > EffectiveContigSpan THEN EffectiveGapSpan := EffectiveContigSpan; END_IF;
            IF EffectiveGapSpan < UINT#1 THEN EffectiveGapSpan := UINT#1; END_IF;
            IF ((Point.area = 'holding_register') OR (Point.area = 'input_register')) AND (Point.dataType <> 'bool') THEN
                MergedPass := TRUE;
                WHILE MergedPass AND (BlockCount < 64) DO
                    MergedPass := FALSE;
                    BestIndex := UINT#0;
                    BestGap := UINT#65535;
                    BestNewStart := BlockStartAddr;
                    BestNewEnd := BlockEndAddr;
                    FOR i := 1 TO Device.PointCount DO
                        CandIndex := TO_UINT(Device.PointStart + i - 1);
                        IF Points[CandIndex].enabled
                            AND (NowMs >= Samples[CandIndex].NextPollMs)
                            AND (Points[CandIndex].area = Point.area)
                            AND (Points[CandIndex].dataType <> 'bool')
                            AND (Points[CandIndex].pollIntervalMs = Point.pollIntervalMs)
                            AND (BlockCount < 64) THEN
                            AlreadyInBlock := FALSE;
                            FOR j := 1 TO BlockCount DO
                                IF BlockIndices[j] = CandIndex THEN AlreadyInBlock := TRUE; EXIT; END_IF;
                            END_FOR;
                            IF NOT AlreadyInBlock THEN
                                CandWidth := UINT#1;
                                IF (Points[CandIndex].dataType = 'float32') OR (Points[CandIndex].dataType = 'int32') OR (Points[CandIndex].dataType = 'uint32') THEN CandWidth := UINT#2; END_IF;
                                IF Points[CandIndex].address <= (UINT#65535 - CandWidth) THEN
                                    CandEnd := Points[CandIndex].address + CandWidth;
                                    IF Points[CandIndex].address >= BlockEndAddr THEN
                                        CandGap := Points[CandIndex].address - BlockEndAddr;
                                        CandSpan := CandEnd - BlockStartAddr;
                                        IF (NOT BlockHasHoles) AND (CandGap = UINT#0) THEN SpanLimit := EffectiveContigSpan; ELSE SpanLimit := EffectiveGapSpan; END_IF;
                                        IF (CandGap <= EffectiveMaxGap) AND (CandSpan <= SpanLimit) AND (CandGap < BestGap) THEN
                                            BestIndex := CandIndex;
                                            BestGap := CandGap;
                                            BestNewStart := BlockStartAddr;
                                            BestNewEnd := CandEnd;
                                        END_IF;
                                    ELSIF CandEnd <= BlockStartAddr THEN
                                        CandGap := BlockStartAddr - CandEnd;
                                        CandSpan := BlockEndAddr - Points[CandIndex].address;
                                        IF (NOT BlockHasHoles) AND (CandGap = UINT#0) THEN SpanLimit := EffectiveContigSpan; ELSE SpanLimit := EffectiveGapSpan; END_IF;
                                        IF (CandGap <= EffectiveMaxGap) AND (CandSpan <= SpanLimit) AND (CandGap < BestGap) THEN
                                            BestIndex := CandIndex;
                                            BestGap := CandGap;
                                            BestNewStart := Points[CandIndex].address;
                                            BestNewEnd := BlockEndAddr;
                                        END_IF;
                                    END_IF;
                                END_IF;
                            END_IF;
                        END_IF;
                    END_FOR;
                    IF BestIndex > UINT#0 THEN
                        BlockCount := BlockCount + 1;
                        BlockIndices[BlockCount] := BestIndex;
                        BlockStartAddr := BestNewStart;
                        BlockEndAddr := BestNewEnd;
                        IF BestGap > UINT#0 THEN BlockHasHoles := TRUE; END_IF;
                        MergedPass := TRUE;
                    END_IF;
                END_WHILE;
            END_IF;
            BlockWidth := BlockEndAddr - BlockStartAddr;
            SourceMarkUs:=GET_MICROSECONDS(TRUE);
            FOR k := 1 TO BlockCount DO
                CandIndex := BlockIndices[k];
                SavedNextDue[k] := Buffer.Cursors[CandIndex].NextDueMonoMs;
                PollSlot(NowMs:=NowMs, PeriodMs:=Points[CandIndex].pollIntervalMs, Cursor:=Buffer.Cursors[CandIndex], Buffer:=Buffer);
                BlockNominalDue[k] := PollSlot.NominalDueMs;
                Samples[CandIndex].NextPollMs := Buffer.Cursors[CandIndex].NextDueMonoMs;
            END_FOR;
            NominalDueMs := BlockNominalDue[1];
            Buffer.SourceWorkUs:=Buffer.SourceWorkUs+GET_MICROSECONDS(TRUE)-SourceMarkUs;
            RequestSlot:=Buffer.ActiveSlot; RequestConfigGeneration:=Buffer.Configs[RequestSlot].Generation;
            RequestSamplingGeneration:=Buffer.SamplingGeneration; State:=18;
        END_IF;
    END_IF;
16:
    IF NOT Socket.ACTIVE THEN
        OperationFailed := TRUE; FailQuality := 'BAD_CONNECTION';
    ELSIF NowMs >= NextTxAllowedMs THEN
        State := 18;
    END_IF;
18:
    Point := Points[BlockIndices[1]];
    Transaction := Transaction + 1;
    IF Point.area = 'coil' THEN FunctionCode := BYTE#1;
    ELSIF Point.area = 'discrete_input' THEN FunctionCode := BYTE#2;
    ELSIF Point.area = 'holding_register' THEN FunctionCode := BYTE#3;
    ELSE FunctionCode := BYTE#4;
    END_IF;
    Tx[0] := TO_BYTE(Transaction / 256); Tx[1] := TO_BYTE(Transaction MOD 256);
    Tx[2] := BYTE#0; Tx[3] := BYTE#0; Tx[4] := BYTE#0; Tx[5] := BYTE#6;
    Tx[6] := TO_BYTE(Device.unitId); Tx[7] := FunctionCode;
    Tx[8] := TO_BYTE(BlockStartAddr / 256); Tx[9] := TO_BYTE(BlockStartAddr MOD 256);
    Tx[10] := BYTE#0; Tx[11] := TO_BYTE(BlockWidth);
    RxCount := 0; FrameLength := 0; TimeoutInReceive := FALSE;
    RequestSentMs := NowMs;
    Deadline := NowMs + Device.requestTimeoutMs; State := 20;
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
    IF (NowMs >= Deadline) AND (State = 30) THEN
        OperationFailed := TRUE; FailQuality := 'BAD_TIMEOUT'; TimeoutInReceive := TRUE;
    END_IF;
40:
    IF (RxCount >= FrameLength) AND (Rx[2] = BYTE#0) AND (Rx[3] = BYTE#0) AND (Rx[6] = Tx[6])
        AND ((Rx[0] <> Tx[0]) OR (Rx[1] <> Tx[1]))
        AND (Retry > USINT#0) AND (StaleDrains < Retry) AND (NowMs < Deadline) THEN
        (* Drain a late response frame from an earlier timed-out attempt on this socket. *)
        StaleDrains := StaleDrains + USINT#1;
        IF RxCount > FrameLength THEN
            RemainBytes := TO_INT(RxCount - FrameLength);
            FOR i := 0 TO RemainBytes - 1 DO Rx[i] := Rx[TO_INT(FrameLength) + i]; END_FOR;
            RxCount := RxCount - FrameLength;
            FrameLength := 0;
            IF RxCount >= 7 THEN
                FrameLength := UDINT#6 + TO_UDINT(Rx[4])*256 + TO_UDINT(Rx[5]);
                IF (FrameLength < 9) OR (FrameLength > 260) THEN OperationFailed := TRUE; FailQuality := 'BAD_PROTOCOL';
                ELSIF RxCount >= FrameLength THEN State := 40;
                ELSE State := 30;
                END_IF;
            ELSE State := 30;
            END_IF;
        ELSE
            RxCount := 0; FrameLength := 0; State := 30;
        END_IF;
    ELSIF (RxCount = FrameLength) AND (FrameLength = UDINT#9)
        AND (Rx[0] = Tx[0]) AND (Rx[1] = Tx[1])
        AND (Rx[2] = BYTE#0) AND (Rx[3] = BYTE#0)
        AND (Rx[6] = Tx[6]) AND (Rx[7] = (FunctionCode OR BYTE#16#80))
        AND BlockHasHoles THEN
        (* Slave rejected a hole-bridged read with Modbus Exception: fall back to contiguous reads. *)
        HoleMergeDisabled := TRUE;
        FOR k := 2 TO BlockCount DO
            CandIndex := BlockIndices[k];
            Buffer.Cursors[CandIndex].NextDueMonoMs := SavedNextDue[k];
            Samples[CandIndex].NextPollMs := SavedNextDue[k];
        END_FOR;
        Point := Points[BlockIndices[1]];
        Width := UINT#1;
        IF (Point.dataType = 'float32') OR (Point.dataType = 'int32') OR (Point.dataType = 'uint32') THEN Width := UINT#2; END_IF;
        BlockCount := 1;
        BlockStartAddr := Point.address;
        BlockEndAddr := Point.address + Width;
        BlockWidth := Width;
        BlockHasHoles := FALSE;
        Retry := USINT#0;
        StaleDrains := USINT#0;
        State := 18;
    ELSIF (RxCount <> FrameLength) OR (Rx[0] <> Tx[0]) OR (Rx[1] <> Tx[1]) OR (Rx[2] <> 0) OR (Rx[3] <> 0) OR (Rx[6] <> Tx[6]) OR (Rx[7] <> FunctionCode) THEN
        OperationFailed := TRUE; FailQuality := 'BAD_PROTOCOL';
    ELSE
        IF Point.dataType = 'bool' THEN ByteCount := UINT#1; ELSE ByteCount := BlockWidth * UINT#2; END_IF;
        IF (TO_UINT(Rx[8]) <> ByteCount) OR (FrameLength <> TO_UDINT(UINT#9+ByteCount)) THEN OperationFailed := TRUE; FailQuality := 'BAD_PROTOCOL';
        ELSE
            BackoffLevel := USINT#0;
            IF NowMs >= RequestSentMs THEN LastRttMs := NowMs - RequestSentMs; ELSE LastRttMs := ULINT#0; END_IF;
            IF InterFrameGapMs > UDINT#0 THEN
                NextTxAllowedMs := NowMs + TO_ULINT(InterFrameGapMs);
            ELSIF LastRttMs >= ULINT#150 THEN
                NextTxAllowedMs := NowMs + ULINT#150;
            ELSE
                NextTxAllowedMs := ULINT#0;
            END_IF;
            AnyGoodInBlock := FALSE;
            AnyErrorInBlock := FALSE;
            BlockLastErr := '';
            SourceMarkUs := GET_MICROSECONDS(TRUE);
            FOR k := 1 TO BlockCount DO
                CandIndex := BlockIndices[k];
                Point := Points[CandIndex];
                PointDecodeFailed := FALSE;
                Width := UINT#1;
                IF (Point.dataType = 'float32') OR (Point.dataType = 'int32') OR (Point.dataType = 'uint32') THEN Width := UINT#2; END_IF;
                IF Point.dataType = 'bool' THEN
                    IF (Rx[9] AND BYTE#1) <> 0 THEN Value := 1; ELSE Value := 0; END_IF;
                ELSE
                    RawOff := 9 + TO_INT(Point.address - BlockStartAddr) * 2;
                    Decode[0] := Rx[RawOff]; Decode[1] := Rx[RawOff + 1];
                    IF Width = UINT#2 THEN Decode[2] := Rx[RawOff + 2]; Decode[3] := Rx[RawOff + 3];
                    ELSE Decode[2] := BYTE#0; Decode[3] := BYTE#0; END_IF;
                    IF (Point.byteOrder = 'BA') OR (Point.byteOrder = 'BADC') OR (Point.byteOrder = 'DCBA') THEN
                        Decode[0] := Rx[RawOff + 1]; Decode[1] := Rx[RawOff];
                        IF Width = UINT#2 THEN Decode[2] := Rx[RawOff + 3]; Decode[3] := Rx[RawOff + 2]; END_IF;
                    END_IF;
                    IF (Point.byteOrder = 'CDAB') OR (Point.byteOrder = 'DCBA') THEN
                        IF Point.byteOrder = 'CDAB' THEN
                            Decode[0] := Rx[RawOff + 2]; Decode[1] := Rx[RawOff + 3]; Decode[2] := Rx[RawOff]; Decode[3] := Rx[RawOff + 1];
                        ELSE
                            Decode[0] := Rx[RawOff + 3]; Decode[1] := Rx[RawOff + 2]; Decode[2] := Rx[RawOff + 1]; Decode[3] := Rx[RawOff];
                        END_IF;
                    END_IF;
                    UIntValue := TO_UDINT(Decode[0])*256 + TO_UDINT(Decode[1]);
                    IF Width = UINT#2 THEN UIntValue := UIntValue*65536 + TO_UDINT(Decode[2])*256 + TO_UDINT(Decode[3]); END_IF;
                    IF Point.dataType = 'float32' THEN
                        IF (TO_DWORD(UIntValue) AND DWORD#16#7F800000) = DWORD#16#7F800000 THEN
                            PointDecodeFailed := TRUE;
                        ELSE
                            ToFloat(REQ := FALSE, BUF_FORMAT := TRUE, BUF_OFFS := 0, BUF_CNT := 4, BUFFER := Decode, DST := FloatValue);
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
                IF PointDecodeFailed THEN
                    SourceResult(Index:=CandIndex, Value:=LREAL#0.0, Quality:='BAD_DECODE', NowMs:=NowMs, UnixMs:=UnixMs, NominalDueMs:=BlockNominalDue[k], ConfigSlot:=RequestSlot, ConfigGeneration:=RequestConfigGeneration, SamplingGeneration:=RequestSamplingGeneration, Samples:=Samples, Buffer:=Buffer);
                    Accepted:=SourceResult.Accepted;
                    AnyErrorInBlock := TRUE; BlockLastErr := 'BAD_DECODE';
                ELSE
                    SourceResult(Index:=CandIndex, Value:=Value*Point.scale+Point.offset, Quality:='GOOD', NowMs:=NowMs, UnixMs:=UnixMs, NominalDueMs:=BlockNominalDue[k], ConfigSlot:=RequestSlot, ConfigGeneration:=RequestConfigGeneration, SamplingGeneration:=RequestSamplingGeneration, Samples:=Samples, Buffer:=Buffer);
                    Accepted:=SourceResult.Accepted;
                    IF Samples[CandIndex].Quality='GOOD' THEN AnyGoodInBlock := TRUE;
                    ELSE AnyErrorInBlock := TRUE; BlockLastErr := Samples[CandIndex].Quality; END_IF;
                END_IF;
                IF Completed<UDINT#4294967295 THEN Completed:=Completed+1; END_IF;
            END_FOR;
            Buffer.SourceWorkUs:=Buffer.SourceWorkUs+GET_MICROSECONDS(TRUE)-SourceMarkUs;
            IF AnyGoodInBlock THEN LastGoodTimestamp:=UnixMs; END_IF;
            IF AnyErrorInBlock THEN StateText:='DEGRADED'; LastError:=BlockLastErr;
            ELSE StateText:='ONLINE'; LastError:=''; END_IF;
            State:=15;
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
    TimeoutRetryCap := Device.retryCount;
    IF TimeoutRetryCap > MaxTimeoutRetries THEN TimeoutRetryCap := MaxTimeoutRetries; END_IF;
    CanRetry := ((FailQuality = 'BAD_PROTOCOL') AND (Retry < Device.retryCount))
        OR ((FailQuality = 'BAD_TIMEOUT') AND TimeoutInReceive AND Socket.ACTIVE AND (Retry < TimeoutRetryCap));
    IF CanRetry THEN
        Retry := Retry + USINT#1;
        IF (FailQuality = 'BAD_TIMEOUT') OR (LastRttMs >= ULINT#150) THEN
            IF InterFrameGapMs >= UDINT#200 THEN NextTxAllowedMs := NowMs + TO_ULINT(InterFrameGapMs);
            ELSE NextTxAllowedMs := NowMs + ULINT#200; END_IF;
            State := 16;
        ELSIF InterFrameGapMs > UDINT#0 THEN
            NextTxAllowedMs := NowMs + TO_ULINT(InterFrameGapMs);
            State := 16;
        ELSE
            State := 18;
        END_IF;
    ELSE
        SourceMarkUs:=GET_MICROSECONDS(TRUE);
        FOR k := 1 TO BlockCount DO
            CandIndex := BlockIndices[k];
            SourceResult(Index:=CandIndex, Value:=LREAL#0.0, Quality:=FailQuality, NowMs:=NowMs, UnixMs:=UnixMs, NominalDueMs:=BlockNominalDue[k], ConfigSlot:=RequestSlot, ConfigGeneration:=RequestConfigGeneration, SamplingGeneration:=RequestSamplingGeneration, Samples:=Samples, Buffer:=Buffer);
            Accepted:=SourceResult.Accepted;
        END_FOR;
        Buffer.SourceWorkUs:=Buffer.SourceWorkUs+GET_MICROSECONDS(TRUE)-SourceMarkUs;
        LastError := FailQuality; StateText := 'DEGRADED';
        IF (FailQuality = 'BAD_TIMEOUT') OR (FailQuality = 'BAD_CONNECTION') THEN
            IF BackoffLevel < USINT#5 THEN BackoffLevel := BackoffLevel + USINT#1; END_IF;
            BackoffMs := ULINT#1000;
            FOR i := 1 TO TO_INT(BackoffLevel) DO
                IF BackoffMs < ULINT#15000 THEN BackoffMs := BackoffMs * ULINT#2; ELSE BackoffMs := ULINT#30000; END_IF;
            END_FOR;
            StateText := 'OFFLINE';
            RetryAt := NowMs + BackoffMs + TO_ULINT(Device.unitId MOD USINT#8) * ULINT#125;
            State := 90;
        ELSE State := 15; END_IF;
    END_IF;
END_IF;
END_FUNCTION_BLOCK
