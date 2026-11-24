"""Plan or apply the pinned Magisk modules declared for B1."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
from zipfile import BadZipFile, ZipFile

from controller import Controller

ACTIVE = "/data/adb/modules"
STAGED = "/data/adb/modules_update"
RECEIPT = ".infra-nixcfg-sha256"


def root_shell(device, *args):
    return device.shell("su", "-c", shlex.join(args))


def module_state(device, module_id):
    active = f"{ACTIVE}/{module_id}"
    staged = f"{STAGED}/{module_id}"
    output = root_shell(device, "sh", "-c", f"""
        target={active}
        if [ -d {staged} ]; then
            target={staged}
            echo staged
        fi
        for marker in disable remove update; do
            if [ -e {active}/"$marker" ]; then echo "$marker"; fi
        done
        if [ -f "$target/{RECEIPT}" ]; then cat "$target/{RECEIPT}"; fi
    """)
    return set(output.splitlines())


def install(device, module_id, archive, digest):
    directory = device.shell("mktemp", "-d", "/data/local/tmp/b1-magisk.XXXXXXXX")
    remote = directory + "/module.zip"
    try:
        device.adb("push", str(archive), remote)
        if device.shell("sha256sum", remote).split()[0] != digest:
            raise RuntimeError(f"{module_id}: transferred module checksum mismatch")
        print(root_shell(device, "magisk", "--install-module", remote), flush=True)
        target = f"{STAGED}/{module_id}"
        root_shell(device, "test", "-f", f"{target}/module.prop")
        root_shell(device, "sh", "-c", f"printf '%s\\n' {digest} > {target}/{RECEIPT}")
    finally:
        device.shell("rm", "-f", remote)
        device.shell("rmdir", directory)


def reconcile(device, modules, apply):
    pending = False
    for module_id, archive, digest, enabled in modules:
        current = module_state(device, module_id)
        needs_install = digest not in current or "remove" in current
        needs_toggle = enabled == ("disable" in current)
        if needs_install:
            print(f"{module_id}: install pinned archive ({'enabled' if enabled else 'disabled'})")
        elif needs_toggle:
            print(f"{module_id}: {'enable' if enabled else 'disable'}")
        elif "staged" in current or "update" in current:
            print(f"{module_id}: staged, reboot required")
        else:
            print(f"{module_id}: matches")
        pending |= needs_install or needs_toggle
        if not apply or not (needs_install or needs_toggle):
            continue
        if needs_install:
            install(device, module_id, archive, digest)
        marker = f"{ACTIVE}/{module_id}/disable"
        root_shell(device, "rm", "-f", marker) if enabled else root_shell(device, "touch", marker)
        root_shell(device, "touch", f"{ACTIVE}/{module_id}/update")
        result = module_state(device, module_id)
        if digest not in result or enabled == ("disable" in result) or "remove" in result:
            raise RuntimeError(f"{module_id}: post-apply state does not match the declaration")
        print(f"{module_id}: verified, reboot to activate changes")
    return 3 if pending and not apply else 0


def read_manifest(path):
    modules = []
    for module_id, entry in json.loads(path.read_text()).items():
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9._-]+", module_id):
            raise ValueError(f"Invalid Magisk module ID: {module_id!r}")
        if not isinstance(entry["enable"], bool):
            raise ValueError(f"{module_id}: enable must be true or false")
        archive = Path(entry["archive"])
        with ZipFile(archive) as zipped:
            ids = [line.removeprefix("id=") for line in zipped.read("module.prop").decode().splitlines()
                   if line.startswith("id=")]
        if ids != [module_id]:
            raise ValueError(f"{archive}: module.prop ID does not match {module_id}")
        modules.append((module_id, archive, hashlib.sha256(archive.read_bytes()).hexdigest(), entry["enable"]))
    return modules


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("command", choices=("plan", "apply"), nargs="?", default="plan")
    args = parser.parse_args()
    modules = read_manifest(args.manifest)
    device = Controller(args.serial, json.loads(args.profile.read_text()))
    device.verify()
    try:
        uid = root_shell(device, "id", "-u")
    except subprocess.CalledProcessError as error:
        raise RuntimeError("Grant Shell superuser access in Magisk before running this command") from error
    if uid != "0":
        raise RuntimeError("Magisk did not grant root to the ADB shell")
    return reconcile(device, modules, args.command == "apply")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        print(f"B1 Magisk: {error.stderr.strip() or error}", file=sys.stderr)
        sys.exit(1)
    except (BadZipFile, OSError, ValueError, RuntimeError, KeyError) as error:
        print(f"B1 Magisk: {error}", file=sys.stderr)
        sys.exit(1)
