"""Build the separate AXC F 1252 gateway source package without PLC access.

The frozen Engineer-validated 1252 project supplies all 66 IEC sources, types,
hardware, tasks, HMI and worksheet identities. Its native-0.8.1 baseline is
independent of uncommitted or later 2152 changes in src/.
Compile the result with PLCnext Engineer 2026.0 and the vendor IIoT user library.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import zipfile
from dev_version import stamp

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "projects/templates/NativeGateway1252.engineering.pcwex"
BASE_SHA = "9a28ee50d940adb218c4d05f68d6394e46707a5d54882f8b567345f13eda62dd"
OUTPUT = ROOT / "projects/candidates/native-0.8.1-axcf1252/NativeGateway1252.pcwex"
VERSION = "native-0.8.1"
GATEWAY_ID = "NG-HUB-1252-01"
STORAGE_PREFIX = "/opt/plcnext/custom/NativeGateway1252"


def build(output):
    if hashlib.sha256(BASE.read_bytes()).hexdigest() != BASE_SHA:
        raise ValueError("Frozen 1252 engineering model changed")
    with zipfile.ZipFile(BASE) as archive:
        entries = archive.infolist()
        files = {entry.filename: archive.read(entry) for entry in entries}
    original = dict(files)
    settings = next(data for name, data in files.items() if name.endswith("ResourceSettings.set"))
    if b"AXCF1252" not in settings or b"-ip192.168.0.10 " not in settings or b"T#20ms" not in settings:
        raise ValueError("Unexpected target hardware, endpoint or task interval")
    names = sorted(name.split("/")[-2][:-4] for name in files if name.endswith(".pou/Code.st"))
    if len(names) != 66:
        raise ValueError("Unexpected frozen POU set")
    store_path = "PROJECT/Logical%20Elements/NG_Store.pou/Code.st"
    if files[store_path].count(b"/opt/plcnext/NativeGateway1252") != 8:
        raise ValueError("Unexpected frozen persistence paths")
    files[store_path] = files[store_path].replace(
        b"/opt/plcnext/NativeGateway1252", STORAGE_PREFIX.encode())
    inputs = {name: hashlib.sha256(data).hexdigest() for name, data in original.items()
              if name.startswith("PROJECT/Logical%20Elements/")}
    main = files["PROJECT/Logical%20Elements/Main.pou/Code.st"].decode()
    store = files["PROJECT/Logical%20Elements/NG_Store.pou/Code.st"].decode()
    if re.findall(r'"agentVersion":"([^"\n]+)"', main) != [VERSION]:
        raise ValueError("Unexpected source heartbeat version")
    if "NG-HUB-2152-01" in main or GATEWAY_ID not in main:
        raise ValueError("1252 gateway identity not isolated")
    if "/opt/plcnext/NativeGateway" in store or STORAGE_PREFIX not in store:
        raise ValueError("1252 persistence must use the writable custom directory")
    dev_version = stamp(files)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as stream, zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        # Keep the validated OPC member order and original ZIP metadata.
        # Repacking is not proof that Engineer can load or compile the result.
        for entry in entries:
            archive.writestr(copy.copy(entry), files[entry.filename])
    report = dict(version=dev_version, variant="AXCF1252", address="192.168.0.10",
                  gatewayId=GATEWAY_ID, clientId=GATEWAY_ID + "-native", storagePrefix=STORAGE_PREFIX,
                  source=str(output), sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                  engineeringBase=str(BASE), engineeringBaseSha256=BASE_SHA, pouCount=len(names), inputs=inputs,
                  hardwareHmiTasksUnchanged=all(files[name] == original[name] for name in files
                      if not name.startswith("PROJECT/Logical%20Elements/")),
                  compiled=False, downloaded=False, controllerAccess=False)
    output.with_suffix(".build.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k:v for k,v in report.items() if k != "inputs"}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    build(parser.parse_args().output.resolve())
