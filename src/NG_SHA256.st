FUNCTION_BLOCK NG_SHA256
VAR_INPUT
    Execute : BOOL;
    Length : UDINT;
END_VAR
VAR_IN_OUT
    Buffer : NG_Bytes;
END_VAR
VAR_OUTPUT
    Busy : BOOL;
    Done : BOOL;
    Digest : STRING[64];
END_VAR
VAR
    Prev : BOOL;
    Block : UDINT;
    Blocks : UDINT;
    Offset : UDINT;
    i : INT;
    j : INT;
    n : INT;
    v : DWORD;
    a : DWORD;
    b : DWORD;
    c : DWORD;
    d : DWORD;
    e : DWORD;
    f : DWORD;
    g : DWORD;
    h : DWORD;
    s0 : DWORD;
    s1 : DWORD;
    t1 : DWORD;
    t2 : DWORD;
    Hs : ARRAY[0..7] OF DWORD;
    W : ARRAY[0..63] OF DWORD;
    K : ARRAY[0..63] OF DWORD := [16#428A2F98,16#71374491,16#B5C0FBCF,16#E9B5DBA5,16#3956C25B,16#59F111F1,16#923F82A4,16#AB1C5ED5,16#D807AA98,16#12835B01,16#243185BE,16#550C7DC3,16#72BE5D74,16#80DEB1FE,16#9BDC06A7,16#C19BF174,16#E49B69C1,16#EFBE4786,16#0FC19DC6,16#240CA1CC,16#2DE92C6F,16#4A7484AA,16#5CB0A9DC,16#76F988DA,16#983E5152,16#A831C66D,16#B00327C8,16#BF597FC7,16#C6E00BF3,16#D5A79147,16#06CA6351,16#14292967,16#27B70A85,16#2E1B2138,16#4D2C6DFC,16#53380D13,16#650A7354,16#766A0ABB,16#81C2C92E,16#92722C85,16#A2BFE8A1,16#A81A664B,16#C24B8B70,16#C76C51A3,16#D192E819,16#D6990624,16#F40E3585,16#106AA070,16#19A4C116,16#1E376C08,16#2748774C,16#34B0BCB5,16#391C0CB3,16#4ED8AA4A,16#5B9CCA4F,16#682E6FF3,16#748F82EE,16#78A5636F,16#84C87814,16#8CC70208,16#90BEFFFA,16#A4506CEB,16#BEF9A3F7,16#C67178F2];
END_VAR
IF Execute AND NOT Prev AND NOT Busy THEN
    Hs[0] := 16#6A09E667; Hs[1] := 16#BB67AE85; Hs[2] := 16#3C6EF372; Hs[3] := 16#A54FF53A;
    Hs[4] := 16#510E527F; Hs[5] := 16#9B05688C; Hs[6] := 16#1F83D9AB; Hs[7] := 16#5BE0CD19;
    Block := 0; Blocks := (Length + 72) / 64; Busy := TRUE; Done := FALSE; Digest := '';
END_IF;
Prev := Execute;
IF NOT Busy THEN RETURN; END_IF;
FOR n := 1 TO 8 DO
    FOR i := 0 TO 15 DO
        W[i] := 0;
        FOR j := 0 TO 3 DO
            Offset := Block*64 + TO_UDINT(i*4+j);
            IF Offset < Length THEN v := TO_DWORD(Buffer[Offset]);
            ELSIF Offset = Length THEN v := DWORD#16#80;
            ELSIF Offset >= Blocks*64-8 THEN v := TO_DWORD(SHR(TO_LWORD(TO_ULINT(Length)*ULINT#8),TO_UINT((Blocks*64-1-Offset)*8)) AND LWORD#255);
            ELSE v := 0; END_IF;
            W[i] := SHL(W[i],8) OR v;
        END_FOR;
    END_FOR;
    FOR i := 16 TO 63 DO
        s0 := ROR(W[i-15],7) XOR ROR(W[i-15],18) XOR SHR(W[i-15],3);
        s1 := ROR(W[i-2],17) XOR ROR(W[i-2],19) XOR SHR(W[i-2],10);
        W[i] := NG_Add4(W[i-16],s0,W[i-7],s1);
    END_FOR;
    a := Hs[0]; b := Hs[1]; c := Hs[2]; d := Hs[3]; e := Hs[4]; f := Hs[5]; g := Hs[6]; h := Hs[7];
    FOR i := 0 TO 63 DO
        s1 := ROR(e,6) XOR ROR(e,11) XOR ROR(e,25);
        t1 := NG_Add4(h,s1,(e AND f) XOR ((NOT e) AND g),K[i]);
        t1 := NG_Add4(t1,W[i],DWORD#0,DWORD#0);
        s0 := ROR(a,2) XOR ROR(a,13) XOR ROR(a,22);
        t2 := NG_Add4(s0,(a AND b) XOR (a AND c) XOR (b AND c),DWORD#0,DWORD#0);
        h := g; g := f; f := e; e := NG_Add4(d,t1,DWORD#0,DWORD#0);
        d := c; c := b; b := a; a := NG_Add4(t1,t2,DWORD#0,DWORD#0);
    END_FOR;
    Hs[0] := NG_Add4(Hs[0],a,DWORD#0,DWORD#0); Hs[1] := NG_Add4(Hs[1],b,DWORD#0,DWORD#0);
    Hs[2] := NG_Add4(Hs[2],c,DWORD#0,DWORD#0); Hs[3] := NG_Add4(Hs[3],d,DWORD#0,DWORD#0);
    Hs[4] := NG_Add4(Hs[4],e,DWORD#0,DWORD#0); Hs[5] := NG_Add4(Hs[5],f,DWORD#0,DWORD#0);
    Hs[6] := NG_Add4(Hs[6],g,DWORD#0,DWORD#0); Hs[7] := NG_Add4(Hs[7],h,DWORD#0,DWORD#0);
    Block := Block + 1;
    IF Block >= Blocks THEN
        FOR i := 0 TO 7 DO Digest := CONCAT(Digest,TO_STRING(Hs[i],'{0:x8}')); END_FOR;
        Busy := FALSE; Done := TRUE; EXIT;
    END_IF;
END_FOR;
END_FUNCTION_BLOCK
