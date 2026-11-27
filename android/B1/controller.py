"""Verify B1's identity before planning/applying its nix-android configuration."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


class Controller:
    def __init__(self, serial, profile, adb_path="adb"):
        self.serial = serial
        self.profile = profile
        self.adb_path = adb_path

    def adb(self, *args):
        return subprocess.run(
            [self.adb_path, "-s", self.serial, *args], check=True,
            capture_output=True, text=True, timeout=20,
        ).stdout.strip()

    def shell(self, *args):
        return self.adb("shell", shlex.join(args))

    def verify(self):
        try:
            state = self.adb("get-state")
        except subprocess.CalledProcessError as error:
            detail = (error.stderr or "").strip()
            if "unauthorized" not in detail.lower():
                raise RuntimeError(f"ADB could not reach the selected USB device: {detail or error}") from error
            state = "unauthorized"
        if state != "device":
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

    def audit(self, identity):
        lock = json.loads(Path(__file__).with_name("apps.lock.json").read_text(encoding="utf-8"))
        inventory = self.shell("pm", "list", "packages", "--user", "0", "--show-versioncode")
        versions = dict(re.findall(r"^package:(\S+)\s+versionCode:(\d+)\s*$", inventory, re.MULTILINE))
        if not versions:
            raise RuntimeError("ADB returned no package version codes for Android user 0.")
        disabled = set(self.shell("pm", "list", "packages", "-d", "--user", "0").splitlines())
        apps = {}
        for package, entry in lock["packages"].items():
            installed = int(versions[package]) if package in versions else None
            apps[package] = {
                "installedVersionCode": installed,
                "minimumVersionCode": entry["versionCode"],
                "disabled": f"package:{package}" in disabled if installed is not None else None,
            }
        return {
            "identity": identity,
            "currentUser": self.shell("am", "get-current-user"),
            "settingsUser0": {
                "screen_off_timeout": self.shell("settings", "get", "--user", "0", "system", "screen_off_timeout"),
                "KEYCODE_BACK": self.shell("settings", "get", "--user", "0", "global", "KEYCODE_BACK"),
                "key_custom_side_key_short_press_enable": self.shell("settings", "get", "--user", "0", "global", "key_custom_side_key_short_press_enable"),
                "default_input_method": self.shell("settings", "get", "--user", "0", "secure", "default_input_method"),
            },
            "pinnedAppsUser0": apps,
            "chatGPTInstalledUser0": "com.openai.chatgpt" in versions,
        }

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
        if command == "audit":
            print(json.dumps(self.audit(identity), indent=2))
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
    parser.add_argument("--profile", type=Path, help="Nix-generated profile for apply; defaults to the checked-in identity")
    parser.add_argument("--adb", default="adb", help="ADB executable for inspect and audit")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--flake", default=".", help="Configuration flake without a #fragment")
    parser.add_argument("command", choices=("inspect", "audit", "plan", "apply"), nargs="?", default="inspect")
    args = parser.parse_args()
    if not args.flake or args.flake.startswith("-") or "#" in args.flake:
        parser.error("--flake must be a flake reference without a fragment or option prefix")
    if args.command in ("plan", "apply") and args.adb != "adb":
        parser.error("--adb is only supported for inspect and audit; plan and apply use the Nix environment")
    if args.command == "apply" and args.profile is None:
        parser.error("apply needs a Nix-generated profile; use nix run .#b1-device")
    with (args.profile or Path(__file__).with_name("identity.json")).open(encoding="utf-8") as source:
        profile = json.load(source)
    if args.command == "apply" and not profile.get("settings"):
        parser.error("apply requires a profile with managed settings to back up")
    return Controller(args.serial, profile, args.adb).converge(args.command, args.flake)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"B1 controller: {error}", file=sys.stderr)
        sys.exit(1)
