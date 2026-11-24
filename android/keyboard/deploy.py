"""Device-agnostic reconciler: pin Unexpected Keyboard's TLTR layout and make
it the default IME. Shared by android/B1/keyboard.py and android/M1/keyboard.py,
which each supply a `device` object exposing `.adb(*args)` and `.shell(*args)`
(see android/B1/controller.py's Controller for the shape expected here)."""

import json
from pathlib import Path
import shlex
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

PACKAGE = "juloo.keyboard2"
# Registered with the relative class name (`ime list` shows it this way); the
# fully-qualified form is rejected by `ime set` as an unknown input method.
IME_ID = f"{PACKAGE}/.Keyboard2"
PREFS = f"/data/data/{PACKAGE}/shared_prefs/{PACKAGE}_preferences.xml"
PREF_KEY = "layouts"


class AdbDevice:
    def __init__(self, serial):
        self.serial = serial

    def adb(self, *args):
        return subprocess.run(
            ["adb", "-s", self.serial, *args], check=True,
            capture_output=True, text=True,
        ).stdout.strip()

    def shell(self, *args):
        return self.adb("shell", shlex.join(args))


def root_shell(device, *args):
    return device.shell("su", "-c", shlex.join(args))


def require_root(device):
    try:
        uid = root_shell(device, "id", "-u")
    except subprocess.CalledProcessError as error:
        raise RuntimeError("Grant this shell root access (Magisk or KernelSU) first") from error
    if uid != "0":
        raise RuntimeError("su did not grant root to the ADB shell")


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

    directory = None
    try:
        directory = device.shell("mktemp", "-d", "/data/local/tmp/android-keyboard.XXXXXXXX")
        remote = directory + "/prefs.xml"
        device.adb("push", str(path), remote)
        parent = str(Path(PREFS).parent)
        root_shell(device, "mkdir", "-p", parent)
        root_shell(device, "chown", f"{uid}:{uid}", parent)
        root_shell(device, "chmod", "771", parent)
        root_shell(device, "restorecon", "-v", parent)
        root_shell(device, "cp", remote, PREFS)
        root_shell(device, "chown", f"{uid}:{uid}", PREFS)
        root_shell(device, "chmod", "660", PREFS)
        root_shell(device, "restorecon", "-v", PREFS)
    finally:
        path.unlink()
        if directory is not None:
            device.shell("rm", "-rf", directory)


def secure_setting(device, name):
    return device.shell("settings", "get", "secure", name)


def ime_enabled(device):
    raw = secure_setting(device, "enabled_input_methods")
    return IME_ID in {entry.split(";", 1)[0] for entry in raw.split(":")}


def reconcile(device, layout_xml, apply):
    if device.shell("am", "get-current-user") != "0":
        raise RuntimeError("Switch to Android's owner user (0) first")
    try:
        if not device.shell("pm", "path", PACKAGE).startswith("package:"):
            raise RuntimeError(f"{PACKAGE} is not installed; install Unexpected Keyboard first")
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"{PACKAGE} is not installed; install Unexpected Keyboard first") from error
    uid = root_shell(device, "stat", "-c", "%u", f"/data/data/{PACKAGE}")

    _, current = read_prefs(device)
    needs_layout = not matches(current, layout_xml)
    needs_ime = not ime_enabled(device)
    needs_default = secure_setting(device, "default_input_method") != IME_ID

    print(f"layout: {'install pinned TLTR XML' if needs_layout else 'matches'}")
    print(f"ime: {'enable' if needs_ime else 'already enabled'}")
    print(f"default ime: {'switch to Unexpected Keyboard' if needs_default else 'already default'}")

    if not apply:
        return 3 if (needs_layout or needs_ime or needs_default) else 0

    if needs_layout:
        device.shell("am", "force-stop", PACKAGE)
        root, _ = read_prefs(device)
        write_prefs(device, root, layout_xml, uid)
        _, verify_current = read_prefs(device)
        if not matches(verify_current, layout_xml):
            raise RuntimeError("Layout preference does not match after writing")
        print("layout: verified")
    if not ime_enabled(device):
        device.shell("ime", "enable", IME_ID)
    active_ime = secure_setting(device, "default_input_method")
    if active_ime != IME_ID:
        # InputMethodManagerService refreshes its enabled-method cache from a
        # ContentObserver on the settings key `ime enable` just wrote; an
        # immediate `ime set` can race that and report the id as unknown.
        for attempt in range(5):
            device.shell("ime", "set", IME_ID)
            active_ime = secure_setting(device, "default_input_method")
            if active_ime == IME_ID:
                break
            if attempt < 4:
                time.sleep(1)
    if active_ime != IME_ID:
        raise RuntimeError(f"Expected default IME {IME_ID!r}, got {active_ime!r}")
    if not ime_enabled(device):
        raise RuntimeError("Unexpected Keyboard is not enabled after applying")
    print("ime: verified")
    return 0
