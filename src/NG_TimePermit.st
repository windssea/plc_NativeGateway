FUNCTION_BLOCK NG_TimePermit
VAR_INPUT
    Purpose : USINT;
    TokenBootId : NG_Id;
    CurrentBootId : NG_Id;
    NowMs : ULINT;
    TokenMonoMs : ULINT;
    TokenClockRevision : ULINT;
    TokenConnectionRevision : ULINT;
    CurrentClockRevision : ULINT;
    CurrentConnectionRevision : ULINT;
    EnqueueAllowed : BOOL;
    ControlAllowed : BOOL;
    SendAllowed : BOOL;
    AckApplyAllowed : BOOL;
END_VAR
VAR_OUTPUT
    Allowed : BOOL;
END_VAR
(* Same-boot token, supplied explicitly; never serialize these mono values.
   1 CAPTURE, 2 ENQUEUE, 3 CONTROL_SEND, 4 SEND, 5 ACK_APPLY. *)
Allowed:=FALSE;
IF Purpose=1 THEN Allowed:=TRUE; RETURN; END_IF;
IF Purpose=5 THEN Allowed:=AckApplyAllowed; RETURN; END_IF;
IF (TokenBootId='') OR (TokenBootId<>CurrentBootId)
    OR (TokenClockRevision<>CurrentClockRevision) OR (TokenConnectionRevision<>CurrentConnectionRevision)
    OR (NowMs<TokenMonoMs) THEN RETURN; END_IF;
IF NowMs-TokenMonoMs>=2000 THEN RETURN; END_IF;
CASE Purpose OF 2: Allowed:=EnqueueAllowed; 3: Allowed:=ControlAllowed; 4: Allowed:=SendAllowed; END_CASE;
END_FUNCTION_BLOCK
