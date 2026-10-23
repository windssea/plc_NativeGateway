FUNCTION NG_Member : INT
VAR_INPUT
    Parent : INT;
    Key : NG_Id;
END_VAR
VAR_INPUT
    Doc : NG_Document;
END_VAR
VAR
    i : INT;
END_VAR
NG_Member := 0;
IF (Parent < 1) OR (Parent > Doc.Count) THEN RETURN; END_IF;
i := Parent + 1;
WHILE i < Doc.Tokens[Parent].NextToken DO
    IF Doc.Tokens[i].Key = Key THEN NG_Member := i; RETURN; END_IF;
    IF Doc.Tokens[i].NextToken <= i THEN RETURN; END_IF;
    i := Doc.Tokens[i].NextToken;
END_WHILE;
END_FUNCTION
