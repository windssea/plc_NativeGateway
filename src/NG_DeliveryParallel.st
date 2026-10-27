FUNCTION_BLOCK NG_DeliveryParallel
VAR_INPUT
    GateOpen : BOOL;
    NowMs : ULINT;
    GatewayId : NG_Id;
    BootId : NG_Id;
    SubmitAck : BOOL;
    AckMessageId : NG_Id;
    AckStored : BOOL;
    AckRetryable : BOOL;
    AckCodes : NG_Text;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
    Packets : ARRAY[1..16] OF NG_Packet;
END_VAR
VAR_OUTPUT
    AckBusy : BOOL;
    SendSlot : UINT;
    SendGeneration : UDINT;
    SendMessageId : NG_Id;
END_VAR
VAR
    AckPath : NG_Delivery;
    SendPath : NG_Delivery;
    preferAck : BOOL;
    priorityHold : BOOL;
END_VAR
(* Independent bounded hash state prevents an incoming ACK from repeatedly
   cancelling an unfinished send verification. Both paths keep the original
   immutable SHA-256 and generation checks; ACK is serialised first. *)
(* Main rotates builder/delivery every scan. Flipping this priority every scan
   locks both clocks together: send always wins the delivery-first scans.
   Hold each inner priority for two calls, giving ACK and send one full-budget
   delivery-first turn each in every four scans. Neither digest is restarted. *)
priorityHold:=NOT priorityHold;
IF priorityHold THEN preferAck:=NOT preferAck; END_IF;
IF preferAck THEN
AckPath(GateOpen:=FALSE,NowMs:=NowMs,GatewayId:=GatewayId,BootId:=BootId,SubmitAck:=SubmitAck,
    AckMessageId:=AckMessageId,AckStored:=AckStored,AckRetryable:=AckRetryable,AckCodes:=AckCodes,Buffer:=Buffer,Packets:=Packets);
SendPath(GateOpen:=GateOpen,NowMs:=NowMs,GatewayId:=GatewayId,BootId:=BootId,SubmitAck:=FALSE,
    AckMessageId:='',AckStored:=FALSE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
ELSE
SendPath(GateOpen:=GateOpen,NowMs:=NowMs,GatewayId:=GatewayId,BootId:=BootId,SubmitAck:=FALSE,
    AckMessageId:='',AckStored:=FALSE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
AckPath(GateOpen:=FALSE,NowMs:=NowMs,GatewayId:=GatewayId,BootId:=BootId,SubmitAck:=SubmitAck,
    AckMessageId:=AckMessageId,AckStored:=AckStored,AckRetryable:=AckRetryable,AckCodes:=AckCodes,Buffer:=Buffer,Packets:=Packets);
END_IF;
AckBusy:=AckPath.AckBusy; SendSlot:=SendPath.SendSlot; SendGeneration:=SendPath.SendGeneration; SendMessageId:=SendPath.SendMessageId;
END_FUNCTION_BLOCK
