"""Verify frozen engineering inputs offline; never connect or download."""
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def verify():
    catalog = json.loads((ROOT / 'projects/catalog.json').read_text(encoding='utf-8'))
    checked = []
    for item in catalog['entries']:
        path = (ROOT / item['path']).resolve()
        if not path.is_relative_to(ROOT / 'projects'):
            raise ValueError('Archive must stay inside projects/')
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError(f'Archive hash mismatch: {path}')
        with zipfile.ZipFile(path) as archive:
            code = archive.read('PROJECT/Logical%20Elements/Main.pou/Code.st').decode('utf-8-sig')
            versions = re.findall(r'"agentVersion":"([^"]+)"', code)
            if versions != [item['embeddedAgentVersion']]:
                raise ValueError(f'Embedded version mismatch: {path}')
            count = sum(n.endswith('/Code.st') for n in archive.namelist())
            if count != item['pouCount']:
                raise ValueError(f'POU count mismatch: {path}')
        checked.append(dict(artifactId=item['artifactId'], sha256=item['sha256'], pouCount=count))
    selected = next(i for i in catalog['entries'] if i['artifactId'] == catalog['defaultArtifactId'])
    formal_id = catalog.get('formalArtifactId')
    formal = [i for i in catalog['entries'] if i['status'] == 'MAINLINE_RELEASE']
    if formal_id:
        if ([i['artifactId'] for i in formal] != [formal_id]
                or formal_id != selected['artifactId']
                or sum(bool(i.get('default')) for i in catalog['entries']) != 1
                or not selected.get('default')):
            raise ValueError('Exactly one formal mainline must be the selected default')
        receipt = ROOT / catalog['formalVerification']['path']
        raw = receipt.read_bytes()
        if hashlib.sha256(raw).hexdigest() != catalog['formalVerification']['sha256']:
            raise ValueError('Mainline verification receipt changed')
        result = json.loads(raw)
        if (result.get('artifactSha256') != selected['sha256']
                or result.get('artifactId') != formal_id or result.get('passed') is not True
                or result.get('observedSeconds', 0) < 1800
                or result.get('sameVersionVerified') is not True):
            raise ValueError('Formal entry needs completed same-version 30-minute verification')
    elif formal:
        raise ValueError('A formal release must have an explicit formalArtifactId')
    if (ROOT / catalog['rootAlias']).read_bytes() != (ROOT / selected['path']).read_bytes():
        raise ValueError('Root project no longer matches the selected engineering archive')
    return dict(archives=checked, rootAliasMatches=True, formalArtifactId=formal_id,
                formalVerificationChecked=bool(formal_id), plcConnected=False, plcDownloaded=False)


if __name__ == '__main__':
    print(json.dumps(verify(), ensure_ascii=False, indent=2))
