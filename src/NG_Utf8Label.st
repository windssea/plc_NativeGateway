FUNCTION_BLOCK NG_Utf8Label
VAR_INPUT
    Text : NG_Text;
    MaxChars : INT;
END_VAR
VAR_OUTPUT
    Value : NG_UiLabel;
END_VAR
VAR
    Convert : BUF_TO_WSTRING;
    Buf : ARRAY[0..513] OF BYTE;
    Length : INT;
    Pos : INT;
    OutBytes : INT;
    B0 : INT;
    B1 : INT;
    B2 : INT;
    B3 : INT;
    Cp : DINT;
    Hi : DINT;
    Lo : DINT;
    HasNonAscii : BOOL;
END_VAR
Value := "";
Length := LEN(Text);
IF Length <= 0 THEN RETURN; END_IF;
HasNonAscii := FALSE;
FOR Pos := 1 TO Length DO
    B0 := GET_CHAR(Text, Pos);
    IF (B0 < 0) OR (B0 >= 128) THEN HasNonAscii := TRUE; EXIT; END_IF;
END_FOR;
IF NOT HasNonAscii THEN
    IF MaxChars = 48 THEN
        Value := TO_WSTRING(NG_Clip(Text), "");
    ELSE
        Value := TO_WSTRING(Text, "");
    END_IF;
ELSE
    Pos := 1;
    OutBytes := 0;
    WHILE (Pos <= Length) AND (OutBytes <= 510) DO
        B0 := GET_CHAR(Text, Pos);
        IF B0 < 0 THEN B0 := B0 + 256; END_IF;
        IF B0 < 128 THEN
            Cp := TO_DINT(B0);
            Pos := Pos + 1;
        ELSIF (B0 >= 194) AND (B0 <= 223) AND ((Pos + 1) <= Length) THEN
            B1 := GET_CHAR(Text, Pos + 1);
            IF B1 < 0 THEN B1 := B1 + 256; END_IF;
            IF (B1 >= 128) AND (B1 <= 191) THEN
                Cp := TO_DINT(B0 - 192) * DINT#64 + TO_DINT(B1 - 128);
                Pos := Pos + 2;
            ELSE
                Cp := DINT#65533;
                Pos := Pos + 1;
            END_IF;
        ELSIF (B0 >= 224) AND (B0 <= 239) AND ((Pos + 2) <= Length) THEN
            B1 := GET_CHAR(Text, Pos + 1);
            B2 := GET_CHAR(Text, Pos + 2);
            IF B1 < 0 THEN B1 := B1 + 256; END_IF;
            IF B2 < 0 THEN B2 := B2 + 256; END_IF;
            IF (B1 >= 128) AND (B1 <= 191) AND (B2 >= 128) AND (B2 <= 191) THEN
                Cp := TO_DINT(B0 - 224) * DINT#4096 + TO_DINT(B1 - 128) * DINT#64 + TO_DINT(B2 - 128);
                Pos := Pos + 3;
            ELSE
                Cp := DINT#65533;
                Pos := Pos + 1;
            END_IF;
        ELSIF (B0 >= 240) AND (B0 <= 244) AND ((Pos + 3) <= Length) AND (OutBytes <= 508) THEN
            B1 := GET_CHAR(Text, Pos + 1);
            B2 := GET_CHAR(Text, Pos + 2);
            B3 := GET_CHAR(Text, Pos + 3);
            IF B1 < 0 THEN B1 := B1 + 256; END_IF;
            IF B2 < 0 THEN B2 := B2 + 256; END_IF;
            IF B3 < 0 THEN B3 := B3 + 256; END_IF;
            IF (B1 >= 128) AND (B1 <= 191) AND (B2 >= 128) AND (B2 <= 191) AND (B3 >= 128) AND (B3 <= 191) THEN
                Cp := TO_DINT(B0 - 240) * DINT#262144 + TO_DINT(B1 - 128) * DINT#4096 + TO_DINT(B2 - 128) * DINT#64 + TO_DINT(B3 - 128);
                Pos := Pos + 4;
            ELSE
                Cp := DINT#65533;
                Pos := Pos + 1;
            END_IF;
        ELSE
            Cp := DINT#65533;
            Pos := Pos + 1;
        END_IF;
        IF Cp <= DINT#65535 THEN
            Buf[OutBytes] := TO_BYTE(Cp MOD DINT#256);
            Buf[OutBytes + 1] := TO_BYTE(Cp / DINT#256);
            OutBytes := OutBytes + 2;
        ELSIF OutBytes <= 508 THEN
            Cp := Cp - DINT#65536;
            Hi := DINT#55296 + (Cp / DINT#1024);
            Lo := DINT#56320 + (Cp MOD DINT#1024);
            Buf[OutBytes] := TO_BYTE(Hi MOD DINT#256);
            Buf[OutBytes + 1] := TO_BYTE(Hi / DINT#256);
            Buf[OutBytes + 2] := TO_BYTE(Lo MOD DINT#256);
            Buf[OutBytes + 3] := TO_BYTE(Lo / DINT#256);
            OutBytes := OutBytes + 4;
        END_IF;
    END_WHILE;
    Buf[OutBytes] := BYTE#0;
    Buf[OutBytes + 1] := BYTE#0;
    IF OutBytes > 0 THEN
        Convert(REQ := FALSE, BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := OutBytes, BUFFER := Buf, DST := Value);
        Convert(REQ := TRUE, BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := OutBytes, BUFFER := Buf, DST := Value);
    END_IF;
END_IF;
IF (MaxChars > 3) AND (LEN(Value) > MaxChars) THEN
    Value := CONCAT_WSTRING(LEFT_WSTRING(Value, MaxChars - 3), "...");
END_IF;
END_FUNCTION_BLOCK
