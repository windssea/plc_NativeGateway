FUNCTION NG_NumberValid : BOOL
VAR_INPUT
    s : NG_Text;
END_VAR
VAR
    i : INT;
    n : INT;
    start : INT;
    c : STRING[1];
END_VAR
NG_NumberValid := FALSE;
n := LEN(s); i := 1;
IF n = 0 THEN RETURN; END_IF;
IF MID(s,1,i) = '-' THEN i := i + 1; END_IF;
IF i > n THEN RETURN; END_IF;
c := MID(s,1,i);
IF c = '0' THEN
    i := i + 1;
ELSIF (c >= '1') AND (c <= '9') THEN
    WHILE i <= n DO
        c := MID(s,1,i);
        IF (c < '0') OR (c > '9') THEN EXIT; END_IF;
        i := i + 1;
    END_WHILE;
ELSE RETURN;
END_IF;
IF i > n THEN NG_NumberValid := TRUE; RETURN; END_IF;
IF MID(s,1,i) = '.' THEN
    i := i + 1; start := i;
    WHILE i <= n DO
        c := MID(s,1,i);
        IF (c < '0') OR (c > '9') THEN EXIT; END_IF;
        i := i + 1;
    END_WHILE;
    IF i = start THEN RETURN; END_IF;
END_IF;
IF i > n THEN NG_NumberValid := TRUE; RETURN; END_IF;
c := MID(s,1,i);
IF (c = 'e') OR (c = 'E') THEN
    i := i + 1; IF i > n THEN RETURN; END_IF; c := MID(s,1,i);
    IF (c = '+') OR (c = '-') THEN i := i + 1; END_IF;
    start := i;
    WHILE i <= n DO
        c := MID(s,1,i);
        IF (c < '0') OR (c > '9') THEN EXIT; END_IF;
        i := i + 1;
    END_WHILE;
    IF i = start THEN RETURN; END_IF;
END_IF;
NG_NumberValid := i = n + 1;
END_FUNCTION
