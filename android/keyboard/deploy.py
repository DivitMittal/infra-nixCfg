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
# Unexpected Keyboard 2.2.1 uses credential storage in SettingsActivity and
# device-protected storage in the IME (DirectBootAwarePreferences, API 24+).
PREF_NAME = f"shared_prefs/{PACKAGE}_preferences.xml"
SETTINGS_PREFS = f"/data/user/0/{PACKAGE}/{PREF_NAME}"
IME_PREFS = f"/data/user_de/0/{PACKAGE}/{PREF_NAME}"
PREF_STORES = {"settings": SETTINGS_PREFS, "live keyboard": IME_PREFS}
PREF_KEY = "layouts"
CONFIG_VERSION = "4"


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


def read_prefs(device, prefs):
    exists = root_shell(device, "sh", "-c", f'if [ -f "{prefs}" ]; then echo yes; fi') == "yes"
    if not exists:
        return ET.Element("map"), None
    content = root_shell(device, "cat", prefs)
    root = ET.fromstring(content)
    current = root.find(f"./string[@name='{PREF_KEY}']")
    return root, (json.loads(current.text) if current is not None else None)


def matches(current, layout_xml):
    return current == desired_layouts(layout_xml)


def needs_initialization(root):
    return root.find("./int[@name='version']") is None


def write_prefs(device, prefs, root, layout_xml, uid):
    if needs_initialization(root):
        # A fresh store or a store written by our old deployer has no schema
        # version. Without this, the app would replace layouts during migration.
        ET.SubElement(root, "int", {"name": "version", "value": CONFIG_VERSION})
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
        parent = str(Path(prefs).parent)
        root_shell(device, "mkdir", "-p", parent)
        root_shell(device, "chown", f"{uid}:{uid}", parent)
        root_shell(device, "chmod", "771", parent)
        root_shell(device, "restorecon", "-v", parent)
        root_shell(device, "cp", remote, prefs)
        root_shell(device, "chown", f"{uid}:{uid}", prefs)
        root_shell(device, "chmod", "660", prefs)
        root_shell(device, "restorecon", "-v", prefs)
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
    if ET.fromstring(layout_xml).tag != "keyboard":
        raise ValueError("Expected an Unexpected Keyboard <keyboard> layout")
    if device.shell("am", "get-current-user") != "0":
        raise RuntimeError("Switch to Android's owner user (0) first")
    try:
        if not device.shell("pm", "path", PACKAGE).startswith("package:"):
            raise RuntimeError(f"{PACKAGE} is not installed; install Unexpected Keyboard first")
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"{PACKAGE} is not installed; install Unexpected Keyboard first") from error
    uid = root_shell(device, "stat", "-c", "%u", f"/data/data/{PACKAGE}")

    stores = {label: read_prefs(device, prefs) for label, prefs in PREF_STORES.items()}
    pending = {label for label, (root, current) in stores.items()
               if needs_initialization(root) or not matches(current, layout_xml)}
    needs_ime = not ime_enabled(device)
    needs_default = secure_setting(device, "default_input_method") != IME_ID

    for label in stores:
        print(f"layout ({label}): {'install pinned TLTR XML' if label in pending else 'matches'}")
    print(f"ime: {'enable' if needs_ime else 'already enabled'}")
    print(f"default ime: {'switch to Unexpected Keyboard' if needs_default else 'already default'}")

    if not apply:
        return 3 if (pending or needs_ime or needs_default) else 0

    if pending:
        device.shell("am", "force-stop", PACKAGE)
        stores = {label: read_prefs(device, prefs) for label, prefs in PREF_STORES.items()}
        for label, (root, _) in stores.items():
            version = root.find("./int[@name='version']")
            has_legacy_config = any(e.tag != "string" or e.get("name") != PREF_KEY for e in root)
            if (version is None and has_legacy_config) or (version is not None and version.get("value") == "0"):
                raise RuntimeError(f"Open Unexpected Keyboard settings once to migrate the {label} preferences before applying")
        for label, prefs in PREF_STORES.items():
            root, current = stores[label]
            if needs_initialization(root) or not matches(current, layout_xml):
                write_prefs(device, prefs, root, layout_xml, uid)
        for label, prefs in PREF_STORES.items():
            root, verify_current = read_prefs(device, prefs)
            if needs_initialization(root) or not matches(verify_current, layout_xml):
                raise RuntimeError(f"Layout preference does not match in {label} after writing")
            print(f"layout ({label}): verified")
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
