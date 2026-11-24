"""Device-free regression checks for the shared Unexpected Keyboard reconciler."""

from pathlib import Path
import shlex
import subprocess
import unittest
from unittest.mock import patch

import deploy

LAYOUT = Path(__file__).with_name("layout.xml")


class FakeDevice:
    """A minimal device: only .adb() and .shell(), as deploy.reconcile needs."""

    def __init__(self, installed=True, ime_set_races=0):
        self.commands = []
        self.installed = installed
        self.files = {}
        self.default_ime = "com.onyx/.inputmethod.OnyxIME"
        self.enabled_imes = ["com.onyx/.inputmethod.OnyxIME"]
        self.ime_set_races = ime_set_races
        self.user = "0"

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
        if args[0] == "ime" and args[1] == "enable":
            self.enabled_imes.append(args[2])
            return ""
        if args[0] == "ime" and args[1] == "set":
            if self.ime_set_races > 0:
                self.ime_set_races -= 1
                return "Unknown input method ... cannot be selected for user #0"
            self.default_ime = args[2]
            return ""
        if args == ("settings", "get", "secure", "enabled_input_methods"):
            return ":".join(self.enabled_imes)
        if args == ("settings", "get", "secure", "default_input_method"):
            return self.default_ime
        if args == ("am", "get-current-user"):
            return self.user
        if args[0] == "am":
            return ""
        if args[0] in ("mktemp", "rm"):
            return "/data/local/tmp/android-keyboard.fake"
        if args[0] == "su":
            return self._root(args[2])
        raise AssertionError(f"Unexpected command: {args}")

    def _root(self, joined):
        args = shlex.split(joined)
        if args[0] == "id" and args[1] == "-u":
            return "0"
        if args[0] == "stat":
            return "10042"
        if args[0] == "mktemp":
            return "/data/local/tmp/android-keyboard.fake"
        if args[0] in ("mkdir", "chown", "chmod", "restorecon"):
            return ""
        if args[0] == "sh" and args[1] == "-c":
            return "yes" if deploy.PREFS in self.files else ""
        if args[0] == "cp":
            self.files[args[2]] = self.files.pop(args[1])
            return ""
        if args[0] == "cat":
            return self.files[args[1]].decode()
        raise AssertionError(f"Unexpected root command: {args}")


class DeployTests(unittest.TestCase):
    def test_refuses_non_owner_without_touching_preferences(self):
        device = FakeDevice()
        device.user = "10"
        with self.assertRaisesRegex(RuntimeError, "owner user"):
            deploy.reconcile(device, LAYOUT.read_text(), True)
        self.assertEqual(device.commands, [("am", "get-current-user")])

    def test_enabled_ime_may_have_subtypes_but_requires_exact_id(self):
        device = FakeDevice()
        device.enabled_imes.append(deploy.IME_ID + "Extra")
        self.assertFalse(deploy.ime_enabled(device))
        device.enabled_imes.append(deploy.IME_ID + ";123")
        self.assertTrue(deploy.ime_enabled(device))

    def test_refuses_without_the_app_installed(self):
        with self.assertRaisesRegex(RuntimeError, "is not installed"):
            deploy.reconcile(FakeDevice(installed=False), LAYOUT.read_text(), False)

    def test_plan_is_read_only_and_reports_pending_changes(self):
        device = FakeDevice()
        self.assertEqual(deploy.reconcile(device, LAYOUT.read_text(), False), 3)
        self.assertNotIn(deploy.PREFS, device.files)
        self.assertEqual(device.default_ime, "com.onyx/.inputmethod.OnyxIME")

    def test_apply_installs_layout_and_switches_ime_then_matches_on_replay(self):
        device = FakeDevice()
        self.assertEqual(deploy.reconcile(device, LAYOUT.read_text(), True), 0)
        self.assertIn(deploy.PREFS, device.files)
        self.assertEqual(device.default_ime, deploy.IME_ID)
        self.assertIn(deploy.IME_ID, device.enabled_imes)
        self.assertEqual(deploy.reconcile(device, LAYOUT.read_text(), False), 0)

    def test_apply_retries_ime_set_through_the_enable_cache_race(self):
        device = FakeDevice(ime_set_races=2)
        with patch("deploy.time.sleep"):
            self.assertEqual(deploy.reconcile(device, LAYOUT.read_text(), True), 0)
        self.assertEqual(device.default_ime, deploy.IME_ID)

    def test_apply_gives_up_if_the_ime_set_race_never_resolves(self):
        device = FakeDevice(ime_set_races=99)
        with patch("deploy.time.sleep"), self.assertRaisesRegex(RuntimeError, "Expected default IME"):
            deploy.reconcile(device, LAYOUT.read_text(), True)

    def test_written_preference_round_trips_through_json_and_xml_escaping(self):
        device = FakeDevice()
        deploy.reconcile(device, LAYOUT.read_text(), True)
        _, current = deploy.read_prefs(device)
        self.assertEqual(current, deploy.desired_layouts(LAYOUT.read_text()))

    def test_require_root_reports_whichever_su_is_missing(self):
        device = FakeDevice()
        with patch.object(device, "shell", side_effect=subprocess.CalledProcessError(1, ["su"])):
            with self.assertRaisesRegex(RuntimeError, "root access"):
                deploy.require_root(device)


if __name__ == "__main__":
    unittest.main()
