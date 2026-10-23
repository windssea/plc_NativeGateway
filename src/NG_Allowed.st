FUNCTION NG_Allowed : BOOL
VAR_INPUT
    Parent : INT;
    Keys : NG_Text; (* Delimited with |, including first and last separator. *)
END_VAR
VAR_INPUT
    Doc : NG_Document;
END_VAR
VAR
    i : INT;
    key : STRING[68];
END_VAR
NG_Allowed := FALSE;
IF (Parent < 1) OR (Parent > Doc.Count) THEN RETURN; END_IF;
IF Doc.Tokens[Parent].Kind <> 1 THEN RETURN; END_IF;
i := Parent + 1;
WHILE i < Doc.Tokens[Parent].NextToken DO
    key := CONCAT('|', Doc.Tokens[i].Key, '|');
    IF FIND(Keys,key) = 0 THEN RETURN; END_IF;
    IF Doc.Tokens[i].NextToken <= i THEN RETURN; END_IF;
    i := Doc.Tokens[i].NextToken;
END_WHILE;
NG_Allowed := TRUE;
END_FUNCTION
