"""Read a bounded set of gateway diagnostics from the authorized AXC F 1252.

No file operations, variable writes, PLC control, download or discovery.
Uses the existing local PyPlcnextRsc SDK; password comes from the process
environment, never an argument or report. Rejects another device identity
before supplying credentials. Suppress the SDK's raw authentication wire log.
"""
import argparse
import contextlib
from datetime import datetime, timezone, timedelta
import enum
import io
import json
import os
from pathlib import Path
import sys
import warnings

ROOT = Path(__file__).resolve().parents[1]
ADDRESS = '192.168.0.10'
SERIAL = '2038744160'
GATEWAY_ID = 'NG-HUB-1252-01'


def read_runtime(output, samples=False):
    original_setitem = enum._EnumDict.__setitem__

    def enum_setitem(self, key, value):
        if key == '_create_pseudo_member_':
            dict.__setitem__(self, key, value)
        else:
            original_setitem(self, key, value)

    enum._EnumDict.__setitem__ = enum_setitem
    if not hasattr(enum, '_decompose'):
        def decompose(cls, value):
            members = [member for member in cls if member.value and member.value & value == member.value]
            remaining = value
            for member in members:
                remaining &= ~member.value
            return members, remaining
        enum._decompose = decompose
    sys.path.insert(0, str(ROOT.parent / 'JPlcnextRsc'))
    from PyPlcnextRsc import Device
    from PyPlcnextRsc.common.device import ExtraConfigure
    from PyPlcnextRsc.Arp.Plc.Gds.Services import IDataAccessService

    password = os.environ.get('PLCNEXT_1252_PASSWORD')
    if not password:
        raise ValueError('Set PLCNEXT_1252_PASSWORD for this read-only verification')

    def authentication(detail):
        if detail.get('General.SerialNumber') != SERIAL or detail.get('Address', (None,))[0] != ADDRESS:
            raise ValueError('Unexpected controller identity; credentials withheld')
        return os.environ.get('PLCNEXT_1252_USERNAME', 'admin'), password

    local_names = [
        'StartupStage', 'StartupReady', 'BootId', 'TimeChecks.Done',
        'TimeChecks.Passed', 'TimeChecks.FailedChecks', 'TimeChecks.WirePassed', 'TimeChecks.WireFailed',
        'Store.Ready', 'Store.Busy', 'Store.Error', 'Store.ErrorText', 'Store.Name',
        'Store.Active.Generation', 'Store.Active.BootCounter', 'Store.Active.Bootstrap.GatewayId',
        'Mqtt.Connected', 'Mqtt.SessionCount', 'NowMs', 'Active.Version', 'Active.DeviceCount',
        'Active.PointCount', 'NativeClock.TimeValid', 'QueueCount',
    ]
    paths = ['Arp.Plc.Eclr/MainInstance.' + name for name in local_names]
    if samples:
        paths += ['Arp.Plc.Eclr/MainInstance.' + name for name in [
            'UnixMs', 'Dropped', 'NativeClock.SyncAgeMs', 'NativeClock.UncertaintyMs',
            'NativeClock.CaptureAllowed', 'NativeClock.SendAllowed',
            'Active.Devices[1].host', 'Active.Devices[1].port', 'Active.Devices[1].unitId',
        ]]
        paths += ['Arp.Plc.Eclr/MainInstance.Samples[' + str(index) + '].' + field
                  for index in range(1, 13) for field in ['Value', 'Quality', 'Timestamp']]
    paths += ['Arp.Plc.Eclr/HMI.' + name for name in ['GatewayId', 'Status', 'Persistence', 'Connection']]
    config = ExtraConfigure()
    config.timeout = 4
    warnings.simplefilter('ignore')
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        with Device(ADDRESS, config=config, secureInfoSupplier=authentication) as device:
            rows = list(IDataAccessService(device).Read(paths))
    values = {name: {'error': int(row.Error), 'value': row.Value.GetValue() if int(row.Error) == 0 else None}
              for name, row in zip(paths, rows)}
    if values['Arp.Plc.Eclr/HMI.GatewayId'] != {'error': 0, 'value': GATEWAY_ID}:
        raise ValueError('Unexpected running gateway identity')
    report = dict(address=ADDRESS, serial=SERIAL, gatewayId=GATEWAY_ID,
                  timeBeijing=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                  readOnly=True, plc19216808Accessed=False, values=values)
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--samples', action='store_true', help='Read the first 12 real-meter samples and time diagnostics')
    args = parser.parse_args()
    read_runtime(args.output, args.samples)
