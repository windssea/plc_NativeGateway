FUNCTION NG_Unix : ULINT
VAR_INPUT
    Clock : RTC_TYPE;
    UtcOffsetMinutes : INT;
END_VAR
VAR
    y : DINT;
    m : DINT;
    days : LINT;
    md : DINT;
    seconds : LINT;
END_VAR
NG_Unix := 0;
IF (Clock.YEAR < 2020) OR (Clock.YEAR > 2199) OR (Clock.MONTH < 1) OR (Clock.MONTH > 12) OR (Clock.DAY < 1) OR (Clock.DAY > 31) THEN RETURN; END_IF;
days := 0;
FOR y := 1970 TO TO_DINT(Clock.YEAR)-1 DO
    days := days + 365;
    IF ((y MOD 4 = 0) AND (y MOD 100 <> 0)) OR (y MOD 400 = 0) THEN days := days + 1; END_IF;
END_FOR;
FOR m := 1 TO TO_DINT(Clock.MONTH)-1 DO
    CASE m OF
        4,6,9,11: md := 30;
        2:
            md := 28; y := TO_DINT(Clock.YEAR);
            IF ((y MOD 4 = 0) AND (y MOD 100 <> 0)) OR (y MOD 400 = 0) THEN md := 29; END_IF;
        ELSE md := 31;
    END_CASE;
    days := days + md;
END_FOR;
days := days + Clock.DAY - 1;
seconds := days * 86400 + TO_LINT(Clock.HOURS) * 3600 + TO_LINT(Clock.MINUTES) * 60 + Clock.SECONDS - TO_LINT(UtcOffsetMinutes)*60;
IF seconds > 0 THEN NG_Unix := TO_ULINT(seconds)*1000; END_IF;
END_FUNCTION
