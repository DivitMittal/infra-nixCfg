"""Device-free regression checks for the declarative Unexpected Keyboard deploy."""

from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

import keyboard
from controller import Controller

LAYOUT = Path(__file__).with_name("keyboard") / "layout.xml"


class FakeDevice(Controller):
    def __init__(self, installed=True, ime_set_races=0):
        super().__init__("B1-test", {"expectedProperties": {}, "kernelPrefix": "", "observedProperties": []})
        self.commands = []
        self.installed = installed
        self.files = {}
        self.default_ime = "com.onyx/.inputmethod.OnyxIME"
        self.enabled_imes = ["com.onyx/.inputmethod.OnyxIME"]
        self.ime_set_races = ime_set_races

    def adb(self, *args):
        self.commands.append(args)
        if args[0] == "push":
            _, local, remote = args
            self.files[remote] = Path(local).read_bytes()
            return "1 file pushed"
        return "device"

    def shell(self, *args):
        self.commands.append(args)
        if args[:2] == ("pm", "path"):
            if not self.installed:
                raise subprocess.CalledProcessError(1, args)
            return "package:/data/app/juloo.keyboard2.apk"
        if args[0] == "ime" and args[1] == "list":
            return "\n".join(self.enabled_imes)
        if args[0] == "ime" and args[1] == "enable":
            self.enabled_imes.append(args[2])
            return ""
        if args[0] == "ime" and args[1] == "set":
            if self.ime_set_races > 0:
                self.ime_set_races -= 1
                return "Unknown input method ... cannot be selected for user #0"
            self.default_ime = args[2]
            return ""
        if args[:3] == ("settings", "get", "secure"):
            return self.default_ime
        if args[0] == "am":
            return ""
        if args[0] in ("mktemp", "rm"):
            return "/data/local/tmp/b1-keyboard.fake"
        if args[0] == "su":
            return self._root(args[2])
        raise AssertionError(f"Unexpected command: {args}")

    def _root(self, joined):
        import shlex

        args = shlex.split(joined)
        if args[0] == "id" and args[1] == "-u":
            return "0"
        if args[0] == "stat":
            return "10042"
        if args[0] == "mktemp":
            return "/data/local/tmp/b1-keyboard.fake"
        if args[0] == "mkdir" or args[0] == "chown" or args[0] == "chmod" or args[0] == "restorecon":
            return ""
        if args[0] == "sh" and args[1] == "-c":
            return "yes" if keyboard.PREFS in self.files else ""
        if args[0] == "cp":
            self.files[args[2]] = self.files.pop(args[1])
            return ""
        if args[0] == "cat":
            return self.files[args[1]].decode()
        raise AssertionError(f"Unexpected root command: {args}")


class KeyboardTests(unittest.TestCase):
    def test_refuses_without_the_app_installed(self):
        with self.assertRaisesRegex(RuntimeError, "is not installed"):
            keyboard.reconcile(FakeDevice(installed=False), LAYOUT.read_text(), False)

    def test_plan_is_read_only_and_reports_pending_changes(self):
        device = FakeDevice()
        self.assertEqual(keyboard.reconcile(device, LAYOUT.read_text(), False), 3)
        self.assertNotIn(keyboard.PREFS, device.files)
        self.assertEqual(device.default_ime, "com.onyx/.inputmethod.OnyxIME")

    def test_apply_installs_layout_and_switches_ime_then_matches_on_replay(self):
        device = FakeDevice()
        self.assertEqual(keyboard.reconcile(device, LAYOUT.read_text(), True), 0)
        self.assertIn(keyboard.PREFS, device.files)
        self.assertEqual(device.default_ime, keyboard.IME_ID)
        self.assertIn(keyboard.IME_ID, device.enabled_imes)
        self.assertEqual(keyboard.reconcile(device, LAYOUT.read_text(), False), 0)

    def test_apply_retries_ime_set_through_the_enable_cache_race(self):
        device = FakeDevice(ime_set_races=2)
        with patch("keyboard.time.sleep"):
            self.assertEqual(keyboard.reconcile(device, LAYOUT.read_text(), True), 0)
        self.assertEqual(device.default_ime, keyboard.IME_ID)

    def test_apply_gives_up_if_the_ime_set_race_never_resolves(self):
        device = FakeDevice(ime_set_races=99)
        with patch("keyboard.time.sleep"), self.assertRaisesRegex(RuntimeError, "Expected default IME"):
            keyboard.reconcile(device, LAYOUT.read_text(), True)

    def test_written_preference_round_trips_through_json_and_xml_escaping(self):
        device = FakeDevice()
        keyboard.reconcile(device, LAYOUT.read_text(), True)
        _, current = keyboard.read_prefs(device)
        self.assertEqual(current, keyboard.desired_layouts(LAYOUT.read_text()))


if __name__ == "__main__":
    unittest.main()
