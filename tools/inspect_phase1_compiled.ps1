param(
    [Parameter(Mandatory=$true)][string]$BinaryDirectory,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
# Inspect generated CIL metadata only. Do not execute the gateway or use CIL
# host execution as a replacement for PLC assertions (eCLR IL is not portable).
$binaryRoot=(Resolve-Path -LiteralPath $BinaryDirectory).Path
$commonName='RES_23CA7F267545404C9FED5DC977A6399F.Common.dll'
$common=[Reflection.Assembly]::LoadFrom((Join-Path $binaryRoot $commonName))
$instanceFlags=[Reflection.BindingFlags]'Public,NonPublic,Instance'
function Measure-Value([Type]$valueType) {
    $method=[Reflection.Emit.DynamicMethod]::new('ValueSize',[int],@())
    $il=$method.GetILGenerator()
    $il.Emit([Reflection.Emit.OpCodes]::Sizeof,$valueType)
    $il.Emit([Reflection.Emit.OpCodes]::Ret)
    return [int]$method.Invoke($null,@())
}
function Measure-StateBound([Type]$stateType,[int]$depth=0) {
    if($depth -gt 12) { throw 'Unexpected recursive state type' }
    if($stateType.IsPointer) { return 8 }
    if($stateType.IsValueType) { return (Measure-Value $stateType) }
    if($stateType.IsArray -or $stateType -eq [string]) { throw "Unbounded state type: $stateType" }
    # Conservative 64-bit references, 16-byte object header and 8-byte field
    # padding. External VAR_IN_OUT pointers are counted but never traversed.
    $bound=16
    foreach($field in $stateType.GetFields($instanceFlags)) {
        $bound=8*[math]::Ceiling($bound/8.0)
        $bound+=Measure-StateBound $field.FieldType ($depth+1)
        if(-not $field.FieldType.IsValueType -and -not $field.FieldType.IsPointer) { $bound+=8 }
    }
    return [int](8*[math]::Ceiling($bound/8.0))
}
$sizes=[ordered]@{}
foreach($name in @('NG_CaptureEvent','NG_Buffer','NG_CaptureConfig','NG_Config','NG_SourceCursor','NG_CaptureGap','NG_Packet')) {
    $sizes[$name]=Measure-Value ($common.GetType($name,$true))
}
foreach($name in @('NG_AuditEvent','NG_Association','NG_DiagnosticSnapshot')) {
    $auditType=$common.GetType($name,$false)
    if($null -ne $auditType) { $sizes[$name]=Measure-Value $auditType }
}
$mqtt=[Reflection.Assembly]::LoadFrom((Join-Path $binaryRoot 'NG_Mqtt.dll')).GetType('NG_Mqtt',$true)
$mqttBound=Measure-StateBound $mqtt
$helperBound=0
# SourceState is now shared by Main, while Result/PollSlot remain per device.
foreach($name in @('NG_SourceResult','NG_PollSlot')) {
    $type=[Reflection.Assembly]::LoadFrom((Join-Path $binaryRoot ($name+'.dll'))).GetType($name,$true)
    $helperBound+=Measure-StateBound $type
}
$helperBound=50*($helperBound+64)
$type=[Reflection.Assembly]::LoadFrom((Join-Path $binaryRoot 'NG_SourceState.dll')).GetType('NG_SourceState',$true)
$helperBound+=Measure-StateBound $type
$mainType=[Reflection.Assembly]::LoadFrom((Join-Path $binaryRoot 'Main.dll')).GetType('Main',$true)
$activation=$mainType.GetFields([Reflection.BindingFlags]'Public,NonPublic,Instance') | Where-Object Name -eq 'CaptureActivation'
if($activation) { $helperBound+=Measure-StateBound $activation.FieldType }
foreach($name in @('NG_SameConfig','NG_ConfigSlot')) {
    $type=[Reflection.Assembly]::LoadFrom((Join-Path $binaryRoot ($name+'.dll'))).GetType($name,$true)
    $helperBound+=Measure-StateBound $type
}
$pipelineBounds=[ordered]@{}
$deliveryType=if(Test-Path -LiteralPath (Join-Path $binaryRoot 'NG_DeliveryParallel.dll')) { 'NG_DeliveryParallel' } else { 'NG_Delivery' }
foreach($name in @('NG_ReportPolicy','NG_BufferMaintenance','NG_BatchBuilder',$deliveryType,'NG_CheckCounters','NG_AuditDrain','NG_Diagnostics')) {
    $helperFile=Join-Path $binaryRoot ($name+'.dll')
    if(Test-Path -LiteralPath $helperFile) {
        $type=[Reflection.Assembly]::LoadFrom($helperFile).GetType($name,$true)
        $pipelineBounds[$name]=Measure-StateBound $type
        $helperBound+=$pipelineBounds[$name]
    }
}
$result=[ordered]@{
    evidenceLevel='COMPILED_CIL_METADATA_BOUNDS'; binaryDirectory=$binaryRoot
    valueSizes=$sizes; mqttStateUpperBound=$mqttBound; mqttStateReserved=16384
    captureHelperUpperBound=$helperBound; helperAndScratchReserved=65536
    pipelineStateBounds=$pipelineBounds
    sdkPayloadReserve=135680; recordCapacity=28800; ingressCapacity=512
    note='IEC/value layout and FB metadata bounds; opaque native SDK heap and task timing remain P06 measurements.'
    hashes=@(Get-ChildItem -LiteralPath $binaryRoot -Filter '*.dll' | Where-Object { $_.BaseName -match '^(Main|NG_|RES_)' } | ForEach-Object {
        [ordered]@{name=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
}
$timeBounds=[ordered]@{}
foreach($name in @('NG_PlatformTime','NG_TimeResponse','NG_PlatformTimeChecks')) {
    $timeFile=Join-Path $binaryRoot ($name+'.dll')
    if(Test-Path -LiteralPath $timeFile) {
        $type=[Reflection.Assembly]::LoadFrom($timeFile).GetType($name,$true)
        $timeBounds[$name]=Measure-StateBound $type
    }
}
$timeTotal=0
foreach($value in $timeBounds.Values) { $timeTotal+=$value }
$result.timeStateBounds=$timeBounds
$result.timeStateUpperBound=$timeTotal+1024
$result.timeStateReserved=16384
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
if($mqttBound -gt 16384 -or $helperBound -gt 65536) { throw 'Compiled FB state exceeds reserved budget' }
if($timeBounds.Count -gt 0 -and $result.timeStateUpperBound -gt 16384) { throw 'Compiled time state exceeds reserved budget' }
[pscustomobject]$result | Select-Object valueSizes,mqttStateUpperBound,captureHelperUpperBound | ConvertTo-Json -Compress
