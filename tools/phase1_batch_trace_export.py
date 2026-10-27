"""Read and fsync the diagnostic-only 16-row lifecycle ring; never writes to PLC."""
import argparse
import contextlib
import io
import json
import time
from pathlib import Path
from build_phase1_batch_trace import TYPES
from phase1_audit_export import Journal, EvidenceError
from phase1_plc_probe import Device, IDataAccessService


class Exporter:
    def __init__(self, read, journal, boot):
        self.read, self.journal, self.boot, self.cursor = read, journal, boot, 0

    def poll(self):
        head = self.read(['BootId', 'P06TraceWriteSeq'])
        if head['BootId'] != self.boot: raise EvidenceError('Trace boot changed')
        end = head['P06TraceWriteSeq']
        if end < self.cursor or end-self.cursor > 16:
            raise EvidenceError('Batch trace ring overwritten or reset')
        while self.cursor < end:
            ordinal = self.cursor+1
            slot = 17+(ordinal-1) % 16
            names = [f'P06B{k}[{slot}]' for k in TYPES]
            row = self.read(names)
            check = self.read(['BootId', f'P06BOrdinal[{slot}]'])
            if check['BootId'] != self.boot: raise EvidenceError('Trace boot changed during row')
            if row[f'P06BOrdinal[{slot}]'] != ordinal or check[f'P06BOrdinal[{slot}]'] != ordinal:
                raise EvidenceError('Batch trace row raced or overwritten; no mixed row exported')
            values = {k: row[f'P06B{k}[{slot}]'] for k in TYPES}
            self.journal.append([dict(kind='batchLifecycle', bootId=self.boot, event=values)])
            self.cursor = ordinal
        return end


def run(args):
    journal = Journal(args.output)
    exporter = None
    try:
        deadline = time.monotonic()+args.wait_ready
        while True:
            try:
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    with Device('192.168.0.8') as device:
                        service = IDataAccessService(device)
                        def read(names):
                            values = list(service.Read(['Arp.Plc.Eclr/MainInstance.'+n for n in names]))
                            if len(values)!=len(names) or any(int(v.Error) for v in values):
                                raise EvidenceError('Batch trace fields unavailable')
                            return {n:v.Value.GetValue() for n,v in zip(names,values)}
                        head = read(['BootId', 'P06TraceWriteSeq'])
                        if head['BootId'] != args.expect_boot: raise EvidenceError('Waiting exact trace boot')
                        exporter = Exporter(read, journal, args.expect_boot)
                        started = time.monotonic()
                        while time.monotonic()-started < args.seconds:
                            exporter.poll()
                            if args.stop_file.exists(): break
                            time.sleep(.2)
                break
            except Exception:
                if exporter is not None or time.monotonic()>=deadline: raise
                time.sleep(.25)
        journal.append([dict(kind='end',bootId=args.expect_boot,lastOrdinal=exporter.cursor,exportCompleted=True,
                             evidenceLevel='INSTRUMENTED_DIAGNOSTIC_NOT_P06_ACCEPTANCE')])
    except Exception as exc:
        journal.append([dict(kind='failure',error=str(exc),exportCompleted=False)])
        if args.run_stop_file: args.run_stop_file.write_text('batch trace failure: '+str(exc),encoding='utf-8')
        raise
    finally: journal.close()
    print(json.dumps(dict(output=str(args.output),lastOrdinal=exporter.cursor)))


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('output',type=Path)
    p.add_argument('--expect-boot',required=True);p.add_argument('--seconds',type=int,default=1200,choices=range(1,3601))
    p.add_argument('--wait-ready',type=int,default=120,choices=range(1,301));p.add_argument('--stop-file',type=Path,required=True)
    p.add_argument('--run-stop-file',type=Path);run(p.parse_args())
