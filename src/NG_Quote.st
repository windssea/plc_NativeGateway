FUNCTION NG_Quote : NG_Quoted
VAR_INPUT
    s : NG_Text;
END_VAR
VAR
    i : INT;
    c : STRING[1];
END_VAR
NG_Quote := '"';
FOR i := 1 TO LEN(s) DO
    c := MID(s,1,i);
    IF c = '"' THEN NG_Quote := CONCAT(NG_Quote,'\\','"');
    ELSIF c = '\\' THEN NG_Quote := CONCAT(NG_Quote,'\\\\');
    ELSIF c = '\n' THEN NG_Quote := CONCAT(NG_Quote,'\\n');
    ELSIF GET_CHAR(c,1) = 13 THEN NG_Quote := CONCAT(NG_Quote,'\\r');
    ELSIF c = '\t' THEN NG_Quote := CONCAT(NG_Quote,'\\t');
    ELSE NG_Quote := CONCAT(NG_Quote,c);
    END_IF;
END_FOR;
NG_Quote := CONCAT(NG_Quote,'"');
END_FUNCTION
