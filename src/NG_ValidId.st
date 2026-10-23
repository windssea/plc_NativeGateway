FUNCTION NG_ValidId : BOOL
VAR_INPUT
    s : NG_Id;
END_VAR
VAR
    i : INT;
    c : STRING[1];
END_VAR
NG_ValidId := (LEN(s) > 0) AND (LEN(s) <= 64);
FOR i := 1 TO LEN(s) DO
    c := MID(s, 1, i);
    IF NOT (((c >= 'A') AND (c <= 'Z')) OR ((c >= 'a') AND (c <= 'z')) OR ((c >= '0') AND (c <= '9')) OR ((i > 1) AND ((c = '.') OR (c = '_') OR (c = '-')))) THEN
        NG_ValidId := FALSE;
    END_IF;
END_FOR;
END_FUNCTION
