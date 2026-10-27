"""Read-only counters from the diagnostic-only full gateway SHA overlay."""
import contextlib
import json
import os
from pathlib import Path
import sys
from phase1_plc_probe import Device, IDataAccessService

names = ['BootId', 'NowMs', 'BatchBuilder.Stage']
names += [f'{prefix}.Profile{field}'
          for prefix in ('BatchBuilder.Digest', 'Delivery.AckPath.Digest', 'Delivery.SendPath.Digest')
          for field in ('TotalUs', 'LoadUs', 'ScheduleUs', 'RoundsUs', 'Blocks', 'Calls')]
names += [f'P06WorkSum[{i}]' for i in range(1, 7)]
with open(os.devnull, 'w') as quiet, contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
    with Device('192.168.0.8') as device:
        rows = list(IDataAccessService(device).Read(['Arp.Plc.Eclr/MainInstance.' + n for n in names]))
        if len(rows) != len(names) or any(int(r.Error) for r in rows):
            raise RuntimeError('Diagnostic profile fields unavailable')
        result = {n: r.Value.GetValue() for n, r in zip(names, rows)}
Path(sys.argv[1]).write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result))
