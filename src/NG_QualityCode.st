FUNCTION NG_QualityCode : USINT
VAR_INPUT
    Quality : STRING[24];
END_VAR
NG_QualityCode := 7;
IF Quality='UNKNOWN' THEN NG_QualityCode:=1;
ELSIF Quality='GOOD' THEN NG_QualityCode:=2;
ELSIF Quality='STALE' THEN NG_QualityCode:=3;
ELSIF Quality='BAD_CONNECTION' THEN NG_QualityCode:=4;
ELSIF Quality='BAD_TIMEOUT' THEN NG_QualityCode:=5;
ELSIF Quality='BAD_PROTOCOL' THEN NG_QualityCode:=6;
END_IF;
END_FUNCTION
