FUNCTION_BLOCK NG_JsonParse
VAR_INPUT
    Execute : BOOL;
    Length : UDINT;
END_VAR
VAR_IN_OUT
    Buffer : NG_Bytes;
    Doc : NG_Document;
END_VAR
VAR_OUTPUT
    Done : BOOL;
    Busy : BOOL;
    Error : BOOL;
    ErrorText : NG_Text;
END_VAR
VAR
    ConvertChar : NG_Char;
    Previous : BOOL;
    Pos : DINT;
    Depth : INT;
    Nodes : ARRAY[0..64] OF INT;
    Expected : ARRAY[0..64] OF INT;
    Keys : ARRAY[0..64] OF NG_Id;
    Mode : INT;
    IsKey : BOOL;
    Text : STRING[512];
    Start : DINT;
    Code : UINT;
    UCode : UDINT;
    HighSurrogate : UDINT;
    HexCount : INT;
    N : INT;
    I : INT;
    Budget : INT;
    C : STRING[1];
    Again : BOOL;
    FinishScalar : BOOL;
    Kind : INT;
    NewValue : BOOL;
    Parent : INT;
    Number : LREAL;
    ClipIndex : INT;
END_VAR
IF Execute AND NOT Previous AND NOT Busy THEN
    Pos := 0; Depth := 0; Doc.Count := 0; Mode := 0;
    Nodes[0] := 0; Expected[0] := 2; Keys[0] := '';
    Done := FALSE; Error := FALSE; ErrorText := ''; Busy := TRUE;
    IF (Length = 0) OR (Length > 131071) THEN
        Error := TRUE; ErrorText := 'PAYLOAD_TOO_LARGE';
    END_IF;
END_IF;
Previous := Execute;
IF NOT Busy THEN RETURN; END_IF;
Budget := 0;
WHILE (Budget < 512) AND NOT Error DO
    IF Pos >= TO_DINT(Length) THEN
        IF Mode = 4 THEN FinishScalar := TRUE;
        ELSIF (Mode = 0) AND (Depth = 0) AND (Doc.Count > 0) THEN
            Done := TRUE; Busy := FALSE; EXIT;
        ELSE Error := TRUE; EXIT;
        END_IF;
        Code := 0; C := '';
    ELSE Code := TO_UINT(Buffer[Pos]); ConvertChar(Code := Code, Utf8 := FALSE); C := ConvertChar.Value;
    END_IF;
    Again := FALSE; NewValue := FALSE;
    CASE Mode OF
    0:
        IF (Code = 32) OR (Code = 9) OR (Code = 10) OR (Code = 13) THEN
            Pos := Pos + 1;
        ELSIF (Code = 125) OR (Code = 93) THEN
            IF Depth = 0 THEN Error := TRUE;
            ELSIF ((Doc.Tokens[Nodes[Depth]].Kind = 1) AND (Code = 125) AND ((Expected[Depth] = 0) OR (Expected[Depth] = 3))) OR
                  ((Doc.Tokens[Nodes[Depth]].Kind = 2) AND (Code = 93) AND ((Expected[Depth] = 5) OR (Expected[Depth] = 6))) THEN
                Doc.Tokens[Nodes[Depth]].NextToken := Doc.Count + 1;
                Depth := Depth - 1; Pos := Pos + 1;
            ELSE Error := TRUE;
            END_IF;
        ELSIF (Code = 44) AND (Depth > 0) THEN
            IF Expected[Depth] = 3 THEN Expected[Depth] := 4;
            ELSIF Expected[Depth] = 6 THEN Expected[Depth] := 7;
            ELSE Error := TRUE; END_IF;
            Pos := Pos + 1;
        ELSIF (Code = 58) AND (Expected[Depth] = 1) THEN
            Expected[Depth] := 2; Pos := Pos + 1;
        ELSIF ((Expected[Depth] = 0) OR (Expected[Depth] = 4)) AND (Code = 34) THEN
            IsKey := TRUE; Text := ''; Mode := 1; Pos := Pos + 1; HighSurrogate := 0;
        ELSIF (Expected[Depth] = 2) OR (Expected[Depth] = 5) OR (Expected[Depth] = 7) THEN
            IF Depth = 0 THEN Expected[Depth] := 8;
            ELSIF Doc.Tokens[Nodes[Depth]].Kind = 1 THEN Expected[Depth] := 3;
            ELSE Expected[Depth] := 6; END_IF;
            Start := Pos; IsKey := FALSE; Text := ''; HighSurrogate := 0;
            IF Code = 34 THEN Mode := 1; Pos := Pos + 1;
            ELSIF (Code = 123) OR (Code = 91) THEN
                IF Code = 123 THEN Kind := 1; ELSE Kind := 2; END_IF;
                NewValue := TRUE; Pos := Pos + 1;
            ELSIF (Code = 45) OR ((Code >= 48) AND (Code <= 57)) OR (Code = 116) OR (Code = 102) OR (Code = 110) THEN
                Mode := 4; Again := TRUE;
            ELSE Error := TRUE; END_IF;
        ELSE Error := TRUE;
        END_IF;
    1:
        IF Code = 34 THEN
            IF HighSurrogate <> 0 THEN Error := TRUE;
            ELSIF IsKey THEN
                IF LEN(Text) > 64 THEN Error := TRUE;
                ELSE Keys[Depth] := Text; Expected[Depth] := 1; END_IF;
            ELSE Kind := 3; NewValue := TRUE; END_IF;
            Mode := 0; Pos := Pos + 1;
        ELSIF Code = 92 THEN Mode := 2; Pos := Pos + 1;
        ELSIF (Code < 32) OR (LEN(Text) >= 512) OR (HighSurrogate <> 0) THEN Error := TRUE;
        ELSE Text := CONCAT(Text,C); Pos := Pos + 1;
        END_IF;
    2:
        IF Code = 117 THEN UCode := 0; HexCount := 0; Mode := 3;
        ELSIF HighSurrogate <> 0 THEN Error := TRUE;
        ELSIF (Code = 34) OR (Code = 92) OR (Code = 47) THEN Text := CONCAT(Text,C); Mode := 1;
        ELSIF Code = 98 THEN ConvertChar(Code := 8, Utf8 := FALSE); Text := CONCAT(Text,ConvertChar.Value); Mode := 1;
        ELSIF Code = 102 THEN ConvertChar(Code := 12, Utf8 := FALSE); Text := CONCAT(Text,ConvertChar.Value); Mode := 1;
        ELSIF Code = 110 THEN ConvertChar(Code := 10, Utf8 := FALSE); Text := CONCAT(Text,ConvertChar.Value); Mode := 1;
        ELSIF Code = 114 THEN ConvertChar(Code := 13, Utf8 := FALSE); Text := CONCAT(Text,ConvertChar.Value); Mode := 1;
        ELSIF Code = 116 THEN ConvertChar(Code := 9, Utf8 := FALSE); Text := CONCAT(Text,ConvertChar.Value); Mode := 1;
        ELSE Error := TRUE;
        END_IF;
        IF LEN(Text) > 512 THEN Error := TRUE; END_IF;
        Pos := Pos + 1;
    3:
        UCode := UCode * 16;
        IF (Code >= 48) AND (Code <= 57) THEN UCode := UCode + Code - 48;
        ELSIF (Code >= 65) AND (Code <= 70) THEN UCode := UCode + Code - 55;
        ELSIF (Code >= 97) AND (Code <= 102) THEN UCode := UCode + Code - 87;
        ELSE Error := TRUE; END_IF;
        HexCount := HexCount + 1; Pos := Pos + 1;
        IF HexCount = 4 THEN
            Mode := 1;
            IF (UCode >= 16#D800) AND (UCode <= 16#DBFF) AND (HighSurrogate = 0) THEN
                HighSurrogate := UCode;
            ELSE
                IF HighSurrogate <> 0 THEN
                    IF (UCode < 16#DC00) OR (UCode > 16#DFFF) THEN Error := TRUE;
                    ELSE UCode := UDINT#65536 + (HighSurrogate - 16#D800) * 1024 + UCode - 16#DC00;
                    END_IF;
                    HighSurrogate := 0;
                ELSIF (UCode >= 16#DC00) AND (UCode <= 16#DFFF) THEN Error := TRUE;
                END_IF;
                (* IEC strings cannot contain NUL. Reject rather than truncate. *)
                IF UCode = 0 THEN Error := TRUE;
                ELSE ConvertChar(Code := UCode, Utf8 := TRUE); Text := CONCAT(Text,ConvertChar.Value);
                END_IF;
                IF LEN(Text) > 512 THEN Error := TRUE; END_IF;
            END_IF;
        END_IF;
    4:
        IF (Pos >= TO_DINT(Length)) OR (Code = 32) OR (Code = 9) OR (Code = 10) OR (Code = 13) OR (Code = 44) OR (Code = 125) OR (Code = 93) THEN
            FinishScalar := TRUE;
        ELSIF LEN(Text) >= 128 THEN Error := TRUE;
        ELSE Text := CONCAT(Text,C); Pos := Pos + 1;
        END_IF;
    END_CASE;
    IF FinishScalar THEN
        FinishScalar := FALSE; Mode := 0; NewValue := TRUE;
        IF (Text = 'true') OR (Text = 'false') THEN Kind := 5;
        ELSIF Text = 'null' THEN Kind := 6;
        ELSIF NG_NumberValid(Text) THEN
            Kind := 4;
            (* Bound conversion exponents before the runtime conversion. *)
            IF (FIND(Text,'e') > 0) OR (FIND(Text,'E') > 0) THEN
                I := FIND(Text,'e'); IF I = 0 THEN I := FIND(Text,'E'); END_IF;
                IF ABS(TO_DINT(MID(Text,LEN(Text)-I,I+1))) > 308 THEN Error := TRUE; END_IF;
            END_IF;
            IF NOT Error THEN Number := TO_LREAL(Text); END_IF;
        ELSE Error := TRUE;
        END_IF;
    END_IF;
    IF NewValue AND NOT Error THEN
        IF Doc.Count >= 8192 THEN Error := TRUE; ErrorText := 'POINT_LIMIT_EXCEEDED';
        ELSE
            Parent := Nodes[Depth];
            IF (Parent > 0) AND (Doc.Tokens[Parent].Kind = 1) THEN
                I := Parent + 1;
                WHILE I <= Doc.Count DO
                    IF Doc.Tokens[I].Key = Keys[Depth] THEN Error := TRUE; EXIT; END_IF;
                    IF Doc.Tokens[I].NextToken <= I THEN Error := TRUE; EXIT; END_IF;
                    I := Doc.Tokens[I].NextToken;
                END_WHILE;
            END_IF;
            Doc.Count := Doc.Count + 1; N := Doc.Count;
            Doc.Tokens[N].Kind := Kind;
            Doc.Tokens[N].Parent := Parent;
            Doc.Tokens[N].Key := Keys[Depth]; Keys[Depth] := '';
            Doc.Tokens[N].TextLength := LEN(Text);
            IF LEN(Text)<=256 THEN Doc.Tokens[N].Text:=Text;
            ELSE
                (* Nested IEC string builtins use an 80-byte temporary. Copy
                   this diagnostic prefix using bounded single-byte results. *)
                Doc.Tokens[N].Text:='';
                FOR ClipIndex:=1 TO 256 DO
                    Doc.Tokens[N].Text:=CONCAT(Doc.Tokens[N].Text,MID(Text,1,ClipIndex));
                END_FOR;
            END_IF;
            Doc.Tokens[N].Number := Number;
            Doc.Tokens[N].Start := Start;
            Doc.Tokens[N].Count := Pos - Start;
            Doc.Tokens[N].NextToken := N + 1;
            IF (Kind = 1) OR (Kind = 2) THEN
                IF Depth >= 64 THEN Error := TRUE;
                ELSE
                    Depth := Depth + 1; Nodes[Depth] := N; Keys[Depth] := '';
                    IF Kind = 1 THEN Expected[Depth] := 0; ELSE Expected[Depth] := 5; END_IF;
                END_IF;
            END_IF;
        END_IF;
    END_IF;
    IF NOT Again THEN Budget := Budget + 1; END_IF;
END_WHILE;
IF Error THEN
    Busy := FALSE; Done := FALSE;
    IF ErrorText = '' THEN ErrorText := 'INVALID_JSON'; END_IF;
END_IF;
END_FUNCTION_BLOCK
