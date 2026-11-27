"""Plan or apply M1's pinned KernelSU/ReSukiSU modules."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from zipfile import BadZipFile, ZipFile

import deploy


RECEIPT = ".infra-nixcfg-sha256"
MODULE_ID = re.compile(r"[A-Za-z][A-Za-z0-9._-]+")


def ksu(device, *args):
    return deploy.root_shell(device, "ksud", *args)


def modules(device):
    raw = ksu(device, "module", "list")
    try:
        listed = json.loads(raw or "[]")
    except json.JSONDecodeError as error:
        raise RuntimeError("ksud module list did not return JSON") from error
    if not isinstance(listed, list):
        raise RuntimeError("ksud module list did not return a module array")
    result = {}
    for entry in listed:
        module_id = entry.get("id")
        if not isinstance(module_id, str) or not MODULE_ID.fullmatch(module_id):
            raise RuntimeError(f"Invalid module ID from ksud: {module_id!r}")
        result[module_id] = entry
    return result


def receipt(device, module_id):
    path = f"/data/adb/modules/{module_id}/{RECEIPT}"
    staged = f"/data/adb/modules_update/{module_id}/{RECEIPT}"
    output = deploy.root_shell(device, "sh", "-c", f"""
        if [ -f {staged} ]; then cat {staged}; elif [ -f {path} ]; then cat {path}; fi
    """)
    return output.splitlines()[0] if output else None


def install(device, module_id, archive, digest):
    directory = device.shell("mktemp", "-d", "/data/local/tmp/m1-ksu.XXXXXXXX")
    remote = directory + "/module.zip"
    try:
        device.adb("push", str(archive), remote)
        if device.shell("sha256sum", remote).split()[0] != digest:
            raise RuntimeError(f"{module_id}: transferred module checksum mismatch")
        print(ksu(device, "module", "install", remote), flush=True)
        if receipt(device, module_id) != digest:
            target = f"/data/adb/modules_update/{module_id}"
            deploy.root_shell(device, "test", "-f", f"{target}/module.prop")
            deploy.root_shell(device, "sh", "-c", f"printf '%s\\n' {digest} > {target}/{RECEIPT}")
    finally:
        device.shell("rm", "-f", remote)
        device.shell("rmdir", directory)


def flag(value, default=False):
    if isinstance(value, str):
        return value.lower() == "true"
    return default if value is None else bool(value)


def reconcile(device, declared, apply):
    installed = modules(device)
    pending = False
    for module_id, archive, digest, enabled in declared:
        current = installed.get(module_id, {})
        current_digest = receipt(device, module_id) if archive is not None else None
        needs_install = archive is not None and (current_digest != digest or flag(current.get("remove")))
        current_enabled = flag(current.get("enabled"), not flag(current.get("disable")))
        needs_toggle = bool(current) and enabled != current_enabled
        missing = module_id not in installed
        if missing and archive is None:
            print(f"{module_id}: missing from device")
        elif missing or needs_install:
            print(f"{module_id}: install pinned archive ({'enabled' if enabled else 'disabled'})")
        elif needs_toggle:
            print(f"{module_id}: {'enable' if enabled else 'disable'}")
        elif flag(current.get("update")):
            print(f"{module_id}: staged, reboot required")
        else:
            print(f"{module_id}: matches")
        pending |= (missing and archive is not None) or needs_install or needs_toggle
        if not apply or not ((missing and archive is not None) or needs_install or needs_toggle):
            continue
        if needs_install or (missing and archive is not None):
            install(device, module_id, archive, digest)
        if enabled:
            ksu(device, "module", "enable", module_id)
        else:
            ksu(device, "module", "disable", module_id)
        updated = modules(device).get(module_id, {})
        updated_enabled = flag(updated.get("enabled"), not flag(updated.get("disable")))
        if archive is not None and (receipt(device, module_id) != digest or updated_enabled != enabled):
            raise RuntimeError(f"{module_id}: post-apply state does not match the declaration")
        print(f"{module_id}: verified, reboot if KernelSU staged the module")
    return 3 if pending and not apply else 0


def read_manifest(path):
    declared = []
    for module_id, entry in json.loads(path.read_text(encoding="utf-8")).items():
        if not MODULE_ID.fullmatch(module_id) or not isinstance(entry.get("enable"), bool):
            raise ValueError(f"Invalid KernelSU declaration: {module_id}")
        archive = entry.get("archive")
        if archive is None:
            declared.append((module_id, None, None, entry["enable"]))
            continue
        archive = Path(archive)
        with ZipFile(archive) as zipped:
            ids = [line.removeprefix("id=") for line in zipped.read("module.prop").decode().splitlines() if line.startswith("id=")]
        if ids != [module_id]:
            raise ValueError(f"{archive}: module.prop ID does not match {module_id}")
        declared.append((module_id, archive, hashlib.sha256(archive.read_bytes()).hexdigest(), entry["enable"]))
    return declared


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("command", choices=("plan", "apply"), nargs="?", default="plan")
    args = parser.parse_args()
    declared = read_manifest(args.manifest)
    device = deploy.AdbDevice(args.serial)
    device.adb_path = args.adb
    if device.adb("get-state") != "device":
        raise RuntimeError("Unlock M1 and authorize USB debugging")
    for key, expected in {"ro.product.model": "DN2103", "ro.product.device": "denniz"}.items():
        actual = device.shell("getprop", key)
        if actual != expected:
            raise RuntimeError(f"M1 identity mismatch for {key}: expected {expected!r}, got {actual!r}")
    deploy.require_root(device)
    try:
        ksu(device, "debug", "version")
    except subprocess.CalledProcessError as error:
        raise RuntimeError("KernelSU/ReSukiSU ksud is not available to this rooted shell") from error
    return reconcile(device, declared, args.command == "apply")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        print(f"M1 KSU: {(error.stderr or '').strip() or error}", file=sys.stderr)
        sys.exit(1)
    except (BadZipFile, OSError, ValueError, RuntimeError, KeyError, json.JSONDecodeError) as error:
        print(f"M1 KSU: {error}", file=sys.stderr)
        sys.exit(1)
