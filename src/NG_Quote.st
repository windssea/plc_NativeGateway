FUNCTION NG_Quote : NG_Quoted
VAR_INPUT
    s : NG_Text;
END_VAR
VAR
    i : INT;
    c : STRING[1];
    character : INT;
    plain : BOOL;
    characters : ARRAY[0..255] OF BYTE;
    copied : BOOL;
    length : INT;
END_VAR
(* Scan once for escaping; common identities take one final concatenation. *)
plain:=TRUE;
length:=LEN(s); copied:=TRUE;
IF length>0 THEN copied:=STRING_COPY(s,characters,UDINT#0,TO_UDINT(length)); END_IF;
FOR i:=1 TO length DO
    IF copied THEN character:=TO_INT(characters[i-1]);
    ELSE character:=GET_CHAR(s,i); END_IF;
    IF (character<32) OR (character=34) OR (character=92) THEN plain:=FALSE; EXIT; END_IF;
END_FOR;
IF plain THEN NG_Quote:=CONCAT('"',s,'"'); RETURN; END_IF;
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
