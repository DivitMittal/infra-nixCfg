"""B1-specific CLI wiring and stock keyboard safeguards."""

from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

import deploy
import keyboard
from test_controller import FakeController


LAYOUT = Path(deploy.__file__).with_name("layout.xml")


class RootAwareFakeController(FakeController):
    def __init__(self, mismatch=None, rooted=True, user="0", packages=(),
                 enabled=deploy.IME_ID, default=deploy.IME_ID, stuck=False):
        super().__init__(mismatch=mismatch)
        self.rooted = rooted
        self.user = user
        self.packages = set(packages)
        self.enabled = enabled
        self.default = default
        self.stuck = stuck

    def shell(self, *args):
        if args == ("am", "get-current-user"):
            return self.user
        if args[0] == "su":
            if not self.rooted:
                raise subprocess.CalledProcessError(1, args)
            return "0"
        if args == ("pm", "list", "packages", "-e", "--user", "0"):
            return "\n".join(f"package:{package}" for package in self.packages)
        if args == ("settings", "get", "secure", "enabled_input_methods"):
            return self.enabled
        if args == ("settings", "get", "secure", "default_input_method"):
            return self.default
        if args[:4] == ("pm", "disable-user", "--user", "0"):
            self.commands.append(args)
            if not self.stuck:
                self.packages.remove(args[4])
            return ""
        return super().shell(*args)

    @property
    def disabled(self):
        return [command[-1] for command in self.commands if command[:2] == ("pm", "disable-user")]


def run_main(command, device=None, **controller_kwargs):
    profile_path = Path(__file__).with_name("identity.json")
    with patch.object(keyboard, "Controller", return_value=device or RootAwareFakeController(**controller_kwargs)), \
            patch.object(sys, "argv", ["b1-keyboard", "--profile", str(profile_path),
                                       "--layout", str(LAYOUT), "--serial", "B1-test", command]):
        return keyboard.main()


class KeyboardCliTests(unittest.TestCase):
    def test_refuses_before_reconcile_on_firmware_mismatch(self):
        with patch.object(deploy, "reconcile") as reconcile:
            with self.assertRaisesRegex(RuntimeError, "identity mismatch"):
                run_main("plan", mismatch="ro.build.fingerprint")
        reconcile.assert_not_called()

    def test_refuses_before_reconcile_without_root(self):
        with patch.object(deploy, "reconcile") as reconcile:
            with self.assertRaisesRegex(RuntimeError, "root access"):
                run_main("plan", rooted=False)
        reconcile.assert_not_called()

    def test_plumbs_the_layout_file_into_the_shared_reconciler(self):
        with patch.object(deploy, "reconcile", return_value=0) as reconcile:
            self.assertEqual(run_main("apply"), 0)
        device, layout_text, apply = reconcile.call_args.args
        self.assertEqual(layout_text, LAYOUT.read_text())
        self.assertTrue(apply)

    def test_non_owner_refuses_before_shared_reconciliation(self):
        device = RootAwareFakeController(user="10", packages=keyboard.STOCK_PACKAGES)
        with patch.object(deploy, "reconcile") as reconcile:
            with self.assertRaisesRegex(RuntimeError, "owner user"):
                run_main("apply", device)
        reconcile.assert_not_called()
        self.assertEqual(device.disabled, [])

    def test_plan_reports_stock_and_shared_drift_without_disabling(self):
        for stock, shared, expected in [((), 0, 0), ((), 3, 3), (keyboard.STOCK_PACKAGES, 0, 3)]:
            with self.subTest(stock=stock, shared=shared):
                device = RootAwareFakeController(packages=stock)
                with patch.object(deploy, "reconcile", return_value=shared) as reconcile:
                    self.assertEqual(run_main("plan", device), expected)
                self.assertFalse(reconcile.call_args.args[2])
                self.assertEqual(device.disabled, [])

    def test_apply_disables_only_present_enabled_stock_after_reconciliation(self):
        for stock in [(keyboard.STOCK_PACKAGES[0],), keyboard.STOCK_PACKAGES]:
            with self.subTest(stock=stock):
                unrelated = "com.onyx.kime.other"
                device = RootAwareFakeController(packages=(*stock, unrelated), enabled="", default="null")

                def reconcile(device, layout_text, apply):
                    self.assertTrue(apply)
                    device.enabled = device.default = deploy.IME_ID
                    return 0

                with patch.object(deploy, "reconcile", side_effect=reconcile):
                    self.assertEqual(run_main("apply", device), 0)
                    self.assertEqual(run_main("apply", device), 0)
                self.assertEqual(device.disabled, list(stock))
                self.assertEqual(device.packages, {unrelated})

    def test_apply_rejects_unverified_replacement(self):
        for state in ({"enabled": deploy.IME_ID + "Other"}, {"default": "null"}):
            with self.subTest(state=state):
                device = RootAwareFakeController(packages=keyboard.STOCK_PACKAGES, **state)
                with patch.object(deploy, "reconcile", return_value=0):
                    with self.assertRaisesRegex(RuntimeError, "must be enabled and default"):
                        run_main("apply", device)
                self.assertEqual(device.disabled, [])

    def test_apply_stops_after_reported_reconcile_failure(self):
        device = RootAwareFakeController(packages=keyboard.STOCK_PACKAGES)
        with patch.object(deploy, "reconcile", return_value=1):
            self.assertEqual(run_main("apply", device), 1)
        self.assertEqual(device.disabled, [])

    def test_apply_stops_if_disable_does_not_take_effect(self):
        device = RootAwareFakeController(packages=keyboard.STOCK_PACKAGES, stuck=True)
        with patch.object(deploy, "reconcile", return_value=0):
            with self.assertRaisesRegex(RuntimeError, "still enabled"):
                run_main("apply", device)
        self.assertEqual(device.disabled, [keyboard.STOCK_PACKAGES[0]])


if __name__ == "__main__":
    unittest.main()
