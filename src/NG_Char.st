FUNCTION_BLOCK NG_Char
VAR_INPUT
    Code : UDINT;
    Utf8 : BOOL;
END_VAR
VAR_OUTPUT
    Value : STRING[4];
END_VAR
VAR
    Bytes : ARRAY[0..4] OF BYTE;
    Convert : BUF_TO_STRING;
    Count : INT;
END_VAR
Count := 1;
Bytes[0] := TO_BYTE(Code);
IF Utf8 THEN
    IF Code < 128 THEN Bytes[0] := TO_BYTE(Code);
    ELSIF Code < 2048 THEN Count := 2; Bytes[0] := TO_BYTE(192 + Code / 64); Bytes[1] := TO_BYTE(128 + Code MOD 64);
    ELSIF Code < 65536 THEN Count := 3; Bytes[0] := TO_BYTE(224 + Code / 4096); Bytes[1] := TO_BYTE(128 + (Code / 64) MOD 64); Bytes[2] := TO_BYTE(128 + Code MOD 64);
    ELSE Count := 4; Bytes[0] := TO_BYTE(240 + Code / 262144); Bytes[1] := TO_BYTE(128 + (Code / 4096) MOD 64); Bytes[2] := TO_BYTE(128 + (Code / 64) MOD 64); Bytes[3] := TO_BYTE(128 + Code MOD 64);
    END_IF;
END_IF;
Bytes[Count] := BYTE#0;
Convert(REQ := FALSE, BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := Count, BUFFER := Bytes, DST := Value);
Convert(REQ := TRUE, BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := Count, BUFFER := Bytes, DST := Value);
END_FUNCTION_BLOCK
