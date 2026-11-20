"""Deterministic dev identity for offline builds; never relabel frozen archives."""
import hashlib
import re

MAIN = 'PROJECT/Logical%20Elements/Main.pou/Code.st'
PATTERN = re.compile(rb'"agentVersion":"([^"\r\n]+)"')


def stamp(files):
    previous = PATTERN.findall(files[MAIN])
    if len(previous) != 1:
        raise ValueError('Exactly one heartbeat agentVersion is required')
    match = re.fullmatch(rb'native-(\d+)\.(\d+)\.(\d+)(?:-.*)?', previous[0])
    if not match:
        raise ValueError('Unsupported baseline version')
    major, minor, patch = map(int, match.groups())
    digest = hashlib.sha256()
    for name, payload in sorted(files.items()):
        encoded = name.encode()
        digest.update(len(encoded).to_bytes(8, 'big')); digest.update(encoded)
        digest.update(len(payload).to_bytes(8, 'big')); digest.update(payload)
    version = f'native-{major}.{minor}.{patch + 1}-dev.{digest.hexdigest()[:16]}'
    files[MAIN] = PATTERN.sub(lambda _: f'"agentVersion":"{version}"'.encode(), files[MAIN])
    return version
