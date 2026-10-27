"""Read-only receipt/sample proof in the existing remote development hub DB.

Uses the repository's existing dev connection helper; never seeds, cleans,
creates a database or changes services. Requires finished native wire evidence.
"""
import argparse
import collections
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]


def verify(wire,cohort,output,wire_only=False):
    proof=json.loads(cohort.read_text(encoding='utf-8'))
    if wire_only:
        assert proof['cohortComplete'] is False and proof['wireReceiptsComplete'] is True
    else:
        assert proof['cohortComplete']
    boot=proof['bootId'];batches={}
    data=json.loads(wire.read_text(encoding='utf-8'))
    assert not data['truncated']
    for row in data['rows']:
        body=json.loads(row['payload'])
        if row['topic'].endswith('/data') and body.get('bootId')==boot:
            assert hashlib.sha256(row['payload'].encode()).hexdigest()==row['sha256']
            batches[body['messageId']]=(row,body)
    assert 0<len(batches)<=4000
    expected=[];timestamps=[]
    for mid,(raw,body) in batches.items():
        for value in body['values']:
            device=value['deviceId'];point=value['pointId']
            assert device.startswith('d-') and device[2:].isdigit()
            assert point.startswith('p-') and point[2:].isdigit()
            expected.append((mid,int(device[2:]),int(point[2:]),value['timestamp'],value['value'],value['quality']))
            timestamps.append(value['timestamp'])
    assert len(expected)==proof['stored']<=100000
    sys.path.insert(0,str(ROOT.parent/'PLCnext-Hub-Backend/tools/phase1'))
    from live_hub_check import connection
    with connection() as c:
        c.rollback()
        c.execute('SET TRANSACTION READ ONLY')
        target=c.execute('SELECT current_database(),current_user,inet_server_addr()::text,inet_server_port()').fetchone()
        assert target[0]=='hub'
        receipts=[];actual=[]
        mids=list(batches)
        for start in range(0,len(mids),250):
            subset=mids[start:start+250]
            receipts += c.execute('SELECT message_id,payload_hash FROM biz_iot_ingest_receipt WHERE gateway_id=%s AND message_id=ANY(%s)',
                ('NG-HUB-2152-01',subset)).fetchall()
            actual += c.execute('SELECT source_message_id,device_id,variable_id,time,value_num::float8,quality_code FROM biz_device_data '
                'WHERE source_gateway_id=%s AND source_message_id=ANY(%s) AND time >= %s AND time <= %s',
                ('NG-HUB-2152-01',subset,datetime.fromtimestamp(min(timestamps)/1000,timezone.utc),
                 datetime.fromtimestamp(max(timestamps)/1000,timezone.utc))).fetchall()
        c.rollback()
    assert len(receipts)==len(batches) and len(dict(receipts))==len(batches)
    assert all(batches[mid][0]['sha256']==digest for mid,digest in receipts)
    actual=[(r[0],r[1],r[2],round(r[3].timestamp()*1000),r[4],r[5]) for r in actual]
    assert collections.Counter(actual)==collections.Counter(expected),'Committed sample multiset differs'
    report=dict(evidenceLevel='EXISTING_DEV_DATABASE_READ_ONLY_RECEIPTS_AND_SAMPLE_MULTISET',
        bootId=boot,cohortComplete=not wire_only,wireReceiptsComplete=True,
        auditAssociationProofComplete=not wire_only,
        receiptHashesVerified=len(receipts),committedSamplesVerified=len(actual),
        database=target[0],serverAddress=target[2],serverPort=target[3],clientEndpoint='69.230.197.241:6001',
        temporaryDatabaseCreated=False,databaseWrites=False,backendRestarted=False)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report))


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['wire','cohort','output']:ap.add_argument(name,type=Path)
    ap.add_argument('--wire-only',action='store_true',help='DB/wire proof only; retain incomplete native audit as failed')
    args=ap.parse_args();verify(args.wire,args.cohort,args.output,args.wire_only)
