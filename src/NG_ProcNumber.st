FUNCTION NG_ProcNumber : ULINT
VAR_INPUT
    Text : NG_ProcText;
    Key : STRING[64];
END_VAR
VAR
    p : INT;
    n : INT;
    c : INT;
    started : BOOL;
END_VAR
NG_ProcNumber := 0; started := FALSE; p := FIND(Text,Key); IF p = 0 THEN RETURN; END_IF;
p := p+LEN(Key); n := LEN(Text);
WHILE p <= n DO
    c := GET_CHAR(Text,p);
    IF (c >= 48) AND (c <= 57) THEN NG_ProcNumber := NG_ProcNumber*10+TO_ULINT(c-48); started := TRUE;
    ELSIF started OR ((c <> 32) AND (c <> 9)) THEN RETURN;
    END_IF;
    p := p+1;
END_WHILE;
END_FUNCTION
