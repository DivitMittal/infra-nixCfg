"""Verify the M1 CLI cannot reconcile B1 or an unauthorized device."""

import unittest
from unittest.mock import Mock

import keyboard


class IdentityTests(unittest.TestCase):
    def test_accepts_m1(self):
        device = Mock()
        device.adb.return_value = "device"
        device.shell.side_effect = ["DN2103", "denniz"]
        keyboard.verify(device)

    def test_rejects_b1(self):
        device = Mock()
        device.adb.return_value = "device"
        device.shell.return_value = "C69_M_STAR"
        with self.assertRaisesRegex(RuntimeError, "identity mismatch"):
            keyboard.verify(device)

    def test_rejects_unauthorized_device(self):
        device = Mock()
        device.adb.return_value = "unauthorized"
        with self.assertRaisesRegex(RuntimeError, "authorize"):
            keyboard.verify(device)
        device.shell.assert_not_called()
