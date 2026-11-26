"""Build an official PLCnext Solution App (.app SquashFS container) from a frozen PCWE release.

Completely additive and read-only with respect to projects/releases/:
- Never modifies projects/releases/ or MCP build/download artifacts.
- Validates app_info.json against the official PLCnext App-Info-Schema (Draft 2020-12) when available.
- Packages app_info.json + arp/PCWE/ into a SquashFS .app container via WSL/Linux mksquashfs
  with PLCnext AppManager UID/GID (1001:1002 = plcnext_firmware:plcnext).
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

TARGET_PROFILES = {
    "AXCF2152": {
        "target_name": "AXC F 2152",
        "identifier": "99000021520001",
        "minfirmware_version": "24.0.0",
    },
    "AXCF1252": {
        "target_name": "AXC F 1252",
        "identifier": "99000012520001",
        "minfirmware_version": "25.0.0",
    },
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def win_to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    rest = resolved.as_posix().split(":", 1)[1]
    return f"/mnt/{drive}{rest}"


def build_app_info(
    *,
    target: str,
    version: str,
    name: str,
    identifier: str,
    manufacturer: str,
    minfirmware_version: str,
) -> dict:
    profile = TARGET_PROFILES[target]
    clean_version = version.removeprefix("native-")
    return {
        "plcnextapp": {
            "name": name,
            "identifier": identifier,
            "version": clean_version,
            "target": profile["target_name"],
            "minfirmware_version": minfirmware_version,
            "manufacturer": manufacturer,
            "licensetype": "Free",
        },
        "engineerapp": {
            "folder": "/arp/PCWE",
        },
        "datastorage": {
            "persistentdata": True,
            "temporarydata": False,
        },
        "plcnextservices": [
            {"service": "EHMI", "action": "MUST_HAVE"},
            {"service": "IEC", "action": "MUST_HAVE"},
        ],
        "updateconfigs": {
            "autoupdate_enabled": False,
            "keep_persistentdata": True,
            "keep_temporarydata": False,
        },
    }


def validate_app_info(app_info: dict, schema_path: Path | None) -> bool:
    if schema_path is None or not schema_path.is_file():
        return False
    try:
        import jsonschema
    except ImportError:
        return False
    schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(app_info), key=lambda e: list(e.path))
    if errors:
        msgs = "; ".join(f"{'.'.join(map(str, e.path)) or '<root>'}: {e.message}" for e in errors)
        raise ValueError(f"app_info.json failed official PLCnext App-Info-Schema validation: {msgs}")
    return True


def package_solution_app(
    *,
    target: str,
    version: str,
    output_dir: Path | None = None,
    name: str = "PLCnext NativeGateway",
    manufacturer: str = "Phoenix Contact Lab",
    identifier: str | None = None,
    minfirmware_version: str | None = None,
    schema_path: Path | None = None,
) -> dict:
    if target not in TARGET_PROFILES:
        raise ValueError(f"Unsupported target: {target}")
    release_dir = ROOT / "projects" / "releases" / target / version
    pcwe_dir = release_dir / "PCWE"
    if not pcwe_dir.is_dir():
        raise FileNotFoundError(f"Frozen release PCWE directory not found: {pcwe_dir}")
    manifest_file = pcwe_dir / "PCWE.manifest.config"
    if not manifest_file.is_file():
        raise FileNotFoundError(f"PCWE.manifest.config not found in {pcwe_dir}")

    profile = TARGET_PROFILES[target]
    app_id = identifier or profile["identifier"]
    min_fw = minfirmware_version or profile["minfirmware_version"]
    app_info = build_app_info(
        target=target,
        version=version,
        name=name,
        identifier=app_id,
        manufacturer=manufacturer,
        minfirmware_version=min_fw,
    )
    schema_validated = validate_app_info(app_info, schema_path)

    dest_dir = output_dir or (ROOT / "projects" / "apps" / target / version)
    dest_dir.mkdir(parents=True, exist_ok=True)
    clean_ver = version.removeprefix("native-")
    app_filename = f"NativeGateway-{target}-{clean_ver}.app"
    app_path = dest_dir / app_filename
    info_copy_path = dest_dir / "app_info.json"

    with tempfile.TemporaryDirectory(prefix="plcnext-solution-app-") as tmp:
        stage = Path(tmp) / "stage"
        stage.mkdir(parents=True, exist_ok=True)
        (stage / "app_info.json").write_text(
            json.dumps(app_info, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        shutil.copytree(pcwe_dir, stage / "arp" / "PCWE")

        # Build SquashFS .app container via Linux/WSL mksquashfs
        if app_path.exists():
            app_path.unlink()

        if sys.platform == "win32":
            wsl_stage = win_to_wsl_path(stage)
            wsl_out = win_to_wsl_path(app_path)
            pack_sh = Path(tmp) / "pack.sh"
            pack_sh.write_text(
                "#!/bin/sh\n"
                "set -e\n"
                "d=$(mktemp -d /tmp/plcnext-app-XXXXXX)\n"
                "trap 'rm -rf \"$d\"' EXIT\n"
                f"cp -r '{wsl_stage}/.' \"$d/\"\n"
                "find \"$d\" -type d -exec chmod 755 {} +\n"
                "find \"$d\" -type f -exec chmod 644 {} +\n"
                "find \"$d\" -type f -name '*.so' -exec chmod 755 {} +\n"
                f"mksquashfs \"$d\" '{wsl_out}' -noappend -force-uid 1001 -force-gid 1002\n",
                encoding="utf-8",
                newline="\n",
            )
            cmd = ["wsl", "sh", win_to_wsl_path(pack_sh)]
        else:
            for p in stage.rglob("*"):
                if p.is_dir():
                    p.chmod(0o755)
                elif p.suffix == ".so":
                    p.chmod(0o755)
                else:
                    p.chmod(0o644)
            cmd = [
                "mksquashfs",
                str(stage),
                str(app_path),
                "-noappend",
                "-force-uid",
                "1001",
                "-force-gid",
                "1002",
            ]
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            raise RuntimeError(f"mksquashfs failed (exit {proc.returncode}): {proc.stderr or proc.stdout}")

        # Verify SquashFS listing via unsquashfs
        if sys.platform == "win32":
            list_cmd = ["wsl", "unsquashfs", "-ls", win_to_wsl_path(app_path)]
        else:
            list_cmd = ["unsquashfs", "-ls", str(app_path)]
        list_proc = subprocess.run(list_cmd, capture_output=True, text=True, check=False)
        if list_proc.returncode != 0:
            raise RuntimeError(f"unsquashfs verification failed: {list_proc.stderr or list_proc.stdout}")
        entries = [line.strip() for line in list_proc.stdout.splitlines() if line.strip().startswith("squashfs-root/")]

    info_copy_path.write_text(
        json.dumps(app_info, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    pcwe_files = sorted(p.relative_to(pcwe_dir).as_posix() for p in pcwe_dir.rglob("*") if p.is_file())
    summary = {
        "schema": "plcnext-solution-app-build/v1",
        "target": target,
        "version": version,
        "source_pcwe_dir": str(pcwe_dir),
        "app_file": str(app_path),
        "app_bytes": app_path.stat().st_size,
        "app_sha256": sha256_file(app_path),
        "app_info_file": str(info_copy_path),
        "app_identifier": app_id,
        "schema_validated": schema_validated,
        "pcwe_file_count": len(pcwe_files),
        "squashfs_entry_count": len(entries),
        "signed": False,
    }
    (dest_dir / "app-build-receipt.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=sorted(TARGET_PROFILES), required=True)
    parser.add_argument("--version", required=True, help="Frozen release version directory name, e.g. native-0.8.6")
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--schema", type=Path, default=None, help="Optional official app-info-schema.json path")
    parser.add_argument("--minfirmware", default=None)
    args = parser.parse_args()
    summary = package_solution_app(
        target=args.target,
        version=args.version,
        output_dir=args.output_dir,
        minfirmware_version=args.minfirmware,
        schema_path=args.schema,
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
