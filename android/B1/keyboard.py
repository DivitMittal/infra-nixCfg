"""Deploy Unexpected Keyboard on B1 and disable bundled Onyx keyboards."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
from xml.etree.ElementTree import ParseError

from controller import Controller
import deploy


STOCK_PACKAGES = ("com.onyx.kime", "com.onyx.latinime")
OWNER = "0"


def require_owner(device):
    if device.shell("am", "get-current-user") != OWNER:
        raise RuntimeError("Switch B1 to the owner user (0) before managing its keyboard")


def enabled_stock_packages(device):
    enabled = set(device.shell("pm", "list", "packages", "-e", "--user", OWNER).splitlines())
    return [package for package in STOCK_PACKAGES if f"package:{package}" in enabled]


def require_replacement(device):
    active = deploy.secure_setting(device, "default_input_method")
    if not deploy.ime_enabled(device) or active != deploy.IME_ID:
        raise RuntimeError("Unexpected Keyboard must be enabled and default for owner user (0)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("command", choices=("plan", "apply"), nargs="?", default="plan")
    args = parser.parse_args()
    device = Controller(args.serial, json.loads(args.profile.read_text()))
    device.verify()
    require_owner(device)
    deploy.require_root(device)
    apply = args.command == "apply"
    status = deploy.reconcile(device, args.layout.read_text(), apply)
    if status != 0 and (apply or status != 3):
        return status

    pending = enabled_stock_packages(device)
    for package in STOCK_PACKAGES:
        print(f"stock keyboard {package}: {'disable for user 0' if package in pending else 'absent or disabled'}")

    if not apply:
        return 3 if status == 3 or pending else 0

    for package in pending:
        require_owner(device)
        require_replacement(device)
        device.shell("pm", "disable-user", "--user", OWNER, package)
        if package in enabled_stock_packages(device):
            raise RuntimeError(f"Stock keyboard {package} is still enabled for owner user (0)")
        require_replacement(device)
        print(f"stock keyboard {package}: disabled for user 0")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        print(f"B1 keyboard: {(error.stderr or '').strip() or error}", file=sys.stderr)
        sys.exit(1)
    except (OSError, ParseError, ValueError, RuntimeError, KeyError) as error:
        print(f"B1 keyboard: {error}", file=sys.stderr)
        sys.exit(1)
