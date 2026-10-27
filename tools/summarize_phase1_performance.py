"""Read-only summary of archived/in-progress P06 observations.

Local DATA gating is explicitly distinguished from a physical network fault.
This report never converts a short/gated trial into full P06 acceptance.
"""
import argparse
import json
from pathlib import Path


def summarize(run, fault=None):
    result = json.loads(run.read_text(encoding='utf-8'))
    rows = result['snapshots']
    last = rows[-1]
    released = None
    duration = None
    if fault:
        faults = [json.loads(s) for s in fault.read_text(encoding='utf-8').splitlines() if s.strip()]
        releases = [r for r in faults if r['kind'] == 'released']
        if releases:
            released = releases[-1]['snapshot']
            duration = releases[-1]['elapsedSeconds'] - next(r['elapsedSeconds'] for r in faults if r['kind'] == 'fault')
    active = [r for r in rows if r['Active.enabled'] and not r['P06HoldSend'] and not r.get('P06Disconnect',False) and r['runStage'] == 'observe']
    if released:
        active = [released] + [r for r in active if r['NowMs'] > released['NowMs']]
    # A fast diagnostic can catch up, after which observed release is arrival-limited.
    # Also expose an explicitly bounded backlog window; never substitute it silently
    # for the complete active recovery rate or frozen acceptance criteria.
    saturated_seconds = 0
    saturated_events = 0
    saturated_intervals = 0
    if released:
        for left, right in zip(active, active[1:]):
            if all(r.get('HMI.Connection') == 'CONNECTED' and
                   r['CaptureBuffer.Watermark'] >= released['CaptureBuffer.CapturedEventsTotal'] and
                   r['CaptureBuffer.OwnedCount'] >= 512 for r in (left, right)):
                elapsed = (right['NowMs']-left['NowMs'])/1000
                if elapsed > 0:
                    saturated_seconds += elapsed
                    saturated_events += right['CaptureBuffer.StoredConfirmedEventsTotal']-left['CaptureBuffer.StoredConfirmedEventsTotal']
                    saturated_intervals += 1
    rate = None
    if len(active) > 1 and active[-1]['NowMs'] > active[0]['NowMs']:
        rate = (active[-1]['CaptureBuffer.StoredConfirmedEventsTotal'] - active[0]['CaptureBuffer.StoredConfirmedEventsTotal']) / ((active[-1]['NowMs'] - active[0]['NowMs']) / 1000)
    cleared = None
    previous = released
    if released:
        for row in rows:
            if row['NowMs'] < released['NowMs']:
                continue
            # Releasing the disconnect switch precedes actual MQTT reconnection.
            # An empty historical queue before the new watermark is established
            # is not evidence that the disconnected cohort has been drained.
            fence = (row.get('HMI.Connection') == 'CONNECTED' and
                     (not released['CaptureBuffer.OwnedCount'] or
                      row['CaptureBuffer.Watermark'] >= released['CaptureBuffer.CapturedEventsTotal']))
            if not fence:
                previous = row
                continue
            history = row['CaptureBuffer.QueueHead[1]'] or any(row[f'CaptureBuffer.BatchOwners[{i}].State'] > 0 and row[f'CaptureBuffer.BatchOwners[{i}].Category'] == 1 for i in range(1, 17))
            if not history:
                cleared = dict(lowerSeconds=(previous['NowMs'] - released['NowMs']) / 1000,
                               upperSeconds=(row['NowMs'] - released['NowMs']) / 1000,
                               acquisitionEnabled=row['Active.enabled'])
                break
            previous = row
    return dict(bootId=last['BootId'], complete=result['complete'], last={k:last[k] for k in
                ('NowMs', 'runStage', 'Active.enabled', 'CaptureBuffer.CapturedEventsTotal',
                 'CaptureBuffer.StoredConfirmedEventsTotal', 'CaptureBuffer.OwnedCount',
                 'CaptureBuffer.WorkMaxUs', 'P06MaxUs', 'P06OverPeriod', 'CaptureBuffer.MissedPollCyclesTotal')},
                faultScope=('REAL_CANDIDATE_MQTT_CLIENT_DISCONNECT_NOT_PHYSICAL_LAN' if released and 'P06Disconnect' in released and any(r['kind']=='connectionClosed' for r in faults) else 'LOCAL_DATA_GATE_NOT_PHYSICAL_NETWORK') if fault else None,
                gatedSeconds=duration, activeRecoveryConfirmedLocalReleaseEventsPerSecond=rate,
                activeRecoveryWindowSeconds=(active[-1]['NowMs']-active[0]['NowMs'])/1000 if len(active)>1 else None,
                saturatedRecoveryMinimumOwned=512, saturatedRecoveryWindowSeconds=saturated_seconds,
                saturatedRecoveryIntervals=saturated_intervals,
                saturatedRecoveryConfirmedLocalReleaseEventsPerSecond=saturated_events/saturated_seconds if saturated_seconds else None,
                historyClearBracket=cleared, fullP06Acceptance=False)


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('run', type=Path)
    ap.add_argument('--fault', type=Path)
    ap.add_argument('--output', type=Path)
    args = ap.parse_args()
    report = summarize(args.run, args.fault)
    if args.output:
        args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))
