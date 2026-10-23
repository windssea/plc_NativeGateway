"""Freeze the user-ended v104 test without claiming an eight-hour pass."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import shutil
import time
import zipfile

root = Path(__file__).resolve().parents[1]
out = root/'tests/soak'
summary = json.loads((out/'summary.json').read_text(encoding='utf-8-sig'))
schedule = json.loads((out/'schedule.json').read_text(encoding='utf-8-sig'))
now = time.time()
end = summary['updatedAt']
summary.update(mode='user_stopped', stoppedAt=now, observedEndAt=end,
               plannedEndAt=schedule['endAt'], actualObservedSeconds=end-summary['startAt'],
               completionReason='User explicitly ended eight-hour test early to develop and integrate Hub-compatible version.',
               eightHourTestPassed=False)
folder = out/'segments'/('20261023-093205-v104-user-ended-'+dt.datetime.fromtimestamp(now).strftime('%H%M%S'))
folder.mkdir(parents=True, exist_ok=False)
for path in out.iterdir():
    if path.is_file():
        shutil.copy2(path, folder/path.name)
for target in (out/'final-summary.json', out/'summary.json', folder/'final-summary.json'):
    target.write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
with zipfile.ZipFile(folder/'native-0.2.0-source-and-project.zip','w',zipfile.ZIP_DEFLATED) as archive:
    archive.write(root/'NativeGateway.pcwex','NativeGateway.pcwex')
    for directory in ['src','hmi']:
        for path in (root/directory).rglob('*'):
            if path.is_file(): archive.write(path,path.relative_to(root).as_posix())
a, c = summary['aggregate'], summary['counters']
text = f'''NativeGateway v104 short-duration stability evidence
Result: USER STOPPED EARLY. NOT an eight-hour pass.
Start: {dt.datetime.fromtimestamp(summary['startAt']).isoformat(timespec='seconds')} Asia/Shanghai
Last observed: {dt.datetime.fromtimestamp(end).isoformat(timespec='seconds')} Asia/Shanghai
Actual observed duration: {summary['actualObservedSeconds']:.1f} seconds
Originally planned end: {schedule['endLocal']}
Reason: user requested immediate Hub-compatible development and maintenance/download.
Devices/points: 50 / 250; latest GOOD: {summary['heartbeat']['points']['good']}
Unique batches: {c.get('uniqueBatches',0)}; values: {c.get('values',0)}; GOOD: {c.get('quality_GOOD',0)}
Schema errors: {c.get('schemaErrors',0)}; incorrect values: {c.get('incorrectValues',0)}
Boot changes: {c.get('bootChanges',0)}; session changes: {c.get('sessionChanges',0)}
CPU range: {a.get('cpuPercentMin')}..{a.get('cpuPercentMax')} percent
Actual memory: {a.get('actualMemoryPercentMin')}..{a.get('actualMemoryPercentMax')} percent
IEC program: {a.get('iecProgramPercentMin')}..{a.get('iecProgramPercentMax')} percent
IEC data: {a.get('iecDataPercentMin')}..{a.get('iecDataPercentMax')} percent
Queue peak: {a.get('maxQueueBatches')}; drops: {a.get('maxDroppedBatches')}
Max point update gap: {a.get('maxPointGapSeconds'):.3f} seconds
Known HMI availability incident: 09:33:19 to recovered by 09:34:50; 443 refusal/timeout.
No PLC reboot or data interruption was observed during that incident. Cause unresolved.
PLC collection/MQTT observations above cover only the actual short window.
No conclusion about eight-hour PLC stability or complete HMI availability is justified.
Original schedule/control and all wire/resource/web evidence retained in:
{folder}
HMI: https://192.168.0.8/ehmi/hmiapp.html
'''
for target in (out/'STABILITY-RESULTS.txt', folder/'STABILITY-RESULTS.txt'):
    target.write_text(text, encoding='utf-8')
termination = dict(reason='user_requested_maintenance', stoppedAt=now, archive=str(folder),
                   observedEndAt=end, actualObservedSeconds=summary['actualObservedSeconds'],
                   originalSchedulePreserved=True, automationDeleted=True, observerAutoAckStopped=True)
(out/'termination.json').write_text(json.dumps(termination,indent=2),encoding='utf-8')
hashes = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.iterdir() if p.is_file()}
(folder/'sha256-manifest.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
print(json.dumps(termination))
