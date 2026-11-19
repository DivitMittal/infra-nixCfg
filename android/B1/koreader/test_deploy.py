"""Check deployment gates, transfer ordering and rollback without invoking ADB."""

from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from deploy import MANAGED, Reader


class FakeReader(Reader):
    def __init__(self, running=False, official=True, fail=None):
        super().__init__("reader-test", "/sdcard/koreader")
        self.commands = []
        self.running = running
        self.official = official
        self.fail = fail

    def adb(self, *args, check=True):
        self.commands.append(args)
        if args[0] == "get-state":
            return subprocess.CompletedProcess(args, 0, "device\n", "")
        if args[0] == "push" and self.fail == "push":
            raise subprocess.CalledProcessError(1, args)
        return subprocess.CompletedProcess(args, 0, "", "")

    def shell(self, *args, check=True):
        self.commands.append(args)
        if args[:2] == ("pm", "path"):
            output = "package:/data/app/koreader.apk\n" if self.official else ""
            return subprocess.CompletedProcess(args, 0, output, "")
        if args[0] == "pidof":
            return subprocess.CompletedProcess(args, 0 if self.running else 1, "42\n" if self.running else "", "")
        if args[0] == "mv" and self.fail == "replace" and "/.b1-stage-" in args[1] and args[1].endswith("settings/b1.lua"):
            self.fail = None  # a transient failure: allow rollback commands through
            raise subprocess.CalledProcessError(1, args)
        return subprocess.CompletedProcess(args, 0, "", "")


class DeployTests(unittest.TestCase):
    def test_preflight_is_read_only_and_requires_official_stopped_app(self):
        reader = FakeReader()
        reader.preflight()
        self.assertTrue(all(command[0] in ("get-state", "pm", "pidof", "test") for command in reader.commands))
        with self.assertRaisesRegex(RuntimeError, "Exit KOReader"):
            FakeReader(running=True).preflight()
        with self.assertRaisesRegex(RuntimeError, "official GitHub"):
            FakeReader(official=False).preflight()

    def test_all_transfers_complete_before_replacing_managed_paths(self):
        reader = FakeReader()
        reader.deploy(Path("/bundle"))
        pushes = [i for i, command in enumerate(reader.commands) if command[0] == "push"]
        moves = [i for i, command in enumerate(reader.commands) if command[0] == "mv"]
        self.assertEqual(len(pushes), len(MANAGED))
        self.assertLess(max(pushes), min(moves))
        self.assertTrue(any(command[0] == "sh" and "sha256sum" in command[2] for command in reader.commands))

    def test_transfer_failure_does_not_replace_live_files(self):
        reader = FakeReader(fail="push")
        with self.assertRaises(subprocess.CalledProcessError):
            reader.deploy(Path("/bundle"))
        self.assertFalse(any(command[0] in ("mv", "rm") for command in reader.commands))

    def test_failed_replacement_restores_both_previous_files(self):
        reader = FakeReader(fail="replace")
        with self.assertRaisesRegex(RuntimeError, "Managed paths restored"):
            reader.deploy(Path("/bundle"))
        restored = [command[2] for command in reader.commands if command[0] == "mv" and "/.b1-backups/" in command[1]]
        self.assertEqual(set(restored), {reader.root + "/" + name for name in MANAGED[:2]})

    def test_remote_arguments_are_shell_quoted(self):
        reader = Reader("serial", "/sdcard/koreader")
        with patch.object(reader, "adb") as adb:
            reader.shell("test", "-e", "/sdcard/koreader/a b;echo bad")
        adb.assert_called_once_with("shell", "test -e '/sdcard/koreader/a b;echo bad'", check=True)


if __name__ == "__main__":
    unittest.main()
