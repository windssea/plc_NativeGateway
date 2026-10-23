FUNCTION NG_Range : BOOL
VAR_INPUT
    Text : NG_Text;
    Minimum : LREAL;
    Maximum : LREAL;
    IntegerOnly : BOOL;
END_VAR
VAR
    n : LREAL;
END_VAR
NG_Range := FALSE;
IF NOT NG_NumberValid(Text) OR (LEN(Text)>20) THEN RETURN; END_IF;
(* UI configuration values do not need exponent notation. *)
IF (FIND(Text,'e')>0) OR (FIND(Text,'E')>0) THEN RETURN; END_IF;
n := TO_LREAL(Text);
NG_Range := (n >= Minimum) AND (n <= Maximum);
IF IntegerOnly AND (n <> TO_LREAL(TO_LINT(n))) THEN NG_Range := FALSE; END_IF;
END_FUNCTION
