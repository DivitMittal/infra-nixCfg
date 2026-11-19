#!/usr/bin/env python3
"""Review or deploy the pinned KOReader bundle to one explicitly selected reader."""

import argparse
from datetime import datetime, timezone
from pathlib import Path
import shlex
import subprocess
import sys
import uuid


MANAGED = (
    "patches/2-b1-reading.lua",
    "settings/b1.lua",
    "news/feed_config.lua",
    "plugins/koassistant.koplugin",
    ".b1-manifest.sha256",
)
PACKAGE = "org.koreader.launcher"


class Reader:
    def __init__(self, serial, root):
        self.serial = serial
        self.root = root

    def adb(self, *args, check=True):
        return subprocess.run(
            ["adb", "-s", self.serial, *args],
            check=check, text=True, capture_output=True,
        )

    def shell(self, *args, check=True):
        # adb shell joins its arguments remotely; quote each one explicitly.
        return self.adb("shell", shlex.join(args), check=check)

    def exists(self, path):
        result = self.shell("test", "-e", path, check=False)
        if result.returncode not in (0, 1):
            raise RuntimeError(f"Could not inspect reader path: {path}")
        return result.returncode == 0

    def preflight(self):
        if self.adb("get-state").stdout.strip() != "device":
            raise RuntimeError("Unlock the selected reader and authorize USB debugging.")
        if not self.shell("pm", "path", PACKAGE).stdout.startswith("package:"):
            raise RuntimeError("Install and launch the official GitHub KOReader APK first; F-Droid disables user patches.")
        for package in (PACKAGE, PACKAGE + ".fdroid"):
            process = self.shell("pidof", package, check=False)
            if process.stdout.strip():
                raise RuntimeError("Exit KOReader using its menu before deployment; unsaved settings must be flushed.")
            if process.returncode != 1:
                raise RuntimeError("Could not verify that KOReader is stopped.")
        if not self.exists(self.root + "/settings.reader.lua"):
            raise RuntimeError("KOReader data folder is not initialized. Launch once, grant storage access, then exit.")

    def deploy(self, bundle):
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
        backup = self.root + "/.b1-backups/" + stamp
        stage = self.root + "/.b1-stage-" + stamp
        self.shell("mkdir", "-p", stage, backup)
        print(f"Backup stays on the reader: {backup}", flush=True)
        # Startup patches mutate these files later; preserve their original state too.
        for relative in ("settings.reader.lua", "settings/profiles.lua"):
            original = self.root + "/" + relative
            if self.exists(original):
                target = backup + "/" + relative
                self.shell("mkdir", "-p", str(Path(target).parent))
                self.shell("cp", "-p", original, target)

        # Finish all transfers before replacing any managed paths.
        for relative in MANAGED:
            target = stage + "/" + relative
            self.shell("mkdir", "-p", str(Path(target).parent))
            self.adb("push", str(bundle / relative), target)
        self.shell("chmod", "-R", "u+rwX", stage)
        self.shell("sh", "-c", 'cd "$1" && sha256sum -c .b1-manifest.sha256', "sh", stage)

        replaced = []
        try:
            for relative in MANAGED:
                target = self.root + "/" + relative
                old = backup + "/" + relative
                self.shell("mkdir", "-p", str(Path(target).parent), str(Path(old).parent))
                had_original = self.exists(target)
                if had_original:
                    self.shell("mv", target, old)
                replaced.append((relative, had_original))
                self.shell("mv", stage + "/" + relative, target)
        except (subprocess.CalledProcessError, RuntimeError) as error:
            # Roll back completed moves if the device is still reachable.
            failures = []
            for relative, had_original in reversed(replaced):
                target = self.root + "/" + relative
                try:
                    self.shell("rm", "-rf", target)
                    if had_original:
                        self.shell("mv", backup + "/" + relative, target)
                except subprocess.CalledProcessError:
                    failures.append(relative)
            detail = f" Manual recovery required for: {', '.join(failures)}." if failures else " Managed paths restored."
            raise RuntimeError(f"Deployment failed. Backup: {backup}.{detail}") from error
        self.shell("mkdir", "-p", self.root + "/exports")
        self.shell("rmdir", stage + "/patches", stage + "/settings", stage + "/news", stage + "/plugins", stage)
        print("Installed. Start the official KOReader app; B1 defaults apply at startup.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--data-dir", choices=("/sdcard/koreader", "/storage/emulated/0/koreader"), default="/sdcard/koreader")
    parser.add_argument("--bundle", type=Path, help="Use an already-built bundle instead of invoking Nix")
    parser.add_argument("--apply", action="store_true", help="Back up and install; the default only reviews")
    args = parser.parse_args()
    reader = Reader(args.serial, args.data_dir)
    reader.preflight()
    bundle = args.bundle
    if bundle is None:
        repo = Path(__file__).resolve().parents[3]
        output = subprocess.run(
            ["nix", "build", "--no-link", "--print-out-paths", ".#b1-koreader"],
            cwd=repo, check=True, text=True, capture_output=True,
        )
        bundle = Path(output.stdout.strip())
    for relative in MANAGED:
        if not (bundle / relative).exists():
            raise RuntimeError(f"Incomplete bundle: {relative}")
    print(f"Reader: {args.serial}; data: {args.data_dir}; bundle: {bundle}")
    for relative in MANAGED:
        state = "replace (with backup)" if reader.exists(args.data_dir + "/" + relative) else "create"
        print(f"  {state}: {relative}")
    if args.apply:
        reader.deploy(bundle)
    else:
        print("Review only. Add --apply to deploy after checking the reader and paths.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"KOReader deployment: {error}", file=sys.stderr)
        sys.exit(1)
