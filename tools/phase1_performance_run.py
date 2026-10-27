"""Bound a real P06 observation; pause and drain before allowing replacement.

No DB/service/persistent-config changes. Requires an exact boot identity. A
failed performance gate is recorded, never reset or counted as a passing run.
The separate durable audit and passive wire observers must already be running.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import time
from phase1_performance_probe import snapshot
from phase1_plc_probe import Device, IDataAccessService, WriteItem, RscVariant


def run(args):
    rows = []
    diagnostic_limit = getattr(args, 'diagnostic_task_limit_us', None)
    if args.wait_ready:
        deadline = time.monotonic() + args.wait_ready
        with open(os.devnull, 'w') as quiet:
            while True:
                try:
                    with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
                        with Device('192.168.0.8') as candidate:
                            ready = snapshot(IDataAccessService(candidate), candidate)
                    if ready['BootId'] != args.expect_boot:
                        raise RuntimeError('Waiting read-only for exact candidate boot')
                    break
                except Exception:
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(.5)
    started = time.monotonic()
    stage = 'observe'
    reason = 'duration'
    drain_started = None
    with open(os.devnull, 'w') as quiet:
        with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
            device = Device('192.168.0.8')
            device.__enter__()
            service = IDataAccessService(device)
        try:
            while True:
                with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
                    row = snapshot(service, device)
                if row['BootId'] != args.expect_boot:
                    raise RuntimeError('Boot changed; refusing controls')
                row['runStage'] = stage
                row['runElapsedSeconds'] = time.monotonic() - started
                row['diagnosticOnly'] = diagnostic_limit is not None
                row['diagnosticTaskLimitUs'] = diagnostic_limit
                rows.append(row)
                args.output.write_text(json.dumps(dict(expectedBoot=args.expect_boot,
                    complete=False, reason=reason, snapshots=rows), ensure_ascii=False, indent=2), encoding='utf-8')
                print(json.dumps({k: row[k] for k in ('runStage', 'NowMs', 'P06MaxUs',
                    'P06OverPeriod', 'CaptureBuffer.WorkLastUs', 'CaptureBuffer.WorkMaxUs',
                    'CaptureBuffer.CapturedEventsTotal', 'CaptureBuffer.StoredConfirmedEventsTotal',
                    'CaptureBuffer.OwnedCount')}), flush=True)
                if stage == 'observe':
                    if args.stop_file and args.stop_file.exists():
                        reason = 'stop_requested'
                    elif row['CaptureBuffer.CaptureStopped'] or (
                        (diagnostic_limit is None and row['P06OverPeriod']) or
                        (diagnostic_limit is not None and (
                            row['P06MaxUs'] > diagnostic_limit or row['P06OverPeriod'] > 3))):
                        reason = 'task_overrun_or_capture_stop'
                    elif row['CaptureBuffer.OwnedCount'] > args.max_owned:
                        reason = 'bounded_backlog'
                    elif time.monotonic() - started < args.seconds:
                        time.sleep(args.interval)
                        continue
                    with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
                        error = service.WriteSingle(WriteItem('Arp.Plc.Eclr/MainInstance.Active.enabled', RscVariant.of(False)))
                    if int(error):
                        raise RuntimeError('Pause refused')
                    stage = 'drain'
                    drain_started = time.monotonic()
                elif (not row['Active.enabled'] and not row['CaptureBuffer.OwnedCount']
                      and not row['CaptureBuffer.IngressCount']):
                    args.output.write_text(json.dumps(dict(expectedBoot=args.expect_boot,
                        complete=True, reason=reason, snapshots=rows), ensure_ascii=False, indent=2), encoding='utf-8')
                    args.final.write_text(json.dumps(row, ensure_ascii=False, indent=2), encoding='utf-8')
                    return
                elif time.monotonic() - drain_started > args.drain_seconds:
                    raise RuntimeError('Paused but drain incomplete; do not replace runtime')
                time.sleep(args.interval)
        finally:
            # On failure, pause only if the exact candidate still owns the RAM.
            with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
                identity = service.ReadSingle('Arp.Plc.Eclr/MainInstance.BootId')
                if not int(identity.Error) and identity.Value.GetValue() == args.expect_boot:
                    service.WriteSingle(WriteItem('Arp.Plc.Eclr/MainInstance.Active.enabled', RscVariant.of(False)))
                device.__exit__(None, None, None)


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output', type=Path)
    ap.add_argument('final', type=Path)
    ap.add_argument('--expect-boot', required=True)
    ap.add_argument('--seconds', type=int, default=120)
    ap.add_argument('--interval', type=int, default=10)
    ap.add_argument('--drain-seconds', type=int, default=900)
    ap.add_argument('--max-owned', type=int, default=4000)
    ap.add_argument('--wait-ready', type=int, default=0, choices=range(301))
    ap.add_argument('--stop-file', type=Path,
                    help='Request bounded pause/drain; does not skip the exact-boot checks')
    ap.add_argument('--diagnostic-task-limit-us', type=int, choices=range(20000,40001),
                    help='Diagnostic only, never acceptance: retain <=3 period overruns but pause above this absolute limit')
    args = ap.parse_args()
    if not 10 <= args.seconds <= 1800 or not 5 <= args.interval <= 30:
        ap.error('Bounded duration/interval required')
    run(args)
