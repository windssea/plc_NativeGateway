"""Explicit, resumable lab acceptance for the native maintenance workflow.

Uses the real HMI command path and real Hub API. Never fabricates data ACKs.
Run one phase at a time on the isolated NG-HUB-2152-01 mock fixture.
The reboot phase restarts the controller OS; the edit phase changes one point's
period, and handback restores the saved Hub table. No point deletion is needed.
"""
from pathlib import Path
import argparse
import contextlib
import hashlib
import io
import json
import math
import socket
import time
import uuid
import threading

with contextlib.redirect_stdout(io.StringIO()):
    import probe_hmi_rsc as sdk
from PyPlcnextRsc.common.serviceDefinition.all_needed import RscType
from PyPlcnextRsc.common.exceptions import CommonRemotingException
import PyPlcnextRsc.common.transport.rsc_sock as rsc_sock
import PyPlcnextRsc.common.transport.rsc_client as rsc_client
rsc_sock.DEBUG = False
rsc_client.DEBUG = False
from hub_api import HubApi

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tests/mode-maintenance-20261023'
OUT.mkdir(exist_ok=True)
PLC = '192.168.0.8'
GW = 'NG-HUB-2152-01'
PFX = 'Arp.Plc.Eclr/'
STATE = OUT / 'state.json'
CORE = ['HMI.GatewayId', 'HMI.ManagementMode', 'HMI.Managed',
        'HMI.LocalChanges', 'HMI.LocalRevision', 'HMI.UiMaintenance',
        'HMI.UiStatus', 'HMI.UiPersistence', 'HMI.Connection',
        'MainInstance.BootId', 'MainInstance.Store.Busy',
        'MainInstance.Store.Error', 'MainInstance.Durable.HasHubBaseline',
        'MainInstance.Durable.Generation', 'MainInstance.Durable.LocalRevision',
        'MainInstance.Durable.LocalChanges', 'MainInstance.Active.Version',
        'MainInstance.Active.MessageId', 'MainInstance.Active.DeviceCount',
        'MainInstance.Active.PointCount', 'MainInstance.QueueCount',
        'MainInstance.Dropped', 'MainInstance.HMI.InvalidAcks']
# HMI is a global external, not a child of MainInstance.
CORE[-1] = 'HMI.InvalidAcks'


def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def read(g, fields):
    values = []
    for start in range(0, len(fields), 80):
        rows = g.Read([PFX + f for f in fields[start:start + 80]])
        for field, row in zip(fields[start:start + 80], rows):
            if int(row.Error):
                raise RuntimeError(field + ': ' + str(row.Error))
            values.append(row.Value.GetValue())
    return values


def core(g):
    value = dict(zip(CORE, read(g, CORE)))
    value['at'] = time.time()
    assert value['HMI.GatewayId'] == GW, 'Unexpected controller identity'
    return value


def write(g, field, value):
    result = g.WriteSingle(sdk.WriteItem(PFX + field, sdk.RscVariant.of(value)))
    assert int(result) == 0, (field, str(result))


def nav(g, code):
    result = g.WriteSingle(sdk.WriteItem(PFX + 'GW_Nav', sdk.RscVariant(code, RscType.Int16)))
    assert int(result) == 0
    time.sleep(.4)


def wait(g, predicate, seconds=120):
    end = time.monotonic() + seconds
    last = None
    while time.monotonic() < end:
        last = core(g)
        assert not last['MainInstance.Store.Error'], last
        if not last['MainInstance.Store.Busy'] and predicate(last):
            return last
        time.sleep(1)
    raise AssertionError({'timeout': seconds, 'last': last})


def configuration(g, source='Active'):
    base = 'MainInstance.' + source + '.'
    heads = ['Version', 'MessageId', 'enabled', 'batchIntervalMs', 'maxBatchPoints', 'DeviceCount', 'PointCount']
    value = dict(zip(heads, read(g, [base + f for f in heads])))
    ds = ['deviceId', 'name', 'enabled', 'host', 'port', 'unitId', 'connectTimeoutMs',
          'requestTimeoutMs', 'retryCount', 'PointStart', 'PointCount']
    ps = ['pointId', 'name', 'enabled', 'dataType', 'pollIntervalMs', 'reportIntervalMs',
          'scale', 'offset', 'unit', 'reportMode', 'deadband', 'staleAfterMs', 'area', 'address', 'byteOrder']
    rows = read(g, [base + f'Devices[{i}].{f}' for i in range(1, value['DeviceCount'] + 1) for f in ds])
    value['devices'] = [dict(zip(ds, rows[i:i + len(ds)])) for i in range(0, len(rows), len(ds))]
    rows = read(g, [base + f'Points[{i}].{f}' for i in range(1, value['PointCount'] + 1) for f in ps])
    value['points'] = [dict(zip(ps, rows[i:i + len(ps)])) for i in range(0, len(rows), len(ps))]
    return value


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def hub_context():
    fixture = json.loads((ROOT / 'tests/hub-runtime/fixture.json').read_text(encoding='utf-8'))
    assert fixture['gatewayId'] == GW and fixture['prefix'] == 'ng-2152-20261023'
    return HubApi(read_timeout=180).login(), fixture


def release_result(api, parent, release, wanted):
    end = time.monotonic() + 160
    while time.monotonic() < end:
        result = api.api('GET', f'/api/device/{parent}/iot-config/releases/{release["id"]}')
        if result['status'] in ('APPLIED', 'REJECTED', 'FAILED', 'TIMEOUT'):
            save('release-' + wanted.lower() + '.json', result)
            assert result['status'] == wanted, result
            return result
        time.sleep(2)
    raise AssertionError('Hub release response missing')


def ready_preview(api, parent):
    """Allow the existing Hub session projector to catch up after a binding edit."""
    deadline = time.monotonic() + 240
    while True:
        preview = api.api('GET', f'/api/device/{parent}/iot-config/device-releases/preview?gatewayOnly=true')
        if not preview.get('issues'):
            return preview
        messages = ' '.join(issue.get('message', '') for issue in preview['issues'])
        if time.monotonic() >= deadline or not any(code in messages for code in
                ['PATCH_CAPABILITY_UNAVAILABLE', 'CONFIG_RECONCILING']):
            raise AssertionError(preview)
        time.sleep(5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['baseline', 'enter', 'edit', 'publish-conflict',
                                        'handback', 'retry', 'verify', 'reboot', 'check-reboot', 'restore-policy',
                                        'replay-conflict', 'final-ui'])
    args = parser.parse_args()
    state = json.loads(STATE.read_text(encoding='utf-8')) if STATE.exists() else {}
    phase = args.phase
    if phase == 'reboot':
        from PyPlcnextRsc.Arp.Device.Interface.Services import IDeviceControlService
        started = time.time()
        with sdk.Device(PLC) as d:
            g = sdk.IDataAccessService(d)
            before = core(g)
            assert not before['HMI.Managed'] and before['HMI.LocalChanges']
            state['beforeReboot'] = before
            state['rebootStartedAt'] = started
            save('state.json', state)
            try:
                IDeviceControlService(d).RestartDevice()
            except Exception as error:
                # A restarting controller may close the request socket. Success
                # still requires observed outage and a different persisted boot ID.
                save('restart-response.json', dict(exception=type(error).__name__))
        observed_down = False
        while time.time() - started < 240:
            ports = {}
            for port in (443, 41100):
                try:
                    with socket.create_connection((PLC, port), timeout=.7):
                        ports[str(port)] = True
                except OSError:
                    ports[str(port)] = False
            observed_down |= not ports['41100']
            with (OUT / 'reboot-reachability.jsonl').open('a', encoding='utf-8') as stream:
                stream.write(json.dumps(dict(at=time.time(), ports=ports)) + '\n')
            if observed_down and all(ports.values()):
                try:
                    with sdk.Device(PLC) as d:
                        g = sdk.IDataAccessService(d)
                        after = core(g)
                        if (after['MainInstance.BootId'] != before['MainInstance.BootId']
                                and after['HMI.Connection'] == 'CONNECTED'
                                and not after['MainInstance.Store.Busy']):
                            assert not after['HMI.Managed'] and after['HMI.LocalChanges']
                            assert after['MainInstance.Durable.LocalRevision'] == before['MainInstance.Durable.LocalRevision']
                            assert configuration(g, 'Durable.HubConfig') == state['config']
                            assert configuration(g)['points'][0]['pollIntervalMs'] == state['config']['points'][0]['pollIntervalMs'] + 1000
                            state['rebootRecovered'] = after
                            save('state.json', state)
                            save('reboot.json', dict(passed=True, observedRscOutage=observed_down,
                                                    elapsedSeconds=round(time.time() - started, 2), core=after))
                            print('PASS: reboot; maintenance, local change and Hub backup restored.', flush=True)
                            return
                except (ConnectionError, OSError, RuntimeError, CommonRemotingException):
                    pass
            time.sleep(2)
        raise AssertionError('Controller maintenance reboot did not recover within 240 seconds')
    with sdk.Device(PLC) as device:
        g = sdk.IDataAccessService(device)
        before = wait(g, lambda r: r['HMI.Connection'] == 'CONNECTED')
        if phase == 'final-ui':
            assert before['HMI.Managed'] and not before['HMI.LocalChanges']
            config = configuration(g)
            initial_session = read(g, ['MainInstance.SessionId'])[0]
            generation = before['MainInstance.Durable.Generation']
            nav(g, 42)
            assert read(g, ['MainInstance.Editor.ModeReviewOpen', 'HMI.ClearOnMaintenance',
                            'HMI.ManagementMode']) == [True, False, 'HUB_MANAGED']
            assert core(g)['HMI.Managed']
            nav(g, 67)  # Select clear, then CANCEL. Never execute the clear operation.
            assert read(g, ['HMI.ClearOnMaintenance'])[0] is True
            nav(g, 65)
            assert read(g, ['MainInstance.Editor.ModeReviewOpen'])[0] is False
            nav(g, 68)  # A stale confirmation command must be harmless after cancel.
            assert core(g)['HMI.Managed'] and configuration(g) == config
            assert core(g)['MainInstance.Durable.Generation'] == generation
            nav(g, 42)
            assert read(g, ['HMI.ClearOnMaintenance'])[0] is False
            nav(g, 68)
            entered = wait(g, lambda r: not r['HMI.Managed'])
            assert configuration(g) == config and not entered['HMI.LocalChanges']
            assert read(g, ['HMI.ManagementMode'])[0] == 'STANDALONE'
            nav(g, 4)
            original = int(config['points'][0]['pollIntervalMs'])
            write(g, 'HMI.PollIntervalMs', str(original + 1000))
            write(g, 'GW_SavePoint', True)
            time.sleep(.4)
            nav(g, 36)
            edited = wait(g, lambda r: r['HMI.LocalChanges'] and
                          r['MainInstance.Durable.LocalRevision'] > entered['MainInstance.Durable.LocalRevision'])
            expected = json.loads(json.dumps(config))
            expected['points'][0]['pollIntervalMs'] = original + 1000
            assert configuration(g) == expected
            assert configuration(g, 'Durable.HubConfig') == config
            assert read(g, ['MainInstance.TelemetryAllowed'])[0] is False
            nav(g, 41)
            assert not core(g)['HMI.Managed']
            assert read(g, ['HMI.ManagementMode'])[0] == 'STANDALONE'
            nav(g, 65)
            nav(g, 68)
            assert not core(g)['HMI.Managed'] and configuration(g) == expected
            nav(g, 41)
            nav(g, 68)
            returned = wait(g, lambda r: r['HMI.Managed'] and not r['HMI.LocalChanges'])
            assert configuration(g) == config == configuration(g, 'Durable.HubConfig')
            assert read(g, ['MainInstance.SessionId'])[0] == initial_session
            assert returned['MainInstance.BootId'] == before['MainInstance.BootId']
            state['finalUi'] = dict(at=time.time(), passed=True, before=before, entered=entered,
                                   edited=edited, returned=returned, configSha256=digest(config),
                                   reviewAndCancelPassed=True, staleConfirmationBlocked=True,
                                   gatewayIdentityAndSessionRetained=True, optionalClearExecuted=False)
            save('final-ui-detail.json', state['finalUi'])
        elif phase == 'baseline':
            assert before['HMI.Managed'] and before['MainInstance.Durable.HasHubBaseline']
            config = configuration(g)
            assert config['DeviceCount'] == 50 and config['PointCount'] == 250
            assert configuration(g, 'Durable.HubConfig') == config
            state = dict(baseline=before, config=config, configSha256=digest(config))
        elif phase == 'enter':
            nav(g, 42)
            assert read(g, ['HMI.ClearOnMaintenance'])[0] is False
            assert core(g)['HMI.Managed'], 'Review must not activate a mode'
            nav(g, 68)
            after = wait(g, lambda r: not r['HMI.Managed'])
            assert configuration(g) == state['config']
            assert not after['HMI.LocalChanges']
            state['entered'] = after
        elif phase == 'edit':
            assert not before['HMI.Managed']
            nav(g, 4)
            original = int(state['config']['points'][0]['pollIntervalMs'])
            write(g, 'HMI.PollIntervalMs', str(original + 1000))
            write(g, 'GW_SavePoint', True)
            time.sleep(.4)
            nav(g, 36)
            after = wait(g, lambda r: r['HMI.LocalChanges'] and
                         r['MainInstance.Durable.LocalRevision'] > before['MainInstance.Durable.LocalRevision'])
            config = configuration(g)
            assert config['Version'] == state['config']['Version']
            assert config['MessageId'] == state['config']['MessageId']
            expected = json.loads(json.dumps(state['config']))
            expected['points'][0]['pollIntervalMs'] = original + 1000
            assert config == expected, 'Only the intended local period may change'
            assert configuration(g, 'Durable.HubConfig') == state['config']
            assert read(g, ['MainInstance.TelemetryAllowed'])[0] is False
            state['edited'] = after
        elif phase == 'publish-conflict':
            assert not before['HMI.Managed'] and before['HMI.LocalChanges']
            api, fixture = hub_context()
            parent = fixture['parentId']
            policy = api.api('GET', f'/api/device/{parent}/iot-gateway')
            assert not policy.get('configDrift'), policy
            save('hub-before.json', policy)
            state['originalPolicy'] = dict(brokerId=fixture['brokerId'], gatewayId=GW,
                                          enabled=policy['enabled'], report=policy['report'])
            request = dict(state['originalPolicy'], expectedRevision=policy['draftRevision'])
            request['report'] = dict(policy['report'], batchIntervalMs=policy['report']['batchIntervalMs'] + 100)
            api.api('PUT', f'/api/device/{parent}/iot-gateway', request)
            # Change only the batch interval; keep the 50-device point table intact.
            preview = ready_preview(api, parent)
            release = api.api('POST', f'/api/device/{parent}/iot-config/device-releases',
                              dict(expectedRevision=preview['draftRevision'], requestId='maint-' + uuid.uuid4().hex,
                                   deviceIds=[], gatewayOnly=True))
            state['release'] = release
            save('state.json', state)
            release_result(api, parent, release, 'REJECTED')
            assert core(g)['MainInstance.Active.Version'] == state['config']['Version']
        elif phase == 'handback':
            assert not before['HMI.Managed']
            nav(g, 41)
            assert not core(g)['HMI.Managed'], 'Review must not activate a mode'
            nav(g, 68)
            after = wait(g, lambda r: r['HMI.Managed'] and not r['HMI.LocalChanges'])
            assert configuration(g) == state['config'], 'Handback must restore the exact saved Hub table'
            state['handback'] = after
        elif phase == 'replay-conflict':
            import paho.mqtt.client as mqtt
            assert not before['HMI.Managed'] and before['HMI.LocalChanges']
            expected_id = state['release']['messageId']
            original = None
            with (ROOT / 'tests/hub-runtime/wire.jsonl').open(encoding='utf-8') as stream:
                for line in stream:
                    row = json.loads(line)
                    if row['topic'] != 'iot/v1/gateway/' + GW + '/config/patch':
                        continue
                    payload = json.loads(row['payload'])
                    if payload['messageId'] == expected_id:
                        original = row['payload']
            assert original is not None, 'Exact Hub command bytes not found'
            subscribed = threading.Event()
            received = threading.Event()
            acknowledgements = []
            client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='native-maintenance-replay-proof')
            client.on_connect = lambda c, u, f, r, p: c.subscribe('iot/v1/gateway/' + GW + '/config/patch/ack', 1)
            client.on_subscribe = lambda *a: subscribed.set()
            def incoming(c, u, message):
                payload = json.loads(message.payload)
                if payload.get('messageId') == expected_id:
                    acknowledgements.append(dict(at=time.time(), payload=payload))
                    received.set()
            client.on_message = incoming
            client.connect('127.0.0.1', 1883)
            client.loop_start()
            try:
                assert subscribed.wait(10)
                client.publish('iot/v1/gateway/' + GW + '/config/patch', original, qos=1, retain=False).wait_for_publish(10)
                assert received.wait(25), 'PLC rejection receipt missing after maintenance reboot'
            finally:
                client.disconnect()
                client.loop_stop()
            ack = acknowledgements[-1]['payload']
            assert ack['status'] == 'REJECTED' and ack['errors'][0]['code'] == 'VERSION_CONFLICT'
            assert configuration(g, 'Durable.HubConfig') == state['config']
            assert configuration(g)['points'][0]['pollIntervalMs'] == state['config']['points'][0]['pollIntervalMs'] + 1000
            state['replayRejection'] = acknowledgements[-1]
            save('maintenance-replay-ack.json', acknowledgements[-1])
        elif phase == 'retry':
            assert before['HMI.Managed'] and not before['HMI.LocalChanges']
            api, fixture = hub_context()
            parent = fixture['parentId']
            # Renew the normal capability cursor before using Hub's existing retry endpoint.
            time.sleep(32)
            api.api('POST', f'/api/device/{parent}/iot-config/releases/{state["release"]["id"]}/retry')
            state['appliedRelease'] = release_result(api, parent, state['release'], 'APPLIED')
        elif phase == 'restore-policy':
            api, fixture = hub_context()
            parent = fixture['parentId']
            policy = api.api('GET', f'/api/device/{parent}/iot-gateway')
            if policy['report'] != state['originalPolicy']['report']:
                api.api('PUT', f'/api/device/{parent}/iot-gateway',
                        dict(state['originalPolicy'], expectedRevision=policy['draftRevision']))
            preview = ready_preview(api, parent)
            state.setdefault('restoreRequestId', 'maint-restore-' + uuid.uuid4().hex)
            save('state.json', state)
            release = api.api('POST', f'/api/device/{parent}/iot-config/device-releases',
                              dict(expectedRevision=preview['draftRevision'], requestId=state['restoreRequestId'],
                                   deviceIds=[], gatewayOnly=True))
            state['appliedRelease'] = release_result(api, parent, release, 'APPLIED')
        elif phase == 'verify':
            config = configuration(g)
            assert before['HMI.Managed'] and not before['HMI.LocalChanges']
            assert config['Version'] == state['appliedRelease']['configVersion']
            assert config['DeviceCount'] == 50 and config['PointCount'] == 250
            assert config == configuration(g, 'Durable.HubConfig')
            rows = read(g, [f'MainInstance.Samples[{i}].{f}' for i in range(1, 251)
                            for f in ['Value', 'Quality', 'Timestamp']])
            at = read(g, ['MainInstance.UnixMs'])[0]
            verified = 0
            for definition in config['devices']:
                unit = definition['unitId']
                expected = dict(voltage=230 + unit / 10, current=(123 + unit) * .1,
                                frequency=(5000 + unit) * .01, power=1234 + unit, energy=100000 + unit)
                for index in range(definition['PointStart'], definition['PointStart'] + definition['PointCount']):
                    value, quality, stamp = rows[(index - 1) * 3:index * 3]
                    point = config['points'][index - 1]
                    assert quality == 'GOOD' and 0 <= at - stamp <= 20000
                    assert math.isclose(value, expected[point['name']], abs_tol=.0001)
                    verified += 1
            state['verified'] = dict(at=time.time(), pointsGoodAndCorrect=verified,
                                     final=core(g), configSha256=digest(config))
        elif phase == 'check-reboot':
            assert before['MainInstance.BootId'] != state['beforeReboot']['MainInstance.BootId']
            assert not before['HMI.Managed'] and before['HMI.LocalChanges']
            assert before['MainInstance.Durable.LocalRevision'] == state['beforeReboot']['MainInstance.Durable.LocalRevision']
            assert configuration(g, 'Durable.HubConfig') == state['config']
            assert configuration(g)['points'][0]['pollIntervalMs'] == state['config']['points'][0]['pollIntervalMs'] + 1000
            state['rebootRecovered'] = before
            probes = [json.loads(line) for line in (OUT / 'reboot-reachability.jsonl').read_text().splitlines()]
            assert any(not r['ports']['41100'] for r in probes), 'Real RSC service outage was not observed'
            save('reboot.json', dict(passed=True, observedRscOutage=True,
                                    elapsedSeconds=round(time.time() - state['rebootStartedAt'], 2),
                                    note='Verified after startup SSL retry; elapsed time includes manual verification delay.',
                                    core=before))
        save('state.json', state)
        save(phase + '.json', dict(at=time.time(), passed=True, core=core(g)))
        print('PASS:', phase, flush=True)


if __name__ == '__main__':
    main()
