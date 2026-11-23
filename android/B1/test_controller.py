"""Device-free regression checks for B1's controller and original-state snapshot."""

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from controller import Controller


def profile():
    identity = json.loads(Path(__file__).with_name("identity.json").read_text())
    identity["settings"] = {
        "global": {"KEYCODE_BACK": "managed", "key_custom_side_key_short_press_enable": 0},
        "system": {"screen_off_timeout": 300000},
    }
    return identity


class FakeController(Controller):
    def __init__(self, mismatch=None):
        super().__init__("B1-test", profile())
        self.commands = []
        self.mismatch = mismatch

    def adb(self, *args):
        self.commands.append(args)
        return "device"

    def shell(self, *args):
        self.commands.append(args)
        if args[0] == "getprop":
            if args[1] == self.mismatch:
                return "unexpected"
            return self.profile["expectedProperties"].get(args[1], "")
        if args[0] == "uname":
            return self.profile["kernelPrefix"] + "+"
        if args[0] == "settings":
            return "null" if args[-1] == "KEYCODE_BACK" else "2147483647"
        if args[0] == "am":
            return "Broadcast completed: result=0"
        raise AssertionError(f"Unexpected command: {args}")


class ControllerTests(unittest.TestCase):
    def test_inspection_never_runs_nix_or_writes_settings(self):
        reader = FakeController()
        with patch("controller.subprocess.run") as run, redirect_stdout(io.StringIO()):
            self.assertEqual(reader.converge("inspect", "."), 0)
        run.assert_not_called()
        self.assertTrue(all(command[0] in ("get-state", "getprop", "uname") for command in reader.commands))

    def test_firmware_and_abi_mismatch_refuse_before_nix(self):
        for name in ("ro.build.fingerprint", "ro.product.cpu.abi"):
            with self.subTest(name=name), patch("controller.subprocess.run") as run:
                with self.assertRaisesRegex(RuntimeError, "identity mismatch"):
                    FakeController(mismatch=name).converge("apply", ".")
                run.assert_not_called()

    def test_plan_preserves_pending_change_exit_code_without_reload(self):
        reader = FakeController()
        with patch("controller.subprocess.run", return_value=subprocess.CompletedProcess([], 3)) as run:
            self.assertEqual(reader.converge("plan", "."), 3)
        self.assertIn("plan", run.call_args.args[0])
        self.assertFalse(any(command[0] in ("am", "settings") for command in reader.commands))

    def test_snapshot_preserves_original_unset_values_with_private_permissions(self):
        reader = FakeController()
        with tempfile.TemporaryDirectory() as state, patch.dict("os.environ", {"XDG_STATE_HOME": state}):
            snapshot = reader.snapshot(reader.verify())
            self.assertEqual(snapshot.stat().st_mode & 0o777, 0o600)
            self.assertEqual(snapshot.parent.stat().st_mode & 0o777, 0o700)
            data = json.loads(snapshot.read_text())
            self.assertEqual(data["settings"]["global"]["KEYCODE_BACK"], "null")
            self.assertEqual(data["serial"], "B1-test")

    def test_reload_only_after_successful_switch(self):
        for result in (0, 1, 4):
            reader = FakeController()
            with self.subTest(result=result), tempfile.TemporaryDirectory() as state, \
                    patch.dict("os.environ", {"XDG_STATE_HOME": state}), \
                    patch("controller.subprocess.run", return_value=subprocess.CompletedProcess([], result)) as run, \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(reader.converge("apply", "."), result)
                self.assertIn("switch", run.call_args.args[0])
                reloads = [command for command in reader.commands if command[0] == "am"]
                self.assertEqual(len(reloads), 1 if result == 0 else 0)

    def test_remote_argument_quoting(self):
        reader = Controller("B1-test", profile())
        with patch.object(reader, "adb") as adb:
            reader.shell("settings", "get", "global", "KEYCODE_BACK")
        adb.assert_called_once_with("shell", "settings get global KEYCODE_BACK")


if __name__ == "__main__":
    unittest.main()
