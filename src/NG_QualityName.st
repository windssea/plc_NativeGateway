FUNCTION NG_QualityName : NG_Text
VAR_INPUT
    Code : USINT;
END_VAR
CASE Code OF
2: NG_QualityName:='GOOD';
3: NG_QualityName:='STALE';
4: NG_QualityName:='BAD_CONNECTION';
5: NG_QualityName:='BAD_TIMEOUT';
6: NG_QualityName:='BAD_PROTOCOL';
7: NG_QualityName:='BAD_DECODE';
ELSE NG_QualityName:='UNKNOWN';
END_CASE;
END_FUNCTION
