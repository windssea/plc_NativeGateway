"""Read-only PLC/Modbus/MQTT validation; optionally restart only the lab NTP server.

Requires the isolated 50 x 5 mock fixture, real Hub ACKs, and the configured
192.168.0.5 NTP container. Never publishes configuration or business ACKs.
Hub receipt delays are measured separately from controller acquisition health.
"""
from pathlib import Path
import argparse
import collections
import json
import math
import subprocess
import sys
import threading
import time

import maintenance_mode_verify as v
import paho.mqtt.client as mqtt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tests/time-locking-20261023'
sys.path.insert(0, str(ROOT.parent / 'PLCnext-iot/src'))
from plcnext_iot.contracts import topic_rules, validate_message


def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def chrony():
    p = subprocess.run(['docker', 'exec', 'nativegateway-ntp', 'chronyc', 'clients'],
                       capture_output=True, text=True, timeout=10)
    return dict(at=time.time(), exitCode=p.returncode, clients=p.stdout.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=480)
    parser.add_argument('--restart-ntp', action='store_true')
    args = parser.parse_args()
    assert args.seconds >= 180
    OUT.mkdir(exist_ok=True)
    errors = []; samples = []; counts = collections.Counter(); points = {}
    batches = {}; stored = set(); ack_latencies = []; broker_errors = []
    lock = threading.RLock(); ready = threading.Event()
    with v.sdk.Device(v.PLC) as device:
        g = v.sdk.IDataAccessService(device)
        config = v.configuration(g)
        assert config['DeviceCount'] == 50 and config['PointCount'] == 250
        assert config['batchIntervalMs'] == 1000
        assert all(p['pollIntervalMs'] == p['reportIntervalMs'] == 5000 for p in config['points'])
        baseline = v.core(g)
        assert baseline['HMI.Managed'] and not baseline['HMI.LocalChanges']
    expected = {}; ordered = []
    for d in config['devices']:
        u = d['unitId']
        numbers = dict(voltage=230+u/10, current=(123+u)*.1, frequency=(5000+u)*.01,
                       power=1234+u, energy=100000+u)
        for i in range(d['PointStart']-1, d['PointStart']-1+d['PointCount']):
            p = config['points'][i]
            assert p['enabled'] and d['enabled']
            value = numbers[p['name']]
            expected[d['deviceId'], p['pointId']] = value
            ordered.append(value)
    kinds = {x['suffix']: k for k, x in topic_rules().items()}
    heartbeats = []

    def incoming(c, u, m):
        if m.retain or not m.payload: return
        at = time.time(); suffix = m.topic.split('/', 4)[-1]
        with lock:
            try:
                p = json.loads(m.payload); counts[suffix] += 1
                if suffix in kinds:
                    issues = validate_message(kinds[suffix], m.payload, expected_gateway_id=v.GW)
                    if issues: broker_errors.append(dict(at=at, kind='schema', issues=[str(x) for x in issues]))
                if suffix == 'heartbeat': heartbeats.append(dict(at=at, payload=p))
                elif suffix == 'data':
                    batches.setdefault(p['messageId'], dict(at=at, points=len(p['values'])))
                    for row in p['values']:
                        key = row['deviceId'], row['pointId']
                        if (key not in expected or row['quality'] != 'GOOD' or row['value'] is None
                                or not math.isclose(row['value'], expected[key], abs_tol=.0001)):
                            broker_errors.append(dict(at=at, kind='incorrect-value', value=row))
                        points[key] = at
                elif suffix == 'data/ack' and p['status'] == 'STORED':
                    mid = p['messageId']
                    if mid in batches and mid not in stored:
                        stored.add(mid); ack_latencies.append(at-batches[mid]['at'])
                with (OUT / 'plc-monitor-wire.jsonl').open('a', encoding='utf-8') as f:
                    f.write(json.dumps(dict(at=at, topic=m.topic, payload=p), ensure_ascii=False)+'\n')
            except Exception as e: broker_errors.append(dict(at=at, kind=type(e).__name__, message=str(e)[:160]))

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='nativegateway-plc-time-readonly')
    client.on_connect = lambda c,u,f,r,p: c.subscribe('iot/v1/gateway/'+v.GW+'/#', 1)
    client.on_subscribe = lambda *a: ready.set()
    client.on_message = incoming
    client.connect('127.0.0.1', 1883); client.loop_start()
    assert ready.wait(10)
    start = time.time(); restarted = False
    ntp = [chrony()]
    try:
        while time.time()-start < args.seconds:
            at = time.time()
            if args.restart_ntp and not restarted and at-start >= 90:
                p = subprocess.run(['docker', 'restart', 'nativegateway-ntp'], capture_output=True, text=True, timeout=30)
                assert p.returncode == 0, p.stderr
                ntp.append(dict(at=time.time(), event='container-restart', container=p.stdout.strip()))
                restarted = True
            try:
                with v.sdk.Device(v.PLC) as device:
                    g = v.sdk.IDataAccessService(device); core = v.core(g)
                    epoch, offset, now_ms = v.read(g, ['MainInstance.UnixMs', 'MainInstance.Bootstrap.UtcOffsetMinutes', 'MainInstance.NowMs'])
                    delta = epoch/1000-time.time()
                    fields = ['Value', 'Quality', 'Timestamp', 'LastGoodMs']
                    rows = v.read(g, [f'MainInstance.Samples[{i}].{f}' for i in range(1,251) for f in fields])
                    bad = []; ages = []
                    for i in range(250):
                        value, quality, stamp, last_good = rows[i*4:i*4+4]
                        age = max(0, (now_ms-last_good)/1000); ages.append(age)
                        if quality != 'GOOD' or not math.isclose(value, ordered[i], abs_tol=.0001) or age > 20:
                            bad.append(dict(point=i+1, quality=quality, ageSeconds=age, value=value))
                    if bad: errors.append(dict(at=at, kind='acquisition', points=bad))
                    if (core['MainInstance.BootId'] != baseline['MainInstance.BootId'] or core['MainInstance.Dropped']
                            or core['HMI.InvalidAcks'] or core['MainInstance.Store.Error'] or core['HMI.Connection'] != 'CONNECTED'
                            or core['MainInstance.Active.Version'] != config['Version']):
                        errors.append(dict(at=at, kind='controller-state', core=core))
                    if offset != 0 or abs(delta) > 5: errors.append(dict(at=at, kind='clock', offsetMinutes=offset, deltaSeconds=delta))
                    resource = json.loads((ROOT/'tests/hub-runtime/controller-resources.json').read_text(encoding='utf-8'))
                    if time.time()-resource['receivedAt'] > 30 or resource['actualMemoryPercent'] > 85:
                        errors.append(dict(at=at, kind='resources', resource=resource))
                    sample = dict(at=at, epochOffsetSeconds=round(delta,3), maxPointAgeSeconds=round(max(ages),3),
                                  goodPoints=250-len(bad), core=core, resources=resource)
                    samples.append(sample)
                    with (OUT/'plc-monitor-samples.jsonl').open('a', encoding='utf-8') as f: f.write(json.dumps(sample,ensure_ascii=False)+'\n')
                    with lock:
                        save('plc-monitor-status.json',dict(at=time.time(), elapsedSeconds=round(time.time()-start,1), samples=len(samples),
                            wireCoverage=len(points), counts=dict(counts), errors=errors[-5:]+broker_errors[-5:]))
            except Exception as e: errors.append(dict(at=at, kind='read-failed', error=str(e)[:250]))
            if len(samples) % 6 == 0: ntp.append(chrony())
            time.sleep(min(15,max(0,start+args.seconds-time.time())))
    finally:
        client.disconnect(); client.loop_stop()
    ntp.append(chrony()); save('plc-ntp-recovery.json',ntp)
    with lock:
        gaps = [b['at']-a['at'] for a,b in zip(heartbeats,heartbeats[1:])]
        if not heartbeats or (gaps and max(gaps)>40): errors.append(dict(kind='heartbeat-gap', gaps=gaps))
        if set(points) != set(expected): errors.append(dict(kind='mqtt-point-coverage', count=len(points)))
        errors.extend(broker_errors)
        result = dict(startedAt=start, finishedAt=time.time(), actualSeconds=round(time.time()-start,2),
            plcPassed=not errors and len(samples)>=args.seconds//25, errors=errors, samples=len(samples),
            devices=50, points=250, activeVersion=config['Version'], bootId=baseline['MainInstance.BootId'],
            ntpRestartTest=args.restart_ntp, ntpRestarted=restarted,
            clockMinOffsetSeconds=min((s['epochOffsetSeconds'] for s in samples),default=None),
            clockMaxOffsetSeconds=max((s['epochOffsetSeconds'] for s in samples),default=None),
            maxPointAgeSeconds=max((s['maxPointAgeSeconds'] for s in samples),default=None),
            cpuRange=[min((s['resources']['cpuPercent'] for s in samples),default=None),max((s['resources']['cpuPercent'] for s in samples),default=None)],
            actualMemoryRange=[min((s['resources']['actualMemoryPercent'] for s in samples),default=None),max((s['resources']['actualMemoryPercent'] for s in samples),default=None)],
            maxQueueBatches=max((s['core']['MainInstance.QueueCount'] for s in samples),default=None),
            mqtt=dict(counts=counts,coverage=len(points), heartbeatMaxGapSeconds=max(gaps,default=0)),
            hubReceipts=dict(storedBatches=len(stored), ackMaxSeconds=max(ack_latencies,default=None),
                unacknowledgedBatches=len(set(batches)-stored), note='Hub persistence latency is recorded separately; not a Hub stability pass.'))
        save('plc-monitor-results.json',result)
        print(json.dumps(result,ensure_ascii=True),flush=True)
    assert result['plcPassed'], 'PLC stability verification failed; inspect JSON evidence'


if __name__ == '__main__': main()
