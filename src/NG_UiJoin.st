FUNCTION NG_UiJoin : NG_UiLabel
VAR_INPUT
    A : NG_UiLabel;
    B : NG_UiLabel;
    C : NG_UiLabel;
    D : NG_UiLabel;
    E : NG_UiLabel;
    F : NG_UiLabel;
    G : NG_UiLabel;
    H : NG_UiLabel;
END_VAR
VAR
    Buffer : NG_UiLabel;
    Parts : ARRAY[1..8] OF NG_UiLabel;
    Chunk : NG_UiLabel;
    Remaining : INT;
    i : INT;
END_VAR
(* Explicit intermediates avoid the vendor's default 80-character FU temporary. *)
Parts[1]:=A; Parts[2]:=B; Parts[3]:=C; Parts[4]:=D;
Parts[5]:=E; Parts[6]:=F; Parts[7]:=G; Parts[8]:=H;
Buffer:="";
FOR i:=1 TO 8 DO
    Remaining:=256-LEN(Buffer);
    IF Remaining<=0 THEN EXIT; END_IF;
    Chunk:=Parts[i];
    IF LEN(Chunk)>Remaining THEN Chunk:=LEFT_WSTRING(Chunk,Remaining); END_IF;
    Buffer:=CONCAT_WSTRING(Buffer,Chunk);
END_FOR;
NG_UiJoin:=Buffer;
END_FUNCTION
