FUNCTION_BLOCK NG_Resources
VAR_INPUT
    NowMs : ULINT;
END_VAR
VAR_OUTPUT
    Changed : BOOL;
    MemoryValid : BOOL;
    CpuValid : BOOL;
    ProcessValid : BOOL;
    TotalKiB : ULINT;
    AvailableKiB : ULINT;
    RssKiB : ULINT;
    CpuPermille : UDINT;
    ProcessName : STRING[64];
    ErrorText : NG_Text;
END_VAR
VAR
    OpenFile : FILE_OPEN;
    ReadFile : FILE_READ;
    CloseFile : FILE_CLOSE;
    Convert : BUF_TO_STRING;
    Name : STRING;
    Bytes : NG_ProcBytes;
    Text : NG_ProcText;
    Stage : INT;
    FileIndex : INT := 1;
    Handle : UINT;
    Count : UDINT;
    NextRead : ULINT;
    p : INT;
    c : INT;
    n : INT;
    start : INT;
    token : ULINT;
    total : ULINT;
    idle : ULINT;
    PrevTotal : ULINT;
    PrevIdle : ULINT;
    HasDigit : BOOL;
    ProcFailed : BOOL;
END_VAR
Changed := FALSE;
CASE FileIndex OF
1: Name := '/proc/meminfo';
2: Name := '/proc/stat';
3: Name := '/proc/self/status';
END_CASE;
OpenFile(Execute := Stage=10, Name := Name);
ReadFile(Execute := Stage=20, Handle := Handle, MaxLength := UDINT#8191, Buffer := Bytes);
CloseFile(Execute := Stage=30, Handle := Handle);
Convert(REQ := Stage=40, BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := TO_INT(Count), BUFFER := Bytes, DST := Text);
CASE Stage OF
0:
    IF NowMs >= NextRead THEN FileIndex := 1; ErrorText := ''; ProcFailed := FALSE; Stage := 10; END_IF;
10:
    IF OpenFile.Error THEN ProcFailed := TRUE; Stage := 80;
    ELSIF OpenFile.Done THEN Handle := OpenFile.Handle; Stage := 20; END_IF;
20:
    IF ReadFile.Error OR ReadFile.Done THEN Count := ReadFile.LengthRead; ProcFailed := Count=0; Stage := 30; END_IF;
30:
    IF CloseFile.Done OR CloseFile.Error THEN IF CloseFile.Error OR ProcFailed THEN Stage := 80; ELSE Stage := 40; END_IF; END_IF;
40:
    IF Convert.ERROR THEN ProcFailed := TRUE; Stage := 80;
    ELSIF Convert.DONE THEN
        CASE FileIndex OF
        1:
            TotalKiB := NG_ProcNumber(Text,'MemTotal:'); AvailableKiB := NG_ProcNumber(Text,'MemAvailable:');
            IF AvailableKiB=0 THEN AvailableKiB := NG_ProcNumber(Text,'MemFree:')+NG_ProcNumber(Text,'Buffers:')+NG_ProcNumber(Text,'Cached:'); END_IF;
            MemoryValid := TotalKiB > 0;
        2:
            total := 0; idle := 0; n := 0; token := 0; HasDigit := FALSE;
            p := FIND(Text,'cpu ');
            IF p > 0 THEN
                p := p+4;
                WHILE p <= LEN(Text) DO
                    c := GET_CHAR(Text,p);
                    IF (c>=48) AND (c<=57) THEN token := token*10+TO_ULINT(c-48); HasDigit := TRUE;
                    ELSE
                        IF HasDigit THEN
                            n := n+1; IF n <= 8 THEN total := total+token; END_IF;
                            IF (n=4) OR (n=5) THEN idle := idle+token; END_IF;
                            token := 0; HasDigit := FALSE;
                        END_IF;
                        IF (c=10) OR (n>=8) THEN EXIT; END_IF;
                    END_IF;
                    p := p+1;
                END_WHILE;
                IF (PrevTotal > 0) AND (total > PrevTotal) AND (idle >= PrevIdle) THEN
                    CpuPermille := TO_UDINT((total-PrevTotal-(idle-PrevIdle))*1000/(total-PrevTotal)); CpuValid := TRUE;
                END_IF;
                PrevTotal := total; PrevIdle := idle;
            END_IF;
        3:
            RssKiB := NG_ProcNumber(Text,'VmRSS:'); ProcessValid := RssKiB > 0;
            start := FIND(Text,'Name:');
            IF start > 0 THEN
                start := start+5;
                WHILE start <= LEN(Text) DO c := GET_CHAR(Text,start); IF (c<>32) AND (c<>9) THEN EXIT; END_IF; start := start+1; END_WHILE;
                p := start;
                WHILE p <= LEN(Text) DO IF GET_CHAR(Text,p)=10 THEN EXIT; END_IF; p := p+1; END_WHILE;
                IF p > start THEN ProcessName := MID(Text,MIN(63,p-start),start); END_IF;
            END_IF;
        END_CASE;
        Stage := 80;
    END_IF;
80:
    IF ProcFailed THEN
        ErrorText := CONCAT('PROC_READ_FAILED:',TO_STRING(FileIndex,'{0:d}'));
        CASE FileIndex OF 1: MemoryValid := FALSE; 2: CpuValid := FALSE; 3: ProcessValid := FALSE; END_CASE;
    END_IF;
    ProcFailed := FALSE;
    IF FileIndex < 3 THEN FileIndex := FileIndex+1; Stage := 10;
    ELSE Changed := TRUE; NextRead := NowMs+10000; Stage := 0; END_IF;
END_CASE;
END_FUNCTION_BLOCK
