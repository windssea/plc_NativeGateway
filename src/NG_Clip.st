FUNCTION NG_Clip : NG_Text
VAR_INPUT
    Value : NG_Text;
END_VAR
IF LEN(Value) > 48 THEN NG_Clip := CONCAT(LEFT(Value,45),'...');
ELSE NG_Clip := Value; END_IF;
END_FUNCTION
