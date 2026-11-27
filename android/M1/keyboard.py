"""Manage M1's system-wide Unexpected Keyboard, not Termux Launcher's keyboard."""

import argparse
from pathlib import Path
import subprocess
import sys
from xml.etree.ElementTree import ParseError

import deploy


def verify(device):
    if device.adb("get-state") != "device":
        raise RuntimeError("Unlock M1 and authorize this computer for USB debugging")
    for key, expected in {"ro.product.model": "DN2103", "ro.product.device": "denniz"}.items():
        actual = device.shell("getprop", key)
        if actual != expected:
            raise RuntimeError(f"M1 identity mismatch for {key}: expected {expected!r}, got {actual!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("command", choices=("plan", "apply"), nargs="?", default="plan")
    args = parser.parse_args()
    device = deploy.AdbDevice(args.serial)
    verify(device)
    deploy.require_root(device)
    return deploy.reconcile(device, args.layout.read_text(), args.command == "apply")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        print(f"M1 keyboard: {(error.stderr or '').strip() or error}", file=sys.stderr)
        sys.exit(1)
    except (OSError, ParseError, RuntimeError, ValueError) as error:
        print(f"M1 keyboard: {error}", file=sys.stderr)
        sys.exit(1)
