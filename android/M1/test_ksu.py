"""Device-free checks for M1's KernelSU module planner."""

import hashlib
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

import ksu


class FakeDevice:
    def __init__(self, listed):
        self.commands = []
        self.digest = ""

    def adb(self, *args):
        self.commands.append(("adb", *args))
        return "device"

    def shell(self, *args):
        self.commands.append(args)
        if args[0] == "su":
            return "0" if args[1:] == ("-c", "id -u") else ""
        if args[:2] == ("mktemp", "-d"):
            return "/data/local/tmp/m1-ksu.test"
        if args[0] == "sha256sum":
            return self.digest
        if args[0] == "getprop":
            return {"ro.product.model": "DN2103", "ro.product.device": "denniz"}[args[1]]
        return ""


def manifest(directory, enabled=True):
    archive = Path(directory) / "module.zip"
    with ZipFile(archive, "w") as zipped:
        zipped.writestr("module.prop", "id=example-module\n")
    path = Path(directory) / "manifest.json"
    path.write_text(json.dumps({"example-module": {"archive": str(archive), "enable": enabled}}), encoding="utf-8")
    return path


class KsuTests(unittest.TestCase):
    def test_plan_reports_missing_module_without_installing(self):
        device = FakeDevice([])
        declared = [("example-module", Path("archive.zip"), "abc", True)]
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(ksu.reconcile(device, declared, False), 3)
        self.assertIn("install pinned archive", output.getvalue())
        self.assertFalse(any("ksud module install" in " ".join(command) for command in device.commands))

    def test_apply_uses_ksud_and_records_receipt(self):
        device = FakeDevice([])
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "module.zip"
            archive.write_bytes(b"pinned")
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            device.digest = digest
            with redirect_stdout(io.StringIO()):
                with patch("ksu.modules", side_effect=({}, {"example-module": {"id": "example-module", "enabled": True}})), \
                     patch("ksu.receipt", side_effect=(None, None, digest)):
                    self.assertEqual(ksu.reconcile(device, [("example-module", archive, digest, True)], True), 0)
        self.assertTrue(any("ksud module install" in " ".join(command) for command in device.commands))
        self.assertTrue(any("ksud module enable" in " ".join(command) for command in device.commands))

    def test_parses_string_booleans_from_resukisu(self):
        raw = json.dumps([{"id": "example-module", "enabled": "true", "remove": "false", "update": "false"}])
        device = FakeDevice([])
        with patch("ksu.ksu", return_value=raw):
            self.assertEqual(ksu.modules(device)["example-module"]["enabled"], "true")
        declared = [("example-module", Path("archive.zip"), "abc", True)]
        with patch("ksu.modules", return_value={"example-module": json.loads(raw)[0]}), patch("ksu.receipt", return_value="abc"):
            self.assertEqual(ksu.reconcile(device, declared, False), 0)

    def test_identity_mismatch_stops_before_root(self):
        device = FakeDevice([])
        with tempfile.TemporaryDirectory() as directory, patch("sys.argv", ["ksu.py", "--manifest", str(manifest(directory)), "--serial", "M1", "plan"]), \
             patch("ksu.deploy.AdbDevice", return_value=device), patch("ksu.deploy.require_root") as root:
            device.shell = lambda *args: "wrong" if args[:1] == ("getprop",) else FakeDevice.shell(device, *args)
            with self.assertRaisesRegex(RuntimeError, "identity mismatch"):
                ksu.main()
        root.assert_not_called()


if __name__ == "__main__":
    unittest.main()
