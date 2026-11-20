"""Offline dual-target candidate builder for BOTH AXC F 2152 mainline and AXC F 1252 variant.

Applies the shared scale-hardened IEC ST sources (including contiguous legal Modbus register
merging and exponential backoff in NG_Modbus.st) into isolated candidate .pcwex packages for
BOTH AXC F 2152 and AXC F 1252 without modifying frozen release archives or contacting any PLC.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import zipfile
from dev_version import stamp

ROOT = Path(__file__).resolve().parents[1]
BASE_2152 = ROOT / "projects/candidates/native-0.8.1/NativeGateway.pcwex"
BASE_2152_SHA = "ac9cfec98d592e6c14f074725176be572831335c39273ef666f468de34236dc0"
BASE_1252 = ROOT / "projects/templates/NativeGateway1252.engineering.pcwex"
BASE_1252_SHA = "9a28ee50d940adb218c4d05f68d6394e46707a5d54882f8b567345f13eda62dd"
SHARED_SCALE_POUS = ("NG_Modbus",)
STORAGE_PREFIX_1252 = "/opt/plcnext/custom/NativeGateway1252"


def split_pou(source: str) -> tuple[str, str]:
    body = source.split("\n", 1)[1]
    end = list(re.finditer(r"\bEND_VAR\b", body))[-1].end()
    code = re.sub(r"\s*END_(PROGRAM|FUNCTION_BLOCK|FUNCTION)\s*$", "", body[end:]).strip() + "\n"
    return body[:end] + "\n", code


def build_2152_candidate(output: Path) -> dict:
    if hashlib.sha256(BASE_2152.read_bytes()).hexdigest() != BASE_2152_SHA:
        raise ValueError("Frozen 2152 engineering base changed")
    with zipfile.ZipFile(BASE_2152) as archive:
        files = {name: archive.read(name) for name in archive.namelist()}
    original = dict(files)
    names = sorted(n.split("/")[-2][:-4] for n in files if n.endswith(".pou/Code.st"))
    src_names = {p.stem for p in (ROOT / "src").glob("*.st")}
    if not set(names).issubset(src_names) or not set(SHARED_SCALE_POUS).issubset(set(names)):
        raise ValueError("Editable POU set differs from 2152 engineering model")
    # Preserve the verified running engineering archive, including unrelated
    # interfaces and types. This regression changes only the shared Modbus POU.
    for name in SHARED_SCALE_POUS:
        path = ROOT / "src" / f"{name}.st"
        variables, code = split_pou(path.read_text(encoding="utf-8-sig"))
        prefix = f"PROJECT/Logical%20Elements/{name}.pou/"
        files[prefix + "Variables.var"] = variables.encode("utf-8")
        files[prefix + "Code.st"] = code.encode("utf-8")
    if files["PROJECT/Logical%20Elements/NG_Types.dt"] != original["PROJECT/Logical%20Elements/NG_Types.dt"]:
        raise ValueError("2152 persistent configuration layout changed")
    version = stamp(files)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as stream, zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, (2026, 11, 20, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, files[name])
    return {
        "target": "AXCF2152",
        "version": version,
        "baseProject": str(BASE_2152),
        "baseProjectSha256": BASE_2152_SHA,
        "output": str(output),
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "pouCount": len(names),
        "updatedScalePous": list(SHARED_SCALE_POUS),
        "durableLayoutUnchanged": True,
        "hardwareHmiTasksUnchanged": all(
            files[n] == original[n] for n in files if not n.startswith("PROJECT/Logical%20Elements/")
        ),
        "controllerAccess": False,
        "downloaded": False,
    }


def build_1252_candidate(output: Path) -> dict:
    if hashlib.sha256(BASE_1252.read_bytes()).hexdigest() != BASE_1252_SHA:
        raise ValueError("Frozen 1252 engineering base changed")
    with zipfile.ZipFile(BASE_1252) as archive:
        entries = archive.infolist()
        files = {entry.filename: archive.read(entry) for entry in entries}
    original = dict(files)
    settings = next(data for name, data in files.items() if name.endswith("ResourceSettings.set"))
    if b"AXCF1252" not in settings or b"T#20ms" not in settings:
        raise ValueError("Unexpected 1252 hardware or task settings")
    store_path = "PROJECT/Logical%20Elements/NG_Store.pou/Code.st"
    files[store_path] = files[store_path].replace(
        b"/opt/plcnext/NativeGateway1252", STORAGE_PREFIX_1252.encode("utf-8")
    )
    for name in SHARED_SCALE_POUS:
        path = ROOT / "src" / f"{name}.st"
        variables, code = split_pou(path.read_text(encoding="utf-8-sig"))
        prefix = f"PROJECT/Logical%20Elements/{name}.pou/"
        files[prefix + "Variables.var"] = variables.encode("utf-8")
        files[prefix + "Code.st"] = code.encode("utf-8")
    main = files["PROJECT/Logical%20Elements/Main.pou/Code.st"].decode("utf-8")
    if "NG-HUB-2152-01" in main or "NG-HUB-1252-01" not in main:
        raise ValueError("1252 gateway identity not isolated")
    version = stamp(files)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("xb") as stream, zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        for entry in entries:
            archive.writestr(copy.copy(entry), files[entry.filename])
    return {
        "target": "AXCF1252",
        "version": version,
        "output": str(output),
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "pouCount": sum(n.endswith(".pou/Code.st") for n in files),
        "updatedScalePous": list(SHARED_SCALE_POUS),
        "durableLayoutUnchanged": True,
        "hardwareHmiTasksUnchanged": all(
            files[n] == original[n] for n in files if not n.startswith("PROJECT/Logical%20Elements/")
        ),
        "controllerAccess": False,
        "downloaded": False,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    out_dir = args.out_dir.resolve()
    result = {
        "axcf2152": build_2152_candidate(out_dir / "NativeGateway-2152-scale.pcwex"),
        "axcf1252": build_1252_candidate(out_dir / "NativeGateway-1252-scale.pcwex"),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
