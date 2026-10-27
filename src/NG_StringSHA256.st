FUNCTION_BLOCK NG_StringSHA256
VAR_INPUT
    Execute : BOOL;
    Length : UDINT;
    DeadlineUs : ULINT;
END_VAR
VAR_IN_OUT
    Payload : NG_Json;
END_VAR
VAR_OUTPUT
    Busy : BOOL;
    Done : BOOL;
    Error : BOOL;
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
    BlockLength : INT;
    Hs : ARRAY[0..7] OF DWORD;
    W : ARRAY[0..63] OF DWORD;
    BlockText : STRING[64];
    ByteOrderProbe : STRING[4] := 'ABCD';
    NativeLittleEndian : BOOL;
    CopyOk : BOOL;
    CopyStatus : UINT;
    HexIndex : INT;
    ReserveUs : ULINT;
END_VAR
IF NOT Execute THEN Busy:=FALSE; Done:=FALSE; Error:=FALSE; Prev:=FALSE; RETURN; END_IF;
IF Error THEN RETURN; END_IF;
IF Execute AND NOT Prev AND NOT Busy THEN
    IF (Length>16380) OR (Length<>TO_UDINT(LEN(Payload))) THEN Error:=TRUE; RETURN; END_IF;
    (* The copy targets complete DWORD elements. Determine byte order from a
       fixed non-palindromic probe; never infer it from arbitrary payload data. *)
    CopyOk:=STRING_COPY(ByteOrderProbe,W,UDINT#0,UDINT#4);
    IF NOT CopyOk THEN Error:=TRUE; RETURN; END_IF;
    IF W[0]=DWORD#16#44434241 THEN NativeLittleEndian:=TRUE;
    ELSIF W[0]=DWORD#16#41424344 THEN NativeLittleEndian:=FALSE;
    ELSE Error:=TRUE; RETURN; END_IF;
    (* Engineer documents the runtime STRING's 4-byte header. Independently
       fence MEMORY_COPY's raw-area interpretation against STRING_COPY's
       character-only interpretation before using an offset on any payload. *)
    CopyStatus:=MEMORY_COPY(ByteOrderProbe,UDINT#4,W,UDINT#0,UDINT#4);
    IF CopyStatus<>0 THEN Error:=TRUE; RETURN; END_IF;
    IF NativeLittleEndian THEN
        IF W[0]<>DWORD#16#44434241 THEN Error:=TRUE; RETURN; END_IF;
    ELSE
        IF W[0]<>DWORD#16#41424344 THEN Error:=TRUE; RETURN; END_IF;
    END_IF;
    Hs[0] := 16#6A09E667; Hs[1] := 16#BB67AE85; Hs[2] := 16#3C6EF372; Hs[3] := 16#A54FF53A;
    Hs[4] := 16#510E527F; Hs[5] := 16#9B05688C; Hs[6] := 16#1F83D9AB; Hs[7] := 16#5BE0CD19;
    Block := 0; HexIndex:=0; Blocks := (Length + 72) / 64; Busy := TRUE; Done := FALSE; Digest := '';
END_IF;
Prev := Execute;
IF NOT Busy THEN RETURN; END_IF;
(* Full blocks use bounded native MEMORY_COPY into the first 16 working words.
   Padding reads only valid remaining bytes, without whole-payload copies. *)
(* Fixed rotates are emitted as shifts/OR: eCLR otherwise calls ROR_DWORD
   576 times per block. Constant indices remove repeated array-bound calls. *)
(* SHA-256 additions intentionally use the documented unsigned overflow value
   modulo 2^32. UDINT arithmetic avoids ARM 64-bit conversion/add/mask work;
   native golden-vector and long-payload tests fence this target behaviour. *)
FOR n := 1 TO 64 DO
    (* A completed compression must never be repeated while formatting waits. *)
    IF Block>=Blocks THEN EXIT; END_IF;
    IF DeadlineUs=0 THEN IF n>8 THEN EXIT; END_IF;
    ELSE
        ReserveUs:=ULINT#60;
        (* Padding uses bounded character/length work rather than the fast copy. *)
        IF Block*64+64>Length THEN ReserveUs:=ULINT#180; END_IF;
        IF GET_MICROSECONDS(TRUE)+ReserveUs>=DeadlineUs THEN EXIT; END_IF;
    END_IF;
    Offset:=Block*64; BlockLength:=0;
    IF Offset<Length THEN BlockLength:=TO_INT(MIN(UDINT#64,Length-Offset)); END_IF;
    IF BlockLength=64 THEN
        CopyStatus:=MEMORY_COPY(Payload,Offset+UDINT#4,W,UDINT#0,UDINT#64);
        IF CopyStatus<>0 THEN Error:=TRUE; Busy:=FALSE; RETURN; END_IF;
        IF NativeLittleEndian THEN
            W[0]:=SHR(W[0],24) OR (SHR(W[0],8) AND DWORD#16#0000FF00) OR (SHL(W[0],8) AND DWORD#16#00FF0000) OR SHL(W[0],24);
            W[1]:=SHR(W[1],24) OR (SHR(W[1],8) AND DWORD#16#0000FF00) OR (SHL(W[1],8) AND DWORD#16#00FF0000) OR SHL(W[1],24);
            W[2]:=SHR(W[2],24) OR (SHR(W[2],8) AND DWORD#16#0000FF00) OR (SHL(W[2],8) AND DWORD#16#00FF0000) OR SHL(W[2],24);
            W[3]:=SHR(W[3],24) OR (SHR(W[3],8) AND DWORD#16#0000FF00) OR (SHL(W[3],8) AND DWORD#16#00FF0000) OR SHL(W[3],24);
            W[4]:=SHR(W[4],24) OR (SHR(W[4],8) AND DWORD#16#0000FF00) OR (SHL(W[4],8) AND DWORD#16#00FF0000) OR SHL(W[4],24);
            W[5]:=SHR(W[5],24) OR (SHR(W[5],8) AND DWORD#16#0000FF00) OR (SHL(W[5],8) AND DWORD#16#00FF0000) OR SHL(W[5],24);
            W[6]:=SHR(W[6],24) OR (SHR(W[6],8) AND DWORD#16#0000FF00) OR (SHL(W[6],8) AND DWORD#16#00FF0000) OR SHL(W[6],24);
            W[7]:=SHR(W[7],24) OR (SHR(W[7],8) AND DWORD#16#0000FF00) OR (SHL(W[7],8) AND DWORD#16#00FF0000) OR SHL(W[7],24);
            W[8]:=SHR(W[8],24) OR (SHR(W[8],8) AND DWORD#16#0000FF00) OR (SHL(W[8],8) AND DWORD#16#00FF0000) OR SHL(W[8],24);
            W[9]:=SHR(W[9],24) OR (SHR(W[9],8) AND DWORD#16#0000FF00) OR (SHL(W[9],8) AND DWORD#16#00FF0000) OR SHL(W[9],24);
            W[10]:=SHR(W[10],24) OR (SHR(W[10],8) AND DWORD#16#0000FF00) OR (SHL(W[10],8) AND DWORD#16#00FF0000) OR SHL(W[10],24);
            W[11]:=SHR(W[11],24) OR (SHR(W[11],8) AND DWORD#16#0000FF00) OR (SHL(W[11],8) AND DWORD#16#00FF0000) OR SHL(W[11],24);
            W[12]:=SHR(W[12],24) OR (SHR(W[12],8) AND DWORD#16#0000FF00) OR (SHL(W[12],8) AND DWORD#16#00FF0000) OR SHL(W[12],24);
            W[13]:=SHR(W[13],24) OR (SHR(W[13],8) AND DWORD#16#0000FF00) OR (SHL(W[13],8) AND DWORD#16#00FF0000) OR SHL(W[13],24);
            W[14]:=SHR(W[14],24) OR (SHR(W[14],8) AND DWORD#16#0000FF00) OR (SHL(W[14],8) AND DWORD#16#00FF0000) OR SHL(W[14],24);
            W[15]:=SHR(W[15],24) OR (SHR(W[15],8) AND DWORD#16#0000FF00) OR (SHL(W[15],8) AND DWORD#16#00FF0000) OR SHL(W[15],24);
        END_IF;
    ELSE
    FOR i := 0 TO 15 DO
        W[i] := 0;
        FOR j := 0 TO 3 DO
            Offset := Block*64 + TO_UDINT(i*4+j);
            IF Offset < Length THEN v := TO_DWORD(TO_BYTE(GET_CHAR(Payload,TO_INT(Offset)+1)));
            ELSIF Offset = Length THEN v := DWORD#16#80;
            ELSIF Offset >= Blocks*64-8 THEN v := TO_DWORD(SHR(TO_LWORD(TO_ULINT(Length)*ULINT#8),TO_UINT((Blocks*64-1-Offset)*8)) AND LWORD#255);
            ELSE v := 0; END_IF;
            W[i] := SHL(W[i],8) OR v;
        END_FOR;
    END_FOR;
    END_IF;
    (* W16 *)
        s0 := (SHR(W[1],7) OR SHL(W[1],25)) XOR (SHR(W[1],18) OR SHL(W[1],14)) XOR SHR(W[1],3);
        s1 := (SHR(W[14],17) OR SHL(W[14],15)) XOR (SHR(W[14],19) OR SHL(W[14],13)) XOR SHR(W[14],10);
        W[16] := TO_DWORD(TO_UDINT(W[0])+TO_UDINT(s0)+TO_UDINT(W[9])+TO_UDINT(s1));
    (* W17 *)
        s0 := (SHR(W[2],7) OR SHL(W[2],25)) XOR (SHR(W[2],18) OR SHL(W[2],14)) XOR SHR(W[2],3);
        s1 := (SHR(W[15],17) OR SHL(W[15],15)) XOR (SHR(W[15],19) OR SHL(W[15],13)) XOR SHR(W[15],10);
        W[17] := TO_DWORD(TO_UDINT(W[1])+TO_UDINT(s0)+TO_UDINT(W[10])+TO_UDINT(s1));
    (* W18 *)
        s0 := (SHR(W[3],7) OR SHL(W[3],25)) XOR (SHR(W[3],18) OR SHL(W[3],14)) XOR SHR(W[3],3);
        s1 := (SHR(W[16],17) OR SHL(W[16],15)) XOR (SHR(W[16],19) OR SHL(W[16],13)) XOR SHR(W[16],10);
        W[18] := TO_DWORD(TO_UDINT(W[2])+TO_UDINT(s0)+TO_UDINT(W[11])+TO_UDINT(s1));
    (* W19 *)
        s0 := (SHR(W[4],7) OR SHL(W[4],25)) XOR (SHR(W[4],18) OR SHL(W[4],14)) XOR SHR(W[4],3);
        s1 := (SHR(W[17],17) OR SHL(W[17],15)) XOR (SHR(W[17],19) OR SHL(W[17],13)) XOR SHR(W[17],10);
        W[19] := TO_DWORD(TO_UDINT(W[3])+TO_UDINT(s0)+TO_UDINT(W[12])+TO_UDINT(s1));
    (* W20 *)
        s0 := (SHR(W[5],7) OR SHL(W[5],25)) XOR (SHR(W[5],18) OR SHL(W[5],14)) XOR SHR(W[5],3);
        s1 := (SHR(W[18],17) OR SHL(W[18],15)) XOR (SHR(W[18],19) OR SHL(W[18],13)) XOR SHR(W[18],10);
        W[20] := TO_DWORD(TO_UDINT(W[4])+TO_UDINT(s0)+TO_UDINT(W[13])+TO_UDINT(s1));
    (* W21 *)
        s0 := (SHR(W[6],7) OR SHL(W[6],25)) XOR (SHR(W[6],18) OR SHL(W[6],14)) XOR SHR(W[6],3);
        s1 := (SHR(W[19],17) OR SHL(W[19],15)) XOR (SHR(W[19],19) OR SHL(W[19],13)) XOR SHR(W[19],10);
        W[21] := TO_DWORD(TO_UDINT(W[5])+TO_UDINT(s0)+TO_UDINT(W[14])+TO_UDINT(s1));
    (* W22 *)
        s0 := (SHR(W[7],7) OR SHL(W[7],25)) XOR (SHR(W[7],18) OR SHL(W[7],14)) XOR SHR(W[7],3);
        s1 := (SHR(W[20],17) OR SHL(W[20],15)) XOR (SHR(W[20],19) OR SHL(W[20],13)) XOR SHR(W[20],10);
        W[22] := TO_DWORD(TO_UDINT(W[6])+TO_UDINT(s0)+TO_UDINT(W[15])+TO_UDINT(s1));
    (* W23 *)
        s0 := (SHR(W[8],7) OR SHL(W[8],25)) XOR (SHR(W[8],18) OR SHL(W[8],14)) XOR SHR(W[8],3);
        s1 := (SHR(W[21],17) OR SHL(W[21],15)) XOR (SHR(W[21],19) OR SHL(W[21],13)) XOR SHR(W[21],10);
        W[23] := TO_DWORD(TO_UDINT(W[7])+TO_UDINT(s0)+TO_UDINT(W[16])+TO_UDINT(s1));
    (* W24 *)
        s0 := (SHR(W[9],7) OR SHL(W[9],25)) XOR (SHR(W[9],18) OR SHL(W[9],14)) XOR SHR(W[9],3);
        s1 := (SHR(W[22],17) OR SHL(W[22],15)) XOR (SHR(W[22],19) OR SHL(W[22],13)) XOR SHR(W[22],10);
        W[24] := TO_DWORD(TO_UDINT(W[8])+TO_UDINT(s0)+TO_UDINT(W[17])+TO_UDINT(s1));
    (* W25 *)
        s0 := (SHR(W[10],7) OR SHL(W[10],25)) XOR (SHR(W[10],18) OR SHL(W[10],14)) XOR SHR(W[10],3);
        s1 := (SHR(W[23],17) OR SHL(W[23],15)) XOR (SHR(W[23],19) OR SHL(W[23],13)) XOR SHR(W[23],10);
        W[25] := TO_DWORD(TO_UDINT(W[9])+TO_UDINT(s0)+TO_UDINT(W[18])+TO_UDINT(s1));
    (* W26 *)
        s0 := (SHR(W[11],7) OR SHL(W[11],25)) XOR (SHR(W[11],18) OR SHL(W[11],14)) XOR SHR(W[11],3);
        s1 := (SHR(W[24],17) OR SHL(W[24],15)) XOR (SHR(W[24],19) OR SHL(W[24],13)) XOR SHR(W[24],10);
        W[26] := TO_DWORD(TO_UDINT(W[10])+TO_UDINT(s0)+TO_UDINT(W[19])+TO_UDINT(s1));
    (* W27 *)
        s0 := (SHR(W[12],7) OR SHL(W[12],25)) XOR (SHR(W[12],18) OR SHL(W[12],14)) XOR SHR(W[12],3);
        s1 := (SHR(W[25],17) OR SHL(W[25],15)) XOR (SHR(W[25],19) OR SHL(W[25],13)) XOR SHR(W[25],10);
        W[27] := TO_DWORD(TO_UDINT(W[11])+TO_UDINT(s0)+TO_UDINT(W[20])+TO_UDINT(s1));
    (* W28 *)
        s0 := (SHR(W[13],7) OR SHL(W[13],25)) XOR (SHR(W[13],18) OR SHL(W[13],14)) XOR SHR(W[13],3);
        s1 := (SHR(W[26],17) OR SHL(W[26],15)) XOR (SHR(W[26],19) OR SHL(W[26],13)) XOR SHR(W[26],10);
        W[28] := TO_DWORD(TO_UDINT(W[12])+TO_UDINT(s0)+TO_UDINT(W[21])+TO_UDINT(s1));
    (* W29 *)
        s0 := (SHR(W[14],7) OR SHL(W[14],25)) XOR (SHR(W[14],18) OR SHL(W[14],14)) XOR SHR(W[14],3);
        s1 := (SHR(W[27],17) OR SHL(W[27],15)) XOR (SHR(W[27],19) OR SHL(W[27],13)) XOR SHR(W[27],10);
        W[29] := TO_DWORD(TO_UDINT(W[13])+TO_UDINT(s0)+TO_UDINT(W[22])+TO_UDINT(s1));
    (* W30 *)
        s0 := (SHR(W[15],7) OR SHL(W[15],25)) XOR (SHR(W[15],18) OR SHL(W[15],14)) XOR SHR(W[15],3);
        s1 := (SHR(W[28],17) OR SHL(W[28],15)) XOR (SHR(W[28],19) OR SHL(W[28],13)) XOR SHR(W[28],10);
        W[30] := TO_DWORD(TO_UDINT(W[14])+TO_UDINT(s0)+TO_UDINT(W[23])+TO_UDINT(s1));
    (* W31 *)
        s0 := (SHR(W[16],7) OR SHL(W[16],25)) XOR (SHR(W[16],18) OR SHL(W[16],14)) XOR SHR(W[16],3);
        s1 := (SHR(W[29],17) OR SHL(W[29],15)) XOR (SHR(W[29],19) OR SHL(W[29],13)) XOR SHR(W[29],10);
        W[31] := TO_DWORD(TO_UDINT(W[15])+TO_UDINT(s0)+TO_UDINT(W[24])+TO_UDINT(s1));
    (* W32 *)
        s0 := (SHR(W[17],7) OR SHL(W[17],25)) XOR (SHR(W[17],18) OR SHL(W[17],14)) XOR SHR(W[17],3);
        s1 := (SHR(W[30],17) OR SHL(W[30],15)) XOR (SHR(W[30],19) OR SHL(W[30],13)) XOR SHR(W[30],10);
        W[32] := TO_DWORD(TO_UDINT(W[16])+TO_UDINT(s0)+TO_UDINT(W[25])+TO_UDINT(s1));
    (* W33 *)
        s0 := (SHR(W[18],7) OR SHL(W[18],25)) XOR (SHR(W[18],18) OR SHL(W[18],14)) XOR SHR(W[18],3);
        s1 := (SHR(W[31],17) OR SHL(W[31],15)) XOR (SHR(W[31],19) OR SHL(W[31],13)) XOR SHR(W[31],10);
        W[33] := TO_DWORD(TO_UDINT(W[17])+TO_UDINT(s0)+TO_UDINT(W[26])+TO_UDINT(s1));
    (* W34 *)
        s0 := (SHR(W[19],7) OR SHL(W[19],25)) XOR (SHR(W[19],18) OR SHL(W[19],14)) XOR SHR(W[19],3);
        s1 := (SHR(W[32],17) OR SHL(W[32],15)) XOR (SHR(W[32],19) OR SHL(W[32],13)) XOR SHR(W[32],10);
        W[34] := TO_DWORD(TO_UDINT(W[18])+TO_UDINT(s0)+TO_UDINT(W[27])+TO_UDINT(s1));
    (* W35 *)
        s0 := (SHR(W[20],7) OR SHL(W[20],25)) XOR (SHR(W[20],18) OR SHL(W[20],14)) XOR SHR(W[20],3);
        s1 := (SHR(W[33],17) OR SHL(W[33],15)) XOR (SHR(W[33],19) OR SHL(W[33],13)) XOR SHR(W[33],10);
        W[35] := TO_DWORD(TO_UDINT(W[19])+TO_UDINT(s0)+TO_UDINT(W[28])+TO_UDINT(s1));
    (* W36 *)
        s0 := (SHR(W[21],7) OR SHL(W[21],25)) XOR (SHR(W[21],18) OR SHL(W[21],14)) XOR SHR(W[21],3);
        s1 := (SHR(W[34],17) OR SHL(W[34],15)) XOR (SHR(W[34],19) OR SHL(W[34],13)) XOR SHR(W[34],10);
        W[36] := TO_DWORD(TO_UDINT(W[20])+TO_UDINT(s0)+TO_UDINT(W[29])+TO_UDINT(s1));
    (* W37 *)
        s0 := (SHR(W[22],7) OR SHL(W[22],25)) XOR (SHR(W[22],18) OR SHL(W[22],14)) XOR SHR(W[22],3);
        s1 := (SHR(W[35],17) OR SHL(W[35],15)) XOR (SHR(W[35],19) OR SHL(W[35],13)) XOR SHR(W[35],10);
        W[37] := TO_DWORD(TO_UDINT(W[21])+TO_UDINT(s0)+TO_UDINT(W[30])+TO_UDINT(s1));
    (* W38 *)
        s0 := (SHR(W[23],7) OR SHL(W[23],25)) XOR (SHR(W[23],18) OR SHL(W[23],14)) XOR SHR(W[23],3);
        s1 := (SHR(W[36],17) OR SHL(W[36],15)) XOR (SHR(W[36],19) OR SHL(W[36],13)) XOR SHR(W[36],10);
        W[38] := TO_DWORD(TO_UDINT(W[22])+TO_UDINT(s0)+TO_UDINT(W[31])+TO_UDINT(s1));
    (* W39 *)
        s0 := (SHR(W[24],7) OR SHL(W[24],25)) XOR (SHR(W[24],18) OR SHL(W[24],14)) XOR SHR(W[24],3);
        s1 := (SHR(W[37],17) OR SHL(W[37],15)) XOR (SHR(W[37],19) OR SHL(W[37],13)) XOR SHR(W[37],10);
        W[39] := TO_DWORD(TO_UDINT(W[23])+TO_UDINT(s0)+TO_UDINT(W[32])+TO_UDINT(s1));
    (* W40 *)
        s0 := (SHR(W[25],7) OR SHL(W[25],25)) XOR (SHR(W[25],18) OR SHL(W[25],14)) XOR SHR(W[25],3);
        s1 := (SHR(W[38],17) OR SHL(W[38],15)) XOR (SHR(W[38],19) OR SHL(W[38],13)) XOR SHR(W[38],10);
        W[40] := TO_DWORD(TO_UDINT(W[24])+TO_UDINT(s0)+TO_UDINT(W[33])+TO_UDINT(s1));
    (* W41 *)
        s0 := (SHR(W[26],7) OR SHL(W[26],25)) XOR (SHR(W[26],18) OR SHL(W[26],14)) XOR SHR(W[26],3);
        s1 := (SHR(W[39],17) OR SHL(W[39],15)) XOR (SHR(W[39],19) OR SHL(W[39],13)) XOR SHR(W[39],10);
        W[41] := TO_DWORD(TO_UDINT(W[25])+TO_UDINT(s0)+TO_UDINT(W[34])+TO_UDINT(s1));
    (* W42 *)
        s0 := (SHR(W[27],7) OR SHL(W[27],25)) XOR (SHR(W[27],18) OR SHL(W[27],14)) XOR SHR(W[27],3);
        s1 := (SHR(W[40],17) OR SHL(W[40],15)) XOR (SHR(W[40],19) OR SHL(W[40],13)) XOR SHR(W[40],10);
        W[42] := TO_DWORD(TO_UDINT(W[26])+TO_UDINT(s0)+TO_UDINT(W[35])+TO_UDINT(s1));
    (* W43 *)
        s0 := (SHR(W[28],7) OR SHL(W[28],25)) XOR (SHR(W[28],18) OR SHL(W[28],14)) XOR SHR(W[28],3);
        s1 := (SHR(W[41],17) OR SHL(W[41],15)) XOR (SHR(W[41],19) OR SHL(W[41],13)) XOR SHR(W[41],10);
        W[43] := TO_DWORD(TO_UDINT(W[27])+TO_UDINT(s0)+TO_UDINT(W[36])+TO_UDINT(s1));
    (* W44 *)
        s0 := (SHR(W[29],7) OR SHL(W[29],25)) XOR (SHR(W[29],18) OR SHL(W[29],14)) XOR SHR(W[29],3);
        s1 := (SHR(W[42],17) OR SHL(W[42],15)) XOR (SHR(W[42],19) OR SHL(W[42],13)) XOR SHR(W[42],10);
        W[44] := TO_DWORD(TO_UDINT(W[28])+TO_UDINT(s0)+TO_UDINT(W[37])+TO_UDINT(s1));
    (* W45 *)
        s0 := (SHR(W[30],7) OR SHL(W[30],25)) XOR (SHR(W[30],18) OR SHL(W[30],14)) XOR SHR(W[30],3);
        s1 := (SHR(W[43],17) OR SHL(W[43],15)) XOR (SHR(W[43],19) OR SHL(W[43],13)) XOR SHR(W[43],10);
        W[45] := TO_DWORD(TO_UDINT(W[29])+TO_UDINT(s0)+TO_UDINT(W[38])+TO_UDINT(s1));
    (* W46 *)
        s0 := (SHR(W[31],7) OR SHL(W[31],25)) XOR (SHR(W[31],18) OR SHL(W[31],14)) XOR SHR(W[31],3);
        s1 := (SHR(W[44],17) OR SHL(W[44],15)) XOR (SHR(W[44],19) OR SHL(W[44],13)) XOR SHR(W[44],10);
        W[46] := TO_DWORD(TO_UDINT(W[30])+TO_UDINT(s0)+TO_UDINT(W[39])+TO_UDINT(s1));
    (* W47 *)
        s0 := (SHR(W[32],7) OR SHL(W[32],25)) XOR (SHR(W[32],18) OR SHL(W[32],14)) XOR SHR(W[32],3);
        s1 := (SHR(W[45],17) OR SHL(W[45],15)) XOR (SHR(W[45],19) OR SHL(W[45],13)) XOR SHR(W[45],10);
        W[47] := TO_DWORD(TO_UDINT(W[31])+TO_UDINT(s0)+TO_UDINT(W[40])+TO_UDINT(s1));
    (* W48 *)
        s0 := (SHR(W[33],7) OR SHL(W[33],25)) XOR (SHR(W[33],18) OR SHL(W[33],14)) XOR SHR(W[33],3);
        s1 := (SHR(W[46],17) OR SHL(W[46],15)) XOR (SHR(W[46],19) OR SHL(W[46],13)) XOR SHR(W[46],10);
        W[48] := TO_DWORD(TO_UDINT(W[32])+TO_UDINT(s0)+TO_UDINT(W[41])+TO_UDINT(s1));
    (* W49 *)
        s0 := (SHR(W[34],7) OR SHL(W[34],25)) XOR (SHR(W[34],18) OR SHL(W[34],14)) XOR SHR(W[34],3);
        s1 := (SHR(W[47],17) OR SHL(W[47],15)) XOR (SHR(W[47],19) OR SHL(W[47],13)) XOR SHR(W[47],10);
        W[49] := TO_DWORD(TO_UDINT(W[33])+TO_UDINT(s0)+TO_UDINT(W[42])+TO_UDINT(s1));
    (* W50 *)
        s0 := (SHR(W[35],7) OR SHL(W[35],25)) XOR (SHR(W[35],18) OR SHL(W[35],14)) XOR SHR(W[35],3);
        s1 := (SHR(W[48],17) OR SHL(W[48],15)) XOR (SHR(W[48],19) OR SHL(W[48],13)) XOR SHR(W[48],10);
        W[50] := TO_DWORD(TO_UDINT(W[34])+TO_UDINT(s0)+TO_UDINT(W[43])+TO_UDINT(s1));
    (* W51 *)
        s0 := (SHR(W[36],7) OR SHL(W[36],25)) XOR (SHR(W[36],18) OR SHL(W[36],14)) XOR SHR(W[36],3);
        s1 := (SHR(W[49],17) OR SHL(W[49],15)) XOR (SHR(W[49],19) OR SHL(W[49],13)) XOR SHR(W[49],10);
        W[51] := TO_DWORD(TO_UDINT(W[35])+TO_UDINT(s0)+TO_UDINT(W[44])+TO_UDINT(s1));
    (* W52 *)
        s0 := (SHR(W[37],7) OR SHL(W[37],25)) XOR (SHR(W[37],18) OR SHL(W[37],14)) XOR SHR(W[37],3);
        s1 := (SHR(W[50],17) OR SHL(W[50],15)) XOR (SHR(W[50],19) OR SHL(W[50],13)) XOR SHR(W[50],10);
        W[52] := TO_DWORD(TO_UDINT(W[36])+TO_UDINT(s0)+TO_UDINT(W[45])+TO_UDINT(s1));
    (* W53 *)
        s0 := (SHR(W[38],7) OR SHL(W[38],25)) XOR (SHR(W[38],18) OR SHL(W[38],14)) XOR SHR(W[38],3);
        s1 := (SHR(W[51],17) OR SHL(W[51],15)) XOR (SHR(W[51],19) OR SHL(W[51],13)) XOR SHR(W[51],10);
        W[53] := TO_DWORD(TO_UDINT(W[37])+TO_UDINT(s0)+TO_UDINT(W[46])+TO_UDINT(s1));
    (* W54 *)
        s0 := (SHR(W[39],7) OR SHL(W[39],25)) XOR (SHR(W[39],18) OR SHL(W[39],14)) XOR SHR(W[39],3);
        s1 := (SHR(W[52],17) OR SHL(W[52],15)) XOR (SHR(W[52],19) OR SHL(W[52],13)) XOR SHR(W[52],10);
        W[54] := TO_DWORD(TO_UDINT(W[38])+TO_UDINT(s0)+TO_UDINT(W[47])+TO_UDINT(s1));
    (* W55 *)
        s0 := (SHR(W[40],7) OR SHL(W[40],25)) XOR (SHR(W[40],18) OR SHL(W[40],14)) XOR SHR(W[40],3);
        s1 := (SHR(W[53],17) OR SHL(W[53],15)) XOR (SHR(W[53],19) OR SHL(W[53],13)) XOR SHR(W[53],10);
        W[55] := TO_DWORD(TO_UDINT(W[39])+TO_UDINT(s0)+TO_UDINT(W[48])+TO_UDINT(s1));
    (* W56 *)
        s0 := (SHR(W[41],7) OR SHL(W[41],25)) XOR (SHR(W[41],18) OR SHL(W[41],14)) XOR SHR(W[41],3);
        s1 := (SHR(W[54],17) OR SHL(W[54],15)) XOR (SHR(W[54],19) OR SHL(W[54],13)) XOR SHR(W[54],10);
        W[56] := TO_DWORD(TO_UDINT(W[40])+TO_UDINT(s0)+TO_UDINT(W[49])+TO_UDINT(s1));
    (* W57 *)
        s0 := (SHR(W[42],7) OR SHL(W[42],25)) XOR (SHR(W[42],18) OR SHL(W[42],14)) XOR SHR(W[42],3);
        s1 := (SHR(W[55],17) OR SHL(W[55],15)) XOR (SHR(W[55],19) OR SHL(W[55],13)) XOR SHR(W[55],10);
        W[57] := TO_DWORD(TO_UDINT(W[41])+TO_UDINT(s0)+TO_UDINT(W[50])+TO_UDINT(s1));
    (* W58 *)
        s0 := (SHR(W[43],7) OR SHL(W[43],25)) XOR (SHR(W[43],18) OR SHL(W[43],14)) XOR SHR(W[43],3);
        s1 := (SHR(W[56],17) OR SHL(W[56],15)) XOR (SHR(W[56],19) OR SHL(W[56],13)) XOR SHR(W[56],10);
        W[58] := TO_DWORD(TO_UDINT(W[42])+TO_UDINT(s0)+TO_UDINT(W[51])+TO_UDINT(s1));
    (* W59 *)
        s0 := (SHR(W[44],7) OR SHL(W[44],25)) XOR (SHR(W[44],18) OR SHL(W[44],14)) XOR SHR(W[44],3);
        s1 := (SHR(W[57],17) OR SHL(W[57],15)) XOR (SHR(W[57],19) OR SHL(W[57],13)) XOR SHR(W[57],10);
        W[59] := TO_DWORD(TO_UDINT(W[43])+TO_UDINT(s0)+TO_UDINT(W[52])+TO_UDINT(s1));
    (* W60 *)
        s0 := (SHR(W[45],7) OR SHL(W[45],25)) XOR (SHR(W[45],18) OR SHL(W[45],14)) XOR SHR(W[45],3);
        s1 := (SHR(W[58],17) OR SHL(W[58],15)) XOR (SHR(W[58],19) OR SHL(W[58],13)) XOR SHR(W[58],10);
        W[60] := TO_DWORD(TO_UDINT(W[44])+TO_UDINT(s0)+TO_UDINT(W[53])+TO_UDINT(s1));
    (* W61 *)
        s0 := (SHR(W[46],7) OR SHL(W[46],25)) XOR (SHR(W[46],18) OR SHL(W[46],14)) XOR SHR(W[46],3);
        s1 := (SHR(W[59],17) OR SHL(W[59],15)) XOR (SHR(W[59],19) OR SHL(W[59],13)) XOR SHR(W[59],10);
        W[61] := TO_DWORD(TO_UDINT(W[45])+TO_UDINT(s0)+TO_UDINT(W[54])+TO_UDINT(s1));
    (* W62 *)
        s0 := (SHR(W[47],7) OR SHL(W[47],25)) XOR (SHR(W[47],18) OR SHL(W[47],14)) XOR SHR(W[47],3);
        s1 := (SHR(W[60],17) OR SHL(W[60],15)) XOR (SHR(W[60],19) OR SHL(W[60],13)) XOR SHR(W[60],10);
        W[62] := TO_DWORD(TO_UDINT(W[46])+TO_UDINT(s0)+TO_UDINT(W[55])+TO_UDINT(s1));
    (* W63 *)
        s0 := (SHR(W[48],7) OR SHL(W[48],25)) XOR (SHR(W[48],18) OR SHL(W[48],14)) XOR SHR(W[48],3);
        s1 := (SHR(W[61],17) OR SHL(W[61],15)) XOR (SHR(W[61],19) OR SHL(W[61],13)) XOR SHR(W[61],10);
        W[63] := TO_DWORD(TO_UDINT(W[47])+TO_UDINT(s0)+TO_UDINT(W[56])+TO_UDINT(s1));
    a := Hs[0]; b := Hs[1]; c := Hs[2]; d := Hs[3]; e := Hs[4]; f := Hs[5]; g := Hs[6]; h := Hs[7];
    (* Round 0: rotated register names remove seven copy assignments. *)
    s1:=(SHR(e,6) OR SHL(e,26)) XOR (SHR(e,11) OR SHL(e,21)) XOR (SHR(e,25) OR SHL(e,7));
    t1:=TO_DWORD(TO_UDINT(h)+TO_UDINT(s1)+TO_UDINT((e AND f) XOR ((NOT e) AND g))+UDINT#1116352408+TO_UDINT(W[0]));
    s0:=(SHR(a,2) OR SHL(a,30)) XOR (SHR(a,13) OR SHL(a,19)) XOR (SHR(a,22) OR SHL(a,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((a AND b) XOR (a AND c) XOR (b AND c)));
    d:=TO_DWORD(TO_UDINT(d)+TO_UDINT(t1)); h:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 1: rotated register names remove seven copy assignments. *)
    s1:=(SHR(d,6) OR SHL(d,26)) XOR (SHR(d,11) OR SHL(d,21)) XOR (SHR(d,25) OR SHL(d,7));
    t1:=TO_DWORD(TO_UDINT(g)+TO_UDINT(s1)+TO_UDINT((d AND e) XOR ((NOT d) AND f))+UDINT#1899447441+TO_UDINT(W[1]));
    s0:=(SHR(h,2) OR SHL(h,30)) XOR (SHR(h,13) OR SHL(h,19)) XOR (SHR(h,22) OR SHL(h,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((h AND a) XOR (h AND b) XOR (a AND b)));
    c:=TO_DWORD(TO_UDINT(c)+TO_UDINT(t1)); g:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 2: rotated register names remove seven copy assignments. *)
    s1:=(SHR(c,6) OR SHL(c,26)) XOR (SHR(c,11) OR SHL(c,21)) XOR (SHR(c,25) OR SHL(c,7));
    t1:=TO_DWORD(TO_UDINT(f)+TO_UDINT(s1)+TO_UDINT((c AND d) XOR ((NOT c) AND e))+UDINT#3049323471+TO_UDINT(W[2]));
    s0:=(SHR(g,2) OR SHL(g,30)) XOR (SHR(g,13) OR SHL(g,19)) XOR (SHR(g,22) OR SHL(g,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((g AND h) XOR (g AND a) XOR (h AND a)));
    b:=TO_DWORD(TO_UDINT(b)+TO_UDINT(t1)); f:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 3: rotated register names remove seven copy assignments. *)
    s1:=(SHR(b,6) OR SHL(b,26)) XOR (SHR(b,11) OR SHL(b,21)) XOR (SHR(b,25) OR SHL(b,7));
    t1:=TO_DWORD(TO_UDINT(e)+TO_UDINT(s1)+TO_UDINT((b AND c) XOR ((NOT b) AND d))+UDINT#3921009573+TO_UDINT(W[3]));
    s0:=(SHR(f,2) OR SHL(f,30)) XOR (SHR(f,13) OR SHL(f,19)) XOR (SHR(f,22) OR SHL(f,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((f AND g) XOR (f AND h) XOR (g AND h)));
    a:=TO_DWORD(TO_UDINT(a)+TO_UDINT(t1)); e:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 4: rotated register names remove seven copy assignments. *)
    s1:=(SHR(a,6) OR SHL(a,26)) XOR (SHR(a,11) OR SHL(a,21)) XOR (SHR(a,25) OR SHL(a,7));
    t1:=TO_DWORD(TO_UDINT(d)+TO_UDINT(s1)+TO_UDINT((a AND b) XOR ((NOT a) AND c))+UDINT#961987163+TO_UDINT(W[4]));
    s0:=(SHR(e,2) OR SHL(e,30)) XOR (SHR(e,13) OR SHL(e,19)) XOR (SHR(e,22) OR SHL(e,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((e AND f) XOR (e AND g) XOR (f AND g)));
    h:=TO_DWORD(TO_UDINT(h)+TO_UDINT(t1)); d:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 5: rotated register names remove seven copy assignments. *)
    s1:=(SHR(h,6) OR SHL(h,26)) XOR (SHR(h,11) OR SHL(h,21)) XOR (SHR(h,25) OR SHL(h,7));
    t1:=TO_DWORD(TO_UDINT(c)+TO_UDINT(s1)+TO_UDINT((h AND a) XOR ((NOT h) AND b))+UDINT#1508970993+TO_UDINT(W[5]));
    s0:=(SHR(d,2) OR SHL(d,30)) XOR (SHR(d,13) OR SHL(d,19)) XOR (SHR(d,22) OR SHL(d,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((d AND e) XOR (d AND f) XOR (e AND f)));
    g:=TO_DWORD(TO_UDINT(g)+TO_UDINT(t1)); c:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 6: rotated register names remove seven copy assignments. *)
    s1:=(SHR(g,6) OR SHL(g,26)) XOR (SHR(g,11) OR SHL(g,21)) XOR (SHR(g,25) OR SHL(g,7));
    t1:=TO_DWORD(TO_UDINT(b)+TO_UDINT(s1)+TO_UDINT((g AND h) XOR ((NOT g) AND a))+UDINT#2453635748+TO_UDINT(W[6]));
    s0:=(SHR(c,2) OR SHL(c,30)) XOR (SHR(c,13) OR SHL(c,19)) XOR (SHR(c,22) OR SHL(c,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((c AND d) XOR (c AND e) XOR (d AND e)));
    f:=TO_DWORD(TO_UDINT(f)+TO_UDINT(t1)); b:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 7: rotated register names remove seven copy assignments. *)
    s1:=(SHR(f,6) OR SHL(f,26)) XOR (SHR(f,11) OR SHL(f,21)) XOR (SHR(f,25) OR SHL(f,7));
    t1:=TO_DWORD(TO_UDINT(a)+TO_UDINT(s1)+TO_UDINT((f AND g) XOR ((NOT f) AND h))+UDINT#2870763221+TO_UDINT(W[7]));
    s0:=(SHR(b,2) OR SHL(b,30)) XOR (SHR(b,13) OR SHL(b,19)) XOR (SHR(b,22) OR SHL(b,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((b AND c) XOR (b AND d) XOR (c AND d)));
    e:=TO_DWORD(TO_UDINT(e)+TO_UDINT(t1)); a:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 8: rotated register names remove seven copy assignments. *)
    s1:=(SHR(e,6) OR SHL(e,26)) XOR (SHR(e,11) OR SHL(e,21)) XOR (SHR(e,25) OR SHL(e,7));
    t1:=TO_DWORD(TO_UDINT(h)+TO_UDINT(s1)+TO_UDINT((e AND f) XOR ((NOT e) AND g))+UDINT#3624381080+TO_UDINT(W[8]));
    s0:=(SHR(a,2) OR SHL(a,30)) XOR (SHR(a,13) OR SHL(a,19)) XOR (SHR(a,22) OR SHL(a,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((a AND b) XOR (a AND c) XOR (b AND c)));
    d:=TO_DWORD(TO_UDINT(d)+TO_UDINT(t1)); h:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 9: rotated register names remove seven copy assignments. *)
    s1:=(SHR(d,6) OR SHL(d,26)) XOR (SHR(d,11) OR SHL(d,21)) XOR (SHR(d,25) OR SHL(d,7));
    t1:=TO_DWORD(TO_UDINT(g)+TO_UDINT(s1)+TO_UDINT((d AND e) XOR ((NOT d) AND f))+UDINT#310598401+TO_UDINT(W[9]));
    s0:=(SHR(h,2) OR SHL(h,30)) XOR (SHR(h,13) OR SHL(h,19)) XOR (SHR(h,22) OR SHL(h,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((h AND a) XOR (h AND b) XOR (a AND b)));
    c:=TO_DWORD(TO_UDINT(c)+TO_UDINT(t1)); g:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 10: rotated register names remove seven copy assignments. *)
    s1:=(SHR(c,6) OR SHL(c,26)) XOR (SHR(c,11) OR SHL(c,21)) XOR (SHR(c,25) OR SHL(c,7));
    t1:=TO_DWORD(TO_UDINT(f)+TO_UDINT(s1)+TO_UDINT((c AND d) XOR ((NOT c) AND e))+UDINT#607225278+TO_UDINT(W[10]));
    s0:=(SHR(g,2) OR SHL(g,30)) XOR (SHR(g,13) OR SHL(g,19)) XOR (SHR(g,22) OR SHL(g,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((g AND h) XOR (g AND a) XOR (h AND a)));
    b:=TO_DWORD(TO_UDINT(b)+TO_UDINT(t1)); f:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 11: rotated register names remove seven copy assignments. *)
    s1:=(SHR(b,6) OR SHL(b,26)) XOR (SHR(b,11) OR SHL(b,21)) XOR (SHR(b,25) OR SHL(b,7));
    t1:=TO_DWORD(TO_UDINT(e)+TO_UDINT(s1)+TO_UDINT((b AND c) XOR ((NOT b) AND d))+UDINT#1426881987+TO_UDINT(W[11]));
    s0:=(SHR(f,2) OR SHL(f,30)) XOR (SHR(f,13) OR SHL(f,19)) XOR (SHR(f,22) OR SHL(f,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((f AND g) XOR (f AND h) XOR (g AND h)));
    a:=TO_DWORD(TO_UDINT(a)+TO_UDINT(t1)); e:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 12: rotated register names remove seven copy assignments. *)
    s1:=(SHR(a,6) OR SHL(a,26)) XOR (SHR(a,11) OR SHL(a,21)) XOR (SHR(a,25) OR SHL(a,7));
    t1:=TO_DWORD(TO_UDINT(d)+TO_UDINT(s1)+TO_UDINT((a AND b) XOR ((NOT a) AND c))+UDINT#1925078388+TO_UDINT(W[12]));
    s0:=(SHR(e,2) OR SHL(e,30)) XOR (SHR(e,13) OR SHL(e,19)) XOR (SHR(e,22) OR SHL(e,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((e AND f) XOR (e AND g) XOR (f AND g)));
    h:=TO_DWORD(TO_UDINT(h)+TO_UDINT(t1)); d:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 13: rotated register names remove seven copy assignments. *)
    s1:=(SHR(h,6) OR SHL(h,26)) XOR (SHR(h,11) OR SHL(h,21)) XOR (SHR(h,25) OR SHL(h,7));
    t1:=TO_DWORD(TO_UDINT(c)+TO_UDINT(s1)+TO_UDINT((h AND a) XOR ((NOT h) AND b))+UDINT#2162078206+TO_UDINT(W[13]));
    s0:=(SHR(d,2) OR SHL(d,30)) XOR (SHR(d,13) OR SHL(d,19)) XOR (SHR(d,22) OR SHL(d,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((d AND e) XOR (d AND f) XOR (e AND f)));
    g:=TO_DWORD(TO_UDINT(g)+TO_UDINT(t1)); c:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 14: rotated register names remove seven copy assignments. *)
    s1:=(SHR(g,6) OR SHL(g,26)) XOR (SHR(g,11) OR SHL(g,21)) XOR (SHR(g,25) OR SHL(g,7));
    t1:=TO_DWORD(TO_UDINT(b)+TO_UDINT(s1)+TO_UDINT((g AND h) XOR ((NOT g) AND a))+UDINT#2614888103+TO_UDINT(W[14]));
    s0:=(SHR(c,2) OR SHL(c,30)) XOR (SHR(c,13) OR SHL(c,19)) XOR (SHR(c,22) OR SHL(c,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((c AND d) XOR (c AND e) XOR (d AND e)));
    f:=TO_DWORD(TO_UDINT(f)+TO_UDINT(t1)); b:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 15: rotated register names remove seven copy assignments. *)
    s1:=(SHR(f,6) OR SHL(f,26)) XOR (SHR(f,11) OR SHL(f,21)) XOR (SHR(f,25) OR SHL(f,7));
    t1:=TO_DWORD(TO_UDINT(a)+TO_UDINT(s1)+TO_UDINT((f AND g) XOR ((NOT f) AND h))+UDINT#3248222580+TO_UDINT(W[15]));
    s0:=(SHR(b,2) OR SHL(b,30)) XOR (SHR(b,13) OR SHL(b,19)) XOR (SHR(b,22) OR SHL(b,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((b AND c) XOR (b AND d) XOR (c AND d)));
    e:=TO_DWORD(TO_UDINT(e)+TO_UDINT(t1)); a:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 16: rotated register names remove seven copy assignments. *)
    s1:=(SHR(e,6) OR SHL(e,26)) XOR (SHR(e,11) OR SHL(e,21)) XOR (SHR(e,25) OR SHL(e,7));
    t1:=TO_DWORD(TO_UDINT(h)+TO_UDINT(s1)+TO_UDINT((e AND f) XOR ((NOT e) AND g))+UDINT#3835390401+TO_UDINT(W[16]));
    s0:=(SHR(a,2) OR SHL(a,30)) XOR (SHR(a,13) OR SHL(a,19)) XOR (SHR(a,22) OR SHL(a,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((a AND b) XOR (a AND c) XOR (b AND c)));
    d:=TO_DWORD(TO_UDINT(d)+TO_UDINT(t1)); h:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 17: rotated register names remove seven copy assignments. *)
    s1:=(SHR(d,6) OR SHL(d,26)) XOR (SHR(d,11) OR SHL(d,21)) XOR (SHR(d,25) OR SHL(d,7));
    t1:=TO_DWORD(TO_UDINT(g)+TO_UDINT(s1)+TO_UDINT((d AND e) XOR ((NOT d) AND f))+UDINT#4022224774+TO_UDINT(W[17]));
    s0:=(SHR(h,2) OR SHL(h,30)) XOR (SHR(h,13) OR SHL(h,19)) XOR (SHR(h,22) OR SHL(h,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((h AND a) XOR (h AND b) XOR (a AND b)));
    c:=TO_DWORD(TO_UDINT(c)+TO_UDINT(t1)); g:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 18: rotated register names remove seven copy assignments. *)
    s1:=(SHR(c,6) OR SHL(c,26)) XOR (SHR(c,11) OR SHL(c,21)) XOR (SHR(c,25) OR SHL(c,7));
    t1:=TO_DWORD(TO_UDINT(f)+TO_UDINT(s1)+TO_UDINT((c AND d) XOR ((NOT c) AND e))+UDINT#264347078+TO_UDINT(W[18]));
    s0:=(SHR(g,2) OR SHL(g,30)) XOR (SHR(g,13) OR SHL(g,19)) XOR (SHR(g,22) OR SHL(g,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((g AND h) XOR (g AND a) XOR (h AND a)));
    b:=TO_DWORD(TO_UDINT(b)+TO_UDINT(t1)); f:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 19: rotated register names remove seven copy assignments. *)
    s1:=(SHR(b,6) OR SHL(b,26)) XOR (SHR(b,11) OR SHL(b,21)) XOR (SHR(b,25) OR SHL(b,7));
    t1:=TO_DWORD(TO_UDINT(e)+TO_UDINT(s1)+TO_UDINT((b AND c) XOR ((NOT b) AND d))+UDINT#604807628+TO_UDINT(W[19]));
    s0:=(SHR(f,2) OR SHL(f,30)) XOR (SHR(f,13) OR SHL(f,19)) XOR (SHR(f,22) OR SHL(f,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((f AND g) XOR (f AND h) XOR (g AND h)));
    a:=TO_DWORD(TO_UDINT(a)+TO_UDINT(t1)); e:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 20: rotated register names remove seven copy assignments. *)
    s1:=(SHR(a,6) OR SHL(a,26)) XOR (SHR(a,11) OR SHL(a,21)) XOR (SHR(a,25) OR SHL(a,7));
    t1:=TO_DWORD(TO_UDINT(d)+TO_UDINT(s1)+TO_UDINT((a AND b) XOR ((NOT a) AND c))+UDINT#770255983+TO_UDINT(W[20]));
    s0:=(SHR(e,2) OR SHL(e,30)) XOR (SHR(e,13) OR SHL(e,19)) XOR (SHR(e,22) OR SHL(e,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((e AND f) XOR (e AND g) XOR (f AND g)));
    h:=TO_DWORD(TO_UDINT(h)+TO_UDINT(t1)); d:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 21: rotated register names remove seven copy assignments. *)
    s1:=(SHR(h,6) OR SHL(h,26)) XOR (SHR(h,11) OR SHL(h,21)) XOR (SHR(h,25) OR SHL(h,7));
    t1:=TO_DWORD(TO_UDINT(c)+TO_UDINT(s1)+TO_UDINT((h AND a) XOR ((NOT h) AND b))+UDINT#1249150122+TO_UDINT(W[21]));
    s0:=(SHR(d,2) OR SHL(d,30)) XOR (SHR(d,13) OR SHL(d,19)) XOR (SHR(d,22) OR SHL(d,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((d AND e) XOR (d AND f) XOR (e AND f)));
    g:=TO_DWORD(TO_UDINT(g)+TO_UDINT(t1)); c:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 22: rotated register names remove seven copy assignments. *)
    s1:=(SHR(g,6) OR SHL(g,26)) XOR (SHR(g,11) OR SHL(g,21)) XOR (SHR(g,25) OR SHL(g,7));
    t1:=TO_DWORD(TO_UDINT(b)+TO_UDINT(s1)+TO_UDINT((g AND h) XOR ((NOT g) AND a))+UDINT#1555081692+TO_UDINT(W[22]));
    s0:=(SHR(c,2) OR SHL(c,30)) XOR (SHR(c,13) OR SHL(c,19)) XOR (SHR(c,22) OR SHL(c,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((c AND d) XOR (c AND e) XOR (d AND e)));
    f:=TO_DWORD(TO_UDINT(f)+TO_UDINT(t1)); b:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 23: rotated register names remove seven copy assignments. *)
    s1:=(SHR(f,6) OR SHL(f,26)) XOR (SHR(f,11) OR SHL(f,21)) XOR (SHR(f,25) OR SHL(f,7));
    t1:=TO_DWORD(TO_UDINT(a)+TO_UDINT(s1)+TO_UDINT((f AND g) XOR ((NOT f) AND h))+UDINT#1996064986+TO_UDINT(W[23]));
    s0:=(SHR(b,2) OR SHL(b,30)) XOR (SHR(b,13) OR SHL(b,19)) XOR (SHR(b,22) OR SHL(b,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((b AND c) XOR (b AND d) XOR (c AND d)));
    e:=TO_DWORD(TO_UDINT(e)+TO_UDINT(t1)); a:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 24: rotated register names remove seven copy assignments. *)
    s1:=(SHR(e,6) OR SHL(e,26)) XOR (SHR(e,11) OR SHL(e,21)) XOR (SHR(e,25) OR SHL(e,7));
    t1:=TO_DWORD(TO_UDINT(h)+TO_UDINT(s1)+TO_UDINT((e AND f) XOR ((NOT e) AND g))+UDINT#2554220882+TO_UDINT(W[24]));
    s0:=(SHR(a,2) OR SHL(a,30)) XOR (SHR(a,13) OR SHL(a,19)) XOR (SHR(a,22) OR SHL(a,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((a AND b) XOR (a AND c) XOR (b AND c)));
    d:=TO_DWORD(TO_UDINT(d)+TO_UDINT(t1)); h:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 25: rotated register names remove seven copy assignments. *)
    s1:=(SHR(d,6) OR SHL(d,26)) XOR (SHR(d,11) OR SHL(d,21)) XOR (SHR(d,25) OR SHL(d,7));
    t1:=TO_DWORD(TO_UDINT(g)+TO_UDINT(s1)+TO_UDINT((d AND e) XOR ((NOT d) AND f))+UDINT#2821834349+TO_UDINT(W[25]));
    s0:=(SHR(h,2) OR SHL(h,30)) XOR (SHR(h,13) OR SHL(h,19)) XOR (SHR(h,22) OR SHL(h,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((h AND a) XOR (h AND b) XOR (a AND b)));
    c:=TO_DWORD(TO_UDINT(c)+TO_UDINT(t1)); g:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 26: rotated register names remove seven copy assignments. *)
    s1:=(SHR(c,6) OR SHL(c,26)) XOR (SHR(c,11) OR SHL(c,21)) XOR (SHR(c,25) OR SHL(c,7));
    t1:=TO_DWORD(TO_UDINT(f)+TO_UDINT(s1)+TO_UDINT((c AND d) XOR ((NOT c) AND e))+UDINT#2952996808+TO_UDINT(W[26]));
    s0:=(SHR(g,2) OR SHL(g,30)) XOR (SHR(g,13) OR SHL(g,19)) XOR (SHR(g,22) OR SHL(g,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((g AND h) XOR (g AND a) XOR (h AND a)));
    b:=TO_DWORD(TO_UDINT(b)+TO_UDINT(t1)); f:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 27: rotated register names remove seven copy assignments. *)
    s1:=(SHR(b,6) OR SHL(b,26)) XOR (SHR(b,11) OR SHL(b,21)) XOR (SHR(b,25) OR SHL(b,7));
    t1:=TO_DWORD(TO_UDINT(e)+TO_UDINT(s1)+TO_UDINT((b AND c) XOR ((NOT b) AND d))+UDINT#3210313671+TO_UDINT(W[27]));
    s0:=(SHR(f,2) OR SHL(f,30)) XOR (SHR(f,13) OR SHL(f,19)) XOR (SHR(f,22) OR SHL(f,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((f AND g) XOR (f AND h) XOR (g AND h)));
    a:=TO_DWORD(TO_UDINT(a)+TO_UDINT(t1)); e:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 28: rotated register names remove seven copy assignments. *)
    s1:=(SHR(a,6) OR SHL(a,26)) XOR (SHR(a,11) OR SHL(a,21)) XOR (SHR(a,25) OR SHL(a,7));
    t1:=TO_DWORD(TO_UDINT(d)+TO_UDINT(s1)+TO_UDINT((a AND b) XOR ((NOT a) AND c))+UDINT#3336571891+TO_UDINT(W[28]));
    s0:=(SHR(e,2) OR SHL(e,30)) XOR (SHR(e,13) OR SHL(e,19)) XOR (SHR(e,22) OR SHL(e,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((e AND f) XOR (e AND g) XOR (f AND g)));
    h:=TO_DWORD(TO_UDINT(h)+TO_UDINT(t1)); d:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 29: rotated register names remove seven copy assignments. *)
    s1:=(SHR(h,6) OR SHL(h,26)) XOR (SHR(h,11) OR SHL(h,21)) XOR (SHR(h,25) OR SHL(h,7));
    t1:=TO_DWORD(TO_UDINT(c)+TO_UDINT(s1)+TO_UDINT((h AND a) XOR ((NOT h) AND b))+UDINT#3584528711+TO_UDINT(W[29]));
    s0:=(SHR(d,2) OR SHL(d,30)) XOR (SHR(d,13) OR SHL(d,19)) XOR (SHR(d,22) OR SHL(d,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((d AND e) XOR (d AND f) XOR (e AND f)));
    g:=TO_DWORD(TO_UDINT(g)+TO_UDINT(t1)); c:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 30: rotated register names remove seven copy assignments. *)
    s1:=(SHR(g,6) OR SHL(g,26)) XOR (SHR(g,11) OR SHL(g,21)) XOR (SHR(g,25) OR SHL(g,7));
    t1:=TO_DWORD(TO_UDINT(b)+TO_UDINT(s1)+TO_UDINT((g AND h) XOR ((NOT g) AND a))+UDINT#113926993+TO_UDINT(W[30]));
    s0:=(SHR(c,2) OR SHL(c,30)) XOR (SHR(c,13) OR SHL(c,19)) XOR (SHR(c,22) OR SHL(c,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((c AND d) XOR (c AND e) XOR (d AND e)));
    f:=TO_DWORD(TO_UDINT(f)+TO_UDINT(t1)); b:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 31: rotated register names remove seven copy assignments. *)
    s1:=(SHR(f,6) OR SHL(f,26)) XOR (SHR(f,11) OR SHL(f,21)) XOR (SHR(f,25) OR SHL(f,7));
    t1:=TO_DWORD(TO_UDINT(a)+TO_UDINT(s1)+TO_UDINT((f AND g) XOR ((NOT f) AND h))+UDINT#338241895+TO_UDINT(W[31]));
    s0:=(SHR(b,2) OR SHL(b,30)) XOR (SHR(b,13) OR SHL(b,19)) XOR (SHR(b,22) OR SHL(b,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((b AND c) XOR (b AND d) XOR (c AND d)));
    e:=TO_DWORD(TO_UDINT(e)+TO_UDINT(t1)); a:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 32: rotated register names remove seven copy assignments. *)
    s1:=(SHR(e,6) OR SHL(e,26)) XOR (SHR(e,11) OR SHL(e,21)) XOR (SHR(e,25) OR SHL(e,7));
    t1:=TO_DWORD(TO_UDINT(h)+TO_UDINT(s1)+TO_UDINT((e AND f) XOR ((NOT e) AND g))+UDINT#666307205+TO_UDINT(W[32]));
    s0:=(SHR(a,2) OR SHL(a,30)) XOR (SHR(a,13) OR SHL(a,19)) XOR (SHR(a,22) OR SHL(a,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((a AND b) XOR (a AND c) XOR (b AND c)));
    d:=TO_DWORD(TO_UDINT(d)+TO_UDINT(t1)); h:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 33: rotated register names remove seven copy assignments. *)
    s1:=(SHR(d,6) OR SHL(d,26)) XOR (SHR(d,11) OR SHL(d,21)) XOR (SHR(d,25) OR SHL(d,7));
    t1:=TO_DWORD(TO_UDINT(g)+TO_UDINT(s1)+TO_UDINT((d AND e) XOR ((NOT d) AND f))+UDINT#773529912+TO_UDINT(W[33]));
    s0:=(SHR(h,2) OR SHL(h,30)) XOR (SHR(h,13) OR SHL(h,19)) XOR (SHR(h,22) OR SHL(h,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((h AND a) XOR (h AND b) XOR (a AND b)));
    c:=TO_DWORD(TO_UDINT(c)+TO_UDINT(t1)); g:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 34: rotated register names remove seven copy assignments. *)
    s1:=(SHR(c,6) OR SHL(c,26)) XOR (SHR(c,11) OR SHL(c,21)) XOR (SHR(c,25) OR SHL(c,7));
    t1:=TO_DWORD(TO_UDINT(f)+TO_UDINT(s1)+TO_UDINT((c AND d) XOR ((NOT c) AND e))+UDINT#1294757372+TO_UDINT(W[34]));
    s0:=(SHR(g,2) OR SHL(g,30)) XOR (SHR(g,13) OR SHL(g,19)) XOR (SHR(g,22) OR SHL(g,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((g AND h) XOR (g AND a) XOR (h AND a)));
    b:=TO_DWORD(TO_UDINT(b)+TO_UDINT(t1)); f:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 35: rotated register names remove seven copy assignments. *)
    s1:=(SHR(b,6) OR SHL(b,26)) XOR (SHR(b,11) OR SHL(b,21)) XOR (SHR(b,25) OR SHL(b,7));
    t1:=TO_DWORD(TO_UDINT(e)+TO_UDINT(s1)+TO_UDINT((b AND c) XOR ((NOT b) AND d))+UDINT#1396182291+TO_UDINT(W[35]));
    s0:=(SHR(f,2) OR SHL(f,30)) XOR (SHR(f,13) OR SHL(f,19)) XOR (SHR(f,22) OR SHL(f,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((f AND g) XOR (f AND h) XOR (g AND h)));
    a:=TO_DWORD(TO_UDINT(a)+TO_UDINT(t1)); e:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 36: rotated register names remove seven copy assignments. *)
    s1:=(SHR(a,6) OR SHL(a,26)) XOR (SHR(a,11) OR SHL(a,21)) XOR (SHR(a,25) OR SHL(a,7));
    t1:=TO_DWORD(TO_UDINT(d)+TO_UDINT(s1)+TO_UDINT((a AND b) XOR ((NOT a) AND c))+UDINT#1695183700+TO_UDINT(W[36]));
    s0:=(SHR(e,2) OR SHL(e,30)) XOR (SHR(e,13) OR SHL(e,19)) XOR (SHR(e,22) OR SHL(e,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((e AND f) XOR (e AND g) XOR (f AND g)));
    h:=TO_DWORD(TO_UDINT(h)+TO_UDINT(t1)); d:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 37: rotated register names remove seven copy assignments. *)
    s1:=(SHR(h,6) OR SHL(h,26)) XOR (SHR(h,11) OR SHL(h,21)) XOR (SHR(h,25) OR SHL(h,7));
    t1:=TO_DWORD(TO_UDINT(c)+TO_UDINT(s1)+TO_UDINT((h AND a) XOR ((NOT h) AND b))+UDINT#1986661051+TO_UDINT(W[37]));
    s0:=(SHR(d,2) OR SHL(d,30)) XOR (SHR(d,13) OR SHL(d,19)) XOR (SHR(d,22) OR SHL(d,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((d AND e) XOR (d AND f) XOR (e AND f)));
    g:=TO_DWORD(TO_UDINT(g)+TO_UDINT(t1)); c:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 38: rotated register names remove seven copy assignments. *)
    s1:=(SHR(g,6) OR SHL(g,26)) XOR (SHR(g,11) OR SHL(g,21)) XOR (SHR(g,25) OR SHL(g,7));
    t1:=TO_DWORD(TO_UDINT(b)+TO_UDINT(s1)+TO_UDINT((g AND h) XOR ((NOT g) AND a))+UDINT#2177026350+TO_UDINT(W[38]));
    s0:=(SHR(c,2) OR SHL(c,30)) XOR (SHR(c,13) OR SHL(c,19)) XOR (SHR(c,22) OR SHL(c,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((c AND d) XOR (c AND e) XOR (d AND e)));
    f:=TO_DWORD(TO_UDINT(f)+TO_UDINT(t1)); b:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 39: rotated register names remove seven copy assignments. *)
    s1:=(SHR(f,6) OR SHL(f,26)) XOR (SHR(f,11) OR SHL(f,21)) XOR (SHR(f,25) OR SHL(f,7));
    t1:=TO_DWORD(TO_UDINT(a)+TO_UDINT(s1)+TO_UDINT((f AND g) XOR ((NOT f) AND h))+UDINT#2456956037+TO_UDINT(W[39]));
    s0:=(SHR(b,2) OR SHL(b,30)) XOR (SHR(b,13) OR SHL(b,19)) XOR (SHR(b,22) OR SHL(b,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((b AND c) XOR (b AND d) XOR (c AND d)));
    e:=TO_DWORD(TO_UDINT(e)+TO_UDINT(t1)); a:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 40: rotated register names remove seven copy assignments. *)
    s1:=(SHR(e,6) OR SHL(e,26)) XOR (SHR(e,11) OR SHL(e,21)) XOR (SHR(e,25) OR SHL(e,7));
    t1:=TO_DWORD(TO_UDINT(h)+TO_UDINT(s1)+TO_UDINT((e AND f) XOR ((NOT e) AND g))+UDINT#2730485921+TO_UDINT(W[40]));
    s0:=(SHR(a,2) OR SHL(a,30)) XOR (SHR(a,13) OR SHL(a,19)) XOR (SHR(a,22) OR SHL(a,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((a AND b) XOR (a AND c) XOR (b AND c)));
    d:=TO_DWORD(TO_UDINT(d)+TO_UDINT(t1)); h:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 41: rotated register names remove seven copy assignments. *)
    s1:=(SHR(d,6) OR SHL(d,26)) XOR (SHR(d,11) OR SHL(d,21)) XOR (SHR(d,25) OR SHL(d,7));
    t1:=TO_DWORD(TO_UDINT(g)+TO_UDINT(s1)+TO_UDINT((d AND e) XOR ((NOT d) AND f))+UDINT#2820302411+TO_UDINT(W[41]));
    s0:=(SHR(h,2) OR SHL(h,30)) XOR (SHR(h,13) OR SHL(h,19)) XOR (SHR(h,22) OR SHL(h,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((h AND a) XOR (h AND b) XOR (a AND b)));
    c:=TO_DWORD(TO_UDINT(c)+TO_UDINT(t1)); g:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 42: rotated register names remove seven copy assignments. *)
    s1:=(SHR(c,6) OR SHL(c,26)) XOR (SHR(c,11) OR SHL(c,21)) XOR (SHR(c,25) OR SHL(c,7));
    t1:=TO_DWORD(TO_UDINT(f)+TO_UDINT(s1)+TO_UDINT((c AND d) XOR ((NOT c) AND e))+UDINT#3259730800+TO_UDINT(W[42]));
    s0:=(SHR(g,2) OR SHL(g,30)) XOR (SHR(g,13) OR SHL(g,19)) XOR (SHR(g,22) OR SHL(g,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((g AND h) XOR (g AND a) XOR (h AND a)));
    b:=TO_DWORD(TO_UDINT(b)+TO_UDINT(t1)); f:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 43: rotated register names remove seven copy assignments. *)
    s1:=(SHR(b,6) OR SHL(b,26)) XOR (SHR(b,11) OR SHL(b,21)) XOR (SHR(b,25) OR SHL(b,7));
    t1:=TO_DWORD(TO_UDINT(e)+TO_UDINT(s1)+TO_UDINT((b AND c) XOR ((NOT b) AND d))+UDINT#3345764771+TO_UDINT(W[43]));
    s0:=(SHR(f,2) OR SHL(f,30)) XOR (SHR(f,13) OR SHL(f,19)) XOR (SHR(f,22) OR SHL(f,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((f AND g) XOR (f AND h) XOR (g AND h)));
    a:=TO_DWORD(TO_UDINT(a)+TO_UDINT(t1)); e:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 44: rotated register names remove seven copy assignments. *)
    s1:=(SHR(a,6) OR SHL(a,26)) XOR (SHR(a,11) OR SHL(a,21)) XOR (SHR(a,25) OR SHL(a,7));
    t1:=TO_DWORD(TO_UDINT(d)+TO_UDINT(s1)+TO_UDINT((a AND b) XOR ((NOT a) AND c))+UDINT#3516065817+TO_UDINT(W[44]));
    s0:=(SHR(e,2) OR SHL(e,30)) XOR (SHR(e,13) OR SHL(e,19)) XOR (SHR(e,22) OR SHL(e,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((e AND f) XOR (e AND g) XOR (f AND g)));
    h:=TO_DWORD(TO_UDINT(h)+TO_UDINT(t1)); d:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 45: rotated register names remove seven copy assignments. *)
    s1:=(SHR(h,6) OR SHL(h,26)) XOR (SHR(h,11) OR SHL(h,21)) XOR (SHR(h,25) OR SHL(h,7));
    t1:=TO_DWORD(TO_UDINT(c)+TO_UDINT(s1)+TO_UDINT((h AND a) XOR ((NOT h) AND b))+UDINT#3600352804+TO_UDINT(W[45]));
    s0:=(SHR(d,2) OR SHL(d,30)) XOR (SHR(d,13) OR SHL(d,19)) XOR (SHR(d,22) OR SHL(d,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((d AND e) XOR (d AND f) XOR (e AND f)));
    g:=TO_DWORD(TO_UDINT(g)+TO_UDINT(t1)); c:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 46: rotated register names remove seven copy assignments. *)
    s1:=(SHR(g,6) OR SHL(g,26)) XOR (SHR(g,11) OR SHL(g,21)) XOR (SHR(g,25) OR SHL(g,7));
    t1:=TO_DWORD(TO_UDINT(b)+TO_UDINT(s1)+TO_UDINT((g AND h) XOR ((NOT g) AND a))+UDINT#4094571909+TO_UDINT(W[46]));
    s0:=(SHR(c,2) OR SHL(c,30)) XOR (SHR(c,13) OR SHL(c,19)) XOR (SHR(c,22) OR SHL(c,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((c AND d) XOR (c AND e) XOR (d AND e)));
    f:=TO_DWORD(TO_UDINT(f)+TO_UDINT(t1)); b:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 47: rotated register names remove seven copy assignments. *)
    s1:=(SHR(f,6) OR SHL(f,26)) XOR (SHR(f,11) OR SHL(f,21)) XOR (SHR(f,25) OR SHL(f,7));
    t1:=TO_DWORD(TO_UDINT(a)+TO_UDINT(s1)+TO_UDINT((f AND g) XOR ((NOT f) AND h))+UDINT#275423344+TO_UDINT(W[47]));
    s0:=(SHR(b,2) OR SHL(b,30)) XOR (SHR(b,13) OR SHL(b,19)) XOR (SHR(b,22) OR SHL(b,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((b AND c) XOR (b AND d) XOR (c AND d)));
    e:=TO_DWORD(TO_UDINT(e)+TO_UDINT(t1)); a:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 48: rotated register names remove seven copy assignments. *)
    s1:=(SHR(e,6) OR SHL(e,26)) XOR (SHR(e,11) OR SHL(e,21)) XOR (SHR(e,25) OR SHL(e,7));
    t1:=TO_DWORD(TO_UDINT(h)+TO_UDINT(s1)+TO_UDINT((e AND f) XOR ((NOT e) AND g))+UDINT#430227734+TO_UDINT(W[48]));
    s0:=(SHR(a,2) OR SHL(a,30)) XOR (SHR(a,13) OR SHL(a,19)) XOR (SHR(a,22) OR SHL(a,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((a AND b) XOR (a AND c) XOR (b AND c)));
    d:=TO_DWORD(TO_UDINT(d)+TO_UDINT(t1)); h:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 49: rotated register names remove seven copy assignments. *)
    s1:=(SHR(d,6) OR SHL(d,26)) XOR (SHR(d,11) OR SHL(d,21)) XOR (SHR(d,25) OR SHL(d,7));
    t1:=TO_DWORD(TO_UDINT(g)+TO_UDINT(s1)+TO_UDINT((d AND e) XOR ((NOT d) AND f))+UDINT#506948616+TO_UDINT(W[49]));
    s0:=(SHR(h,2) OR SHL(h,30)) XOR (SHR(h,13) OR SHL(h,19)) XOR (SHR(h,22) OR SHL(h,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((h AND a) XOR (h AND b) XOR (a AND b)));
    c:=TO_DWORD(TO_UDINT(c)+TO_UDINT(t1)); g:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 50: rotated register names remove seven copy assignments. *)
    s1:=(SHR(c,6) OR SHL(c,26)) XOR (SHR(c,11) OR SHL(c,21)) XOR (SHR(c,25) OR SHL(c,7));
    t1:=TO_DWORD(TO_UDINT(f)+TO_UDINT(s1)+TO_UDINT((c AND d) XOR ((NOT c) AND e))+UDINT#659060556+TO_UDINT(W[50]));
    s0:=(SHR(g,2) OR SHL(g,30)) XOR (SHR(g,13) OR SHL(g,19)) XOR (SHR(g,22) OR SHL(g,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((g AND h) XOR (g AND a) XOR (h AND a)));
    b:=TO_DWORD(TO_UDINT(b)+TO_UDINT(t1)); f:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 51: rotated register names remove seven copy assignments. *)
    s1:=(SHR(b,6) OR SHL(b,26)) XOR (SHR(b,11) OR SHL(b,21)) XOR (SHR(b,25) OR SHL(b,7));
    t1:=TO_DWORD(TO_UDINT(e)+TO_UDINT(s1)+TO_UDINT((b AND c) XOR ((NOT b) AND d))+UDINT#883997877+TO_UDINT(W[51]));
    s0:=(SHR(f,2) OR SHL(f,30)) XOR (SHR(f,13) OR SHL(f,19)) XOR (SHR(f,22) OR SHL(f,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((f AND g) XOR (f AND h) XOR (g AND h)));
    a:=TO_DWORD(TO_UDINT(a)+TO_UDINT(t1)); e:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 52: rotated register names remove seven copy assignments. *)
    s1:=(SHR(a,6) OR SHL(a,26)) XOR (SHR(a,11) OR SHL(a,21)) XOR (SHR(a,25) OR SHL(a,7));
    t1:=TO_DWORD(TO_UDINT(d)+TO_UDINT(s1)+TO_UDINT((a AND b) XOR ((NOT a) AND c))+UDINT#958139571+TO_UDINT(W[52]));
    s0:=(SHR(e,2) OR SHL(e,30)) XOR (SHR(e,13) OR SHL(e,19)) XOR (SHR(e,22) OR SHL(e,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((e AND f) XOR (e AND g) XOR (f AND g)));
    h:=TO_DWORD(TO_UDINT(h)+TO_UDINT(t1)); d:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 53: rotated register names remove seven copy assignments. *)
    s1:=(SHR(h,6) OR SHL(h,26)) XOR (SHR(h,11) OR SHL(h,21)) XOR (SHR(h,25) OR SHL(h,7));
    t1:=TO_DWORD(TO_UDINT(c)+TO_UDINT(s1)+TO_UDINT((h AND a) XOR ((NOT h) AND b))+UDINT#1322822218+TO_UDINT(W[53]));
    s0:=(SHR(d,2) OR SHL(d,30)) XOR (SHR(d,13) OR SHL(d,19)) XOR (SHR(d,22) OR SHL(d,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((d AND e) XOR (d AND f) XOR (e AND f)));
    g:=TO_DWORD(TO_UDINT(g)+TO_UDINT(t1)); c:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 54: rotated register names remove seven copy assignments. *)
    s1:=(SHR(g,6) OR SHL(g,26)) XOR (SHR(g,11) OR SHL(g,21)) XOR (SHR(g,25) OR SHL(g,7));
    t1:=TO_DWORD(TO_UDINT(b)+TO_UDINT(s1)+TO_UDINT((g AND h) XOR ((NOT g) AND a))+UDINT#1537002063+TO_UDINT(W[54]));
    s0:=(SHR(c,2) OR SHL(c,30)) XOR (SHR(c,13) OR SHL(c,19)) XOR (SHR(c,22) OR SHL(c,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((c AND d) XOR (c AND e) XOR (d AND e)));
    f:=TO_DWORD(TO_UDINT(f)+TO_UDINT(t1)); b:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 55: rotated register names remove seven copy assignments. *)
    s1:=(SHR(f,6) OR SHL(f,26)) XOR (SHR(f,11) OR SHL(f,21)) XOR (SHR(f,25) OR SHL(f,7));
    t1:=TO_DWORD(TO_UDINT(a)+TO_UDINT(s1)+TO_UDINT((f AND g) XOR ((NOT f) AND h))+UDINT#1747873779+TO_UDINT(W[55]));
    s0:=(SHR(b,2) OR SHL(b,30)) XOR (SHR(b,13) OR SHL(b,19)) XOR (SHR(b,22) OR SHL(b,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((b AND c) XOR (b AND d) XOR (c AND d)));
    e:=TO_DWORD(TO_UDINT(e)+TO_UDINT(t1)); a:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 56: rotated register names remove seven copy assignments. *)
    s1:=(SHR(e,6) OR SHL(e,26)) XOR (SHR(e,11) OR SHL(e,21)) XOR (SHR(e,25) OR SHL(e,7));
    t1:=TO_DWORD(TO_UDINT(h)+TO_UDINT(s1)+TO_UDINT((e AND f) XOR ((NOT e) AND g))+UDINT#1955562222+TO_UDINT(W[56]));
    s0:=(SHR(a,2) OR SHL(a,30)) XOR (SHR(a,13) OR SHL(a,19)) XOR (SHR(a,22) OR SHL(a,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((a AND b) XOR (a AND c) XOR (b AND c)));
    d:=TO_DWORD(TO_UDINT(d)+TO_UDINT(t1)); h:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 57: rotated register names remove seven copy assignments. *)
    s1:=(SHR(d,6) OR SHL(d,26)) XOR (SHR(d,11) OR SHL(d,21)) XOR (SHR(d,25) OR SHL(d,7));
    t1:=TO_DWORD(TO_UDINT(g)+TO_UDINT(s1)+TO_UDINT((d AND e) XOR ((NOT d) AND f))+UDINT#2024104815+TO_UDINT(W[57]));
    s0:=(SHR(h,2) OR SHL(h,30)) XOR (SHR(h,13) OR SHL(h,19)) XOR (SHR(h,22) OR SHL(h,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((h AND a) XOR (h AND b) XOR (a AND b)));
    c:=TO_DWORD(TO_UDINT(c)+TO_UDINT(t1)); g:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 58: rotated register names remove seven copy assignments. *)
    s1:=(SHR(c,6) OR SHL(c,26)) XOR (SHR(c,11) OR SHL(c,21)) XOR (SHR(c,25) OR SHL(c,7));
    t1:=TO_DWORD(TO_UDINT(f)+TO_UDINT(s1)+TO_UDINT((c AND d) XOR ((NOT c) AND e))+UDINT#2227730452+TO_UDINT(W[58]));
    s0:=(SHR(g,2) OR SHL(g,30)) XOR (SHR(g,13) OR SHL(g,19)) XOR (SHR(g,22) OR SHL(g,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((g AND h) XOR (g AND a) XOR (h AND a)));
    b:=TO_DWORD(TO_UDINT(b)+TO_UDINT(t1)); f:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 59: rotated register names remove seven copy assignments. *)
    s1:=(SHR(b,6) OR SHL(b,26)) XOR (SHR(b,11) OR SHL(b,21)) XOR (SHR(b,25) OR SHL(b,7));
    t1:=TO_DWORD(TO_UDINT(e)+TO_UDINT(s1)+TO_UDINT((b AND c) XOR ((NOT b) AND d))+UDINT#2361852424+TO_UDINT(W[59]));
    s0:=(SHR(f,2) OR SHL(f,30)) XOR (SHR(f,13) OR SHL(f,19)) XOR (SHR(f,22) OR SHL(f,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((f AND g) XOR (f AND h) XOR (g AND h)));
    a:=TO_DWORD(TO_UDINT(a)+TO_UDINT(t1)); e:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 60: rotated register names remove seven copy assignments. *)
    s1:=(SHR(a,6) OR SHL(a,26)) XOR (SHR(a,11) OR SHL(a,21)) XOR (SHR(a,25) OR SHL(a,7));
    t1:=TO_DWORD(TO_UDINT(d)+TO_UDINT(s1)+TO_UDINT((a AND b) XOR ((NOT a) AND c))+UDINT#2428436474+TO_UDINT(W[60]));
    s0:=(SHR(e,2) OR SHL(e,30)) XOR (SHR(e,13) OR SHL(e,19)) XOR (SHR(e,22) OR SHL(e,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((e AND f) XOR (e AND g) XOR (f AND g)));
    h:=TO_DWORD(TO_UDINT(h)+TO_UDINT(t1)); d:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 61: rotated register names remove seven copy assignments. *)
    s1:=(SHR(h,6) OR SHL(h,26)) XOR (SHR(h,11) OR SHL(h,21)) XOR (SHR(h,25) OR SHL(h,7));
    t1:=TO_DWORD(TO_UDINT(c)+TO_UDINT(s1)+TO_UDINT((h AND a) XOR ((NOT h) AND b))+UDINT#2756734187+TO_UDINT(W[61]));
    s0:=(SHR(d,2) OR SHL(d,30)) XOR (SHR(d,13) OR SHL(d,19)) XOR (SHR(d,22) OR SHL(d,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((d AND e) XOR (d AND f) XOR (e AND f)));
    g:=TO_DWORD(TO_UDINT(g)+TO_UDINT(t1)); c:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 62: rotated register names remove seven copy assignments. *)
    s1:=(SHR(g,6) OR SHL(g,26)) XOR (SHR(g,11) OR SHL(g,21)) XOR (SHR(g,25) OR SHL(g,7));
    t1:=TO_DWORD(TO_UDINT(b)+TO_UDINT(s1)+TO_UDINT((g AND h) XOR ((NOT g) AND a))+UDINT#3204031479+TO_UDINT(W[62]));
    s0:=(SHR(c,2) OR SHL(c,30)) XOR (SHR(c,13) OR SHL(c,19)) XOR (SHR(c,22) OR SHL(c,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((c AND d) XOR (c AND e) XOR (d AND e)));
    f:=TO_DWORD(TO_UDINT(f)+TO_UDINT(t1)); b:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    (* Round 63: rotated register names remove seven copy assignments. *)
    s1:=(SHR(f,6) OR SHL(f,26)) XOR (SHR(f,11) OR SHL(f,21)) XOR (SHR(f,25) OR SHL(f,7));
    t1:=TO_DWORD(TO_UDINT(a)+TO_UDINT(s1)+TO_UDINT((f AND g) XOR ((NOT f) AND h))+UDINT#3329325298+TO_UDINT(W[63]));
    s0:=(SHR(b,2) OR SHL(b,30)) XOR (SHR(b,13) OR SHL(b,19)) XOR (SHR(b,22) OR SHL(b,10));
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT((b AND c) XOR (b AND d) XOR (c AND d)));
    e:=TO_DWORD(TO_UDINT(e)+TO_UDINT(t1)); a:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));
    Hs[0] := TO_DWORD(TO_UDINT(Hs[0])+TO_UDINT(a)); Hs[1] := TO_DWORD(TO_UDINT(Hs[1])+TO_UDINT(b));
    Hs[2] := TO_DWORD(TO_UDINT(Hs[2])+TO_UDINT(c)); Hs[3] := TO_DWORD(TO_UDINT(Hs[3])+TO_UDINT(d));
    Hs[4] := TO_DWORD(TO_UDINT(Hs[4])+TO_UDINT(e)); Hs[5] := TO_DWORD(TO_UDINT(Hs[5])+TO_UDINT(f));
    Hs[6] := TO_DWORD(TO_UDINT(Hs[6])+TO_UDINT(g)); Hs[7] := TO_DWORD(TO_UDINT(Hs[7])+TO_UDINT(h));
    Block := Block + 1;
    IF Block >= Blocks THEN EXIT; END_IF;
END_FOR;
(* Digest rendering shares the same absolute scan budget. Consumers may use
   Digest only with Done; partial text is never a committed batch digest. *)
IF Block>=Blocks THEN
    FOR i:=1 TO 8 DO
        IF HexIndex>=8 THEN EXIT; END_IF;
        IF DeadlineUs>0 THEN
            IF GET_MICROSECONDS(TRUE)+ULINT#80>=DeadlineUs THEN RETURN; END_IF;
        END_IF;
        Digest:=CONCAT(Digest,TO_STRING(Hs[HexIndex],'{0:x8}'));
        HexIndex:=HexIndex+1;
    END_FOR;
    IF HexIndex=8 THEN Busy:=FALSE; Done:=TRUE; END_IF;
END_IF;
END_FUNCTION_BLOCK
