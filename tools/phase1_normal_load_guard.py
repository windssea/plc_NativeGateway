"""Observe the frozen 50-device/250-point GOOD load; never write to the PLC.

A failed environment/nominal-load check requests the separate exact-boot
monitor and fault tool to stop through their shared file. It never certifies
P06 performance or replaces the independent raw-event audit.
"""
import argparse
import contextlib
import io
import json
from pathlib import Path
import time
import urllib.request

from phase1_performance_probe import snapshot, Device, IDataAccessService


def observe(args):
    rows = []
    started = time.monotonic()
    first = None
    baseline = None
    ready_deadline = started + args.wait_ready
    complete = False
    reason = 'waiting_for_good_source'

    def save():
        args.output.write_text(json.dumps(dict(
            expectedBoot=args.expect_boot, complete=complete, reason=reason,
            ready=baseline is not None, baseline=baseline, snapshots=rows,
            evidenceLevel='READ_ONLY_MOCK_QUALITY_AND_COUNTER_LOAD_GUARD',
            performanceAccepted=False), ensure_ascii=False, indent=2), encoding='utf-8')

    try:
        while time.monotonic() - started < args.seconds:
            if args.stop_file.exists():
                reason = 'stop_requested'
                break
            try:
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    with Device('192.168.0.8') as device:
                        service = IDataAccessService(device)
                        row = snapshot(service, device)
                        if row['BootId'] != args.expect_boot:
                            raise RuntimeError('Waiting for exact candidate boot')
                        qualities = []
                        for start in range(1, 251, 50):
                            names = [f'Arp.Plc.Eclr/MainInstance.Samples[{i}].Quality'
                                     for i in range(start, min(start + 50, 251))]
                            values = list(service.Read(names))
                            if any(int(v.Error) for v in values):
                                raise RuntimeError('Source qualities unavailable')
                            qualities.extend(v.Value.GetValue() for v in values)
                with urllib.request.urlopen('http://127.0.0.1:18080/api/v1/status', timeout=5) as response:
                    mock = json.load(response)
                if not row['Active.enabled'] and first is not None:
                    complete = True
                    reason = 'candidate_paused_by_monitor'
                    break
                if qualities != ['GOOD'] * 250:
                    raise RuntimeError('Not all 250 source points are GOOD')
                if (mock['config_revision'] != 5 or mock['config_error']
                        or len(mock['devices']) != 50
                        or mock['adapters']['modbus']['state'] != 'running'
                        or mock['adapters']['modbus']['last_error']):
                    raise RuntimeError('Mock configuration/service unhealthy')
                if not row['Active.enabled'] or row['CaptureBuffer.MissedPollCyclesTotal']:
                    raise RuntimeError('Acquisition disabled or nominal poll cycles missed')
                if first is None and row['HMI.Connection'] != 'CONNECTED':
                    raise RuntimeError('Waiting for initial MQTT connection')
            except Exception:
                if first is not None or time.monotonic() >= ready_deadline:
                    raise
                time.sleep(.5)
                continue
            current = dict(atUtc=row['atUtc'], elapsedSeconds=time.monotonic()-started,
                           NowMs=row['NowMs'], captured=row['CaptureBuffer.CapturedEventsTotal'],
                           stored=row['CaptureBuffer.StoredConfirmedEventsTotal'],
                           missedPoll=row['CaptureBuffer.MissedPollCyclesTotal'],
                           all250Good=True, mockRevision=mock['config_revision'],
                           connection=row['HMI.Connection'])
            if first is None:
                first = current
                reason = 'observing_normal_source'
            rows.append(current)
            elapsed = (current['NowMs'] - first['NowMs']) / 1000
            if elapsed >= 60 and baseline is None:
                rate = (current['captured']-first['captured']) / elapsed
                if not 45 <= rate <= 55:
                    raise RuntimeError(f'Frozen input load missing: {rate:.3f} events/s')
                baseline = dict(bootId=args.expect_boot, inputEventsPerSecond=rate,
                                durationSeconds=elapsed, all250Good=True, missedPoll=0)
                args.ready_file.write_text(json.dumps(baseline, indent=2), encoding='utf-8')
                print(json.dumps(baseline), flush=True)
            if baseline is not None:
                prior = next((r for r in reversed(rows[:-1]) if current['NowMs']-r['NowMs'] >= 60000), None)
                if prior is not None:
                    rate = (current['captured']-prior['captured']) / ((current['NowMs']-prior['NowMs'])/1000)
                    if not 45 <= rate <= 55:
                        raise RuntimeError(f'Normal load lost: {rate:.3f} events/s')
                    current['windowInputEventsPerSecond'] = rate
            save()
            time.sleep(10)
        else:
            reason = 'guard_duration_reached'
        save()
    except BaseException as exc:
        reason = 'guard_failed: ' + str(exc)
        args.stop_file.write_text(reason, encoding='utf-8')
        save()
        raise
    print(json.dumps(dict(output=str(args.output), reason=reason, ready=baseline is not None)))


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output', type=Path)
    ap.add_argument('--expect-boot', required=True)
    ap.add_argument('--ready-file', type=Path, required=True)
    ap.add_argument('--stop-file', type=Path, required=True)
    ap.add_argument('--wait-ready', type=int, default=180, choices=range(1,301))
    ap.add_argument('--seconds', type=int, default=1400, choices=range(1,3601))
    observe(ap.parse_args())
