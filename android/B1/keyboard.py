"""Plan or apply the pinned Unexpected Keyboard layout and make it B1's IME."""

import argparse
import json
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

from controller import Controller

PACKAGE = "juloo.keyboard2"
# Registered with the relative class name (`ime list` shows it this way); the
# fully-qualified form is rejected by `ime set` as an unknown input method.
IME_ID = f"{PACKAGE}/.Keyboard2"
PREFS = f"/data/data/{PACKAGE}/shared_prefs/{PACKAGE}_preferences.xml"
PREF_KEY = "layouts"


def root_shell(device, *args):
    return device.shell("su", "-c", shlex.join(args))


def desired_layouts(layout_xml):
    return [{"kind": "custom", "xml": layout_xml}]


def read_prefs(device):
    exists = root_shell(device, "sh", "-c", f'if [ -f "{PREFS}" ]; then echo yes; fi') == "yes"
    if not exists:
        return ET.Element("map"), None
    content = root_shell(device, "cat", PREFS)
    root = ET.fromstring(content)
    current = root.find(f"./string[@name='{PREF_KEY}']")
    return root, (json.loads(current.text) if current is not None else None)


def matches(current, layout_xml):
    return current == desired_layouts(layout_xml)


def write_prefs(device, root, layout_xml, uid):
    element = root.find(f"./string[@name='{PREF_KEY}']")
    if element is None:
        element = ET.SubElement(root, "string", {"name": PREF_KEY})
    element.text = json.dumps(desired_layouts(layout_xml), ensure_ascii=False)
    with tempfile.NamedTemporaryFile("wb", suffix=".xml", delete=False) as local:
        local.write(b"<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n")
        ET.ElementTree(root).write(local, encoding="utf-8")
        path = Path(local.name)

    directory = device.shell("mktemp", "-d", "/data/local/tmp/b1-keyboard.XXXXXXXX")
    remote = directory + "/prefs.xml"
    try:
        device.adb("push", str(path), remote)
        root_shell(device, "mkdir", "-p", str(Path(PREFS).parent))
        root_shell(device, "cp", remote, PREFS)
        root_shell(device, "chown", f"{uid}:{uid}", PREFS)
        root_shell(device, "chmod", "660", PREFS)
        root_shell(device, "restorecon", "-v", PREFS)
    finally:
        device.shell("rm", "-rf", directory)
        path.unlink()


def reconcile(device, layout_xml, apply):
    try:
        device.shell("pm", "path", PACKAGE)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"{PACKAGE} is not installed; run android-rebuild first") from error
    uid = root_shell(device, "stat", "-c", "%u", f"/data/data/{PACKAGE}")

    root, current = read_prefs(device)
    needs_layout = not matches(current, layout_xml)
    enabled_imes = device.shell("ime", "list", "-s", "-a")
    needs_ime = IME_ID not in enabled_imes
    active_ime = device.shell("settings", "get", "secure", "default_input_method")
    needs_default = active_ime != IME_ID

    print(f"layout: {'install pinned TLTR XML' if needs_layout else 'matches'}")
    print(f"ime: {'enable' if needs_ime else 'already enabled'}")
    print(f"default ime: {'switch to Unexpected Keyboard' if needs_default else 'already default'}")

    if not apply:
        return 3 if (needs_layout or needs_ime or needs_default) else 0

    if needs_layout:
        write_prefs(device, root, layout_xml, uid)
        device.shell("am", "force-stop", PACKAGE)
        _, verify_current = read_prefs(device)
        if not matches(verify_current, layout_xml):
            raise RuntimeError("Layout preference does not match after writing")
        print("layout: verified")
    if needs_ime:
        device.shell("ime", "enable", IME_ID)
    if needs_default:
        # InputMethodManagerService refreshes its enabled-method cache from a
        # ContentObserver on the settings key `ime enable` just wrote; an
        # immediate `ime set` can race that and report the id as unknown.
        for attempt in range(5):
            device.shell("ime", "set", IME_ID)
            if device.shell("settings", "get", "secure", "default_input_method") == IME_ID:
                break
            time.sleep(1)
    active_ime = device.shell("settings", "get", "secure", "default_input_method")
    if active_ime != IME_ID:
        raise RuntimeError(f"Expected default IME {IME_ID!r}, got {active_ime!r}")
    print("ime: verified")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("command", choices=("plan", "apply"), nargs="?", default="plan")
    args = parser.parse_args()
    device = Controller(args.serial, json.loads(args.profile.read_text()))
    device.verify()
    try:
        uid = root_shell(device, "id", "-u")
    except subprocess.CalledProcessError as error:
        raise RuntimeError("Grant Shell superuser access in Magisk before running this command") from error
    if uid != "0":
        raise RuntimeError("Magisk did not grant root to the ADB shell")
    return reconcile(device, args.layout.read_text(), args.command == "apply")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        print(f"B1 keyboard: {error.stderr.strip() or error}", file=sys.stderr)
        sys.exit(1)
    except (ET.ParseError, OSError, ValueError, RuntimeError, KeyError) as error:
        print(f"B1 keyboard: {error}", file=sys.stderr)
        sys.exit(1)
