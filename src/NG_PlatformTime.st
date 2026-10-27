FUNCTION_BLOCK NG_PlatformTime
VAR_INPUT
    Reset : BOOL;
    PlatformMode : BOOL;
    Connected : BOOL;
    SessionId : NG_Id;
    NowMs : ULINT;
    SystemUtcMs : ULINT;
    TimeBasisRef : NG_Id;
    DriftBoundPpm : LREAL;
    DriftEvidence : NG_Text;
    HistoryBasisRef : NG_Id;
    HistoryUtcLowerMs : ULINT;
    RequestSubmitted : BOOL;
    RequestSubmittedMonoMs : ULINT;
    ResponseReady : BOOL;
    ResponseClientMonoMs : ULINT;
    ResponseReceivedMonoMs : ULINT;
    ServerReceivedMs : ULINT;
    ServerSentMs : ULINT;
    HeartbeatSubmitted : BOOL;
    ConfigGetSubmitted : BOOL;
END_VAR
VAR_OUTPUT
    State : USINT;
    TimeValid : BOOL;
    UtcMs : ULINT;
    UncertaintyMs : ULINT;
    SyncAgeMs : ULINT;
    ClockRevision : ULINT;
    ConnectionRevision : ULINT;
    CaptureAllowed : BOOL;
    EnqueueAllowed : BOOL;
    ControlAllowed : BOOL;
    SendAllowed : BOOL;
    AckApplyAllowed : BOOL;
    RequestWanted : BOOL;
    RequestId : NG_Id;
    RequestClientMonoMs : ULINT;
    PendingRequest : BOOL;
    Attempts : UINT;
    HeartbeatReady : BOOL;
    ConfigGetReady : BOOL;
    ErrorText : NG_Text;
END_VAR
VAR
    Started : BOOL;
    SeenConnected : BOOL;
    SeenSession : NG_Id;
    SeenPlatformMode : BOOL;
    SeenBasis : NG_Id;
    SeenDrift : LREAL;
    SeenDriftEvidence : NG_Text;
    SessionChecked : BOOL;
    HeartbeatAccepted : BOOL;
    GetAccepted : BOOL;
    LastMono : ULINT;
    Anchor : LREAL;
    HasAnchor : BOOL;
    Residual : LREAL;
    BaseError : LREAL;
    LastSync : ULINT;
    RoundStart : ULINT;
    RoundOpen : BOOL;
    NextSync : ULINT;
    Failures : UINT;
    RequestSequence : ULINT;
    Candidates : UINT;
    CandidateUtc : ARRAY[1..3] OF LREAL;
    CandidateMono : ARRAY[1..3] OF ULINT;
    CandidatePath : ARRAY[1..3] OF LREAL;
    CandidateError : ARRAY[1..3] OF LREAL;
    CandidateRtt : ARRAY[1..3] OF ULINT;
    ConfirmDeviation : BOOL;
    Elapsed : LREAL;
    Correction : LREAL;
    ErrorBound : LREAL;
    Rtt : LREAL;
    Processing : LREAL;
    PathMs : LREAL;
    Target : LREAL;
    CandidateLow : LREAL;
    CandidateHigh : LREAL;
    ChosenError : LREAL;
    BestPath : LREAL;
    DelayMs : ULINT;
    FinishRound : BOOL;
    Adopt : BOOL;
    Invalidate : BOOL;
    WasValid : BOOL;
    Chosen : UINT;
    i : UINT;
END_VAR
(* Pure clock kernel: no RTC writes, file, socket, device or vendor timing calls.
   ResponseReady must come from NG_TimeResponse after exact echo/retained checks.
   RequestSubmitted/control inputs mean synchronous SDK acceptance, never PUBACK.
   State: 0 UNSYNCED, 1 SYNCING, 2 SYNCED, 3 HOLDOVER, 4 EXPIRED,
          5 SUSPECT, 6 MAINTENANCE. Reset means a NEW boot only. *)
IF Reset OR NOT Started THEN
    Started:=TRUE; State:=0; HasAnchor:=FALSE; TimeValid:=FALSE; Anchor:=0;
    Residual:=0; ClockRevision:=0; ConnectionRevision:=0; LastMono:=NowMs;
    SeenConnected:=FALSE; SeenSession:=''; SessionChecked:=FALSE;
    SeenPlatformMode:=PlatformMode; SeenBasis:=TimeBasisRef;
    SeenDrift:=DriftBoundPpm; SeenDriftEvidence:=DriftEvidence;
    HeartbeatAccepted:=FALSE; GetAccepted:=FALSE; PendingRequest:=FALSE;
    RequestWanted:=FALSE; RoundOpen:=FALSE; NextSync:=0; RequestSequence:=0;
    Attempts:=0; Candidates:=0; Failures:=0; ConfirmDeviation:=FALSE; ErrorText:='';
END_IF;
WasValid:=TimeValid; Invalidate:=FALSE; Adopt:=FALSE; FinishRound:=FALSE;
IF (PlatformMode<>SeenPlatformMode) OR (TimeBasisRef<>SeenBasis)
    OR (DriftBoundPpm<>SeenDrift) OR (DriftEvidence<>SeenDriftEvidence) THEN
    State:=6; Invalidate:=TRUE; ErrorText:='TIME_SOURCE_CHANGE_REQUIRES_MAINTENANCE';
END_IF;
IF NowMs<LastMono THEN
    State:=6; HasAnchor:=FALSE; Invalidate:=TRUE; ErrorText:='CLOCK_CONTINUITY_REQUIRES_MAINTENANCE';
END_IF;
Elapsed:=0; IF NowMs>=LastMono THEN Elapsed:=TO_LREAL(NowMs-LastMono); END_IF;
IF HasAnchor THEN
    Correction:=MAX(-Elapsed*LREAL#0.005,MIN(Elapsed*LREAL#0.005,Residual));
    Anchor:=Anchor+Elapsed+Correction; Residual:=Residual-Correction;
END_IF;
LastMono:=NowMs;
IF (Connected<>SeenConnected) OR (Connected AND (SessionId<>SeenSession)) THEN
    IF ConnectionRevision>=ULINT#9007199254740991 THEN State:=6; ErrorText:='CONNECTION_REVISION_EXHAUSTED';
    ELSE ConnectionRevision:=ConnectionRevision+1; END_IF;
    SeenConnected:=Connected; SeenSession:=SessionId; SessionChecked:=FALSE;
    HeartbeatAccepted:=FALSE; GetAccepted:=FALSE; PendingRequest:=FALSE;
    RequestWanted:=FALSE; RoundOpen:=FALSE; Candidates:=0; Attempts:=0; NextSync:=NowMs;
END_IF;
IF PlatformMode THEN
    IF NOT NG_ValidId(TimeBasisRef) OR (DriftEvidence='') OR NOT ((DriftBoundPpm>=0) AND (DriftBoundPpm<=1000)) THEN
        State:=6; Invalidate:=TRUE; ErrorText:='MISSING_TIME_BASIS_OR_DRIFT_EVIDENCE';
    END_IF;
    IF (HistoryUtcLowerMs>0) AND (HistoryBasisRef<>TimeBasisRef) THEN
        State:=6; Invalidate:=TRUE; ErrorText:='HISTORY_BASIS_REQUIRES_MAINTENANCE';
    END_IF;
    IF PendingRequest AND (NowMs>=RequestClientMonoMs+2000) THEN PendingRequest:=FALSE; END_IF;
    IF ResponseReady AND PendingRequest AND (State<>6) THEN
        (* Reader is required to compare the exact six request fields first. *)
        PendingRequest:=FALSE;
        IF (ResponseClientMonoMs=RequestClientMonoMs) AND (ResponseReceivedMonoMs>=RequestClientMonoMs)
            AND (ResponseReceivedMonoMs<=NowMs) AND (NowMs<RequestClientMonoMs+2000)
            AND (ServerSentMs>=ServerReceivedMs) AND (ServerSentMs<=ULINT#9007199254740991) THEN
            Rtt:=TO_LREAL(ResponseReceivedMonoMs-RequestClientMonoMs);
            Processing:=TO_LREAL(ServerSentMs-ServerReceivedMs); PathMs:=Rtt-Processing;
            Target:=TO_LREAL(ServerSentMs)+MAX(LREAL#0.0,PathMs)/2;
            ErrorBound:=MAX(LREAL#0.0,PathMs)/2+MAX(LREAL#0.0,-PathMs)+22;
            IF (Rtt<2000) AND (Processing<=500) AND (PathMs>=-50)
                AND (Target-ErrorBound>=0) AND (Target+ErrorBound<=LREAL#9007199254740991.0) THEN
                IF Candidates<3 THEN
                    Candidates:=Candidates+1; CandidateUtc[Candidates]:=Target;
                    CandidateMono[Candidates]:=ResponseReceivedMonoMs; CandidatePath[Candidates]:=MAX(LREAL#0.0,PathMs);
                    CandidateError[Candidates]:=ErrorBound; CandidateRtt[Candidates]:=TO_ULINT(Rtt);
                    IF Candidates=3 THEN FinishRound:=TRUE; END_IF;
                END_IF;
            ELSE ErrorText:='HIGH_DELAY_OR_UNSAFE_TIME'; END_IF;
        ELSE ErrorText:='STALE_TIME_RESPONSE'; END_IF;
    END_IF;
    IF RoundOpen AND ((NowMs>=RoundStart+30000) OR ((Attempts>=10) AND NOT PendingRequest)) THEN FinishRound:=TRUE; END_IF;
    IF FinishRound THEN
        Chosen:=0; CandidateLow:=LREAL#9007199254740991.0; CandidateHigh:=0; BestPath:=LREAL#9007199254740991.0;
        FOR i:=1 TO Candidates DO
            Target:=CandidateUtc[i]+TO_LREAL(NowMs-CandidateMono[i]);
            CandidateLow:=MIN(CandidateLow,Target); CandidateHigh:=MAX(CandidateHigh,Target);
            IF ((Candidates>=3) OR (CandidateRtt[i]<=500)) AND (CandidatePath[i]<BestPath) THEN
                Chosen:=i; BestPath:=CandidatePath[i];
            END_IF;
        END_FOR;
        IF (Chosen>0) AND (CandidateHigh-CandidateLow<=500) THEN
            Target:=CandidateUtc[Chosen]+TO_LREAL(NowMs-CandidateMono[Chosen]);
            ChosenError:=CandidateError[Chosen]+TO_LREAL(NowMs-CandidateMono[Chosen])*DriftBoundPpm/LREAL#1000000.0;
            IF (HistoryUtcLowerMs>0) AND (Target+ChosenError<TO_LREAL(HistoryUtcLowerMs)) THEN
                State:=6; Invalidate:=TRUE; ErrorText:='HISTORY_ROLLBACK_REQUIRES_MAINTENANCE';
            ELSIF HasAnchor AND (ABS(Target-Anchor)>1000) THEN
                State:=5; Invalidate:=TRUE; ErrorText:='CLOCK_DISCONTINUITY';
                IF NOT ConfirmDeviation THEN ConfirmDeviation:=TRUE; NextSync:=NowMs;
                ELSIF Target+ChosenError<Anchor THEN State:=6; ErrorText:='ROLLBACK_REQUIRES_MAINTENANCE';
                ELSE HasAnchor:=FALSE; Adopt:=TRUE; END_IF;
            ELSE Adopt:=TRUE; END_IF;
            IF Adopt THEN
                IF NOT HasAnchor OR (State=4) OR (State=0) OR (State=1) THEN
                    Anchor:=Target; Residual:=0; HasAnchor:=TRUE;
                    IF ClockRevision>=ULINT#9007199254740991 THEN State:=6; Invalidate:=TRUE;
                    ELSE ClockRevision:=ClockRevision+1; END_IF;
                ELSE Residual:=Target-Anchor; END_IF;
                IF State<>6 THEN
                    BaseError:=ChosenError; LastSync:=NowMs; State:=2; SessionChecked:=Connected;
                    ConfirmDeviation:=FALSE; Failures:=0; ErrorText:=''; Invalidate:=FALSE;
                    IF Candidates<3 THEN NextSync:=NowMs+10000;
                    ELSE NextSync:=NowMs+270000+(RequestSequence MOD 60001); END_IF;
                END_IF;
            END_IF;
        ELSE
            Failures:=MIN(Failures+1,UINT#5); DelayMs:=5000;
            CASE Failures OF 2: DelayMs:=10000; 3: DelayMs:=20000; 4: DelayMs:=40000; 5: DelayMs:=60000; END_CASE;
            NextSync:=NowMs+MIN(ULINT#60000,DelayMs+(RequestSequence MOD 1001)); ErrorText:='TIMEOUT_OR_INCONSISTENT';
        END_IF;
        RoundOpen:=FALSE; PendingRequest:=FALSE; Candidates:=0;
    END_IF;
    IF (State<>6) AND Connected AND (NowMs>=NextSync) AND NOT PendingRequest THEN
        IF NOT RoundOpen THEN
            RoundOpen:=TRUE; RoundStart:=NowMs; Attempts:=0; Candidates:=0;
            IF NOT HasAnchor THEN State:=1; END_IF;
        END_IF;
        RequestWanted:=(Attempts<10) AND (NowMs<RoundStart+30000);
    ELSE RequestWanted:=FALSE; END_IF;
    IF RequestWanted THEN RequestId:=CONCAT('t-',TO_STRING(ConnectionRevision,'{0:d}'),'-',TO_STRING(RequestSequence+1,'{0:d}')); END_IF;
    IF RequestSubmitted AND RequestWanted THEN
        IF RequestSequence>=ULINT#9007199254740990 THEN State:=6; Invalidate:=TRUE; ErrorText:='REQUEST_SEQUENCE_EXHAUSTED';
        ELSE
            RequestSequence:=RequestSequence+1; RequestClientMonoMs:=NowMs;
            IF (RequestSubmittedMonoMs>0) AND (RequestSubmittedMonoMs<=NowMs) THEN RequestClientMonoMs:=RequestSubmittedMonoMs; END_IF;
            Attempts:=Attempts+1; PendingRequest:=TRUE; RequestWanted:=FALSE;
        END_IF;
    END_IF;
END_IF;
UtcMs:=0; UncertaintyMs:=0; SyncAgeMs:=0; TimeValid:=FALSE;
IF HasAnchor THEN
    SyncAgeMs:=NowMs-LastSync;
    ErrorBound:=BaseError+TO_LREAL(SyncAgeMs)*DriftBoundPpm/LREAL#1000000.0+ABS(Residual);
    (* Round up positive error; TO_ULINT rounds rather than truncates on target. *)
    IF (ErrorBound>=0) AND (ErrorBound<LREAL#9007199254740990.0) THEN
        UncertaintyMs:=TO_ULINT(TRUNC_LINT(ErrorBound));
        IF TO_LREAL(UncertaintyMs)<ErrorBound THEN UncertaintyMs:=UncertaintyMs+1; END_IF;
    END_IF;
    TimeValid:=PlatformMode AND ((State=2) OR (State=3)) AND (SyncAgeMs<3600000)
        AND (ErrorBound>=0) AND (UncertaintyMs<1000) AND (Anchor-ErrorBound>=0)
        AND (Anchor+ErrorBound<=LREAL#9007199254740991.0);
    IF TimeValid THEN
        UtcMs:=TO_ULINT(TRUNC_LINT(Anchor)); IF SessionChecked THEN State:=2; ELSE State:=3; END_IF;
    ELSIF (State=2) OR (State=3) THEN State:=4; Invalidate:=TRUE; ErrorText:='HOLDOVER_EXPIRED'; END_IF;
END_IF;
IF Invalidate THEN
    IF WasValid THEN
        IF ClockRevision>=ULINT#9007199254740991 THEN State:=6;
        ELSE ClockRevision:=ClockRevision+1; END_IF;
    END_IF;
    SessionChecked:=FALSE; HeartbeatAccepted:=FALSE; GetAccepted:=FALSE;
END_IF;
CaptureAllowed:=TRUE; AckApplyAllowed:=Connected;
EnqueueAllowed:=TimeValid; ControlAllowed:=TimeValid AND Connected AND SessionChecked;
IF NOT PlatformMode AND (State<>6) THEN
    EnqueueAllowed:=(SystemUtcMs>0) AND (SystemUtcMs<=ULINT#9007199254740991);
    ControlAllowed:=EnqueueAllowed AND Connected; UtcMs:=SystemUtcMs;
END_IF;
IF ControlAllowed THEN
    IF HeartbeatSubmitted THEN HeartbeatAccepted:=TRUE; END_IF;
    IF ConfigGetSubmitted AND HeartbeatAccepted THEN GetAccepted:=TRUE; END_IF;
END_IF;
SendAllowed:=ControlAllowed AND HeartbeatAccepted AND GetAccepted;
HeartbeatReady:=HeartbeatAccepted; ConfigGetReady:=GetAccepted;
END_FUNCTION_BLOCK
