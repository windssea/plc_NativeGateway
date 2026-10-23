FUNCTION NG_Bool : STRING
VAR_INPUT
    Value : BOOL;
END_VAR
IF Value THEN NG_Bool := 'true'; ELSE NG_Bool := 'false'; END_IF;
END_FUNCTION
