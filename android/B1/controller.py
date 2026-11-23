"""Verify B1's identity before planning/applying its nix-android configuration."""

import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


class Controller:
    def __init__(self, serial, profile):
        self.serial = serial
        self.profile = profile

    def adb(self, *args):
        return subprocess.run(
            ["adb", "-s", self.serial, *args], check=True,
            capture_output=True, text=True,
        ).stdout.strip()

    def shell(self, *args):
        return self.adb("shell", shlex.join(args))

    def verify(self):
        if self.adb("get-state") != "device":
            raise RuntimeError("Unlock B1 and authorize this computer's USB debugging key.")
        actual = {}
        for name, expected in self.profile["expectedProperties"].items():
            actual[name] = self.shell("getprop", name)
            if actual[name] != expected:
                raise RuntimeError(f"B1 identity mismatch for {name}: expected {expected!r}, received {actual[name]!r}. No settings applied.")
        kernel = self.shell("uname", "-r")
        if not kernel.startswith(self.profile["kernelPrefix"]):
            raise RuntimeError(f"B1 kernel mismatch: received {kernel!r}. No settings applied.")
        actual["kernel"] = kernel
        for name in self.profile["observedProperties"]:
            actual[name] = self.shell("getprop", name)
        return actual

    def snapshot(self, identity):
        # Keep original values outside Git; never claim a guessed factory reset.
        state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "infra-nixCfg/B1"
        state.mkdir(parents=True, exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="before-apply-", dir=state))
        values = {}
        for namespace, settings in self.profile["settings"].items():
            values[namespace] = {
                key: self.shell("settings", "get", "--user", "0", namespace, key)
                for key in settings
            }
        path = directory / "settings.json"
        with open(path, "x", opener=lambda name, flags: os.open(name, flags, 0o600)) as output:
            json.dump({"serial": self.serial, "identity": identity, "settings": values}, output, indent=2)
        return path

    def converge(self, command, flake):
        identity = self.verify()
        if command == "inspect":
            print(json.dumps(identity, indent=2))
            return 0
        if command == "apply":
            print(f"Original managed settings saved to {self.snapshot(identity)}", flush=True)
        operation = "switch" if command == "apply" else "plan"
        result = subprocess.run([
            "nix", "run", flake + "#android-rebuild", "--", operation,
            "--flake", flake + "#B1", "--serial", self.serial,
        ])
        if result.returncode == 0 and command == "apply":
            response = self.shell("am", "broadcast", "-a", "onyx.action.refresh_keymapping")
            if "Broadcast completed" not in response:
                raise RuntimeError("Settings applied, but Onyx did not confirm key-map reload; inspect before retrying.")
        return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--flake", default=".", help="Configuration flake without a #fragment")
    parser.add_argument("command", choices=("inspect", "plan", "apply"), nargs="?", default="inspect")
    args = parser.parse_args()
    if not args.flake or args.flake.startswith("-") or "#" in args.flake:
        parser.error("--flake must be a flake reference without a fragment or option prefix")
    with args.profile.open() as source:
        profile = json.load(source)
    return Controller(args.serial, profile).converge(args.command, args.flake)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"B1 controller: {error}", file=sys.stderr)
        sys.exit(1)
