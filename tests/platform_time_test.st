PROGRAM Main
VAR
    LogicalClock : NG_PlatformTime;
    Permit : NG_TimePermit;
    WireTests : NG_TimeResponseTest;
    ClockDone : BOOL;
    Stage : UINT;
    Checks : ARRAY[1..24] OF BOOL;
    Passed : UINT;
    FailedChecks : UINT;
    Done : BOOL;
    Tick : ULINT := 100000;
    ResetClock : BOOL;
    Connected : BOOL := TRUE;
    Session : NG_Id := 'session-one';
    Submit : BOOL;
    Reply : BOOL;
    Heartbeat : BOOL;
    GetConfig : BOOL;
    RequestMono : ULINT;
    ServerT3 : ULINT;
    SystemDate : ULINT := 1000;
    SavedClockRevision : ULINT;
    SavedConnectionRevision : ULINT;
    i : UINT;
END_VAR
(* Offline assertion program. No gateway, socket, store, physical IO or RTC writes.
   Cold compilation is not execution; Done/Checks need a later authorized test runtime. *)
WireTests();
Done:=ClockDone AND WireTests.Done;
IF ClockDone THEN RETURN; END_IF;
ResetClock:=FALSE; Submit:=FALSE; Reply:=FALSE; Heartbeat:=FALSE; GetConfig:=FALSE;
CASE Stage OF
    0: ResetClock:=TRUE;
    1,3,5: Submit:=TRUE; RequestMono:=Tick;
    2,4,6: Tick:=Tick+20; Reply:=TRUE; ServerT3:=ULINT#1792000000000+Tick-100000-9;
    7: GetConfig:=TRUE;
    8: Heartbeat:=TRUE;
    9: GetConfig:=TRUE;
    10: SystemDate:=ULINT#9000000000000; Tick:=Tick+20;
    11: Connected:=FALSE; Tick:=Tick+20;
    12: Connected:=TRUE; Session:='session-two'; Tick:=Tick+20;
    13: Tick:=Tick+3600000;
    14: Tick:=Tick-1;
END_CASE;
LogicalClock(Reset:=ResetClock,PlatformMode:=TRUE,Connected:=Connected,SessionId:=Session,NowMs:=Tick,SystemUtcMs:=SystemDate,
    TimeBasisRef:='site-hub-1',DriftBoundPpm:=LREAL#50.0,DriftEvidence:='TEST_FIXTURE_ONLY',HistoryBasisRef:='',HistoryUtcLowerMs:=0,
    RequestSubmitted:=Submit,ResponseReady:=Reply,ResponseClientMonoMs:=RequestMono,ResponseReceivedMonoMs:=Tick,
    ServerReceivedMs:=ServerT3-2,ServerSentMs:=ServerT3,HeartbeatSubmitted:=Heartbeat,ConfigGetSubmitted:=GetConfig);
CASE Stage OF
0:
    Checks[1]:=LogicalClock.CaptureAllowed AND LogicalClock.AckApplyAllowed AND NOT LogicalClock.EnqueueAllowed AND NOT LogicalClock.ControlAllowed;
    Checks[2]:=LogicalClock.RequestWanted AND NOT LogicalClock.TimeValid;
1: Checks[3]:=LogicalClock.PendingRequest AND (LogicalClock.RequestClientMonoMs=Tick) AND (LogicalClock.Attempts=1);
2: Checks[4]:=NOT LogicalClock.TimeValid AND LogicalClock.RequestWanted;
6:
    Checks[5]:=LogicalClock.TimeValid AND LogicalClock.ControlAllowed AND NOT LogicalClock.SendAllowed;
    Checks[6]:=(LogicalClock.UtcMs=ULINT#1792000000060) AND (LogicalClock.UncertaintyMs=32);
    SavedClockRevision:=LogicalClock.ClockRevision; SavedConnectionRevision:=LogicalClock.ConnectionRevision;
7: Checks[7]:=NOT LogicalClock.SendAllowed;
8: Checks[8]:=NOT LogicalClock.SendAllowed;
9: Checks[9]:=LogicalClock.SendAllowed;
10: Checks[10]:=LogicalClock.TimeValid AND (LogicalClock.UtcMs=ULINT#1792000000080);
11: Checks[11]:=LogicalClock.TimeValid AND LogicalClock.EnqueueAllowed AND NOT LogicalClock.ControlAllowed AND NOT LogicalClock.SendAllowed;
12:
    Checks[12]:=LogicalClock.TimeValid AND NOT LogicalClock.ControlAllowed AND NOT LogicalClock.SendAllowed;
    Checks[13]:=(LogicalClock.ClockRevision=SavedClockRevision) AND (LogicalClock.ConnectionRevision>SavedConnectionRevision);
    Permit(Purpose:=USINT#4,TokenBootId:='boot-one',CurrentBootId:='boot-one',NowMs:=Tick,TokenMonoMs:=Tick,
        TokenClockRevision:=SavedClockRevision,TokenConnectionRevision:=SavedConnectionRevision,
        CurrentClockRevision:=LogicalClock.ClockRevision,CurrentConnectionRevision:=LogicalClock.ConnectionRevision,
        EnqueueAllowed:=TRUE,ControlAllowed:=TRUE,SendAllowed:=TRUE,AckApplyAllowed:=TRUE);
    Checks[14]:=NOT Permit.Allowed;
13:
    Checks[15]:=NOT LogicalClock.TimeValid AND NOT LogicalClock.EnqueueAllowed AND LogicalClock.CaptureAllowed AND LogicalClock.AckApplyAllowed;
    Checks[16]:=LogicalClock.State=4;
14:
    Checks[17]:=(LogicalClock.State=6) AND NOT LogicalClock.TimeValid;
    Permit(Purpose:=USINT#5,TokenBootId:='',CurrentBootId:='boot-one',NowMs:=Tick,TokenMonoMs:=0,
        TokenClockRevision:=0,TokenConnectionRevision:=0,CurrentClockRevision:=99,CurrentConnectionRevision:=99,
        EnqueueAllowed:=FALSE,ControlAllowed:=FALSE,SendAllowed:=FALSE,AckApplyAllowed:=TRUE);
    Checks[18]:=Permit.Allowed;
    Permit(Purpose:=USINT#2,TokenBootId:='old-boot',CurrentBootId:='boot-one',NowMs:=Tick,TokenMonoMs:=Tick,
        TokenClockRevision:=0,TokenConnectionRevision:=0,CurrentClockRevision:=0,CurrentConnectionRevision:=0,
        EnqueueAllowed:=TRUE,ControlAllowed:=TRUE,SendAllowed:=TRUE,AckApplyAllowed:=TRUE);
    Checks[19]:=NOT Permit.Allowed;
    Permit(Purpose:=USINT#2,TokenBootId:='boot-one',CurrentBootId:='boot-one',NowMs:=Tick,TokenMonoMs:=Tick-2000,
        TokenClockRevision:=0,TokenConnectionRevision:=0,CurrentClockRevision:=0,CurrentConnectionRevision:=0,
        EnqueueAllowed:=TRUE,ControlAllowed:=TRUE,SendAllowed:=TRUE,AckApplyAllowed:=TRUE);
    Checks[20]:=NOT Permit.Allowed;
    Permit(Purpose:=USINT#2,TokenBootId:='boot-one',CurrentBootId:='boot-one',NowMs:=Tick,TokenMonoMs:=Tick,
        TokenClockRevision:=0,TokenConnectionRevision:=0,CurrentClockRevision:=0,CurrentConnectionRevision:=0,
        EnqueueAllowed:=TRUE,ControlAllowed:=TRUE,SendAllowed:=TRUE,AckApplyAllowed:=TRUE);
    Checks[21]:=Permit.Allowed;
    LogicalClock(Reset:=TRUE,PlatformMode:=FALSE,Connected:=TRUE,SessionId:='compat',NowMs:=Tick,SystemUtcMs:=SystemDate,
        TimeBasisRef:='',DriftBoundPpm:=0,DriftEvidence:='',HistoryBasisRef:='',HistoryUtcLowerMs:=0,
        RequestSubmitted:=FALSE,ResponseReady:=FALSE,HeartbeatSubmitted:=FALSE,ConfigGetSubmitted:=FALSE);
    Checks[22]:=NOT LogicalClock.TimeValid AND LogicalClock.EnqueueAllowed AND NOT LogicalClock.RequestWanted;
    LogicalClock(Reset:=TRUE,PlatformMode:=TRUE,Connected:=TRUE,SessionId:='bad-drift',NowMs:=Tick,SystemUtcMs:=SystemDate,
        TimeBasisRef:='site-hub-1',DriftBoundPpm:=50,DriftEvidence:='',HistoryBasisRef:='',HistoryUtcLowerMs:=0);
    Checks[23]:=(LogicalClock.State=6) AND NOT LogicalClock.EnqueueAllowed;
    LogicalClock(Reset:=TRUE,PlatformMode:=TRUE,Connected:=TRUE,SessionId:='bad-basis',NowMs:=Tick,SystemUtcMs:=SystemDate,
        TimeBasisRef:='site-hub-1',DriftBoundPpm:=50,DriftEvidence:='TEST_FIXTURE_ONLY',HistoryBasisRef:='other-hub',HistoryUtcLowerMs:=1);
    Checks[24]:=(LogicalClock.State=6) AND NOT LogicalClock.EnqueueAllowed;
    Passed:=0; FailedChecks:=0;
    FOR i:=1 TO 24 DO IF Checks[i] THEN Passed:=Passed+1; ELSE FailedChecks:=FailedChecks+1; END_IF; END_FOR;
    ClockDone:=TRUE;
END_CASE;
Stage:=Stage+1;
END_PROGRAM
