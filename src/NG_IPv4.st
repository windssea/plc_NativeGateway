FUNCTION NG_IPv4 : BOOL
VAR_INPUT
    Host : STRING[253];
END_VAR
VAR
    i : INT;
    dots : INT;
    digits : INT;
    value : INT;
    c : STRING[1];
END_VAR
NG_IPv4 := FALSE; dots := 0; digits := 0; value := 0;
FOR i := 1 TO LEN(Host) DO
    c := MID(Host,1,i);
    IF c = '.' THEN
        IF (digits = 0) OR (value > 255) THEN RETURN; END_IF;
        dots := dots + 1; digits := 0; value := 0;
    ELSIF (c >= '0') AND (c <= '9') THEN
        value := value * 10 + TO_INT(c); digits := digits + 1;
        IF digits > 3 THEN RETURN; END_IF;
    ELSE RETURN;
    END_IF;
END_FOR;
NG_IPv4 := (dots = 3) AND (digits > 0) AND (value <= 255);
END_FUNCTION
