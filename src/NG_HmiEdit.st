FUNCTION_BLOCK NG_HmiEdit
VAR_INPUT
    Busy : BOOL;
    Managed : BOOL;
    LocalRevision : ULINT;
    NowMs : ULINT;
END_VAR
VAR_IN_OUT
    Hmi : NG_Hmi;
    Active : NG_Config;
    Bootstrap : NG_Bootstrap;
    States : ARRAY[1..50] OF NG_MeterState;
    Samples : ARRAY[1..320] OF NG_Sample;
END_VAR
VAR_OUTPUT
    Submit : BOOL;
    SubmitBroker : BOOL;
    SubmitMode : BOOL;
    ClearConfig : BOOL;
    Draft : NG_Config;
    NewBroker : NG_Bootstrap;
    NewManaged : BOOL;
END_VAR
VAR
    Change : NG_EditDevice;
    EditPoints : ARRAY[1..32] OF NG_Point;
    BlankPoint : NG_Point;
    BlankDevice : NG_Device;
    BaseVersion : ULINT;
    BaseRevision : ULINT;
    ModeTargetManaged : BOOL;
    ModeReviewOpen : BOOL;
    Initialized : BOOL;
    Dirty : BOOL;
    Awaiting : BOOL;
    Reload : BOOL;
    LoadDevice : BOOL;
    LoadPoint : BOOL;
    ValidBroker : BOOL;
    RefreshAt : ULINT;
    Nav : STRING[16];
    d : INT;
    p : INT;
    i : INT;
    row : INT;
    a : INT;
    b : INT;
    idx : INT;
    pages : INT;
    point : NG_Point;
    device : NG_Device;
    rows : ARRAY[1..8] OF NG_UiLabel;
    marker : STRING[3];
    status : STRING[24];
    value : STRING[64];
    cmd : BOOL;
END_VAR
Submit := FALSE; SubmitBroker := FALSE; SubmitMode := FALSE; ClearConfig := FALSE; LoadDevice := FALSE; LoadPoint := FALSE;
Nav := Hmi.Navigation; Hmi.Navigation := '';
IF Nav='ZH' THEN Hmi.English:=FALSE;
ELSIF Nav='EN' THEN Hmi.English:=TRUE;
ELSIF Nav='REFRESH' THEN IF Dirty THEN Hmi.View:=5; ELSE Hmi.Load:=TRUE; END_IF;
ELSIF Nav='DISCARD' THEN Hmi.Load:=TRUE; Hmi.View:=0;
ELSIF Nav='REVIEW' THEN Hmi.View:=6;
ELSIF Nav='COMMIT' THEN Hmi.Apply:=TRUE;
ELSIF Nav='DEVON' THEN Hmi.DeviceEnabled:='true';
ELSIF Nav='DEVOFF' THEN Hmi.DeviceEnabled:='false';
ELSIF Nav='POINTON' THEN Hmi.PointEnabled:='true';
ELSIF Nav='POINTOFF' THEN Hmi.PointEnabled:='false';
ELSIF Nav='MODEPAGE' THEN ModeReviewOpen:=FALSE; Hmi.View:=13;
ELSIF Nav='MODEHUB' THEN ModeTargetManaged:=TRUE; ModeReviewOpen:=TRUE; Hmi.ClearOnMaintenance:=FALSE; Hmi.View:=15;
ELSIF Nav='MODELOCAL' THEN ModeTargetManaged:=FALSE; ModeReviewOpen:=TRUE; Hmi.ClearOnMaintenance:=FALSE; Hmi.View:=14;
ELSIF Nav='MODEKEEP' THEN Hmi.ClearOnMaintenance:=FALSE;
ELSIF Nav='MODECLEAR' THEN Hmi.ClearOnMaintenance:=TRUE;
ELSIF Nav='MODECOMMIT' THEN
    IF ModeReviewOpen AND ((Hmi.View=14) OR (Hmi.View=15)) THEN Hmi.SwitchMode:=TRUE;
    ELSE Hmi.Status:='Open the management mode confirmation before saving.'; END_IF;
ELSIF Nav='CYCLIC' THEN Hmi.ReportMode:='cyclic';
ELSIF Nav='CHANGE' THEN Hmi.ReportMode:='change';
ELSIF Nav='BOTH' THEN Hmi.ReportMode:='change_or_cyclic';
ELSIF Nav='HOLDING' THEN Hmi.Area:='holding_register';
ELSIF Nav='INPUT' THEN Hmi.Area:='input_register';
ELSIF Nav='COIL' THEN Hmi.Area:='coil';
ELSIF Nav='DISCRETE' THEN Hmi.Area:='discrete_input';
ELSIF Nav='UINT16' THEN Hmi.DataType:='uint16'; Hmi.ByteOrder:='AB';
ELSIF Nav='INT16' THEN Hmi.DataType:='int16'; Hmi.ByteOrder:='AB';
ELSIF Nav='UINT32' THEN Hmi.DataType:='uint32'; Hmi.ByteOrder:='ABCD';
ELSIF Nav='INT32' THEN Hmi.DataType:='int32'; Hmi.ByteOrder:='ABCD';
ELSIF Nav='FLOAT32' THEN Hmi.DataType:='float32'; Hmi.ByteOrder:='ABCD';
ELSIF Nav='BOOL' THEN Hmi.DataType:='bool'; Hmi.ByteOrder:=''; Hmi.Scale:='1'; Hmi.Offset:='0'; Hmi.Deadband:='0';
ELSIF Nav='ADVANCED' THEN Hmi.Advanced:=NOT Hmi.Advanced;
ELSIF Nav='BROKERREVIEW' THEN Hmi.View:=7;
ELSIF Nav='BROKERCOMMIT' THEN Hmi.SaveBroker:=TRUE;
ELSIF Nav='HELP' THEN Hmi.View:=8;
ELSIF Nav='TYPEPICK' THEN Hmi.View:=9;
ELSIF Nav='AREAPICK' THEN Hmi.View:=10;
ELSIF Nav='REPORTPICK' THEN Hmi.View:=11;
ELSIF Nav='GATEWAY' THEN Hmi.View:=12;
ELSIF Nav='POINTBACK' THEN Hmi.View:=2;
END_IF;
IF (Nav='CYCLIC') OR (Nav='CHANGE') OR (Nav='BOTH') OR (Nav='HOLDING') OR (Nav='INPUT') OR (Nav='COIL') OR (Nav='DISCRETE') OR (Nav='UINT16') OR (Nav='INT16') OR (Nav='UINT32') OR (Nav='INT32') OR (Nav='FLOAT32') OR (Nav='BOOL') THEN Hmi.View:=2; END_IF;
Hmi.Managed:=Managed;
IF Managed THEN Hmi.ManagementMode:='HUB_MANAGED'; ELSE Hmi.ManagementMode:='STANDALONE'; END_IF;
IF Managed AND ((Nav='DNEW') OR (Nav='PNEW') OR (Nav='DDEL') OR (Nav='PDEL') OR (Nav='PERIOD') OR Hmi.SaveDevice OR Hmi.SavePoint OR Hmi.RemoveDevice OR Hmi.RemovePoint OR Hmi.Apply) THEN
    Nav := ''; Hmi.SaveDevice:=FALSE; Hmi.SavePoint:=FALSE; Hmi.RemoveDevice:=FALSE; Hmi.RemovePoint:=FALSE; Hmi.Apply:=FALSE;
    Hmi.View:=0; Hmi.Status:='HUB_MANAGED: publish device and point changes from Hub.';
END_IF;
IF Managed THEN Hmi.ConfigSource:='HUB_MANAGED - local device/point changes blocked'; ELSE Hmi.ConfigSource:='MAINTENANCE - incoming platform configuration locked'; END_IF;
IF NOT Initialized THEN Reload := TRUE; Initialized := TRUE; END_IF;
IF Awaiting AND (Active.Version = Draft.Version) AND NOT Busy THEN Dirty := FALSE; Awaiting := FALSE; Reload := TRUE; Hmi.View:=0; END_IF;
IF ((Active.Version <> BaseVersion) OR (LocalRevision <> BaseRevision)) AND NOT Dirty AND NOT Awaiting AND NOT Busy THEN Reload := TRUE; END_IF;
IF Hmi.Load AND NOT Busy THEN Reload := TRUE; Hmi.View:=0; Hmi.Status := 'Display refreshed from active configuration. Unapplied draft discarded.'; END_IF;
IF Reload THEN
    Draft := Active; BaseVersion := Active.Version; BaseRevision := LocalRevision; Dirty := FALSE; Reload := FALSE;
    Hmi.Enabled := TO_STRING(Draft.enabled,''); Hmi.BatchIntervalMs := TO_STRING(Draft.batchIntervalMs,'{0:d}'); Hmi.MaxBatchPoints := TO_STRING(Draft.maxBatchPoints,'{0:d}');
    IF NOT NG_Range(Hmi.DeviceIndex,1,50,TRUE) THEN Hmi.DeviceIndex := '1'; END_IF;
    Hmi.PointIndex := '1'; LoadDevice := TRUE; LoadPoint := TRUE;
END_IF;
d := 1; p := 1;
IF NG_Range(Hmi.DeviceIndex,1,50,TRUE) THEN d := TO_INT(Hmi.DeviceIndex); END_IF;
IF NG_Range(Hmi.PointIndex,1,32,TRUE) THEN p := TO_INT(Hmi.PointIndex); END_IF;
IF Nav = 'LIST' THEN Hmi.View := 0;
ELSIF Nav = 'MQTT' THEN Hmi.View := 3;
ELSIF Nav = 'DEDIT' THEN Hmi.View := 1; LoadDevice := TRUE;
ELSIF Nav = 'PEDIT' THEN Hmi.View := 2; LoadPoint := TRUE;
ELSIF Nav = 'DPREV' THEN Hmi.DevicePage := MAX(1,Hmi.DevicePage-1);
ELSIF Nav = 'DNEXT' THEN Hmi.DevicePage := MIN(MAX(1,(Draft.DeviceCount+7)/8),Hmi.DevicePage+1);
ELSIF Nav = 'PPREV' THEN Hmi.PointPage := MAX(1,Hmi.PointPage-1);
ELSIF Nav = 'PNEXT' THEN IF d <= Draft.DeviceCount THEN Hmi.PointPage := MIN(MAX(1,(Draft.Devices[d].PointCount+7)/8),Hmi.PointPage+1); END_IF;
ELSIF Nav = 'DDEL' THEN Hmi.DeleteKind := 1; Hmi.View := 4;
ELSIF Nav = 'PDEL' THEN Hmi.DeleteKind := 2; Hmi.View := 4;
ELSIF Nav = 'CANCEL' THEN Hmi.DeleteKind := 0; Hmi.View := 0;
ELSIF Nav = 'DNEW' THEN
    IF Draft.DeviceCount >= 50 THEN Hmi.Status := 'Capacity reached: 50 devices.';
    ELSE
        d := Draft.DeviceCount+1; Hmi.DeviceIndex := TO_STRING(d,'{0:d}'); Hmi.PointIndex := '1'; Hmi.View := 1;
        Hmi.DeviceId := CONCAT('meter-',TO_STRING(d,'{0:d}')); Hmi.DeviceName := CONCAT('Meter ',TO_STRING(d,'{0:d}'));
        Hmi.Host := '192.168.0.5'; Hmi.Port := '11502'; Hmi.UnitId := TO_STRING(d,'{0:d}'); Hmi.DeviceEnabled := 'true';
        Hmi.ConnectTimeoutMs := '3000'; Hmi.RequestTimeoutMs := '1500'; Hmi.RetryCount := '0';
        Hmi.Status := 'New device: save into draft, then add its points.';
    END_IF;
ELSIF Nav = 'PNEW' THEN
    IF d > Draft.DeviceCount THEN Hmi.Status := 'Save a device into the draft first.';
    ELSIF (Draft.Devices[d].PointCount >= 32) OR (Draft.PointCount >= 320) THEN Hmi.Status := 'Capacity reached: 32 points/device, 320 shared points.';
    ELSE
        p := Draft.Devices[d].PointCount+1; Hmi.PointIndex := TO_STRING(p,'{0:d}'); Hmi.View := 2;
        Hmi.PointId := CONCAT('point-',TO_STRING(p,'{0:d}')); Hmi.PointName := CONCAT('Point ',TO_STRING(p,'{0:d}')); Hmi.PointEnabled := 'true';
        Hmi.DataType := 'float32'; Hmi.Area := 'input_register'; Hmi.Address := TO_STRING((p-1)*2,'{0:d}'); Hmi.ByteOrder := 'ABCD';
        Hmi.PollIntervalMs := '5000'; Hmi.ReportIntervalMs := '5000'; Hmi.Scale := '1'; Hmi.Offset := '0'; Hmi.Unit := '';
        Hmi.ReportMode := 'cyclic'; Hmi.Deadband := '0'; Hmi.StaleAfterMs := '20000';
        Hmi.Status := 'New point: save into draft, then apply the complete draft.';
    END_IF;
ELSIF LEN(Nav) = 2 THEN
    IF (LEFT(Nav,1) = 'D') AND NG_Range(RIGHT(Nav,1),1,8,TRUE) THEN
        i := (Hmi.DevicePage-1)*8+TO_INT(RIGHT(Nav,1));
        IF i <= Draft.DeviceCount THEN d := i; p := 1; Hmi.DeviceIndex := TO_STRING(d,'{0:d}'); Hmi.PointIndex := '1'; Hmi.PointPage := 1; LoadDevice := TRUE; LoadPoint := TRUE; END_IF;
    ELSIF (LEFT(Nav,1) = 'P') AND NG_Range(RIGHT(Nav,1),1,8,TRUE) AND (d <= Draft.DeviceCount) THEN
        i := (Hmi.PointPage-1)*8+TO_INT(RIGHT(Nav,1));
        IF i <= Draft.Devices[d].PointCount THEN p := i; Hmi.PointIndex := TO_STRING(p,'{0:d}'); LoadPoint := TRUE; END_IF;
    END_IF;
END_IF;
IF LoadDevice AND (d <= Draft.DeviceCount) THEN
    device := Draft.Devices[d];
    Hmi.DeviceId := device.deviceId; Hmi.DeviceName := device.name; Hmi.DeviceEnabled := TO_STRING(device.enabled,''); Hmi.Host := device.host;
    Hmi.Port := TO_STRING(device.port,'{0:d}'); Hmi.UnitId := TO_STRING(device.unitId,'{0:d}'); Hmi.ConnectTimeoutMs := TO_STRING(device.connectTimeoutMs,'{0:d}');
    Hmi.RequestTimeoutMs := TO_STRING(device.requestTimeoutMs,'{0:d}'); Hmi.RetryCount := TO_STRING(device.retryCount,'{0:d}');
END_IF;
IF Hmi.LoadPoint THEN LoadPoint := TRUE; END_IF;
IF LoadPoint AND (d <= Draft.DeviceCount) THEN
    IF p <= Draft.Devices[d].PointCount THEN
        point := Draft.Points[Draft.Devices[d].PointStart+p-1];
        Hmi.PointId := point.pointId; Hmi.PointName := point.name; Hmi.PointEnabled := TO_STRING(point.enabled,''); Hmi.DataType := point.dataType;
        Hmi.PollIntervalMs := TO_STRING(point.pollIntervalMs,'{0:d}'); Hmi.ReportIntervalMs := TO_STRING(point.reportIntervalMs,'{0:d}');
        Hmi.Scale := TO_STRING(point.scale,'{0:F6}'); Hmi.Offset := TO_STRING(point.offset,'{0:F6}'); Hmi.Unit := point.unit; Hmi.ReportMode := point.reportMode;
        Hmi.Deadband := TO_STRING(point.deadband,'{0:F6}'); Hmi.StaleAfterMs := TO_STRING(point.staleAfterMs,'{0:d}'); Hmi.Area := point.area;
        Hmi.Address := TO_STRING(point.address,'{0:d}'); Hmi.ByteOrder := point.byteOrder;
        Hmi.DevicePollMs := Hmi.PollIntervalMs; Hmi.DeviceReportMs := Hmi.ReportIntervalMs;
    END_IF;
END_IF;
cmd := Hmi.SaveDevice OR Hmi.SavePoint OR Hmi.RemoveDevice OR Hmi.RemovePoint OR Hmi.Apply OR Hmi.SaveBroker OR Hmi.SwitchMode OR (Nav = 'PERIOD');
IF cmd AND Busy THEN Hmi.Status := 'Busy: configuration transaction in progress. Try again shortly.';
ELSIF cmd THEN
    IF NOT NG_Range(Hmi.DeviceIndex,1,50,TRUE) OR NOT NG_Range(Hmi.PointIndex,1,32,TRUE) THEN Hmi.Status := 'Device index 1..50; point index 1..32.';
    ELSE
        d := TO_INT(Hmi.DeviceIndex); p := TO_INT(Hmi.PointIndex); device := BlankDevice;
        IF d <= Draft.DeviceCount THEN device := Draft.Devices[d]; FOR i := 1 TO device.PointCount DO EditPoints[i] := Draft.Points[device.PointStart+i-1]; END_FOR; END_IF;
        IF Hmi.SaveDevice THEN
            IF (d > Draft.DeviceCount+1) OR NOT NG_ValidId(Hmi.DeviceId) OR (LEN(Hmi.DeviceName)=0) OR NOT NG_IPv4(Hmi.Host) OR
               NOT NG_Range(Hmi.Port,1,65535,TRUE) OR NOT NG_Range(Hmi.UnitId,0,255,TRUE) OR NOT NG_Range(Hmi.ConnectTimeoutMs,1,300000,TRUE) OR NOT NG_Range(Hmi.RequestTimeoutMs,1,300000,TRUE) OR NOT NG_Range(Hmi.RetryCount,0,10,TRUE) THEN Hmi.Status := 'Invalid device fields: check ID, name, IPv4, port and timeout values.';
            ELSE
                device.deviceId := Hmi.DeviceId; device.name := Hmi.DeviceName; device.enabled := (Hmi.DeviceEnabled='true') OR (Hmi.DeviceEnabled='TRUE');
                device.host := Hmi.Host; device.port := TO_UINT(Hmi.Port); device.unitId := TO_USINT(Hmi.UnitId); device.connectTimeoutMs := TO_UDINT(Hmi.ConnectTimeoutMs);
                device.requestTimeoutMs := TO_UDINT(Hmi.RequestTimeoutMs); device.retryCount := TO_USINT(Hmi.RetryCount);
                Change(DeviceIndex := d, Remove := FALSE, Replacement := device, Config := Draft, Points := EditPoints);
                IF Change.ErrorText = '' THEN Dirty := TRUE; Hmi.View := 0; Hmi.Status := 'Device saved to draft. Apply draft to persist.'; ELSE Hmi.Status := Change.ErrorText; END_IF;
            END_IF;
        END_IF;
        IF Hmi.SavePoint THEN
            IF (d > Draft.DeviceCount) OR (p > device.PointCount+1) OR NOT NG_ValidId(Hmi.PointId) OR (LEN(Hmi.PointName)=0) OR
               NOT NG_Range(Hmi.PollIntervalMs,1,86400000,TRUE) OR NOT NG_Range(Hmi.ReportIntervalMs,1,86400000,TRUE) OR NOT NG_Range(Hmi.StaleAfterMs,1,86400000,TRUE) OR NOT NG_Range(Hmi.Address,0,65535,TRUE) OR
               NOT NG_Range(Hmi.Scale,-1.0E20,1.0E20,FALSE) OR NOT NG_Range(Hmi.Offset,-1.0E20,1.0E20,FALSE) OR NOT NG_Range(Hmi.Deadband,0,1.0E20,FALSE) THEN Hmi.Status := 'Invalid point fields; save the device first and check numeric fields.';
            ELSE
                point := BlankPoint; point.pointId := Hmi.PointId; point.name := Hmi.PointName; point.enabled := (Hmi.PointEnabled='true') OR (Hmi.PointEnabled='TRUE');
                point.dataType := Hmi.DataType; point.pollIntervalMs := TO_UDINT(Hmi.PollIntervalMs); point.reportIntervalMs := TO_UDINT(Hmi.ReportIntervalMs);
                point.scale := TO_LREAL(Hmi.Scale); point.offset := TO_LREAL(Hmi.Offset); point.unit := Hmi.Unit; point.reportMode := Hmi.ReportMode;
                point.deadband := TO_LREAL(Hmi.Deadband); point.staleAfterMs := TO_UDINT(Hmi.StaleAfterMs); point.area := Hmi.Area; point.address := TO_UINT(Hmi.Address); point.byteOrder := Hmi.ByteOrder;
                EditPoints[p] := point; IF p > device.PointCount THEN device.PointCount := p; END_IF;
                Change(DeviceIndex := d, Remove := FALSE, Replacement := device, Config := Draft, Points := EditPoints);
                IF Change.ErrorText = '' THEN Dirty := TRUE; Hmi.View := 0; Hmi.Status := 'Point saved to draft. Apply draft to persist.'; ELSE Hmi.Status := Change.ErrorText; END_IF;
            END_IF;
        END_IF;
        IF Hmi.RemoveDevice AND (d <= Draft.DeviceCount) THEN
            Change(DeviceIndex := d, Remove := TRUE, Replacement := device, Config := Draft, Points := EditPoints);
            IF Change.ErrorText = '' THEN Dirty := TRUE; Hmi.DeviceIndex := '1'; Hmi.PointIndex := '1'; Hmi.View := 0; Hmi.DeleteKind := 0; Hmi.Status := 'Device and points removed from draft. Apply to persist.'; END_IF;
        END_IF;
        IF Hmi.RemovePoint AND (d <= Draft.DeviceCount) AND (p <= device.PointCount) THEN
            FOR i := p TO device.PointCount-1 DO EditPoints[i] := EditPoints[i+1]; END_FOR; device.PointCount := device.PointCount-1;
            Change(DeviceIndex := d, Remove := FALSE, Replacement := device, Config := Draft, Points := EditPoints);
            IF Change.ErrorText = '' THEN Dirty := TRUE; Hmi.PointIndex := '1'; Hmi.View := 0; Hmi.DeleteKind := 0; Hmi.Status := 'Point removed from draft. Apply to persist.'; END_IF;
        END_IF;
        IF (Nav = 'PERIOD') AND (d <= Draft.DeviceCount) THEN
            IF NOT NG_Range(Hmi.DevicePollMs,1,28800000,TRUE) OR NOT NG_Range(Hmi.DeviceReportMs,1,86400000,TRUE) THEN Hmi.Status := 'Invalid device polling/report period.';
            ELSE
                FOR i := 1 TO device.PointCount DO idx := device.PointStart+i-1; Draft.Points[idx].pollIntervalMs := TO_UDINT(Hmi.DevicePollMs); Draft.Points[idx].reportIntervalMs := TO_UDINT(Hmi.DeviceReportMs); Draft.Points[idx].staleAfterMs := MAX(Draft.Points[idx].staleAfterMs,Draft.Points[idx].pollIntervalMs*3); END_FOR;
                Dirty := TRUE; Hmi.Status := 'Device point periods updated in draft. Apply to persist.';
            END_IF;
        END_IF;
        IF Hmi.Apply THEN
            IF (BaseVersion <> Active.Version) OR (BaseRevision <> LocalRevision) THEN Hmi.Status := 'VERSION_CONFLICT: reload active configuration before applying.';
            ELSIF NOT NG_Range(Hmi.BatchIntervalMs,1,86400000,TRUE) OR NOT NG_Range(Hmi.MaxBatchPoints,1,64,TRUE) THEN Hmi.Status := 'Invalid gateway batch settings.';
            ELSE
                Draft.enabled := (Hmi.Enabled='true') OR (Hmi.Enabled='TRUE'); Draft.batchIntervalMs := TO_UDINT(Hmi.BatchIntervalMs); Draft.maxBatchPoints := TO_UINT(Hmi.MaxBatchPoints); Hmi.Status := NG_CheckConfig(Draft);
                IF Hmi.Status = '' THEN Draft.Version := Active.Version; Submit := TRUE; Awaiting := TRUE; Dirty := TRUE; Hmi.Status := 'Saving, hashing and reading back configuration...'; END_IF;
            END_IF;
        END_IF;
        IF Hmi.SwitchMode THEN
            NewManaged := ModeTargetManaged;
            IF NewManaged = Managed THEN Hmi.Status := 'The selected management mode is already active.';
            ELSE
                ClearConfig := NOT NewManaged AND Hmi.ClearOnMaintenance;
                SubmitMode := TRUE; ModeReviewOpen:=FALSE; Dirty := FALSE; Awaiting := FALSE; Reload := TRUE;
                Hmi.View := 13; Hmi.Status := 'Saving management mode; existing identity is retained.';
            END_IF;
        END_IF;
        IF Hmi.SaveBroker THEN
            ValidBroker := FALSE;
            IF LEN(Hmi.BrokerUri) >= 6 THEN ValidBroker := (LEFT(Hmi.BrokerUri,6)='tcp://') OR (LEFT(Hmi.BrokerUri,6)='ssl://'); END_IF;
            IF NOT ValidBroker OR NOT NG_ValidId(Hmi.BrokerGatewayId) OR ((Hmi.ManagementMode<>'HUB_MANAGED') AND (Hmi.ManagementMode<>'STANDALONE')) OR (LEN(Hmi.ClientId)=0) OR NOT NG_Range(Hmi.UtcOffsetMinutes,-840,840,TRUE) THEN Hmi.Status := 'Check broker URI, gateway ID, client ID and time zone.';
            ELSE
                NewManaged := Managed; NewBroker := Bootstrap; NewBroker.GatewayId:=Hmi.BrokerGatewayId; NewBroker.BrokerUri := Hmi.BrokerUri; NewBroker.ClientId := Hmi.ClientId; NewBroker.UserName := Hmi.UserName; NewBroker.UtcOffsetMinutes := TO_INT(Hmi.UtcOffsetMinutes);
                IF Hmi.Password <> '' THEN NewBroker.Password := Hmi.Password; END_IF;
                SubmitBroker := TRUE; Hmi.Password := ''; Hmi.View:=3; Hmi.Status := 'Saving broker settings...';
            END_IF;
        END_IF;
    END_IF;
END_IF;
Hmi.Load := FALSE; Hmi.LoadPoint := FALSE; Hmi.SaveDevice := FALSE; Hmi.SavePoint := FALSE; Hmi.RemoveDevice := FALSE; Hmi.RemovePoint := FALSE; Hmi.Apply := FALSE; Hmi.SaveBroker := FALSE; Hmi.SwitchMode := FALSE;
Hmi.UiStatus:=NG_UiText(Hmi.Status,Hmi.English);
Hmi.UiDeviceEnabled:=NG_UiText(Hmi.DeviceEnabled,Hmi.English); Hmi.UiPointEnabled:=NG_UiText(Hmi.PointEnabled,Hmi.English);
Hmi.UiArea:=NG_UiText(Hmi.Area,Hmi.English); Hmi.UiReportMode:=NG_UiText(Hmi.ReportMode,Hmi.English); Hmi.UiManagementMode:=NG_UiText(Hmi.ManagementMode,Hmi.English);
IF Dirty THEN Hmi.DraftState := 'UNSAVED DRAFT'; ELSE Hmi.DraftState := 'PERSISTED'; END_IF;
IF Dirty AND ((BaseVersion <> Active.Version) OR (BaseRevision <> LocalRevision)) AND NOT Awaiting THEN Hmi.DraftState := 'VERSION CONFLICT'; END_IF;
Hmi.UiDraftState:=NG_UiText(Hmi.DraftState,Hmi.English);
Hmi.UiConfigSource:=NG_UiText(Hmi.ConfigSource,Hmi.English);
Hmi.TotalPoints := TO_STRING(Active.PointCount,'{0:d}');
IF (NowMs < RefreshAt) AND (Nav = '') AND NOT cmd THEN RETURN; END_IF;
RefreshAt := NowMs+250;
Hmi.DevicePage := MAX(1,MIN(MAX(1,(Draft.DeviceCount+7)/8),Hmi.DevicePage));
Hmi.DevicePages := CONCAT(TO_STRING(Hmi.DevicePage,'{0:d}'),' / ',TO_STRING(MAX(1,(Draft.DeviceCount+7)/8),'{0:d}'));
FOR row := 1 TO 8 DO
    i := (Hmi.DevicePage-1)*8+row; rows[row] := "";
    IF i <= Draft.DeviceCount THEN
        device := Draft.Devices[i]; marker := ''; IF i = d THEN marker := '> '; END_IF;
        status := 'DRAFT'; FOR a := 1 TO Active.DeviceCount DO IF Active.Devices[a].deviceId = device.deviceId THEN status := States[a].StateText; EXIT; END_IF; END_FOR;
        IF Hmi.English THEN
            rows[row]:=NG_UiJoin(TO_WSTRING(marker,""),TO_WSTRING(NG_Clip(device.name),"")," | ",NG_UiText(status,TRUE),"\n",TO_WSTRING(CONCAT(device.host,':',TO_STRING(device.port,'{0:d}')),""),TO_WSTRING(device.unitId," / Unit {0:d}"),TO_WSTRING(device.PointCount," / {0:d} points"));
        ELSE
            rows[row]:=NG_UiJoin(TO_WSTRING(marker,""),TO_WSTRING(NG_Clip(device.name),"")," | ",NG_UiText(status,FALSE),"\n",TO_WSTRING(CONCAT(device.host,':',TO_STRING(device.port,'{0:d}')),""),TO_WSTRING(device.unitId," / 站号 {0:d}"),TO_WSTRING(device.PointCount," / {0:d} 个点位"));
        END_IF;
    END_IF;
END_FOR;
Hmi.DeviceRow1 := rows[1]; Hmi.DeviceRow2 := rows[2]; Hmi.DeviceRow3 := rows[3]; Hmi.DeviceRow4 := rows[4]; Hmi.DeviceRow5 := rows[5]; Hmi.DeviceRow6 := rows[6]; Hmi.DeviceRow7 := rows[7]; Hmi.DeviceRow8 := rows[8];
Hmi.SelectedDevice := NG_UiText('No device selected',Hmi.English); Hmi.SelectedPoint := NG_UiText('No point selected',Hmi.English);
IF d <= Draft.DeviceCount THEN Hmi.SelectedDevice := TO_WSTRING(Draft.Devices[d].name,""); END_IF;
pages := 1; IF d <= Draft.DeviceCount THEN pages := MAX(1,(Draft.Devices[d].PointCount+7)/8); END_IF;
Hmi.PointPage := MAX(1,MIN(pages,Hmi.PointPage)); Hmi.PointPages := CONCAT(TO_STRING(Hmi.PointPage,'{0:d}'),' / ',TO_STRING(pages,'{0:d}'));
FOR row := 1 TO 8 DO
    i := (Hmi.PointPage-1)*8+row; rows[row] := "";
    IF d <= Draft.DeviceCount THEN
        IF i <= Draft.Devices[d].PointCount THEN
            point := Draft.Points[Draft.Devices[d].PointStart+i-1]; marker := ''; IF i = p THEN marker := '> '; Hmi.SelectedPoint := NG_UiText(point.name,Hmi.English); END_IF;
            status := 'DRAFT'; value := '';
            FOR a := 1 TO Active.DeviceCount DO
                IF Active.Devices[a].deviceId = Draft.Devices[d].deviceId THEN
                    FOR b := 1 TO Active.Devices[a].PointCount DO idx := Active.Devices[a].PointStart+b-1; IF Active.Points[idx].pointId = point.pointId THEN status := Samples[idx].Quality; IF status = 'GOOD' THEN IF ABS(Samples[idx].Value)<1.0E9 THEN value := TO_STRING(Samples[idx].Value,'{0:F3}'); ELSE value := TO_STRING(Samples[idx].Value,'{0:E6}'); END_IF; END_IF; EXIT; END_IF; END_FOR; EXIT;
                END_IF;
            END_FOR;
            rows[row]:=NG_UiJoin(TO_WSTRING(marker,""),NG_UiText(point.name,Hmi.English),"  |  ",TO_WSTRING(CONCAT(value,' ',point.unit),""),"  |  ",NG_UiText(status,Hmi.English),"\n",NG_UiText(point.area,Hmi.English));
            IF Hmi.English THEN
                rows[row]:=NG_UiJoin(rows[row],TO_WSTRING(point.address," @{0:d}"),TO_WSTRING(point.pollIntervalMs," / Poll {0:d}"),TO_WSTRING(point.reportIntervalMs," / Send {0:d} ms"),"","","","");
            ELSE
                rows[row]:=NG_UiJoin(rows[row],TO_WSTRING(point.address," @{0:d}"),TO_WSTRING(point.pollIntervalMs," / 采集 {0:d}"),TO_WSTRING(point.reportIntervalMs," / 上报 {0:d} 毫秒"),"","","","");
            END_IF;
        END_IF;
    END_IF;
END_FOR;
Hmi.PointRow1 := rows[1]; Hmi.PointRow2 := rows[2]; Hmi.PointRow3 := rows[3]; Hmi.PointRow4 := rows[4]; Hmi.PointRow5 := rows[5]; Hmi.PointRow6 := rows[6]; Hmi.PointRow7 := rows[7]; Hmi.PointRow8 := rows[8];
END_FUNCTION_BLOCK
